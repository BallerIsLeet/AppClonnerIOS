#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AdSupport/AdSupport.h>
#import "ClonerConfig.h"

#pragma mark - Globals

static void floatingButtonTapped(UIButton *btn, UIEvent *event, NSString *finalCopyToken);

static NSString *gfinalCopyTokenString = nil;

@interface IGButtonTarget : NSObject
@end

@implementation IGButtonTarget
- (void)buttonTapped:(UIButton *)sender {
    floatingButtonTapped(sender, nil, gfinalCopyTokenString);
}
@end

static IGButtonTarget *gButtonTarget = nil;
static UIButton *gFloatingBtn = nil;
static NSString *base_username = nil;

#pragma mark - IGBaseUser hook

%hook IGBaseUser
- (NSString *)username {
    NSString *result = %orig;
    if (!base_username && result.length) {
        base_username = [result copy];
        NSLog(@"[igdumper] base_username: %@", base_username);
    }
    return result;
}
%end

#pragma mark - Helpers

static NSDictionary *userDefaultsDict(void) {
    static NSDictionary *cached = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cached = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] copy];
    });
    return cached;
}

static NSString *stringFromData(NSData *data) {
    if (!data) return @"";
    NSString *utf8 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (utf8) return utf8;

    const unsigned char *bytes = data.bytes;
    NSUInteger len = data.length;
    NSMutableString *hex = [NSMutableString stringWithCapacity:len * 2];
    for (NSUInteger i = 0; i < len; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [NSString stringWithFormat:@"<data length=%lu: %@>", (unsigned long)len, hex];
}

__attribute__((visibility("default"))) extern NSString *keychainAccessGroup;

static NSString *keychainGet(NSString *service, NSString *account, NSString *accessGroup) {
    accessGroup = keychainAccessGroup ?: accessGroup;

    NSMutableDictionary *query = @{
        (__bridge id)kSecClass       : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service ?: @"",
        (__bridge id)kSecReturnData  : @YES
    }.mutableCopy;

    if (account.length)      query[(__bridge id)kSecAttrAccount]     = account;
    if (accessGroup.length)  query[(__bridge id)kSecAttrAccessGroup] = accessGroup;

    CFTypeRef result = NULL;
    OSStatus status  = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        return stringFromData((__bridge_transfer NSData *)result);
    }
    return nil;
}

static NSString *keychainGetAccountForService(NSString *service, NSString *accessGroup) {
    accessGroup = keychainAccessGroup ?: accessGroup;

    NSMutableDictionary *query = @{
        (__bridge id)kSecClass            : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService      : service ?: @"",
        (__bridge id)kSecReturnAttributes : @YES,
        (__bridge id)kSecMatchLimit       : (__bridge id)kSecMatchLimitOne
    }.mutableCopy;

    if (accessGroup.length)  query[(__bridge id)kSecAttrAccessGroup] = accessGroup;

    CFDictionaryRef resultDict = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&resultDict);

    if (status == errSecSuccess && resultDict) {
        NSDictionary *attributes = (__bridge_transfer NSDictionary *)resultDict;
        NSString *accountName = attributes[(__bridge NSString *)kSecAttrAccount];
        if ([accountName isKindOfClass:[NSString class]] && accountName.length) {
            return accountName;
        }
    }
    return nil;
}

#pragma mark - Instagram-specific getters

static NSString *getUserAgent(void) {
    NSDictionary *d = userDefaultsDict();
    for (NSString *k in @[@"STAUserAgent", @"UserAgent"]) {
        if ([d[k] isKindOfClass:NSString.class] && [d[k] length]) return d[k];
    }
    return @"Instagram 70.0.0.0.89 Android (…)";
}

static NSString *getUsername(void) {
    NSDictionary *acct = userDefaultsDict()[@"last-logged-in-account-dict"];
    if ([acct isKindOfClass:NSDictionary.class]) {
        NSString *u = acct[@"username"];
        if (u.length) return u;
    }
    return @"LOGIN";
}

static NSString *getSessionApi(NSString *userID) {
    return keychainGet(@"group.com.facebook.family.instagramtokenshare.service", userID, @"group.com.facebook.family");
}

static NSString *getInstagramMID(void) {
    NSArray *svcList = @[@"instagram.mid", @"com.instagram.device.midfinalCopyToken", @"unique_id"];
    for (NSString *svc in svcList) {
        NSString *mid = keychainGet(svc, nil, nil);
        if (mid.length) return mid;
    }
    return nil;
}

static NSString *getUserId(void) {
    return keychainGetAccountForService(@"instagram.activeaccount", @"group.com.facebook.family");
}

static NSString *getWWWClaim(void) {
    NSString *jsonString = keychainGet(@"com.instagram.users.loggingclaims.service",
                                       @"com.instagram.users.loggingclaims",
                                       @"MH9GU9K5PX.platformFamily");
    if (jsonString.length) {
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if ([jsonDict isKindOfClass:[NSDictionary class]]) {
            NSString *value = jsonDict[getUserId()];
            if (value.length) return value;
        }
    }
    return nil;
}

