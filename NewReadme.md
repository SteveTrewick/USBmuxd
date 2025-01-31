# USBmuxd
 
 USBMuxd is a swift 5.5 package for communicating with the USB Multiplexing Daemon, primarily on macoS.
 
 Using USBMuxd you can :
 
 * Enumerate USB attached devices.
 * Monitor devices being connected and disconnected.
 * Communicate with running TCP services on USB connected devices.
 * Communicate with the lockdownd service on iOS devices to query device info.
 
 
## Libraries You Should Probably Use Instead

USBMuxd has a very limited scope and most of the fancy things you might want to do probably involve
talking to lockdownd. Well maintained featureful projects are 

* Cross Platform C : https://libimobiledevice.org
* Swift : https://github.com/jensmeder/DarkLightning

## Example - 

## Example - 


## Protocols

Both usbmuxd and lockdownd (hereafter, muxd and lockd) use an Apple XML format called 
Information Property Lists or PList for short. These are practically ubiquitous on Apple platforms.

There was a time when usbmuxd used a binary protocol but as of the moment, if you try to use it 
muxd on macOS will throw a huff and disconnect you.  On the one hand chucking XML requests around
feels very 90s enterprisey, but on the other, we can read XML with our eyes which makes figuring what's going on 
in packet traces much easier.

I started out with nformation from the [Apple Wiki](https://theapplewiki.com/wiki/Usbmux) ([Archive](https://archive.is/6Mu0D))
and from [This](https://jon-gabilondo-angulo-7635.medium.com/understanding-usbmux-and-the-ios-lockdown-service-7f2a1dfd07ae)
Medium article ([Archive](https://archive.is/uLAyw)) but really to figure it out you're going to want to proxy 
the domain socket and watch what's going on. You can do this with the neat socket tool socat

```bash
$ sudo mv /var/run/usbmuxd /var/run/usbmuxd_real
$ sudo socat -t100 -x -v UNIX-LISTEN:/var/run/usbmuxd,mode=777,reuseaddr,fork UNIX-CONNECT:/var/run/usbmux_real
When you are done do not forget to:
$ sudo mv /var/run/usbmuxd_real /var/run/usbmuxd
```

Anyway, lets have a look. We'll send a "ListDevices" message and look at the message and response

```swift

func dumpXML (_ data: Data ) -> String { String(data: data, encoding: .utf8) ?? "" }

socket.dataHandler = { result in
  switch result {
    case .failure(let fail): print(fail)
    case .success(let data): print ( hex.dump(data) ); parser.process (data: data )
  }
}

parser.messageHandler = { result in
  switch result {
      case .failure(let fail) : print(fail)
      case .success(let (tag, data)) : print(String(format:"%02x", tag));  print( dumpXML(data) )
  }
}

socket.connect()

let dlmsg = message.muxd(msg: MuxMessage(messageType: "ListDevices"), tag: 0xdeadbeef)

print ( dumpXML( dlmsg[16...] )) // avoid header
print ( hex.dump(dlmsg)        )

socket.write(data: dlmsg)

RunLoop.current.run() //4eva

```

## XML Request

The XML we just generated looks like this, pretty noisy TBH.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>MessageType</key>
  <string>ListDevices</string>
</dict>
</plist>
```

## Data Packet

To actually send that out on the wire we need to prepend a 16 byte header

```
02 01 00 00 01 00 00 00 08 00 00 00 ef be ad de  ................


3c 3f 78 6d 6c 20 76 65 72 73 69 6f 6e 3d 22 31  <?xml.version="1
...
0a 3c 2f 64 69 63 74 3e 0a 3c 2f 70 6c 69 73 74  .</dict>.</plist
3e 0a                                            >.
```

## USBmuxd Header

The header is defined thusly, in fact, exactly thusly as there is a C target in Sources/USBMuxdHeader
which defines exactly this struct. We have 4 x 4 byte fields, usbmuxd uses little endian. Lockdownd, does not.

```c
 typedef struct {
   uint32_t length;   // 16 + plist payload length
   uint32_t version;  // this is the version and it should be 1
   uint32_t type;     // message format, PList == 8
   uint32_t tag;      // response tag, this will only happen in OK/NOK messages
 }
 __attribute__((packed)) USBMuxdHeader;
```

From our actual header above we can see the following values 

```c
length  = 0x00000102 // 258
version = 0x00000001
type    = 0x00000008
tag     = 0xdeadbeef
```

Usbmuxd includes the 16 byte length of the header in the length field so our 242 bytes of XML
gives us 258. Version and type fields will always (until they aren't) be set to 1 and 8 respectively.
The tag field allows us to distinguish which of our requests usbmuxd is responding to. We add it
to our request and the response will carry the same tag. Note however that if we issue a 'Listen' request
the notifications we recieve will always have tag == 0. 

## Response Data Packet

In return we get a similar packet indicating 847 total bytes and including our tag.

```
4f 03 00 00 01 00 00 00 08 00 00 00 ef be ad de  O...............

3c 3f 78 6d 6c 20 76 65 72 73 69 6f 6e 3d 22 31  <?xml.version="1
2e 30 22 20 65 6e 63 6f 64 69 6e 67 3d 22 55 54  .0".encoding="UT
...
64 69 63 74 3e 0a 3c 2f 70 6c 69 73 74 3e 0a     dict>.</plist>.
```

## Response XML

In our XML resposne we get what swift would call a `[String : Any]` where the value for key DeviceList
is a `[ [String: Any] ]`. Awesome. XML is fun! For reasons, macOS lacks the fancier XML parsing facilities
that exist on iOS (at least on the version I'm stranded on) so I have leaned heavily into Codable 
to encode/decode these messages.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>DeviceList</key>
  <array>
    <dict>
      <key>DeviceID</key>
      <integer>38</integer>
      <key>MessageType</key>
      <string>Attached</string>
      <key>Properties</key>
      <dict>
        <key>ConnectionSpeed</key>
        <integer>480000000</integer>
        <key>ConnectionType</key>
        <string>USB</string>
        <key>DeviceID</key>
        <integer>38</integer>
        <key>LocationID</key>
        <integer>337641472</integer>
        <key>ProductID</key>
        <integer>4776</integer>
        <key>SerialNumber</key>
        <string>00008120-0006696026A2201E</string>
        <key>USBSerialNumber</key>
        <string>000081200006696026A2201E</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>

```
