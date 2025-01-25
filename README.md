# USBmuxdCore

USBMuxdCore is an experimental, evolving and currently very bare set of swift routines for 
talking to the usbmux deamon on macOS which mediates communication between things
on your system and things on your USB connected iPhone.

usbmuxd lives at /var/run/usbmuxd as a Unix domain socket.

usbmuxd messages are pretty simple, while things can get complex on the bus
with all the lockdownd etc binary and SSL chat, the basic usbnuxd part is
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

Not yet covered is talking to lockdownd on the phone, via which we can retrieve such things
as the name of connected devices. lockdownd also uses a PList format but with a 4 byte header.
I haven't written the parser yet but it is trivial and will be along soon.

More information will be added to this repo about message formats and the like as we go along.
If you'd like to snoop on usbmuxd to see what it is doing, there are instructions to do that
using socat in the above links.

## Details

There aren't too many. Of note is that there is a C package included so that we can use a C
struct to encode and retrieve the header, we could 'just' do this with a swift codable, but 
who can be bothered, really?

The message builder simply serializes a dict to an XML PList and smooshes it along with 
the appropriate header bytes.

Since usbmuxd occasionaly fragments messages, at the very lest sending only a header, 
or smooshes them all together is a single transmission I use a trivial state machine 
to process the response. 

## Future

The future scope for this project includes (and is probably, but not necessarily, limited to)
adding the facility to talk to lockdownd on the phone to retrieve the device name and connecting
to services on the phone given a port number (NB that in the PList these are big endian, so
for instance lockdownd lives on port 62708, 0xf27e but the number we need to pass in the PList is
0x7ef2 = 32498).

See also the issues tab.

## Example

