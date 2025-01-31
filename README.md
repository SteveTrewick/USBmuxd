# USBmuxd

USBmuxd is an experimental, evolving and currently very bare set of swift routines for 
talking to the usbmux deamon on macOS which mediates communication between things
on your system and things on your USB connected iPhone.

usbmuxd lives at /var/run/usbmuxd as a Unix domain socket.

usbmuxd messages are pretty simple, while things can get complex on the bus
with all the lockdownd etc binary and SSL chat, the basic usbmuxd part is
just a dictionary encoded as a PList in XML format.

Older versions of usbmuxd used a binary format, but that's gone now, on macOS anyway,
which honestly is nice, because we can read PLists with our eyes.

each message consists of a 16 byte header split into 4 UInt32 fields defined like this :
```C
 typedef struct {
   uint32_t length;   // 16 + plist payload length
   uint32_t version;  // this is the version and it should be 1
   uint32_t type;     // message format, PList == 8
   uint32_t tag;      // response tag, this will only happen in OK/NOK messages
 }
 __attribute__((packed)) USBMuxdHeader;
```

The following bytes contain an XML encoded PList.

Some fun info on (some of) the format of the PList messages can be found at :

https://jon-gabilondo-angulo-7635.medium.com/understanding-usbmux-and-the-ios-lockdown-service-7f2a1dfd07ae

https://archive.is/uLAyw

Many of the fields are optional but will help if you are tracing.

If you need a ready made solution for communicating with your own (or other) 
apps that open sockets on a USB connected iPhone I suggest https://github.com/jensmeder/DarkLightning
which looks featureful and nice.

If you're interested in maybe poking usbmuxd yourself to see what happens, keep an 
eye on this repo as it develops.

