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
  var  machine : StateMachine { get }
  init ( _ machine: StateMachine)
}

// TODO: Extract mux message machine to protocol

public enum MachineError : Error {
  case shrug // no errors yet TODO: add errors
}

protocol MachineHeader {
  var length : UInt32 { get }
  // ok, but we also need to extract tags for usbmuxd
  // we'll just have to cast it, sort out later.
}


extension USBMuxdHeader : MachineHeader {
  
}

protocol StateMachine {
  
  var buffer         : Data          { get set }
  var buffptr        : Int           { get set }
  var state          : MachineState! { get set }
  var HEADER_LENGTH  : Int           { get     }
  var header         : MachineHeader { get set }
  
  var messageHandler : ((Result< [String: Any], MachineError>) -> Void)? { get set }
  
  func transition ( to state: MachineState)
  func process    ( data: Data )
  func finished   () -> Bool
  
}

public class MuxMessageMachine : StateMachine {
  
  

  
  let HEADER_LENGTH = 16 // USBMuxHeader length
  
  var buffer  : Data          =  Data()
  var buffptr : Int           = 0
  var header  : MachineHeader = USBMuxdHeader()
  var state   : MachineState!
  
  public var messageHandler : ((Result< [String: Any], MachineError>) -> Void)? = nil
  
  
  public init() {
    self.state = ReadHeader(self)
  }
  
  /*
    every time data come in from the usbmuxd socket we process it through here
    it gets added to the buffer and then we execute the current state which will
    be either ReadHeader or ReadPlist.
   
    If they are unable to complete their reads due to insiffucuent data, they will exit
    without transitioning and wait for more data to arrive to finish their tasks
   
    when they are done they will transition to the next suitable state and either execute
    it or wait
  */
  
  public func process( data: Data ) {
    buffer += data
    state.execute()
  }
  
  
  func transition(to state: MachineState) {
    self.state = state
  }
  

  /*
    check to see if we have processed all the data in the buffer
    called by the Read states to detrmine which state to transition to next
  */
  func finished() -> Bool {
    buffptr >= buffer.count
  }
  
}




class Reset : MachineState {
  
  var machine: StateMachine
  
  required init(_ machine: StateMachine) {
    self.machine = machine
  }
  
  /*
    reset the data buffer and pointer and transition back to ReadHeader
    ready for the next batch of data
  */
  
  func execute() {
    machine.buffer   = Data()
    machine.buffptr  = 0
    machine.transition(to: ReadHeader( machine ) )
  }
}




class ReadPlist : MachineState {
  
  var machine: StateMachine
  
  required init (_ machine: StateMachine ) {
    self.machine = machine
  }
  
  /*
    attempt to read a PList (well, [String : Any]) from the data buffer
  */
  
  func execute() {
    
    
    /*
      retrieve the length of the PList data from the USBMuxHeader we just read
    */
    let datalen = Int(machine.header.length) - machine.HEADER_LENGTH
    
    /*
      if there is not enough data in the buffer yet, we stop and wait in this state
      until more data comes along and we get executed again
    */
    guard (machine.buffer.count - machine.buffptr) >= datalen else { return }
      
    /*
      extract the relevant bytes from the buffer
    */
    let chunk = machine.buffer[machine.buffptr..<(machine.buffptr + datalen)]
    
    /*
      I have no idea why this form of PLS requires us to pass a pointer, but it does <shrug>
    */
    var xml : PropertyListSerialization.PropertyListFormat = .xml
    
    if let plist = try? PropertyListSerialization.propertyList(from: chunk, options: .mutableContainersAndLeaves, format: &xml) {
      if let dict = plist as? [String : Any] {
        if let handler = machine.messageHandler {
          handler ( .success(dict) )
        }
      }
    }
    
    machine.buffptr += datalen
    
    
    /*
      if we are at the end of the buffer, time to reset all the things
      if there is more data it will be a header so we transition
      in both cases we execute the next state
    */
    if machine.finished() { machine.transition ( to: Reset(machine)     ) }
    else                  { machine.transition ( to: ReadHeader(machine)) }
    
    machine.state.execute()
  }
}



class ReadHeader : MachineState {
  
  var machine: StateMachine
  
  required init(_ machine: StateMachine) {
    self.machine = machine
  }
  
  /*
    attempt to read a USBMuxHeader from the buffer
  */
  
  
  /*  MARK: the only actual difference between muxd and lockdownd is the header,
      
      so realistically, if we make this bit here work for both, we don't need a new
      machine and we dont even reall need the protocol (not that protoocl anyway)
      actually, if we create a wrapper class to pull the length we're nearly there,
      we can't just manipulate the tyoe though as lockdownd is big endian and we need
      to byte swap, plus in the case of usbmuxd we arguably need the tags (though
      we can just zero them for ldd. Also we need to add an additional check on muxd
      to make sure we are reading the right type of message (8) so we need to add an
      error condition
   
   */
  
  func execute() {
    
    
    /*
      if there is not enough data to read a full header, we simply exit, remaining in the
      same state until more data is available (I have never seen this happen, TBH, but still)
    */
    guard (machine.buffer.count - machine.buffptr) >= machine.HEADER_LENGTH else { return }
    
    let headend = machine.buffptr + machine.HEADER_LENGTH
    
    let header = machine.buffer[machine.buffptr..<headend].withUnsafeBytes { bytes in
      bytes.load(as: USBMuxdHeader.self)
    }
    
    machine.buffptr += 16
    machine.header  = header //; print(header)
  
    /*
      finished reading header, there will be a PList next,
    */

    machine.transition(to: ReadPlist(machine) )
    
    /*
      if we are the end of the buffer though, it isn't here yet,
      so we transition to the ready state but do not execute.
     
      if there is more data, we try to make a PList out of it by executing
    */
    
    if machine.finished() { return }
    else                  { machine.state.execute() }
    
  }
  
}
