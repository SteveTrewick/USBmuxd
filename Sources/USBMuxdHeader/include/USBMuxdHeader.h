
#ifndef USBMuxdHeader_h
#define USBMuxdHeader_h

#include <stdint.h>

typedef struct {
  uint32_t length;   // 16 + plist payload
  uint32_t version;  // this is the version and it should be 1
  uint32_t type;     // 8, PLIST BAYBEE
  uint32_t tag;      // response tag, this will only happen in OK/NOK messages
}
__attribute__((packed)) USBMuxdHeader;

#endif /* USBMuxdHeader_h */