If you'd like to snoop on usbmuxd to see what it is doing, there are instructions to do that
using socat in the above links. Or you can build an intercepting proxy yourself using the [example](https://github.com/SteveTrewick/GCDSocket?tab=readme-ov-file#intercepting-proxy-server) 
in GCDSocket


## Details

There aren't too many. Of note is that there is a C package included so that we can use a C
struct to encode and retrieve the usbmuxd header, we could 'just' do this with a swift codable, but 
who can be bothered, really?

The headers for lockdownd, which we also want to talk to are just a UInt32.

Since usbmuxd and lockdownd occasionaly fragment messages, at the very least sending only a header, 
or smooshes them all together in a single transmission I use a trivial state machine 
to process the responses.

This lives in PListParser. 



## Scope

In terms of the functionality that I personally need, most of it is here now.
The project scope here is to be able to :

* Enumerate USB connected devices
* Connect to lockdownd to retrieve a device name
* Connect to a running TCP service on the device

The first two of these are now complete (see examples below) and the third is trivial to implement with
the existing code base, so I'm going to start tagging releases. 

See also the issues tab.



## Examples

OK, how do we use it? This example also uses [GCDSocket](https://github.com/SteveTrewick/GCDSocket) 
for talking to the domain socket, which is also now a dependency in the swift package. 

## Listen/ListDevices - Old School Bare Calls

Using the base features we can do that like this. Note that the Listen call sends you a device message 
for each device that is already attached Note also the device list gives us an extra network connected device, 
I have two iPhones connected for this example and one is doing some wireless thangs. Funky.  Note especially that 
sending the Listen message more than once makes usbmuxd very, very unhappy, so don't do that.

```swift
import Foundation

import GCDSocket
import USBmuxd


// enumerate / listen for attach/detach using raw calls

// quick raw plist dumper
public struct RawPlist {
  public func dump ( tag: UInt32,  data: Data ) {
    var xml : PropertyListSerialization.PropertyListFormat = .xml
    if let any = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &xml) {
      print(tag, any)
    }
  }
}

let main      = DispatchQueue.main
let raw       = RawPlist()
let construct = GCDSocketConstructor()
let socket    = construct.domainSocketClient(path: "/var/run/usbmuxd")

let parser    = USBmuxd.PListParser(header: .muxd)
let message   = USBmuxd.MessageBuilder()

socket.dataHandler = { result in
  switch result {
    case .failure(let fail): main.async { print(fail) }
    case .success(let data): parser.process(data: data)
  }
}

parser.messageHandler = { result in
  switch result {
    case .failure(let fail)        : main.async { print(fail) }
    case .success(let (tag, data)) : main.async { raw.dump(tag: tag, data: data) }
  }
}

socket.connect()


// listen for attach/detach notifications
socket.write ( data: message.muxd(msg: MuxMessage(messageType: "Listen"), tag: 0xfe) )

// lets also grab a device list using the new Codable interface
socket.write ( data: message.muxd(msg: MuxMessage(messageType: "ListDevices"), tag: 0xfd) )

// run 4eva
RunLoop.current.run()

/*
254 {
    MessageType = Result;
    Number = 0;
}
0 {
    DeviceID = 5;
    MessageType = Attached;
    Properties =     {
        ConnectionSpeed = 480000000;
        ConnectionType = USB;
        DeviceID = 5;
        LocationID = 336592896;
        ProductID = 4776;
        SerialNumber = "00008030-001E752A22D2402E";
        UDID = "00008030-001E752A22D2402E";
        USBSerialNumber = 00008030001E752A22D2402E;
    };
}
0 {
    DeviceID = 1;
    MessageType = Attached;
    Properties =     {
        ConnectionSpeed = 480000000;
        ConnectionType = USB;
        DeviceID = 1;
        LocationID = 337641472;
        ProductID = 4776;
        SerialNumber = "00008120-0006696026A2201E";
        USBSerialNumber = 000081200006696026A2201E;
    };
}
253 {
    DeviceList =     (
                {
            DeviceID = 5;
            MessageType = Attached;
            Properties =             {
                ConnectionSpeed = 480000000;
                ConnectionType = USB;
                DeviceID = 5;
                LocationID = 336592896;
                ProductID = 4776;
                SerialNumber = "00008030-001E752A22D2402E";
                UDID = "00008030-001E752A22D2402E";
                USBSerialNumber = 00008030001E752A22D2402E;
            };
        },
                {
            DeviceID = 2;
            MessageType = Attached;
            Properties =             {
                ConnectionType = Network;
                DeviceID = 2;
                EscapedFullServiceName = "78:e3:de:10:ba:bc@fe80::7ae3:deff:fe10:babc._apple-mobdev2._tcp.local.";
                InterfaceIndex = 4;
                NetworkAddress = {length = 128, bytes = 0x1c1e0000 00000000 fe800000 00000000 ... 00000000 00000000 };
                SerialNumber = "00008030-001E752A22D2402E";
            };
        },
                {
            DeviceID = 1;
            MessageType = Attached;
            Properties =             {
                ConnectionSpeed = 480000000;
                ConnectionType = USB;
                DeviceID = 1;
                LocationID = 337641472;
                ProductID = 4776;
                SerialNumber = "00008120-0006696026A2201E";
                USBSerialNumber = 000081200006696026A2201E;
            };
        }
    );
}
*/
```


## Message Builder

`MessageBuilder` uses either a `[String : Any]` or a `Codable` type to generate message data. There
are also seperate calls for lockdownd and usbmuxd as they have differing headers. If you are wanting
to craft custom messages to fling, the dictionary approach will be useful, or go ahead and add a message type. 
If you only need things that are in `Messages.swift`, go with the codable. 

```swift

if let muxDictMsg = message.muxd (dict: ["MessageType" : "DeviceList"], tag: 0xcafe) {
  // do the thing
}

let muxCodMsg  = message.muxd (msg : MuxMessage(messageType: "DeviceList"), tag: 0xcafe)


if let locDictMsg = message.lockd ( dict: [ "Key" : "DeviceName", "Request" : "GetValue"] ) {
  // do the thing
}

let locCodMsg = message.lockd ( msg: LockdownRequest(key: "DeviceName", request: "GetValue") )
  
```

Note that the `Codable` versions don't return an optional type because I have dangerosuly assumed that anything that is
actually Codable will in fact encode. This is almost certainly not true, so best not to feed it arbitrary things until you test them.

`ResponseRouter` also makes use of the Codables, only in the other direction, see below.


## Listening for Devices - NotificationListener

Honestly though, if you are going to listen for the notifications, just do it like this, get your notifications
as concrete Device types and do things with them later using another socket.  Speaking of which, open 
as many as you like, one for everything, usbmuxd doesn't care, that's its job and it keeps your result paths clean.
Though in this case, the notifier takes care of that for you, which is nice.


```swift

import Foundation
import USBmuxd


var notification = USBmuxd.NotificationListener()

notification.notify = { result in
  switch result {
    
    case .failure(let fail)   : print(fail)
    
    case .success(let notify) :
      
      switch notify {
        case .detach(let id)     : print("DETACHED : \(id)")
        case .attach(let device) : print("ATTACHED : \(device)")
      }
  }
}
notification.connect()

// run 4eva
RunLoop.current.run()

/*
ATTACHED : Device(deviceID: 5, messageType: "Attached", properties: USBmuxd.DeviceProperties(connectionSpeed: Optional(480000000), connectionType: "USB", deviceID: 5, locationID: Optional(336592896), productID: Optional(4776), serialNumber: "00008030-001E752A22D2402E", usbSerialNumber: Optional("00008030001E752A22D2402E"), escapedFullServiceName: nil, interfaceIndex: nil, networkAddress: nil, udid: Optional("00008030-001E752A22D2402E")))
ATTACHED : Device(deviceID: 1, messageType: "Attached", properties: USBmuxd.DeviceProperties(connectionSpeed: Optional(480000000), connectionType: "USB", deviceID: 1, locationID: Optional(337641472), productID: Optional(4776), serialNumber: "00008120-0006696026A2201E", usbSerialNumber: Optional("000081200006696026A2201E"), escapedFullServiceName: nil, interfaceIndex: nil, networkAddress: nil, udid: nil))

... further messages if we mess with stuff

*/
```


## Enumerating Devices and Getting Names

One of the nain things we're here for right? Like this.

```swift

import Foundation
import USBmuxd


let enumerator = DeviceEnumerator()

enumerator.enumerateDevices { result  in

  switch result {

    case .failure(let fail)        : main.async { print(fail) }

    case .success(let descriptors) : main.async {
      
      // show only USB connected devices
      // avoiding any wireless sync type stubs that might show up
      for descriptor in descriptors {
        if descriptor.device.properties.connectionType == "USB" {
          print(descriptor)
        }
      }
    }
  }
}

// run 4eva
RunLoop.current.run()

/*
DeviceDescriptor(device: USBmuxd.Device(deviceID: 5, ... )), name: "iPhone SE")
DeviceDescriptor(device: USBmuxd.Device(deviceID: 1, ... )), name: "iPhone")
*/

```

```DeviceEnumerator``` is pretty complex, take a look! It uses a state machine to facillitate
async 'looping' and avoid some doom pyramids. In essence we open a muxd socket, get a device 
list then for each device in the list we open a new socket, send a connect message, swap out muxd
parser for a lockdownd one then ask for the name. `DeviceEnumerator` makes use of the `ResponseRouter`
which we will likely need if we are to complete bullet 3, connecting to a running TCP service on a device.
Let's have a look.


## Response Router

If we want actual sensible responses to our rquests we need to catch them, classify them, decode them
and do, er, things. To this end we have `ResponseRouter`. Each usbmuxd request we send gets a tag 
field in the header which usbmuxd will repeat back to us in the response, so if we decide to fire off multiple
requests we can keep track of them. To prime the router for our incoming response we give it a tag, an expected 
response type for decoding and a closure to process the generated result.

`ResponseRouter` currently knows about the following response types

```swift
public enum ResponseType {
  case deviceList, result, device, lockdResponse
}
```

Which correspond to `[Device]`, `MuxResult`, `Device` and `LockdownResponse` message types. When we send a 
regular request such as Connect, we get a result, 0 is all good, other numbers are errors.

In this example, we connect to a device we happen to know the ID for, send a connect message, check if it was OK
then we change our parser format to read lockdownd messages and send a lockdownd message to get the device name (which is how
`DeviceEnumertor` does it), catching it through our router.

The closures for the router are untyped, well, typed as `Any?` and so we must check/cast them.

Note that lockdownd does not use tags, so all are set 0.  The port for lockdownd on the device is 62078. 
Although in this example we are connecting to lockdownd, we could be connecting to any service which 
pretty much makes this feature complete per the scope. 

```swift

import GCDSocket
import USBmuxd

let construct = GCDSocketConstructor()
let socket    = construct.domainSocketClient(path: "/var/run/usbmuxd")
let parser    = USBmuxd.PListParser(header: .muxd)
let message   = USBmuxd.MessageBuilder()
let router    = USBmuxd.ResponseRouter()

socket.dataHandler = { result in
  switch result {
    case .failure(let fail): print (fail)
    case .success(let data): parser.process(data: data)
  }
}

parser.messageHandler = { result in
  switch result {
    case .failure(let fail)        : print (fail)
    case .success(let (tag, data)) : router.route(tag: tag, data: data)
  }
}

router.expect(tag: 0xdeadbeef, response: .result) { result in
  
  if let result = result as? MuxResult {
    
    print(result)
    
    if result.number == 0 {
      
      parser.setHeader(type: .lockd)
      
      router.expect(tag: 0, response: .lockdResponse) { response in
        if let response = response as? LockdownResponse {
          print(response)
        }
      }
      socket.write(data: message.lockd(msg: LockdownRequest(key: "DeviceName", request: "GetValue")))
    }
  }
}
socket.connect()
socket.write(data: message.muxd(msg: Connect(device: 1, port: 62078), tag: 0xdeadbeef))
  
// run 4eva
RunLoop.current.run()
```
