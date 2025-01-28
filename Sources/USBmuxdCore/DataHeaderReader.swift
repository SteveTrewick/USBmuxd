
import Foundation
import USBMuxdHeader



/*
  the usbmuxd header includes its own length, but the lockdownd header does not
  so for the usbmuxd header we must subtract 16 bytes to get the length of the data
  but we need to not do that with lockdownd, hence subtract
*/
public protocol DataHeaderReader {
  
  var length : Int { get }
  
  func load ( from bytes : UnsafeRawBufferPointer  ) -> HeaderInfo
}


public struct USBMuxHeaderReader : DataHeaderReader {
  
  public let length : Int = 16
  
  public init() {}
  
  public func load ( from bytes: UnsafeRawBufferPointer  ) -> HeaderInfo {
    
    let header = bytes.load(as: USBMuxdHeader.self)
    
    return HeaderInfo (
      dataLength: Int(header.length) - length, // usbmuxd header includes its own length
      tag       : header.tag                   // so we need to subtract it
    )
  }
}


public struct LockdownHeaderReader : DataHeaderReader {
  
  public let length  : Int = 4
  
  public init() {}
  
  public func load ( from bytes: UnsafeRawBufferPointer) -> HeaderInfo {
    
    let len = bytes.load(as: UInt32.self)
    
    return HeaderInfo (
      dataLength: Int( len.bigEndian ),
      tag       : 0
    )
  }
  
}

