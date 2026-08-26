#include "SensorBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

typedef CFTypeRef (*HIDCreateFn)(CFAllocatorRef);
typedef int (*HIDSetMatchingFn)(CFTypeRef, CFDictionaryRef);
typedef CFArrayRef (*HIDCopyServicesFn)(CFTypeRef);
typedef CFTypeRef (*HIDCopyEventFn)(CFTypeRef, int64_t, int32_t, int64_t);
typedef double (*HIDGetFloatFn)(CFTypeRef, int32_t);
typedef CFTypeRef (*HIDCopyPropertyFn)(CFTypeRef, CFStringRef);

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef union {
    char chars[4];
    uint32_t raw;
} SMCFourChar;

typedef struct {
    uint32_t dataSize;
    SMCFourChar dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    SMCFourChar key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

enum {
    SMCSelector = 2,
    SMCReadBytes = 5,
    SMCReadKeyInfo = 9,
    HIDTemperatureEvent = 15
};

static SMCFourChar fourChar(const char key[4]) {
    SMCFourChar value = { .raw =
        ((uint32_t)(uint8_t)key[0] << 24) |
        ((uint32_t)(uint8_t)key[1] << 16) |
        ((uint32_t)(uint8_t)key[2] << 8) |
        (uint32_t)(uint8_t)key[3]
    };
    return value;
}

static void typeName(SMCFourChar type, char output[5]) {
    output[0] = (char)((type.raw >> 24) & 0xff);
    output[1] = (char)((type.raw >> 16) & 0xff);
    output[2] = (char)((type.raw >> 8) & 0xff);
    output[3] = (char)(type.raw & 0xff);
    output[4] = '\0';
}

static io_connect_t openSMC(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
    }
    if (!service) return IO_OBJECT_NULL;

    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS ? connection : IO_OBJECT_NULL;
}

static bool readSMCKey(io_connect_t connection, const char key[4], SMCKeyInfo *info, uint8_t bytes[32]) {
    if (connection == IO_OBJECT_NULL || !key || !bytes) return false;

    SMCParam input = {0};
    SMCParam output = {0};
    input.key = fourChar(key);
    input.data8 = SMCReadKeyInfo;
    size_t outputSize = sizeof(output);

    kern_return_t result = IOConnectCallStructMethod(
        connection, SMCSelector, &input, sizeof(input), &output, &outputSize
    );
    if (result != KERN_SUCCESS || output.result != 0 ||
        output.keyInfo.dataSize == 0 || output.keyInfo.dataSize > sizeof(output.bytes)) return false;

    input.keyInfo.dataSize = output.keyInfo.dataSize;
    input.data8 = SMCReadBytes;
    memset(&output, 0, sizeof(output));
    outputSize = sizeof(output);
    result = IOConnectCallStructMethod(
        connection, SMCSelector, &input, sizeof(input), &output, &outputSize
    );
    if (result != KERN_SUCCESS || output.result != 0) return false;

    if (info) *info = output.keyInfo.dataSize ? output.keyInfo : input.keyInfo;
    if (info && info->dataType.raw == 0) {
        SMCParam keyInfoOutput = {0};
        input.data8 = SMCReadKeyInfo;
        outputSize = sizeof(keyInfoOutput);
        if (IOConnectCallStructMethod(connection, SMCSelector, &input, sizeof(input), &keyInfoOutput, &outputSize) == KERN_SUCCESS) {
            if (keyInfoOutput.keyInfo.dataSize > 0 && keyInfoOutput.keyInfo.dataSize <= sizeof(output.bytes)) {
                *info = keyInfoOutput.keyInfo;
            }
        }
    }
    uint32_t dataSize = info ? info->dataSize : input.keyInfo.dataSize;
    if (dataSize == 0 || dataSize > sizeof(output.bytes)) return false;
    memset(bytes, 0, 32);
    memcpy(bytes, output.bytes, dataSize);
    return true;
}

