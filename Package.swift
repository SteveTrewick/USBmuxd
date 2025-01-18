// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "USBmuxdCore",
    products: [ .library( name: "USBmuxdCore", targets: ["USBmuxdCore"] ), ],
    dependencies: [ ],
    targets: [
       
      .target(
          name: "USBmuxdCore",
          dependencies: ["USBMuxdHeader"],
          path: "Sources/USBmuxdCore"
      ),
      
      .target(
        name: "USBMuxdHeader",
        path: "Sources/USBMuxdHeader"
      )
    ]
)
