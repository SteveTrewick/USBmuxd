import Foundation
import USBMuxdHeader


/*
  So my switch/case got out of hand and this is after all a state machine thing,
  so I made it an explcit state machine, it kind of has some hidden wait states, TBH
  but eh, w/e, it is robust to fragmentation of responses and multiple response per call,
  so that's nice.
*/

protocol MachineState {
  func execute()
  var  machine : PListParser { get }
  init ( _ machine: PListParser)
}


public enum MachineError : Error {
  case xmlfail, dictfail
}


public struct HeaderInfo {
  
  public let dataLength : Int
  public let tag        : UInt32
  
  public init(dataLength: Int, tag: UInt32) {
    self.dataLength = dataLength
    self.tag        = tag
  }
}




public class PListParser  {
  
    
  var buffer  : Data       =  Data()
  var buffptr : Int        = 0
  var header  : HeaderInfo = HeaderInfo(dataLength: 0, tag: 0)
  
  var state  : MachineState!
  var reader : DataHeaderReader
  
  public var messageHandler : ((Result < ( tag: UInt32, data: Data ), MachineError > ) -> Void)? = nil
  
  
  public enum HeaderType {
    case lockd, muxd
  }
  
  
  
  public init ( header type: HeaderType ) {
    
    func reader(for type: HeaderType) -> DataHeaderReader {
      switch type {
        case .muxd  : return USBMuxHeaderReader()
        case .lockd : return LockdownHeaderReader()
      }
    }
    
    self.reader = reader(for: type)
    self.state  = ReadHeader(self)
  }
  
  // weirdly, switching this halts everything! Why?
  public func setHeader(type: HeaderType) {
    switch type {
      case .lockd: self.reader = LockdownHeaderReader()
      case .muxd : self.reader = USBMuxHeaderReader()
    }
  }
  
  /*
    every time data come in from the usbmuxd socket we process it through here
    it gets added to the buffer and then we execute the current state which will
    be either ReadHeader or ReadPlist.
   
    If they are unable to complete their reads due to insuffucient data, they will exit
    without transitioning and wait for more data to arrive to finish their tasks
   
    when they are done they will transition to the next suitable state and either execute
    it or wait
  */
  
  public func process ( data: Data ) {
    
    // if we have failed, do nothing. or, should we embrace the chaos?
    if let _ = state as? Fail { return }
    
    buffer += data
    state.execute()
  }
  
  
  func transition ( to state: MachineState ) {
    self.state = state
  }
  
  /*
    count of the unprocessed bytes remaining in the buffer
  */
  var unprocessedBytes : Int { buffer.count - buffptr }

  /*
    check to see if we have processed all the data in the buffer
    called by the Read states to determine which state to transition to next
  */
  var finished : Bool { buffptr >= buffer.count }
  
}


class Fail : MachineState {
  
  func execute() { }
  
  var machine: PListParser
  
  required init (_ machine: PListParser ) {
    self.machine = machine
  }
  
}


class Reset : MachineState {
  
  var machine: PListParser
  
  required init ( _ machine: PListParser ) {
    self.machine = machine
  }
  
  /*
    reset the data buffer and pointer and transition back to ReadHeader
    ready for the next batch of data
  */
  
  func execute() {
    machine.buffer   = Data()
    machine.buffptr  = 0
    machine.transition ( to: ReadHeader( machine ) )
  }
}



class ReadHeader : MachineState {
  
  var machine: PListParser
  
  required init ( _ machine: PListParser ) {
    self.machine = machine
  }
  
  
  
  /*
    attempt to read a header from the buffer
  */
  func execute() {
    
    /*
      if there is not enough data to read a full header, we simply exit, remaining in the
      same state until more data is available (I have never seen this happen, TBH, but still)
    */
    guard machine.unprocessedBytes >= machine.reader.length else { return }
    
    let headend = machine.buffptr + machine.reader.length
    
    let headerInfo = machine.buffer[machine.buffptr..<headend].withUnsafeBytes { bytes in
      machine.reader.load(from: bytes)
    }
    
    machine.buffptr += machine.reader.length
    machine.header  = headerInfo
  
    /*
      finished reading header, there will be a PList next,
    */

    machine.transition(to: ReadPlist(machine) )
    
    /*
      if we are the end of the buffer though, it isn't here yet,
      so we transition to the ready state but do not execute.
     
      if there is more data, we try to make a PList out of it by executing
    */
    
    if machine.finished { return }
    else                { machine.state.execute() }
    
  }
  
}



class ReadPlist : MachineState {
  
  var machine: PListParser
  
  required init (_ machine: PListParser ) {
    self.machine = machine
  }
  
  /*
    attempt to read a PList (well, [String : Any]) from the data buffer
  */
  
  func execute() {
        
    /*
      if there is not enough data in the buffer yet, we stop and wait in this state
      until more data comes along and we get executed again
    */
    guard machine.unprocessedBytes >= machine.header.dataLength else { return }
      
    /*
      extract the relevant bytes from the buffer
    */
    let chunk = machine.buffer[machine.buffptr..<(machine.buffptr + machine.header.dataLength)]
    
    machine.messageHandler?( .success( (machine.header.tag, chunk) ) )
    
    machine.buffptr += machine.header.dataLength
    
    /*
      if we are at the end of the buffer, time to reset all the things
      if there is more data it will be a header so we transition
      in both cases we execute the next state
    */
    if machine.finished { machine.transition ( to: Reset(machine)     ) }
    else                { machine.transition ( to: ReadHeader(machine)) }
    
    machine.state.execute()
  }
}



