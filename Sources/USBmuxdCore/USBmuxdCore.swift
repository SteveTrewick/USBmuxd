import Foundation
import USBMuxdHeader


struct MessageBuilder {
  
  func build(from dict: [String : Any] ) -> Data? {
    // first create the PList so we know how long it is
    guard
      let pldata = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    else {
      return nil
    }
    var header = USBMuxdHeader(length: UInt32(16 + pldata.count), version: 1, type: 8, tag: 0xdeadbeef)
    let hdata  = Data(bytes: &header, count: 16)
    
    return hdata + pldata
  }
}
