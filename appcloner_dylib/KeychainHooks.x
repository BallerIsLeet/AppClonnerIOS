#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "fishhook/fishhook.h"
#import "ClonerConfig.h"

#pragma mark - Globals

__attribute__((visibility("default"))) NSString *keychainAccessGroup;
static NSString *originalKeychainAccessGroup;

#pragma mark - Original Function Pointers

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef);
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);

#pragma mark - SecItem Hooks

static OSStatus hook_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (CFDictionaryContainsKey(attributes, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mutableAttributes = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, attributes);
        CFDictionarySetValue(mutableAttributes, kSecAttrAccessGroup, (__bridge void *)keychainAccessGroup);
        attributes = CFDictionaryCreateCopy(kCFAllocatorDefault, mutableAttributes);
        CFRelease(mutableAttributes);
    }

    OSStatus status = orig_SecItemAdd(attributes, result);

    if (result && *result && CFGetTypeID(*result) == CFDictionaryGetTypeID() &&
        CFDictionaryContainsKey(*result, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mutableResult = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, *result);
        CFDictionarySetValue(mutableResult, kSecAttrAccessGroup, (__bridge void *)originalKeychainAccessGroup);
        *result = CFDictionaryCreateCopy(kCFAllocatorDefault, mutableResult);
        CFRelease(mutableResult);
    }
    return status;
}

static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (CFDictionaryContainsKey(query, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mutableQuery = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
        CFDictionarySetValue(mutableQuery, kSecAttrAccessGroup, (__bridge void *)keychainAccessGroup);
        query = CFDictionaryCreateCopy(kCFAllocatorDefault, mutableQuery);
        CFRelease(mutableQuery);
    }

    OSStatus status = orig_SecItemCopyMatching(query, result);

    if (result && *result && CFGetTypeID(*result) == CFDictionaryGetTypeID() &&
        CFDictionaryContainsKey(*result, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mutableResult = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, *result);
        CFDictionarySetValue(mutableResult, kSecAttrAccessGroup, (__bridge void *)originalKeychainAccessGroup);
        *result = CFDictionaryCreateCopy(kCFAllocatorDefault, mutableResult);
        CFRelease(mutableResult);
    }
    return status;
}

static OSStatus hook_SecItemDelete(CFDictionaryRef query) {
    if (CFDictionaryContainsKey(query, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mutableQuery = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
        CFDictionarySetValue(mutableQuery, kSecAttrAccessGroup, (__bridge void *)keychainAccessGroup);
        query = CFDictionaryCreateCopy(kCFAllocatorDefault, mutableQuery);
        CFRelease(mutableQuery);
    }
    return orig_SecItemDelete(query);
}

static OSStatus hook_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (CFDictionaryContainsKey(query, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mutableQuery = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
        CFDictionarySetValue(mutableQuery, kSecAttrAccessGroup, (__bridge void *)keychainAccessGroup);
        query = CFDictionaryCreateCopy(kCFAllocatorDefault, mutableQuery);
        CFRelease(mutableQuery);
    }
    return orig_SecItemUpdate(query, attributesToUpdate);
}

#pragma mark - Public Functions

void initSecurityHooks(void) {
    struct rebinding bindings[] = {
        {"SecItemAdd",          (void *)hook_SecItemAdd,       (void **)&orig_SecItemAdd},
        {"SecItemCopyMatching", (void *)hook_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
        {"SecItemDelete",       (void *)hook_SecItemDelete,    (void **)&orig_SecItemDelete},
        {"SecItemUpdate",       (void *)hook_SecItemUpdate,    (void **)&orig_SecItemUpdate}
    };
    rebind_symbols(bindings, sizeof(bindings) / sizeof(bindings[0]));
    NSLog(@"[AppCloner][Keychain] Security hooks installed");
}

void loadKeychainAccessGroup(void) {
    NSDictionary *dummyItem = @{
        (__bridge id)kSecClass :          (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount :    @"dummyItem",
        (__bridge id)kSecAttrService :    @"dummyService",
        (__bridge id)kSecReturnAttributes : @YES
    };

    CFTypeRef result = NULL;
    OSStatus ret = SecItemCopyMatching((__bridge CFDictionaryRef)dummyItem, &result);
    if (ret == errSecItemNotFound) {
        ret = SecItemAdd((__bridge CFDictionaryRef)dummyItem, &result);
    }

    if (ret == errSecSuccess && result) {
        NSDictionary *resultDict = (__bridge NSDictionary *)result;
        keychainAccessGroup = resultDict[(__bridge id)kSecAttrAccessGroup];
        NSString *teamId = ClonerConfig.originalTeamId;
        if (keychainAccessGroup && teamId.length) {
            originalKeychainAccessGroup =
            [keychainAccessGroup stringByReplacingCharactersInRange:NSMakeRange(0, 10)
                                                         withString:teamId];
        }
        NSLog(@"[AppCloner][Keychain] Loaded access group: %@", keychainAccessGroup);
    }

    if (result) CFRelease(result);
}

void setKeychainAccessGroupFromConfig(void) {
    NSString *configuredGroup = ClonerConfig.keychainAccessGroup;
    if (configuredGroup.length) {
        keychainAccessGroup = configuredGroup;
        NSLog(@"[AppCloner][Keychain] Using configured access group: %@", keychainAccessGroup);
    }
}
