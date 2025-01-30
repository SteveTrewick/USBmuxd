
import Foundation


/*
  eventually we need to pull concrete tyeps out of the various PLists.
  
  Muggins here forgot all about PropertyListDecoder and Codable,
  which means we can just do this and not fuss fart around with dictionaries
 
 e.g.
 
 if let deviceList = try decoder.decode( [String : [Device] ].self, from: devdata)["DeviceList"] {
     debugPrint ( deviceList )
 }
 
 
*/


public struct DeviceProperties : Codable {

  let connectionSpeed : Int
  let connectionType  : String
  let deviceID        : Int
  let locationID      : Int
  let productID       : Int
  let serialNumber    : String
  let usbSerialNumber : String
  
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
  }
}



public struct Device : Codable {
  
  let deviceID    : Int
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
  
  let messageType : String
  let number      : Int
  
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
