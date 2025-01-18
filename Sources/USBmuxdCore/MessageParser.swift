import Foundation
import USBMuxdHeader


/*
  So my switch/case got out of hand and this is after all a state machine thing,
  so I made it an explcit state machine, it kind of has some hidden wait states, TBH
  but eh, w/e
*/

protocol MachineState {
  func execute()
  var  machine : MuxMessageMachine { get }
  init (_ machine: MuxMessageMachine)
}

/*
 
*/

public class MuxMessageMachine {
  
  let HEADER_LENGTH = 16 // USBMuxHeader length
  
  var buffer  : Data          =  Data()
  var buffptr : Int           = 0
  var header  : USBMuxdHeader = USBMuxdHeader()
  var state   : MachineState!
  
  
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
    print("transitioned to : \(state)")
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
  
  var machine: MuxMessageMachine
  
  required init(_ machine: MuxMessageMachine) {
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
  
  var machine: MuxMessageMachine
  
  required init (_ machine: MuxMessageMachine ) {
    self.machine = machine
  }
  
  /*
    attempt to read a PList (well, [String : Any]) from the data buffer
  */
  
  func execute() {
    print("executing \(self))")
    
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
        print(dict)
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
  
  var machine: MuxMessageMachine
  
  required init(_ machine: MuxMessageMachine) {
    self.machine = machine
  }
  
  /*
    attempt to read a USBMuxHeader from the buffer
  */
  
  func execute() {
    
    print("executing \(self))")
    
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
    machine.header  = header ; print(header)
  
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