static double decodeSMCValue(SMCKeyInfo info, const uint8_t bytes[32]) {
    char type[5];
    typeName(info.dataType, type);
    if (strcmp(type, "flt ") == 0 && info.dataSize >= 4) {
        float value = 0;
        memcpy(&value, bytes, sizeof(value));
        return value;
    }
    if (strcmp(type, "fpe2") == 0 && info.dataSize >= 2) {
        return (double)(((uint16_t)bytes[0] << 8) | bytes[1]) / 4.0;
    }
    if (strcmp(type, "sp78") == 0 && info.dataSize >= 2) {
        int16_t raw = (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
        return (double)raw / 256.0;
    }
    if ((strncmp(type, "ui8", 3) == 0 || strcmp(type, "flag") == 0) && info.dataSize >= 1) {
        return bytes[0];
    }
    if (strncmp(type, "ui16", 4) == 0 && info.dataSize >= 2) {
        return (double)(((uint16_t)bytes[0] << 8) | bytes[1]);
    }
    return NAN;
}

static void readSMCSensors(MSCSensorSnapshot *snapshot) {
    io_connect_t connection = openSMC();
    if (!connection) {
        snapshot->fanStatus = -1;
        return;
    }

    uint8_t bytes[32] = {0};
    SMCKeyInfo info = {0};
    if (readSMCKey(connection, "FNum", &info, bytes)) {
        double countValue = decodeSMCValue(info, bytes);
        int count = isfinite(countValue) ? (int)countValue : (int)bytes[0];
        if (count <= 0) {
            snapshot->fanStatus = 0;
        } else {
            snapshot->fanStatus = 1;
            snapshot->fanCount = count > MSC_MAX_FANS ? MSC_MAX_FANS : count;
            for (int index = 0; index < snapshot->fanCount; index++) {
                char key[5] = {'F', (char)('0' + index), 'A', 'c', '\0'};
                memset(bytes, 0, sizeof(bytes));
                memset(&info, 0, sizeof(info));
                if (readSMCKey(connection, key, &info, bytes)) {
                    double rpm = decodeSMCValue(info, bytes);
                    snapshot->fanRPM[index] = isfinite(rpm) && rpm >= 0 && rpm < 20000 ? rpm : 0;
                }
            }
        }
    } else {
        snapshot->fanStatus = -1;
    }

#if !defined(__arm64__)
    const char *temperatureKeys[] = {"TC0P", "TC0D", "TC0E", "TC0F", "TC0H"};
    double sum = 0;
    double hottest = 0;
    int count = 0;
    for (size_t index = 0; index < sizeof(temperatureKeys) / sizeof(temperatureKeys[0]); index++) {
        memset(bytes, 0, sizeof(bytes));
        memset(&info, 0, sizeof(info));
        if (readSMCKey(connection, temperatureKeys[index], &info, bytes)) {
            double value = decodeSMCValue(info, bytes);
            if (isfinite(value) && value > 0 && value < 110) {
                sum += value;
                if (value > hottest) hottest = value;
                count++;
            }
        }
    }
    if (count > 0) {
        snapshot->temperatureAvailable = true;
        snapshot->averageTemperature = sum / count;
        snapshot->hottestTemperature = hottest;
    }
#endif
    IOServiceClose(connection);
}

static void readHIDTemperatures(MSCSensorSnapshot *snapshot) {
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) return;

    HIDCreateFn create = (HIDCreateFn)dlsym(handle, "IOHIDEventSystemClientCreate");
    HIDSetMatchingFn setMatching = (HIDSetMatchingFn)dlsym(handle, "IOHIDEventSystemClientSetMatching");
    HIDCopyServicesFn copyServices = (HIDCopyServicesFn)dlsym(handle, "IOHIDEventSystemClientCopyServices");
    HIDCopyEventFn copyEvent = (HIDCopyEventFn)dlsym(handle, "IOHIDServiceClientCopyEvent");
    HIDGetFloatFn getFloat = (HIDGetFloatFn)dlsym(handle, "IOHIDEventGetFloatValue");
    HIDCopyPropertyFn copyProperty = (HIDCopyPropertyFn)dlsym(handle, "IOHIDServiceClientCopyProperty");
    if (!create || !setMatching || !copyServices || !copyEvent || !getFloat || !copyProperty) {
        dlclose(handle);
        return;
    }

    int usagePage = 0xff00;
    int usage = 5;
    CFNumberRef pageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usagePage);
    CFNumberRef usageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    if (!pageNumber || !usageNumber) {
        if (pageNumber) CFRelease(pageNumber);
        if (usageNumber) CFRelease(usageNumber);
        dlclose(handle);
        return;
    }
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *values[] = {pageNumber, usageNumber};
    CFDictionaryRef matching = CFDictionaryCreate(
        kCFAllocatorDefault, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
    );
    CFRelease(pageNumber);
    CFRelease(usageNumber);

    CFTypeRef client = create(kCFAllocatorDefault);
    if (!client || !matching) {
        if (client) CFRelease(client);
        if (matching) CFRelease(matching);
        dlclose(handle);
        return;
    }
    setMatching(client, matching);
    CFRelease(matching);
    CFArrayRef services = copyServices(client);
    if (!services) {
        CFRelease(client);
        dlclose(handle);
        return;
    }

    double cpuSum = 0;
    double hottest = 0;
    double gpuSum = 0;
    int cpuCount = 0;
    int gpuCount = 0;
    CFIndex serviceCount = CFArrayGetCount(services);
    for (CFIndex index = 0; index < serviceCount; index++) {
        CFTypeRef service = CFArrayGetValueAtIndex(services, index);
        CFTypeRef event = copyEvent(service, HIDTemperatureEvent, 0, 0);
        if (!event) continue;
        double temperature = getFloat(event, HIDTemperatureEvent << 16);
        CFRelease(event);
        if (!isfinite(temperature) || temperature <= 0 || temperature >= 110) continue;

        char product[128] = {0};
        CFTypeRef productValue = copyProperty(service, CFSTR("Product"));
        if (productValue && CFGetTypeID(productValue) == CFStringGetTypeID()) {
            CFStringGetCString((CFStringRef)productValue, product, sizeof(product), kCFStringEncodingUTF8);
        }
        if (productValue) CFRelease(productValue);

        bool isGPU = strstr(product, "GPU") != NULL;
        bool isCPU = strstr(product, "pACC") != NULL || strstr(product, "eACC") != NULL ||
                     strstr(product, "tdie") != NULL || strstr(product, "CPU") != NULL;
        if (isGPU) {
            gpuSum += temperature;
            gpuCount++;
        }
        if (isCPU) {
            cpuSum += temperature;
            cpuCount++;
            if (temperature > hottest) hottest = temperature;
        }
    }

    if (cpuCount > 0) {
        snapshot->temperatureAvailable = true;
        snapshot->averageTemperature = cpuSum / cpuCount;
        snapshot->hottestTemperature = hottest;
    }
    if (gpuCount > 0) snapshot->gpuTemperature = gpuSum / gpuCount;

    CFRelease(services);
    CFRelease(client);
    dlclose(handle);
}

bool MSCReadSensorSnapshot(MSCSensorSnapshot *snapshot) {
    if (!snapshot) return false;
    memset(snapshot, 0, sizeof(*snapshot));
    snapshot->fanStatus = -1;
    readHIDTemperatures(snapshot);
    readSMCSensors(snapshot);
    return snapshot->temperatureAvailable || snapshot->fanStatus >= 0;
}