OK, how do we use it? This example also uses [GCDSocket](https://github.com/SteveTrewick/GCDSocket) 
for talking to the domain socket and [HexDump](https://github.com/SteveTrewick/HexDump) for 
dumping the data.

We send a simple ListDevices message and usbmuxd responds with a list of connected devices.


```swift

import Foundation

import HexDump
import GCDSocket
import USBmuxdCore

/*
  template for the foundation of yakking it up with usbmuxd
*/

let sox = GCDSocketConstructor()

let socket  = sox.domainSocketClient(path: "/var/run/usbmuxd")
let message = MessageBuilder()
let hex     = HexDump()
let machine = MuxMessageMachine()  // recieved messages are processed in a state machine
                                   // to guard against fragmentation


socket.dataHandler = { result in
  switch result {
    
    case .failure(let fail): print ( "fail: \(fail)")
    
    case .success(let data):
      
      // show me the hexies
      print ( "recv: \(data.count) \n\(hex.dump(bytes: Array(data)))" )
      
      // stuff the data in the state machine for parsing
      machine.process(data: data)
  }
}

/*
  the state machine will emit a result when ever it has a full message
*/
machine.messageHandler = { result in
  switch result {
    case .failure(let fail) : print( "fail \(fail)" )
    case .success(let dict) : print(dict as CFDictionary) // CFDict has better debug format <shrug>
  }
}


socket.connect()


/*
  We could also send ["MessageType" : "Listen"], and then usbmuxd will send us
  this same list, and then a message every time a device is connected or disconnected

  We append a tag to every message we send, this will be echoed back to us in a direct
  response, but not in packets that are sent as the result of (e.g.) a listen message
 
  If you get anything wrong in your request, usbmuxd may or may not send an error message
  and then will close the connection. Rude!
  
*/

if let list = message.build(from:  ["MessageType" : "ListDevices"], tag: 0xdeadbeef ) {
  socket.write(data: list)
}



// run 4eva
dispatchMain()

/*
recv: 847 
4f 03 00 00 01 00 00 00 08 00 00 00 ef be ad de  O...............
3c 3f 78 6d 6c 20 76 65 72 73 69 6f 6e 3d 22 31  <?xml.version="1
2e 30 22 20 65 6e 63 6f 64 69 6e 67 3d 22 55 54  .0".encoding="UT
46 2d 38 22 3f 3e 0a 3c 21 44 4f 43 54 59 50 45  F-8"?>.<!DOCTYPE
20 70 6c 69 73 74 20 50 55 42 4c 49 43 20 22 2d  .plist.PUBLIC."-
2f 2f 41 70 70 6c 65 2f 2f 44 54 44 20 50 4c 49  //Apple//DTD.PLI
53 54 20 31 2e 30 2f 2f 45 4e 22 20 22 68 74 74  ST.1.0//EN"."htt
70 3a 2f 2f 77 77 77 2e 61 70 70 6c 65 2e 63 6f  p://www.apple.co
6d 2f 44 54 44 73 2f 50 72 6f 70 65 72 74 79 4c  m/DTDs/PropertyL
69 73 74 2d 31 2e 30 2e 64 74 64 22 3e 0a 3c 70  ist-1.0.dtd">.<p
6c 69 73 74 20 76 65 72 73 69 6f 6e 3d 22 31 2e  list.version="1.
30 22 3e 0a 3c 64 69 63 74 3e 0a 09 3c 6b 65 79  0">.<dict>..<key
3e 44 65 76 69 63 65 4c 69 73 74 3c 2f 6b 65 79  >DeviceList</key
3e 0a 09 3c 61 72 72 61 79 3e 0a 09 09 3c 64 69  >..<array>...<di
63 74 3e 0a 09 09 09 3c 6b 65 79 3e 44 65 76 69  ct>....<key>Devi
63 65 49 44 3c 2f 6b 65 79 3e 0a 09 09 09 3c 69  ceID</key>....<i
6e 74 65 67 65 72 3e 34 32 3c 2f 69 6e 74 65 67  nteger>42</integ
65 72 3e 0a 09 09 09 3c 6b 65 79 3e 4d 65 73 73  er>....<key>Mess
61 67 65 54 79 70 65 3c 2f 6b 65 79 3e 0a 09 09  ageType</key>...
09 3c 73 74 72 69 6e 67 3e 41 74 74 61 63 68 65  .<string>Attache
64 3c 2f 73 74 72 69 6e 67 3e 0a 09 09 09 3c 6b  d</string>....<k
65 79 3e 50 72 6f 70 65 72 74 69 65 73 3c 2f 6b  ey>Properties</k
65 79 3e 0a 09 09 09 3c 64 69 63 74 3e 0a 09 09  ey>....<dict>...
09 09 3c 6b 65 79 3e 43 6f 6e 6e 65 63 74 69 6f  ..<key>Connectio
6e 53 70 65 65 64 3c 2f 6b 65 79 3e 0a 09 09 09  nSpeed</key>....
09 3c 69 6e 74 65 67 65 72 3e 34 38 30 30 30 30  .<integer>480000
30 30 30 3c 2f 69 6e 74 65 67 65 72 3e 0a 09 09  000</integer>...
09 09 3c 6b 65 79 3e 43 6f 6e 6e 65 63 74 69 6f  ..<key>Connectio
6e 54 79 70 65 3c 2f 6b 65 79 3e 0a 09 09 09 09  nType</key>.....
3c 73 74 72 69 6e 67 3e 55 53 42 3c 2f 73 74 72  <string>USB</str
69 6e 67 3e 0a 09 09 09 09 3c 6b 65 79 3e 44 65  ing>.....<key>De
76 69 63 65 49 44 3c 2f 6b 65 79 3e 0a 09 09 09  viceID</key>....
09 3c 69 6e 74 65 67 65 72 3e 34 32 3c 2f 69 6e  .<integer>42</in
74 65 67 65 72 3e 0a 09 09 09 09 3c 6b 65 79 3e  teger>.....<key>
4c 6f 63 61 74 69 6f 6e 49 44 3c 2f 6b 65 79 3e  LocationID</key>
0a 09 09 09 09 3c 69 6e 74 65 67 65 72 3e 33 33  .....<integer>33
37 36 34 31 34 37 32 3c 2f 69 6e 74 65 67 65 72  7641472</integer
3e 0a 09 09 09 09 3c 6b 65 79 3e 50 72 6f 64 75  >.....<key>Produ
63 74 49 44 3c 2f 6b 65 79 3e 0a 09 09 09 09 3c  ctID</key>.....<
69 6e 74 65 67 65 72 3e 34 37 37 36 3c 2f 69 6e  integer>4776</in
74 65 67 65 72 3e 0a 09 09 09 09 3c 6b 65 79 3e  teger>.....<key>
53 65 72 69 61 6c 4e 75 6d 62 65 72 3c 2f 6b 65  SerialNumber</ke
79 3e 0a 09 09 09 09 3c 73 74 72 69 6e 67 3e 30  y>.....<string>0
30 30 30 38 31 32 30 2d 30 30 30 36 36 39 36 30  000XXX0-000XXXX0
32 36 41 32 32 30 31 45 3c 2f 73 74 72 69 6e 67  XXXXXXXX</string
3e 0a 09 09 09 09 3c 6b 65 79 3e 55 53 42 53 65  >.....<key>USBSe
72 69 61 6c 4e 75 6d 62 65 72 3c 2f 6b 65 79 3e  rialNumber</key>
0a 09 09 09 09 3c 73 74 72 69 6e 67 3e 30 30 30  .....<string>000
30 38 31 32 30 30 30 30 36 36 39 36 30 32 36 41  0XXX0000XXXX0XXX
32 32 30 31 45 3c 2f 73 74 72 69 6e 67 3e 0a 09  XXXX</string>..
09 09 3c 2f 64 69 63 74 3e 0a 09 09 3c 2f 64 69  ..</dict>...</di
63 74 3e 0a 09 3c 2f 61 72 72 61 79 3e 0a 3c 2f  ct>..</array>.</
64 69 63 74 3e 0a 3c 2f 70 6c 69 73 74 3e 0a     dict>.</plist>.
{
    DeviceList =     (
                {
            DeviceID = 42;
            MessageType = Attached;
            Properties =             {
                ConnectionSpeed = 480000000;
                ConnectionType = USB;
                DeviceID = 42;
                LocationID = 337641472;
                ProductID = 4776;
                SerialNumber = "0000XXX0-000XXXX0XXXXX0XX";     // obfuscated by me
                USBSerialNumber = 0000XXX0000XXXX0XXXXX0XX;
            };
        }
    );
}
*/
```
