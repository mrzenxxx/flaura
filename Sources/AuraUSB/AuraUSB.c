#include "AuraUSB.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdlib.h>

struct AuraUSBDevice {
    IOUSBDeviceInterface182 **interface;
};

AuraUSBDevice *aura_usb_open(uint64_t registryEntryID, int32_t *outError) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryEntryID));
    if (service == IO_OBJECT_NULL) {
        if (outError) *outError = kIOReturnNoDevice;
        return NULL;
    }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t result = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID,
                                                             kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (result != kIOReturnSuccess || plugin == NULL) {
        if (outError) *outError = result != kIOReturnSuccess ? result : kIOReturnError;
        return NULL;
    }

    IOUSBDeviceInterface182 **interface = NULL;
    HRESULT queried = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID182),
                                                (LPVOID *)&interface);
    (*plugin)->Release(plugin);
    if (queried != S_OK || interface == NULL) {
        if (outError) *outError = kIOReturnUnsupported;
        return NULL;
    }

    AuraUSBDevice *device = calloc(1, sizeof(AuraUSBDevice));
    if (device == NULL) {
        (*interface)->Release(interface);
        if (outError) *outError = kIOReturnNoMemory;
        return NULL;
    }
    device->interface = interface;
    if (outError) *outError = kIOReturnSuccess;
    return device;
}

int32_t aura_usb_control(AuraUSBDevice *device, uint8_t requestType, uint8_t request, uint16_t value,
                         uint16_t index, void *data, uint16_t length, uint32_t timeoutMilliseconds,
                         uint32_t *transferred) {
    IOUSBDevRequestTO transfer = {
        .bmRequestType = requestType,
        .bRequest = request,
        .wValue = value,
        .wIndex = index,
        .wLength = length,
        .pData = data,
        .wLenDone = 0,
        .noDataTimeout = timeoutMilliseconds,
        .completionTimeout = timeoutMilliseconds,
    };
    IOReturn result = (*device->interface)->DeviceRequestTO(device->interface, &transfer);
    if (transferred) *transferred = transfer.wLenDone;
    return result;
}

void aura_usb_close(AuraUSBDevice *device) {
    if (device == NULL) return;
    (*device->interface)->Release(device->interface);
    free(device);
}
