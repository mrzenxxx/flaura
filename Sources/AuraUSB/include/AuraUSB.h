#ifndef AURA_USB_H
#define AURA_USB_H

#include <stdint.h>

#pragma clang assume_nonnull begin

/// Opaque handle to a USB device user client.
typedef struct AuraUSBDevice AuraUSBDevice;

/// Opens a user client on the IOUSBHostDevice whose IORegistry entry ID is `registryEntryID`.
/// Control transfers on the default pipe do not need exclusive access, so the kernel HID
/// driver keeps working and no TCC permission is required.
/// Returns NULL and writes an IOReturn code to `outError` on failure.
AuraUSBDevice *_Nullable aura_usb_open(uint64_t registryEntryID, int32_t *_Nullable outError);

/// Performs a control transfer on the default pipe. Returns an IOReturn code (0 = success).
int32_t aura_usb_control(AuraUSBDevice *device,
                         uint8_t requestType,
                         uint8_t request,
                         uint16_t value,
                         uint16_t index,
                         void *_Nullable data,
                         uint16_t length,
                         uint32_t timeoutMilliseconds,
                         uint32_t *_Nullable transferred);

/// Releases the user client. Safe to call with NULL.
void aura_usb_close(AuraUSBDevice *_Nullable device);

#pragma clang assume_nonnull end

#endif
