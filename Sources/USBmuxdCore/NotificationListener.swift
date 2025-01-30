
import Foundation
import GCDSocket


public struct NotificationListener {
  
  public enum Notification {
    case attach(Device)
    case detatch(Int)
  }
  
  public enum NOK : Error {
    case nok
  }
  
  public init() {}
  
  var socket : GCDSocketClient<sockaddr_un>!
  public var notify : ((Result<Notification, Error>) -> Void)? = nil
  
  let decoder   = PropertyListDecoder()
  let construct = GCDSocketConstructor()
  let message   = MessageBuilder()
  let parser    = PListParser(header: .muxd)
  
  
  
  mutating public func connect() {
    
    socket = construct.domainSocketClient(path: "/var/run/usbmuxd")
    
    socket.dataHandler = { [self] result in
      switch result {
        case .failure(let fail): notify?(.failure(fail))
        case .success(let data): parser.process(data: data)
      }
    }
    
    parser.messageHandler = { [self] result in
      switch result {
        
        case .failure(let fail) : notify?(.failure(fail))
        
        case .success(let (_, data)) :
        
            if let device = try? decoder.decode(Device.self, from: data) {
              notify? ( .success(.attach(device)) )
              return
            }
          
            if let detach = try? decoder.decode(MuxDetatch.self, from: data) {
              notify? ( .success(.detatch(detach.deviceID)) )
              return
            }
          
            if let result = try? decoder.decode(MuxResult.self, from: data) {
              print(result)
              if result.number != 0 {
                notify? (.failure(NOK.nok) )
              }
            }
      }
    }
    socket.connect()
    socket.write(data: message.muxd(msg: ["MessageType":"Listen"], tag: 0))
  }
  
}

