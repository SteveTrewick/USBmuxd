// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "USBmuxd",
    products: [ .library( name: "USBmuxd", targets: ["USBmuxd"] ), ],
    dependencies: [ ],
    targets: [
       
      .target(
          name: "USBmuxd",
          dependencies: ["USBMuxdHeader"],
          path: "Sources/USBmuxd"
      ),
      
      .target(
        name: "USBMuxdHeader",
        path: "Sources/USBMuxdHeader"
      )
    ]
)
