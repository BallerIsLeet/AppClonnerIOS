#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <string.h>
#import "ClonerConfig.h"

#pragma mark - Meta Apps (FBFamily Jailbreak Check)

%hook FBFamilyDeviceIDReportInternal

- (int)FBFamilyIDDeviceIsJailbroken {
    return 0;
}

%end

#pragma mark - FaceTecSDK Bypass

extern struct mach_header *_dyld_get_prog_image_header(void);

%hookf(struct mach_header *, _dyld_get_image_header, uint32_t idx) {
    NSLog(@"[AppCloner][Bundle] _dyld_get_image_header called");
    void *lr = __builtin_extract_return_addr(__builtin_return_address(0));
    Dl_info info;

    if (dladdr(lr, &info) != 0 && strstr(info.dli_fname, "FaceTecSDK")) {
        NSLog(@"[AppCloner][Bundle] FaceTecSDK caller detected, returning prog header");
        return _dyld_get_prog_image_header();
    }

    return %orig;
}

#pragma mark - YouTube Login Fix

%hook NSBundle
- (NSDictionary *)infoDictionary {
    NSString *processName = NSProcessInfo.processInfo.processName;
    if ([processName isEqualToString:@"YouTube"]) {
        NSMutableDictionary *info = %orig.mutableCopy;
        if ([self isEqual:NSBundle.mainBundle]) {
            info[@"CFBundleIdentifier"] = ClonerConfig.originalBundleId;
        }
        return info;
    }
    return %orig;
}
%end

%hook YTHotConfig
- (BOOL)disableAfmaIdfaCollection { return NO; }
%end

#pragma mark - RCAapfzobca Hook

%hook RCAapfzobca
- (void)setJvnifzvx:(NSString *)bundleIdentifier {
    %orig(ClonerConfig.originalBundleId);
}
%end

#pragma mark - NSBundle Identity Hooks

%hook NSBundle

- (NSString *)bundleIdentifier {
    NSArray<NSNumber *> *addresses = NSThread.callStackReturnAddresses;
    Dl_info info;
    if (dladdr((void *)[addresses[2] longLongValue], &info) == 0) {
        return %orig;
    }
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    if ([path hasPrefix:NSBundle.mainBundle.bundlePath]) {
        return ClonerConfig.originalBundleId;
    }
    return %orig;
}

- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"CFBundleIdentifier"]) {
        return ClonerConfig.originalBundleId;
    }
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"]) {
        return ClonerConfig.bundleName;
    }
    return %orig;
}

%end
