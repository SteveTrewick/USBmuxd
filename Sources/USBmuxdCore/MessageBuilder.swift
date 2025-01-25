import Foundation
import USBMuxdHeader


public struct MessageBuilder {
  
  public init() {}
  
  public func build(from dict: [String : Any], tag: UInt32 ) -> Data? {
    // first create the PList so we know how long it is
    guard
      let pldata = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    else {
      return nil
    }
    var header = USBMuxdHeader(length: UInt32(16 + pldata.count), version: 1, type: 8, tag: tag)
    let hdata  = Data(bytes: &header, count: 16)
    
    return hdata + pldata
  }
}