static NSString *getDeviceID(void) {
    for (NSString *k in userDefaultsDict()) {
        if ([k hasSuffix:@"db_device_id"]) {
            NSString *val = userDefaultsDict()[k];
            if (val.length) return val;
        }
    }
    return @"ios-xxxxxxxxxxxxxxxx";
}

#pragma mark - Draggable Button

@interface UIButton (IGPan)
@end

@implementation UIButton (IGPan)
- (void)__handlePan:(UIPanGestureRecognizer *)gr {
    CGPoint translation = [gr translationInView:self.superview];
    CGFloat halfWidth = self.bounds.size.width / 2.0;
    CGFloat superWidth = self.superview.bounds.size.width;
    CGFloat superHeight = self.superview.bounds.size.height;
    CGFloat y = MIN(MAX(self.center.y + translation.y, halfWidth), superHeight - halfWidth);
    CGFloat x = superWidth - halfWidth - 12;
    self.center = CGPointMake(x, y);
    [gr setTranslation:CGPointZero inView:self.superview];
}
@end

#pragma mark - Floating Button

static UIWindow *findForegroundWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive
                && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *winScene = (UIWindowScene *)scene;
                if (winScene.windows.count > 0) return winScene.windows.firstObject;
            }
        }
        return nil;
    }
    return nil;
}

static void floatingButtonTapped(UIButton *btn, UIEvent *event, NSString *finalCopyToken) {
    UIWindow *win = findForegroundWindow();
    if (!win) return;
    UIViewController *rootVC = win.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
    if (!rootVC) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"IGDumper IAM Token"
                                                                   message:finalCopyToken
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = finalCopyToken;
    }]];
    [rootVC presentViewController:alert animated:YES completion:nil];
}

static void createFloatingButton(NSString *finalCopyToken) {
    if (gFloatingBtn) return;

    const CGFloat size = 56.0;
    UIWindow *win = findForegroundWindow();
    if (!win) return;

    gfinalCopyTokenString = [finalCopyToken copy];
    if (!gButtonTarget) gButtonTarget = [[IGButtonTarget alloc] init];

    gFloatingBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    gFloatingBtn.frame = CGRectMake(win.bounds.size.width - size - 12,
                                    win.bounds.size.height / 2.0 - size / 2.0,
                                    size, size);
    gFloatingBtn.layer.cornerRadius = size / 2.0;
    gFloatingBtn.clipsToBounds = YES;
    gFloatingBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    [gFloatingBtn setTitle:@"IG" forState:UIControlStateNormal];
    [gFloatingBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    gFloatingBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gFloatingBtn action:@selector(__handlePan:)];
    [gFloatingBtn addGestureRecognizer:pan];

    [gFloatingBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [gFloatingBtn addTarget:gButtonTarget action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];

    [win addSubview:gFloatingBtn];
    [win bringSubviewToFront:gFloatingBtn];
}

#pragma mark - Inline Helpers

static inline NSString *getUDID(void) { return [[[UIDevice currentDevice] identifierForVendor] UUIDString]; }
static inline NSString *getADID(void) { return [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString]; }

#pragma mark - Constructor

%ctor {
    NSString *binaryName = [[NSProcessInfo processInfo] processName];
    if (![binaryName isEqualToString:@"Instagram"]) {
        NSLog(@"[igdumper] Not Instagram binary (%@), skipping", binaryName);
        return;
    }

    NSLog(@"[igdumper] Instagram detected, initializing...");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(2);

        NSString *login        = getUsername();
        NSString *password     = @"PASSWORD";
        NSString *userID       = getUserId();
        NSString *sessionAPI   = getSessionApi(userID);
        NSString *userAgent    = getUserAgent();
        NSString *deviceID     = getDeviceID();
        NSString *mid          = getInstagramMID();
        NSString *wwwClaim     = getWWWClaim();
        NSString *udid         = getUDID();
        NSString *adid         = getADID();

        NSString *finalCopyToken = [NSString stringWithFormat:
            @"%@:|%@|%@;%@;%@;%@|Authorization=Bearer %@;IG-U-DS-USER-ID=%@;IG-INTENDED-USER-ID=%@;X-MID=%@;X-IG-WWW-Claim=%@;||",
            login ?: @"", userAgent ?: @"", udid ?: @"", userID ?: @"",
            adid ?: @"", deviceID ?: @"", sessionAPI ?: @"",
            userID ?: @"", userID ?: @"", mid ?: @"", wwwClaim ?: @""];

        NSLog(@"[igdumper] IAM FORMAT: %@", finalCopyToken);

        BOOL allAvailable = login.length && userID.length && sessionAPI.length && userAgent.length &&
                            deviceID.length && mid.length && wwwClaim.length && udid.length && adid.length;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (allAvailable && ClonerConfig.igDumperEnabled) {
                createFloatingButton(finalCopyToken);
            }
        });
    });
}
