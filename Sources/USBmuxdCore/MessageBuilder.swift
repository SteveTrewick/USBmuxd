import Foundation
import USBMuxdHeader



/*
  usbmuxd messages are pretty simple, while things can get complex on the bus
  with all the lockdownd etc binary and SSL chat, the basic usbnuxd part is
  just a dictionary encoded as a PList in XML format.
 
  older versions of usbmuxd used a binary format, but that's gone now, on macOS anyway,
  which honestly is nice, because we can read PLists with our eyes.
 
  each message consists of a 16 byte header split into 4 UInt32 fields defined like this
 
   typedef struct {
     uint32_t length;   // 16 + plist payload length
     uint32_t version;  // this is the version and it should be 1
     uint32_t type;     // message format, PList == 8
     uint32_t tag;      // response tag, this will only happen in OK/NOK messages
   }
   __attribute__((packed)) USBMuxdHeader;
 
   the following bytes contain an XML encoded PList
 
   some fun info on (some of) the format of the PList messages can be found at :
    https://jon-gabilondo-angulo-7635.medium.com/understanding-usbmux-and-the-ios-lockdown-service-7f2a1dfd07ae
    https://archive.is/uLAyw
 
   many of the fields are optional but will help if you are tracing
 
   lockdownd headers consist of a single UInt32 containing a big endian representation of the
   length of the XML PList that follows :
 
   00 00 01 52 [338 bytes of XML PLIST]
 
*/
public struct MessageBuilder {
  
  
  let encoder = PropertyListEncoder()
  
  public init() {
    encoder.outputFormat = .xml
  }
  
  
  
  
  public func muxd ( dict: [String : Any], tag: UInt32 ) -> Data? {
    
    guard let pldata = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    else {
      return nil
    }
    
    // add 16 because usbmuxd headers include their own length
    var header = USBMuxdHeader ( length: UInt32(16 + pldata.count), version: 1, type: 8, tag: tag )
    let hdata  = Data ( bytes: &header, count: 16 )
    
    return hdata + pldata
  }
  
  
  // same but with typeed message
  public func muxd ( msg: MuxMessage, tag: UInt32 ) -> Data? {
    
    guard let pldata = try? encoder.encode(msg)
    else {
      return nil
    }
    
    var header = USBMuxdHeader ( length: UInt32(16 + pldata.count), version: 1, type: 8, tag: tag )
    let hdata  = Data ( bytes: &header, count: 16 )
    
    return hdata + pldata
  }
  
  
  
  // same but different header
  public func lockd ( dict: [String : Any ] ) -> Data? {
    
    guard let pldata = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    else {
      return nil
    }
    
    // lockdownd headers DO NOT include their own length
    var header = UInt32 (pldata.count).byteSwapped
    let hdata  = Data   ( bytes: &header, count: 4 )
    
    return hdata + pldata
    
  }
  
}
