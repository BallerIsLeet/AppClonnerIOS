#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <substrate.h>
#import <sys/utsname.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import "ClonerConfig.h"

#pragma mark - Global Variables

static NSString *selectedModel = nil;
static NSString *realSystemVersion = nil;
static NSString *realMachineModel = nil;

#pragma mark - Spoofing Utilities

static inline NSArray *spoofVersions() {
    static NSArray *versions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        versions = @[@"18", @"18.0.1", @"18.1", @"18.1.1", @"18.2", @"18.2.1", @"18.3", @"18.3.1"];
    });
    return versions;
}

static NSString *getSpoofedVersion() {
    static NSString *spoofedVersion = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        spoofedVersion = [defaults objectForKey:@"spoofed_iOS_version"];
        if (!spoofedVersion) {
            NSArray *versions = spoofVersions();
            NSUInteger randomIndex = arc4random_uniform((u_int32_t)[versions count]);
            spoofedVersion = versions[randomIndex];
            [defaults setObject:spoofedVersion forKey:@"spoofed_iOS_version"];
            [defaults synchronize];
        }
    });
    return spoofedVersion;
}

static NSDictionary *osToBuildVersionMap() {
    static NSDictionary *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"18": @"22A5282m",
            @"18.0.1": @"22A5297f",
            @"18.1": @"22B5045h",
            @"18.1.1": @"22B5050k",
            @"18.2": @"22C5034e",
            @"18.2.1": @"22C5040f",
            @"18.3": @"22D5024f",
            @"18.3.1": @"22D5030g"
        };
    });
    return map;
}

static NSString *getSpoofedBuildVersion() {
    static NSString *spoofedBuild = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        spoofedBuild = [defaults objectForKey:@"spoofed_iOS_build_version"];
        if (!spoofedBuild) {
            NSString *spoofedOS = getSpoofedVersion();
            NSDictionary *map = osToBuildVersionMap();
            spoofedBuild = map[spoofedOS];
            if (!spoofedBuild) {
                NSString *majorVersion = [[spoofedOS componentsSeparatedByString:@"."] firstObject];
                int majorInt = [majorVersion intValue];
                char baseLetter = 'A' + (majorInt - 18);
                if (baseLetter < 'A' || baseLetter > 'Z') baseLetter = 'X';
                spoofedBuild = [NSString stringWithFormat:@"%d%c%dSPOOFED", 20 + (majorInt - 16), baseLetter, arc4random_uniform(900) + 100];
            }
            [defaults setObject:spoofedBuild forKey:@"spoofed_iOS_build_version"];
            [defaults synchronize];
        }
    });
    return spoofedBuild;
}

static inline NSString *humanReadableModel(NSString *modelIdentifier) {
    static NSDictionary *modelMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        modelMap = @{
            @"iPhone14,2": @"iPhone 13 Pro",
            @"iPhone14,3": @"iPhone 13 Pro Max",
            @"iPhone14,4": @"iPhone 13 mini",
            @"iPhone14,5": @"iPhone 13",
            @"iPhone15,2": @"iPhone 14 Pro",
            @"iPhone15,3": @"iPhone 14 Pro Max",
            @"iPhone15,4": @"iPhone 14",
            @"iPhone15,5": @"iPhone 14 Plus",
            @"iPhone16,1": @"iPhone 15 Pro",
            @"iPhone16,2": @"iPhone 15 Pro Max"
        };
    });
    return modelMap[modelIdentifier] ?: @"iPhone";
}

#pragma mark - Original Method Pointers

static NSString *(*orig_systemVersion)(id, SEL);
static NSString *(*orig_operatingSystemVersionString)(id, SEL);
static NSUUID *(*orig_identifierForVendor)(id, SEL);
static NSString *(*orig_machineName)(id, SEL);
static id (*orig_deviceInfoForKey)(id, SEL, NSString *);
static NSString *(*orig_model)(id, SEL);
static NSString *(*orig_localizedModel)(id, SEL);
static NSString *(*orig_name)(id, SEL);
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
static int (*orig_uname)(struct utsname *);
static CFPropertyListRef (*orig_MGCopyAnswer_internal)(CFStringRef property, uint32_t *outTypeCode);

#pragma mark - MGCopyAnswer Hook

