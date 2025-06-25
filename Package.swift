// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name        : "USBmuxd",
    products    : [ .library( name: "USBmuxd", targets: ["USBmuxd"] ), ],
    dependencies: [
      .package(name: "GCDSocket", url: "https://github.com/SteveTrewick/GCDSocket", from: "1.1.0")
    ],
    targets: [
       
      .target(
          name: "USBmuxd",
          dependencies: ["USBMuxdHeader", "GCDSocket"],
          path: "Sources/USBmuxd"
      ),
      
      .target(
        name: "USBMuxdHeader",
        path: "Sources/USBMuxdHeader"
      )
    ]
)
