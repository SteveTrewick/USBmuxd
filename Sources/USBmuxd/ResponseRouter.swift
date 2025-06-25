import Foundation
import GCDSocket

/*
  ok, some routing, this is not very elegant TBH
*/




public class ResponseRouter {
  
  public enum ResponseType {
    case deviceList, result, device, lockdResponse
  }
  
  public struct TagResponse {
    let type    : ResponseType
    let handler : (Any?) -> Void
  }
  
  var expecting : [ UInt32 : TagResponse ] = [:]
  let decoder   = PropertyListDecoder()

  
  
  public init() {
    
  }
  
  
  public func expect ( tag: UInt32, response: ResponseType, _ handler: @escaping (Any) -> Void ) {
    expecting[ tag ] = TagResponse(type: response, handler: handler)
  }
  
  
  public func unexpect ( tag: UInt32 ) {
    expecting[ tag ] = nil
  }
  
  func dumpXML (_ data: Data ) -> String { String(data: data, encoding: .utf8) ?? "" }
  
  public func route ( tag: UInt32, data: Data ) {
    
    
    guard let response = expecting[ tag ] else {
      print("unexpected \(tag) \n \(dumpXML(data))")
      return
    } // oof
    
    unexpect(tag: tag)
    switch response.type {
      case .deviceList    : response.handler ( extractDeviceList       (from: data) )
      case .device        : response.handler ( extractDevice           (from: data) )
      case .result        : response.handler ( extractResult           (from: data) )
      case .lockdResponse : response.handler ( extractLockdownResponse (from: data) )
    }
    
  }
  
  
  
  func extractDeviceList (from data: Data ) -> [Device]? {
    
    guard let deviceList = try? decoder.decode( [String : [Device] ].self, from: data)["DeviceList"]
    else {
      print("failed to extract device list")
      return nil
    }
    return deviceList
    
  }
  
  
  
  func extractDevice ( from data: Data ) -> Device? {
    guard let device = try? decoder.decode(Device.self, from: data)
    else {
      print("failed to extract device")
      return nil
    }
    return device
  }
  
  
  
  func extractResult ( from data: Data ) -> MuxResult? {
    guard let result = try? decoder.decode(MuxResult.self, from: data)
    else {
      print("failed to extract result")
      return nil
    }
    return result
  }
  
  
  func extractLockdownResponse ( from data: Data ) -> LockdownResponse? {
    guard let response = try? decoder.decode(LockdownResponse.self, from: data)
    else {
      print("failed to extract lockd response")
      return nil
    }
    return response
  }
}
