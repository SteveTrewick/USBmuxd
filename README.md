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

As of the initial release this library supports encoding a PList message from a dictionary
and parsing the header and PList resposne and really nothing else.

If you need a ready made solution for communicating with your own (or other) 
apps that open sockets on a USB connected iPhone I suggest https://github.com/jensmeder/DarkLightning
which looks featureful and nice.

If you're interested in maybe poking usbmuxd yourself to see what happens, keep an 
eye on this repo as it develops.

There is now a parser for lockdownd messages as well, but not yet a way to talk to it. 
That will be added soon.

More information will be added to this repo about message formats and the like as we go along.
If you'd like to snoop on usbmuxd to see what it is doing, there are instructions to do that
using socat in the above links.

## Details

There aren't too many. Of note is that there is a C package included so that we can use a C
struct to encode and retrieve the usbmuxd header, we could 'just' do this with a swift codable, but 
who can be bothered, really?

The headers for lockdownd, which we also want to talk to are just a UInr32.

As it turns out though, we do have a use for Codable in encoding and decoding PLists. More on that later.


Since usbmuxd and lockdownd occasionaly fragment messages, at the very least sending only a header, 
or smooshes them all together in a single transmission I use a trivial state machine 
to process the responses.

This lives in PListParser. 



## Future

In terms of the functionality that I personally need, most of it is there now.
The project scope here is to be able to :

* Enumerate USB connected devices
* Connect to lockdownd to retrieve a device name
* Connect to a running TCP service on the device

The first two of these are now complete (see examples below) and the third is trivial to implment with
the existing code bas, so I'm going to start tagging releases. 

See also the issues tab.



## Examples

OK, how do we use it? This example also uses [GCDSocket](https://github.com/SteveTrewick/GCDSocket) 
for talking to the domain socket, which is also now a dependency in the swift package. 

## Listen/ListDevices - old school bare calls

Using the base features we can do that like this

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
```