static CFPropertyListRef new_MGCopyAnswer_internal(CFStringRef property, uint32_t *outTypeCode) {
    NSString *key = (__bridge NSString *)property;

    if ([key isEqualToString:@"ProductVersion"]) {
        return (__bridge_retained CFStringRef)getSpoofedVersion();
    } else if ([key isEqualToString:@"ProductType"] || [key isEqualToString:@"HardwareModel"]) {
        return (__bridge_retained CFStringRef)selectedModel;
    } else if ([key isEqualToString:@"BuildVersion"] || [key isEqualToString:@"j9Th5smJpdztHwc+i39zIg"]) {
        return (__bridge_retained CFStringRef)getSpoofedBuildVersion();
    }

    return orig_MGCopyAnswer_internal(property, outTypeCode);
}

static uintptr_t findBranchAndFollow(const uint8_t *start) {
    uint32_t instr = *(uint32_t *)(start + 4);
    if ((instr & 0xFC000000) == 0x14000000) {
        int32_t offset = (instr & 0x03FFFFFF) << 2;
        if (offset & 0x02000000)
            offset |= 0xFC000000;
        return (uintptr_t)(start + 4 + offset);
    }
    return 0;
}

#pragma mark - UIDevice and NSProcessInfo Hooks

static NSString *new_systemVersion(id self, SEL _cmd) {
    return getSpoofedVersion();
}

static NSString *new_operatingSystemVersionString(id self, SEL _cmd) {
    return [NSString stringWithFormat:@"Version %@ (Build Spoofed)", getSpoofedVersion()];
}

#define SPOOFED_VENDOR_ID_KEY @"SpoofedVendorID_"
static NSUUID *new_identifierForVendor(id self, SEL _cmd) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *spoofedID = [defaults objectForKey:SPOOFED_VENDOR_ID_KEY];

    if (!spoofedID) {
        spoofedID = [[NSUUID UUID] UUIDString];
        [defaults setObject:spoofedID forKey:SPOOFED_VENDOR_ID_KEY];
        [defaults synchronize];
    }

    return [[NSUUID alloc] initWithUUIDString:spoofedID];
}

static NSString *new_machineName(id self, SEL _cmd) {
    return selectedModel;
}

static id new_deviceInfoForKey(id self, SEL _cmd, NSString *key) {
    id originalValue = orig_deviceInfoForKey(self, _cmd, key);

    if ([originalValue isKindOfClass:[NSString class]]) {
        NSString *strValue = (NSString *)originalValue;

        if ([key isEqualToString:@"ProductVersion"] || [strValue isEqualToString:realSystemVersion]) {
            return getSpoofedVersion();
        } else if ([key isEqualToString:@"BuildVersion"] || [key isEqualToString:@"j9Th5smJpdztHwc+i39zIg"]) {
            return getSpoofedBuildVersion();
        } else if ([key isEqualToString:@"DeviceName"]) {
            return humanReadableModel(selectedModel);
        } else if ([key isEqualToString:@"ProductType"] || [strValue isEqualToString:realMachineModel]) {
            return selectedModel;
        }
    }

    return originalValue;
}

static NSString *new_model(id self, SEL _cmd) {
    return humanReadableModel(selectedModel);
}

static NSString *new_localizedModel(id self, SEL _cmd) {
    return humanReadableModel(selectedModel);
}

static NSString *new_name(id self, SEL _cmd) {
    return humanReadableModel(selectedModel);
}

#pragma mark - uname and sysctl Hooks

static int hooked_uname(struct utsname *name) {
    int result = orig_uname(name);
    if (result == 0 && selectedModel) {
        strlcpy(name->machine, [selectedModel UTF8String], sizeof(name->machine));
    }
    return result;
}

static int new_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, const void *newp, size_t newlen) {
    if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0 || strcmp(name, "hw.product") == 0) {
        if (oldlenp && !oldp) {
            *oldlenp = selectedModel.length + 1;
            return 0;
        }
        if (oldp && oldlenp && *oldlenp >= (selectedModel.length + 1)) {
            strlcpy((char *)oldp, [selectedModel UTF8String], *oldlenp);
            return 0;
        }
    } else if (strcmp(name, "hw.memsize") == 0 && oldp && oldlenp && *oldlenp >= sizeof(uint64_t)) {
        uint64_t spoofedMemsize = 6ULL * 1024 * 1024 * 1024;
        memcpy(oldp, &spoofedMemsize, sizeof(spoofedMemsize));
        return 0;
    }

    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

