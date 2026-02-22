#import <substrate.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ClonerConfig.h"

void (*original_beginBackgroundTaskWithName)(id, SEL, NSString *, void (^)(void)) = NULL;
UIBackgroundTaskIdentifier hooked_beginBackgroundTaskWithName(id self, SEL _cmd, NSString *taskName, void (^handler)(void)) {
    NSLog(@"[AppCloner][BGBlocker] Background task prevented: %@", taskName);
    return UIBackgroundTaskInvalid;
}

void (*original_beginBackgroundTaskWithExpirationHandler)(id, SEL, void (^)(void)) = NULL;
UIBackgroundTaskIdentifier hooked_beginBackgroundTaskWithExpirationHandler(id self, SEL _cmd, void (^handler)(void)) {
    NSLog(@"[AppCloner][BGBlocker] Background task prevented (no name)");
    return UIBackgroundTaskInvalid;
}

BOOL (*original_registerForTaskWithIdentifier)(id, SEL, NSString *, id, void (^)(id)) = NULL;
BOOL hooked_registerForTaskWithIdentifier(id self, SEL _cmd, NSString *identifier, id queue, void (^launchHandler)(id)) {
    NSLog(@"[AppCloner][BGBlocker] Background task registration prevented: %@", identifier);
    return NO;
}

BOOL (*original_submitTaskRequest)(id, SEL, id, NSError **) = NULL;
BOOL hooked_submitTaskRequest(id self, SEL _cmd, id request, NSError **error) {
    NSLog(@"[AppCloner][BGBlocker] Background task submission prevented");
    return NO;
}

%ctor {
    NSLog(@"[AppCloner][BGBlocker] Background Task Blocker Loaded");

    if (!ClonerConfig.backgroundProcessEnabled) {
        NSLog(@"[AppCloner][BGBlocker] Background blocking disabled");
        return;
    }

    NSLog(@"[AppCloner][BGBlocker] Background tasks blocked");

    Class UIApplicationClass = objc_getClass("UIApplication");
    if (UIApplicationClass) {
        MSHookMessageEx(UIApplicationClass, @selector(beginBackgroundTaskWithName:expirationHandler:), (IMP)hooked_beginBackgroundTaskWithName, (IMP *)&original_beginBackgroundTaskWithName);
        MSHookMessageEx(UIApplicationClass, @selector(beginBackgroundTaskWithExpirationHandler:), (IMP)hooked_beginBackgroundTaskWithExpirationHandler, (IMP *)&original_beginBackgroundTaskWithExpirationHandler);
    }

    Class BGTaskSchedulerClass = objc_getClass("BGTaskScheduler");
    if (BGTaskSchedulerClass) {
        MSHookMessageEx(BGTaskSchedulerClass, @selector(registerForTaskWithIdentifier:usingQueue:launchHandler:), (IMP)hooked_registerForTaskWithIdentifier, (IMP *)&original_registerForTaskWithIdentifier);
        MSHookMessageEx(BGTaskSchedulerClass, @selector(submitTaskRequest:error:), (IMP)hooked_submitTaskRequest, (IMP *)&original_submitTaskRequest);
    }
}
