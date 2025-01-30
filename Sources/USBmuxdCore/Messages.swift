
import Foundation


public struct DeviceProperties : Codable {

  let connectionSpeed : Int?
  let connectionType  : String
  let deviceID        : Int
  let locationID      : Int?
  let productID       : Int?
  let serialNumber    : String
  let usbSerialNumber : String?
  
  /*
   these cropped up, fun!
   I plugged in another phone, an old one that has been used for XCode development and
   appears to have WiFi debugging enabled or something, anyhoo, then it also turned out
   that it creates a whole extra device with a whole different set of properties, sigh.
   hence this mess. we will of course want to filter it out later because we don't want to
   connect over WiFi.
   
   annoying, because it means there could be more of this lurking
  */
  
  let escapedFullServiceName : String?
  let interfaceIndex         : Int?
  let networkAddress         : Data?
  let udid                   : String?
  
  
  
  /*
    this is somewhat petty but I just don't want the capitalisation OK?
  */
  enum CodingKeys : String, CodingKey {
    case connectionSpeed = "ConnectionSpeed"
    case connectionType  = "ConnectionType"
    case deviceID        = "DeviceID"
    case locationID      = "LocationID"
    case productID       = "ProductID"
    case serialNumber    = "SerialNumber"
    case usbSerialNumber = "USBSerialNumber"
    
    case escapedFullServiceName = "EscapedFullServiceName"
    case interfaceIndex         = "InterfaceIndex"
    case networkAddress         = "NetworkAddress"
    case udid                   = "UDID"
  }
}



public struct Device : Codable {
  
  public let deviceID    : Int
         let messageType : String
         let properties  : DeviceProperties

  enum CodingKeys : String, CodingKey {
    case deviceID    = "DeviceID"
    case messageType = "MessageType"
    case properties  = "Properties"
  }
  
}

/*
  one for result, we will likely want intermediate types,
  but these will do to pull all the info out of the plists
*/

public struct MuxResult : Codable {
  
  public let messageType : String
  public let number      : Int
  
  enum CodingKeys : String, CodingKey {
    case messageType = "MessageType"
    case number      = "Number"
  }
}

/*
  really we should also build our own messages this way using
  a constructor to handle the boilerplate stuff.
 
*/

public struct MuxMessage : Codable {
  
  let messageType : StringLiteralType
  
  public init(messageType: String) {
    self.messageType = messageType
  }
  
  enum CodingKeys : String, CodingKey {
    case messageType = "MessageType"
  }
}


/* NB the attach message is all good, but this, not so much
   we will need additional code to process attach/detach events
 0 {
     DeviceID = 1395;
     MessageType = Detached;
 }
*/

public struct MuxDetatch : Codable {
  let deviceID   : Int
  let messageType: String
  
  enum CodingKeys : String, CodingKey {
    case messageType = "MessageType"
    case deviceID    = "DeviceID"
  }
}


public struct Connect : Codable {
  
  let messageType: String = "Connect"
  let portNumber : Int
  let deviceID   : Int
  
  public init ( device: Int, port : Int ) {
    self.deviceID   = device
    self.portNumber = port
  }
  
  enum CodingKeys : String, CodingKey {
    case messageType = "MessageType"
    case portNumber  = "PortNumber"
    case deviceID    = "DeviceID"
  }
  
}


public struct LockdownRequest : Codable {
  let key     : String
  let request : String
  
  public init ( key: String, request: String ) {
    self.key     = key
    self.request = request
  }
  
  enum CodingKeys : String, CodingKey {
    case key     = "Key"
    case request = "Request"
  }
  
}


public struct LockdownResponse : Codable {
  
  public let key     : String
  public let request : String
  public let value   : String
  
  enum CodingKeys : String, CodingKey {
    case key     = "Key"
    case request = "Request"
    case value   = "Value"
  }
  
  
}
