#import <Security/Security.h>
#import <Foundation/Foundation.h>

void* (SecTaskCopyValueForEntitlement)(void* task, CFStringRef entitlement, CFErrorRef _Nullable *error);
void* (SecTaskCreateFromSelf)(CFAllocatorRef allocator);

static NSString* defaultSecurityApplicationGroupIdentifier(void) {
    void* task = NULL;
    NSString *applicationGroupIdentifier = nil;

    do {
        task = SecTaskCreateFromSelf(kCFAllocatorDefault);
        if (task == NULL) {
            NSLog(@"[AppCloner][Container] Failed to create security task.");
            break;
        }

        CFTypeRef applicationGroupIdentifiers = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.security.application-groups"), NULL);
        if (applicationGroupIdentifiers == NULL) {
            NSLog(@"[AppCloner][Container] No application groups entitlement found.");
            break;
        }

        if (CFGetTypeID(applicationGroupIdentifiers) != CFArrayGetTypeID() || CFArrayGetCount(applicationGroupIdentifiers) == 0) {
            CFRelease(applicationGroupIdentifiers);
            break;
        }

        CFTypeRef firstApplicationGroupIdentifier = CFArrayGetValueAtIndex(applicationGroupIdentifiers, 0);
        CFRelease(applicationGroupIdentifiers);

        if (CFGetTypeID(firstApplicationGroupIdentifier) != CFStringGetTypeID()) {
            break;
        }

        applicationGroupIdentifier = CFBridgingRelease(CFRetain(firstApplicationGroupIdentifier));
        NSLog(@"[AppCloner][Container] Retrieved application group: %@", applicationGroupIdentifier);

    } while (0);

    if (task != NULL) {
        CFRelease(task);
    }

    return applicationGroupIdentifier;
}

%hook NSUserDefaults
- (id)initWithSuiteName:(NSString *)arg1 {
    if (!arg1 || [arg1 hasPrefix:@"com.apple."]) {
        return %orig(arg1);
    } else {
        NSString *defaultIdentifier = defaultSecurityApplicationGroupIdentifier();
        NSLog(@"[AppCloner][Container] Substituting suite name with: %@", defaultIdentifier);
        return %orig(defaultIdentifier);
    }
}
%end

%hook NSFileManager
- (id)containerURLForSecurityApplicationGroupIdentifier:(NSString *)arg1 {
    if (!arg1 || [arg1 hasPrefix:@"com.apple."]) {
        return %orig(arg1);
    } else {
        NSString *defaultIdentifier = defaultSecurityApplicationGroupIdentifier();
        NSLog(@"[AppCloner][Container] Substituting container group with: %@", defaultIdentifier);
        return %orig(defaultIdentifier);
    }
}
%end
