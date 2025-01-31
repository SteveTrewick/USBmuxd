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

If you want to write your own you can have a look at the sample in [GCDSocket](https://github.com/SteveTrewick/GCDSocket?tab=readme-ov-file#intercepting-proxy-server)
which USBmuxd depends upon, though a proper trace will require stateful connection tracking to detect, amongst other
things, when a client has transitioned to connection to lockd or initiated an SSL connection.

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

## Request Data Packet

To actually send that out on the wire we need to prepend a 16 byte header

```
02 01 00 00 01 00 00 00 08 00 00 00 ef be ad de  ................
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
3e 4d 65 73 73 61 67 65 54 79 70 65 3c 2f 6b 65  >MessageType</ke
79 3e 0a 09 3c 73 74 72 69 6e 67 3e 4c 69 73 74  y>..<string>List
44 65 76 69 63 65 73 3c 2f 73 74 72 69 6e 67 3e  Devices</string>
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

In return we get a similar packet indicating 847 total bytes (including the header) and including our tag.

```
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
6e 74 65 67 65 72 3e 33 38 3c 2f 69 6e 74 65 67  nteger>38</integ
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
09 3c 69 6e 74 65 67 65 72 3e 33 38 3c 2f 69 6e  .<integer>38</in
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
30 30 30 38 31 32 30 2d 30 30 30 36 36 39 36 30  0008120-00066960
32 36 41 32 32 30 31 45 3c 2f 73 74 72 69 6e 67  26A2201E</string
3e 0a 09 09 09 09 3c 6b 65 79 3e 55 53 42 53 65  >.....<key>USBSe
72 69 61 6c 4e 75 6d 62 65 72 3c 2f 6b 65 79 3e  rialNumber</key>
0a 09 09 09 09 3c 73 74 72 69 6e 67 3e 30 30 30  .....<string>000
30 38 31 32 30 30 30 30 36 36 39 36 30 32 36 41  081200006696026A
32 32 30 31 45 3c 2f 73 74 72 69 6e 67 3e 0a 09  2201E</string>..
09 09 3c 2f 64 69 63 74 3e 0a 09 09 3c 2f 64 69  ..</dict>...</di
63 74 3e 0a 09 3c 2f 61 72 72 61 79 3e 0a 3c 2f  ct>..</array>.</
64 69 63 74 3e 0a 3c 2f 70 6c 69 73 74 3e 0a     dict>.</plist>.
```

## Response XML

In our XML resposne we get what swift would call a `[String : Any]` where the value for key DeviceList
is a `[ [String: Any] ]`. Awesome. XML is fun! For reasons, macOS lacks the fancier XML parsing facilities
that exist on iOS (at least on the version I'm stranded on) so I have leaned heavily into Codable 
to encode/decode these messages.

I had only the one iPhone connected for this, since otherwise these will get very long. An important note though
is that many of these fields are optional and not all of them are represented in this one response. For example
I have an iPhone SE that presents an additional wireless interface and includes a UDID field.

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

## Listening For Device Connections

Using the exact same as bove, we send a "Listen" message, usbmuxd will now do several things :

1. Send us an OK message.
2. Send us a message for every device that is currently connected.
3. Send us a message every time a device is connected or disconnected.

## Listen XML Message

We wont do the full packet trace for this one, here's the XML.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>MessageType</key>
  <string>Listen</string>
</dict>
</plist>
```

## Listen Response Data Packet

Here is the response, note that this one has our tag in it.

```
26 01 00 00 01 00 00 00 08 00 00 00 ef be ad de  &...............
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
3e 4d 65 73 73 61 67 65 54 79 70 65 3c 2f 6b 65  >MessageType</ke
79 3e 0a 09 3c 73 74 72 69 6e 67 3e 52 65 73 75  y>..<string>Resu
6c 74 3c 2f 73 74 72 69 6e 67 3e 0a 09 3c 6b 65  lt</string>..<ke
79 3e 4e 75 6d 62 65 72 3c 2f 6b 65 79 3e 0a 09  y>Number</key>..
3c 69 6e 74 65 67 65 72 3e 30 3c 2f 69 6e 74 65  <integer>0</inte
67 65 72 3e 0a 3c 2f 64 69 63 74 3e 0a 3c 2f 70  ger>.</dict>.</p
6c 69 73 74 3e 0a                                list>.
```

## XML Response

When we extract the XML (or our actual representation) we see that this time, we have a result with a number
attached. In a familar pattern, if this number is non zero it indicates an error. Error codes are described below.
In this case, we're all good. usbmuxd will now send us notifications.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>MessageType</key>
  <string>Result</string>
  <key>Number</key>
  <integer>0</integer>
</dict>
</plist>
```

## Notification Data Packets - Connected Devices

Look like this, note the lack of a tag? All notifications from here on in will have tag == 0

```
e8 02 00 00 01 00 00 00 08 00 00 00 00 00 00 00  ................
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
3e 44 65 76 69 63 65 49 44 3c 2f 6b 65 79 3e 0a  >DeviceID</key>.
09 3c 69 6e 74 65 67 65 72 3e 33 38 3c 2f 69 6e  .<integer>38</in
74 65 67 65 72 3e 0a 09 3c 6b 65 79 3e 4d 65 73  teger>..<key>Mes
73 61 67 65 54 79 70 65 3c 2f 6b 65 79 3e 0a 09  sageType</key>..
3c 73 74 72 69 6e 67 3e 41 74 74 61 63 68 65 64  <string>Attached
3c 2f 73 74 72 69 6e 67 3e 0a 09 3c 6b 65 79 3e  </string>..<key>
50 72 6f 70 65 72 74 69 65 73 3c 2f 6b 65 79 3e  Properties</key>
0a 09 3c 64 69 63 74 3e 0a 09 09 3c 6b 65 79 3e  ..<dict>...<key>
43 6f 6e 6e 65 63 74 69 6f 6e 53 70 65 65 64 3c  ConnectionSpeed<
2f 6b 65 79 3e 0a 09 09 3c 69 6e 74 65 67 65 72  /key>...<integer
3e 34 38 30 30 30 30 30 30 30 3c 2f 69 6e 74 65  >480000000</inte
67 65 72 3e 0a 09 09 3c 6b 65 79 3e 43 6f 6e 6e  ger>...<key>Conn
65 63 74 69 6f 6e 54 79 70 65 3c 2f 6b 65 79 3e  ectionType</key>
0a 09 09 3c 73 74 72 69 6e 67 3e 55 53 42 3c 2f  ...<string>USB</
73 74 72 69 6e 67 3e 0a 09 09 3c 6b 65 79 3e 44  string>...<key>D
65 76 69 63 65 49 44 3c 2f 6b 65 79 3e 0a 09 09  eviceID</key>...
3c 69 6e 74 65 67 65 72 3e 33 38 3c 2f 69 6e 74  <integer>38</int
65 67 65 72 3e 0a 09 09 3c 6b 65 79 3e 4c 6f 63  eger>...<key>Loc
61 74 69 6f 6e 49 44 3c 2f 6b 65 79 3e 0a 09 09  ationID</key>...
3c 69 6e 74 65 67 65 72 3e 33 33 37 36 34 31 34  <integer>3376414
37 32 3c 2f 69 6e 74 65 67 65 72 3e 0a 09 09 3c  72</integer>...<
6b 65 79 3e 50 72 6f 64 75 63 74 49 44 3c 2f 6b  key>ProductID</k
65 79 3e 0a 09 09 3c 69 6e 74 65 67 65 72 3e 34  ey>...<integer>4
37 37 36 3c 2f 69 6e 74 65 67 65 72 3e 0a 09 09  776</integer>...
3c 6b 65 79 3e 53 65 72 69 61 6c 4e 75 6d 62 65  <key>SerialNumbe
72 3c 2f 6b 65 79 3e 0a 09 09 3c 73 74 72 69 6e  r</key>...<strin
67 3e 30 30 30 30 38 31 32 30 2d 30 30 30 36 36  g>00008120-00066
39 36 30 32 36 41 32 32 30 31 45 3c 2f 73 74 72  96026A2201E</str
69 6e 67 3e 0a 09 09 3c 6b 65 79 3e 55 53 42 53  ing>...<key>USBS
65 72 69 61 6c 4e 75 6d 62 65 72 3c 2f 6b 65 79  erialNumber</key
3e 0a 09 09 3c 73 74 72 69 6e 67 3e 30 30 30 30  >...<string>0000
38 31 32 30 30 30 30 36 36 39 36 30 32 36 41 32  81200006696026A2
32 30 31 45 3c 2f 73 74 72 69 6e 67 3e 0a 09 3c  201E</string>..<
2f 64 69 63 74 3e 0a 3c 2f 64 69 63 74 3e 0a 3c  /dict>.</dict>.<
2f 70 6c 69 73 74 3e 0a                          /plist>.
```

## Notification XML - Connected Devices

We will receive one of these for each device currently connected.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
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
</plist>
```

## Notification XML - Disonnected Devices

OK, let's unplug something and see what we get.

```
2b 01 00 00 01 00 00 00 08 00 00 00 00 00 00 00  +...............
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
3e 44 65 76 69 63 65 49 44 3c 2f 6b 65 79 3e 0a  >DeviceID</key>.
09 3c 69 6e 74 65 67 65 72 3e 33 38 3c 2f 69 6e  .<integer>38</in
74 65 67 65 72 3e 0a 09 3c 6b 65 79 3e 4d 65 73  teger>..<key>Mes
73 61 67 65 54 79 70 65 3c 2f 6b 65 79 3e 0a 09  sageType</key>..
3c 73 74 72 69 6e 67 3e 44 65 74 61 63 68 65 64  <string>Detached
3c 2f 73 74 72 69 6e 67 3e 0a 3c 2f 64 69 63 74  </string>.</dict
3e 0a 3c 2f 70 6c 69 73 74 3e 0a                 >.</plist>.
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>DeviceID</key>
  <integer>38</integer>
  <key>MessageType</key>
  <string>Detached</string>
</dict>
</plist>

```
