
import Foundation
import GCDSocket


public protocol EnumeratorState {
  func execute()
  var  machine : DeviceEnumerator { get }
  init ( _ machine: DeviceEnumerator)
}

public class DeviceEnumerator {
  
  
  public struct DeviceDescriptor {
    public let device: Device
    public let name  : String
  }
  
  let message     = MessageBuilder()
  let construct   = GCDSocketConstructor()
  let router      = ResponseRouter()
  var parser      = PListStateMachine ( header: .muxd )
  var muxdSocket  : GCDSocketClient<sockaddr_un>!
  var lockdSocket : GCDSocketClient<sockaddr_un>!
  var state       : EnumeratorState!
  
  var devices     : [Int: DeviceDescriptor] = [:]
  var candidates  : [Device]      = []
  var candidate   : Int           = 0
  
  // shit type
  var completion: ((Result<[Int : DeviceDescriptor], Error>)->Void)? = nil
  
  public init() {
    
  }
  
  public func enumerateDevices(_ completion: @escaping (Result<[Int : DeviceDescriptor], Error>)->Void ) {
    self.completion = completion
    self.state      = EnumConnect(self)
    self.state.execute()
  }
  
  func transition(to state: EnumeratorState) {
    self.state = state
    self.state.execute()
  }
  
}

class EnumConnect : EnumeratorState {
  
  var machine: DeviceEnumerator
  
  required init (_ machine: DeviceEnumerator ) {
    self.machine = machine
  }
  
  
  func execute() {
    
    machine.muxdSocket = machine.construct.domainSocketClient(path: "/var/run/usbmuxd")
    machine.muxdSocket.dataHandler = { [self] result in
      //print(result)
      switch result {
        case .failure(let fail): machine.completion? (.failure(fail) )
        case .success(let data): machine.parser.process(data: data)
      }
    }
    machine.parser.messageHandler = { [self] result in
      //print(result)
      switch result {
        case .failure (let fail)        : machine.completion? (.failure(fail) )
        case .success (let (tag, data)) : machine.router.route(tag: tag, data: data)
      }
    }
    machine.muxdSocket.connect()
    machine.transition ( to: EnumRequest(machine) )
  }
  
}

class EnumRequest : EnumeratorState {
  
  var machine: DeviceEnumerator
  
  required init (_ machine: DeviceEnumerator ) {
    self.machine = machine
  }
  
  
  enum Fails : Error {
    case requestFail
  }
  
  func execute() {
    
    let list = machine.message.muxd ( msg: MuxMessage(messageType: "ListDevices"), tag: 0xbeef )
    
    machine.router.expect(tag: 0xbeef, response: .deviceList) { [self] devices in
      if let devices = devices as? [Device] {
        //print(devices)
        machine.candidates = devices
        machine.transition ( to: EnumLockdQuery(machine) )
      }
      else {
        // TODO: add fail state or regen
        machine.completion? ( .failure(Fails.requestFail) )
      }
    }
    machine.muxdSocket.write(data: list)
  }
}

class EnumLockdQuery : EnumeratorState {
  
  var machine     : DeviceEnumerator
  var lockdSocket : GCDSocketClient<sockaddr_un>!
  var parser      = PListStateMachine(header: .muxd )
  let lockdParser = PListStateMachine(header: .lockd)
  let router      = ResponseRouter()
  
  required init (_ machine: DeviceEnumerator ) {
    self.machine = machine
  }

  enum QueryFail : Error {
    case lockdQueryFail
  }
  
  func execute() {
    
    if machine.candidate == machine.candidates.count {
      defer {
        machine.transition(to: EnumDeliver(machine) )
      }
      return
    }
    
    lockdSocket = machine.construct.domainSocketClient(path: "/var/run/usbmuxd")
    lockdSocket.dataHandler = { [self] result in
      //print(result)
      switch result {
        case .failure(let fail): machine.completion? (.failure(fail) )
        case .success(let data): parser.process(data: data)
      }
    }
    parser.messageHandler = { [self] result in
      //print(result)
      switch result {
        case .failure(let fail)       : machine.completion? (.failure(fail) )
        case .success(let (tag, data)): router.route(tag: tag, data: data)
      }
    }
    lockdSocket.connect()
    
    let device  = machine.candidates[machine.candidate].deviceID
    let connect = Connect(device: device, port: 32498)
    
    router.expect(tag: 0xcafe, response: .result) { [self] result  in
      //print(result)
      if let result = result as? MuxResult, result.number == 0 {
        
        lockdParser.messageHandler = parser.messageHandler
        parser = lockdParser
        
        router.expect(tag: 0, response: .lockdResponse) { response in
          // we never get ere
          //print(response)
          if let response = response as? LockdownResponse {
            machine.devices [device] = DeviceEnumerator.DeviceDescriptor (
              device: machine.candidates[machine.candidate],
              name  : response.value
            )
            machine.candidate += 1
            lockdSocket.dataHandler = nil
            lockdSocket.close()
            machine.transition(to: EnumLockdQuery(machine) )
          }
        }
        lockdSocket.write(data: machine.message.lockd(msg: LockdownRequest(key: "DeviceName", request: "GetValue")))
      }
    }
    // feel like we might need difeerent numbers??
    lockdSocket.write(data: machine.message.muxd(msg: connect, tag: 0xcafe))
    

  }

}

class EnumDeliver : EnumeratorState {
  
  
  var machine: DeviceEnumerator
  
  required init(_ machine: DeviceEnumerator) {
    self.machine = machine
  }
  
  func execute() {
    
    machine.completion? ( .success(machine.devices) )
  }
}


