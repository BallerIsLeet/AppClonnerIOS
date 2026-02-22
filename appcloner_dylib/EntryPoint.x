#import <Foundation/Foundation.h>
#import "ClonerConfig.h"

// External functions from KeychainHooks.x
extern void initSecurityHooks(void);
extern void loadKeychainAccessGroup(void);
extern void setKeychainAccessGroupFromConfig(void);

static NSURL *fakeGroupContainerURL;

#pragma mark - Directory Helper

static void createDirectoryIfNotExists(NSURL *URL) {
    if (![URL checkResourceIsReachableAndReturnError:nil]) {
        [[NSFileManager defaultManager] createDirectoryAtURL:URL
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:nil];
    }
}

#pragma mark - Sideloaded Fixes

%group SideloadedFixes

%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    NSURL *fakeURL = [fakeGroupContainerURL URLByAppendingPathComponent:groupIdentifier];
    createDirectoryIfNotExists(fakeURL);
    createDirectoryIfNotExists([fakeURL URLByAppendingPathComponent:@"Library"]);
    createDirectoryIfNotExists([fakeURL URLByAppendingPathComponent:@"Library/Caches"]);
    return fakeURL;
}
%end

%end

#pragma mark - Constructor

%ctor {
    // Load config first — everything depends on it
    [ClonerConfig loadConfig];

    // Set keychain access group from config if available
    setKeychainAccessGroupFromConfig();

    // Setup fake group container directory
    fakeGroupContainerURL = [NSURL fileURLWithPath:
                             [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FakeGroupContainers"]
                                       isDirectory:YES];

    // Load default keychain group (then override via hooks)
    loadKeychainAccessGroup();

    // Install fishhook rebindings for Security calls
    initSecurityHooks();

    NSLog(@"[AppCloner][Entry] Initialization complete");

    %init;
    %init(SideloadedFixes);
}
