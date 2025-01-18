#include "USBMuxdHeader.h"

/*
  this is a fakey kind of bridging header, since you're interested.
  note that we have a C dependency in our swift package!
 
  all the stuff we actualy want is in includes/descriptors.h
  and is all C structs. we have to use c structs becuase we have to pack them
  to get them filled from pointers, and swift (in the version I'm stuck on
  at least) still won't do that.
 
  anyway, if you want to know how that works have a look at
  
    this blog         : https://www.bensnider.com/posts/wrapping-c-code-within-a-single-swift-package/
    this forum thread : https://forums.swift.org/t/swift-package-and-xcframework-target-for-c-library-where-to-include-the-header/51163
    
  or just peak at the Package.swift and the file layout, which is actually kind of important,
  as it turns out.

 */