#pragma mark - Constructor

__attribute__((constructor))
static void tweak_init() {
    if (!ClonerConfig.deviceSpoofingEnabled) {
        NSLog(@"[AppCloner][DeviceSpoofer] Disabled, skipping hooks");
        return;
    }

    NSLog(@"[AppCloner][DeviceSpoofer] Enabled, setting hooks");

    realSystemVersion = [[UIDevice currentDevice] systemVersion];
    struct utsname systemInfo;
    uname(&systemInfo);
    realMachineModel = [NSString stringWithUTF8String:systemInfo.machine];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    selectedModel = [defaults stringForKey:@"SelectedDeviceModel"];
    if (!selectedModel) {
        static NSArray *deviceModels = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            deviceModels = @[
                @"iPhone14,2", @"iPhone14,3", @"iPhone14,4", @"iPhone14,5",
                @"iPhone15,2", @"iPhone15,3", @"iPhone15,4", @"iPhone15,5",
                @"iPhone16,1", @"iPhone16,2"
            ];
        });
        selectedModel = deviceModels[arc4random_uniform((u_int32_t)deviceModels.count)];
        [defaults setObject:selectedModel forKey:@"SelectedDeviceModel"];
        [defaults synchronize];
    }

    getSpoofedVersion();
    getSpoofedBuildVersion();

    void *unamePtr = dlsym(RTLD_DEFAULT, "uname");
    if (unamePtr) MSHookFunction(unamePtr, (void *)hooked_uname, (void **)&orig_uname);

    void *sysctlbynamePtr = dlsym(RTLD_DEFAULT, "sysctlbyname");
    if (sysctlbynamePtr) MSHookFunction(sysctlbynamePtr, (void *)new_sysctlbyname, (void **)&orig_sysctlbyname);

    Class NSProcessInfoClass = objc_getClass("NSProcessInfo");
    if (NSProcessInfoClass) {
        MSHookMessageEx(NSProcessInfoClass, @selector(operatingSystemVersionString),
                        (IMP)new_operatingSystemVersionString, (IMP *)&orig_operatingSystemVersionString);
    }

    Class UIDeviceClass = objc_getClass("UIDevice");
    if (UIDeviceClass) {
        MSHookMessageEx(UIDeviceClass, @selector(systemVersion), (IMP)new_systemVersion, (IMP *)&orig_systemVersion);
        MSHookMessageEx(UIDeviceClass, @selector(identifierForVendor), (IMP)new_identifierForVendor, (IMP *)&orig_identifierForVendor);

        SEL machineNameSel = NSSelectorFromString(@"machineName");
        if ([UIDeviceClass respondsToSelector:machineNameSel])
            MSHookMessageEx(UIDeviceClass, machineNameSel, (IMP)new_machineName, (IMP *)&orig_machineName);

        SEL deviceInfoSel = NSSelectorFromString(@"_deviceInfoForKey:");
        if ([UIDeviceClass instancesRespondToSelector:deviceInfoSel])
            MSHookMessageEx(UIDeviceClass, deviceInfoSel, (IMP)new_deviceInfoForKey, (IMP *)&orig_deviceInfoForKey);

        MSHookMessageEx(UIDeviceClass, @selector(model), (IMP)new_model, (IMP *)&orig_model);
        MSHookMessageEx(UIDeviceClass, @selector(localizedModel), (IMP)new_localizedModel, (IMP *)&orig_localizedModel);
        MSHookMessageEx(UIDeviceClass, @selector(name), (IMP)new_name, (IMP *)&orig_name);
    }

    MSImageRef libGestalt = MSGetImageByName("/usr/lib/libMobileGestalt.dylib");
    if (libGestalt) {
        void *MGCopyAnswerFn = MSFindSymbol(libGestalt, "_MGCopyAnswer");
        if (MGCopyAnswerFn) {
            uintptr_t internalFn = findBranchAndFollow((const uint8_t *)MGCopyAnswerFn);
            if (internalFn) MSHookFunction((void *)internalFn, (void *)new_MGCopyAnswer_internal, (void **)&orig_MGCopyAnswer_internal);
        }
    }

    NSLog(@"[AppCloner][DeviceSpoofer] All hooks installed.");
}
