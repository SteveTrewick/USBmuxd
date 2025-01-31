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


## Protocols

Both usbmuxd and lockdownd (hereafter, muxd and lockd) use an Apple XML format called 
Information Property Lists or PList for short. These are practically ubiquitous on Apple platforms.

There was a time when usbmuxd used a binary protocol but as of the moment, if you try to use it 
muxd on macOS will throw a huff and disconnect you.  On the one hand chucking XML requests around
feels very 90s, but on the other, we can read XML with our eyes which makes figuring what's going on 
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

import Foundation
import HexDump
import USBmuxd
import GCDSocket


let msgDict = ["MessageType":"ListDevices"]


let socket  = GCDSocketConstructor().domainSocketClient(path: "/var/run/usbmuxd")
let message = USBmuxd.MessageBuilder()
let parser  = USBmuxd.PListParser(header: .muxd)
let hex     = HexDump()


func dumpXML(_ data: Data) {
  if let xml = String(data: data, encoding: .utf8) {
    print(xml)
  }
}

socket.dataHandler = { result in
  switch result {
    case .failure(let fail): print(fail)
    case .success(let data):
       
        print ( hex.dump(data) )
        parser.process (data: data )
  }
}

parser.messageHandler = { result in
  switch result {
      case .failure(let fail)        : print(fail)
      case .success(let (tag, data)) :
        
        print(String(format:"%02x", tag))
        dumpXML(data)
  }
}

socket.connect()

let dlmsg = message.muxd(msg: MuxMessage(messageType: "ListDevices"), tag: 0xdeadbeef)

dumpXML(dlmsg[16...])
print( hex.dump(dlmsg) )

socket.write(data: dlmsg)

RunLoop.current.run()
```

# XML Request

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

