#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import "FakeCapturePhoto.h"
#import "TweakImagePickerDelegate.h"
#import "CameraHooks.h"
#import "ImageTransforms.h"

#pragma mark - Extern Globals (from CameraHooks.m)

extern FakeCapturePhoto *g_cachedPhoto;
extern BOOL g_shouldApplyEdits;
extern BOOL g_isVerifierModeEnabled;
extern UIButton *g_cameraFloatingButton;

#pragma mark - Forward Declarations

static void showEditActionSheet(void);

#pragma mark - Singleton Picker Delegate

static TweakImagePickerDelegate *g_pickerDelegate = nil;

static TweakImagePickerDelegate *getSingletonPickerDelegate(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_pickerDelegate = [[TweakImagePickerDelegate alloc] init];
    });
    return g_pickerDelegate;
}

#pragma mark - Top View Controller

static UIViewController *topMostViewController(void) {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = keyWindow.rootViewController;
    UIViewController *presentedVC = rootVC;
    while (presentedVC.presentedViewController) {
        presentedVC = presentedVC.presentedViewController;
    }
    return presentedVC;
}

#pragma mark - Edit Actions

static void performRotateAction(void) {
    NSData *originalData = g_cachedPhoto.jpegData;
    if (!originalData) return;
    UIImage *originalImage = [UIImage imageWithData:originalData];
    if (!originalImage) return;

    UIImage *rotatedImage = rotateImage(originalImage, M_PI_2);
    if (!rotatedImage) return;

    NSData *rotatedData = UIImageJPEGRepresentation(rotatedImage, 1.0);
    if (rotatedData) {
        g_cachedPhoto.jpegData = rotatedData;
    }
}

static void performMirrorAction(void) {
    NSData *originalData = g_cachedPhoto.jpegData;
    if (!originalData) return;
    UIImage *originalImage = [UIImage imageWithData:originalData];
    if (!originalImage) return;

    UIImage *mirroredImage = mirrorImage(originalImage);
    if (!mirroredImage) return;

    NSData *mirroredData = UIImageJPEGRepresentation(mirroredImage, 1.0);
    if (mirroredData) {
        g_cachedPhoto.jpegData = mirroredData;
    }
}

static void performToggleVerifierModeAction(void) {
    g_isVerifierModeEnabled = !g_isVerifierModeEnabled;
    NSLog(@"[AppCloner][Camera] Verifier Mode toggled: %s", g_isVerifierModeEnabled ? "ON" : "OFF");
}

static void performOpenPickerAction(void) {
    UIViewController *topVC = topMostViewController();
    if (!topVC) return;

    TweakImagePickerDelegate *pickerDelegate = getSingletonPickerDelegate();
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = pickerDelegate;
    picker.allowsEditing = NO;
    [topVC presentViewController:picker animated:YES completion:nil];
}

static void showEditActionSheet(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Options"
                                                                   message:@"Choose an action"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Rotate" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        performRotateAction();
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Mirror" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        performMirrorAction();
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Open Picker" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        performOpenPickerAction();
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Verifier Mode: %@", g_isVerifierModeEnabled ? @"ON" : @"OFF"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        performToggleVerifierModeAction();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            showEditActionSheet();
        });
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *topVC = topMostViewController();
    if (topVC) {
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - Gesture Handler

@interface CameraGestureHandler : NSObject
- (void)handleFloatingButtonTap:(UIButton *)button;
- (void)handlePanGesture:(UIPanGestureRecognizer *)gesture;
@end

@implementation CameraGestureHandler {
    CGPoint initialCenter;
}

- (void)handleFloatingButtonTap:(UIButton *)button {
    showEditActionSheet();
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)gesture {
    UIView *button = gesture.view;
    UIWindow *window = button.window;
    if (!window) return;

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            initialCenter = button.center;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [gesture translationInView:window];
            button.center = CGPointMake(initialCenter.x + translation.x, initialCenter.y + translation.y);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat screenWidth = window.bounds.size.width;
            CGFloat screenHeight = window.bounds.size.height;
            CGFloat halfW = button.bounds.size.width / 2.0;
            CGFloat halfH = button.bounds.size.height / 2.0;
            CGFloat finalY = fmin(fmax(button.center.y, halfH + 10), screenHeight - halfH - 10);
            CGFloat finalX = (button.center.x < screenWidth / 2) ? halfW + 10 : screenWidth - halfW - 10;

            [UIView animateWithDuration:0.3 animations:^{
                button.center = CGPointMake(finalX, finalY);
            }];
            break;
        }
        default:
            break;
    }
}

@end

#pragma mark - Photos Permission

static void checkAndLogPhotosPermission(void) {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus newStatus) {
            NSLog(@"[AppCloner][Camera] Photos permission: %@", newStatus == PHAuthorizationStatusAuthorized ? @"granted" : @"denied");
        }];
    }
}

#pragma mark - Entry Point

static CameraGestureHandler *g_gestureHandler = nil;

__attribute__((constructor))
static void cameraFloatingButtonEntry(void) {
    NSLog(@"[AppCloner][Camera] Initializing floating button...");
    checkAndLogPhotosPermission();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) {
            NSLog(@"[AppCloner][Camera] No keyWindow found after delay.");
            return;
        }

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            g_gestureHandler = [[CameraGestureHandler alloc] init];
        });

        CGRect screenBounds = [[UIScreen mainScreen] bounds];
        UIButton *floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(screenBounds.size.width - 60,
                                          (screenBounds.size.height / 2) - 25,
                                          50, 50);
        floatingButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
        floatingButton.layer.cornerRadius = 25;
        floatingButton.clipsToBounds = YES;
        floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
        floatingButton.layer.shadowOpacity = 0.3f;
        floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
        floatingButton.layer.shadowRadius = 4.0f;
        [floatingButton setTitle:@"C" forState:UIControlStateNormal];
        [floatingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];

        [floatingButton addTarget:g_gestureHandler
                           action:@selector(handleFloatingButtonTap:)
                 forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:g_gestureHandler
                                                                                    action:@selector(handlePanGesture:)];
        [floatingButton addGestureRecognizer:panGesture];

        g_cameraFloatingButton = floatingButton;
        g_cameraFloatingButton.hidden = YES;

        [keyWindow addSubview:g_cameraFloatingButton];
        [keyWindow bringSubviewToFront:g_cameraFloatingButton];
        NSLog(@"[AppCloner][Camera] Floating button added (initially hidden).");
    });
}
