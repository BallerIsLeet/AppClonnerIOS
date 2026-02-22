#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import "FakeCapturePhoto.h"
#import "ImageTransforms.h"
#import "CameraHooks.h"

#pragma mark - Globals

static IMP g_originalCapturePhotoImp = NULL;
static IMP g_originalIsRunningImp = NULL;

// Shared state (accessed by CameraFloatingButton.m)
FakeCapturePhoto *g_cachedPhoto = nil;
BOOL g_shouldApplyEdits = YES;
BOOL g_isVerifierModeEnabled = NO;
UIButton *g_cameraFloatingButton = nil;

#pragma mark - Helper

void callOriginalCapturePhoto(AVCapturePhotoOutput *output, AVCapturePhotoSettings *settings, id<AVCapturePhotoCaptureDelegate> delegate) {
    if (g_originalCapturePhotoImp) {
        ((void (*)(id, SEL, AVCapturePhotoSettings *, id<AVCapturePhotoCaptureDelegate>))g_originalCapturePhotoImp)(output, @selector(capturePhotoWithSettings:delegate:), settings, delegate);
    } else {
        NSLog(@"[AppCloner][Camera] Error: Original capturePhoto implementation not found!");
    }
}

#pragma mark - AVCapturePhotoOutput Swizzling

@implementation AVCapturePhotoOutput (Swizzling)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SEL originalSelector = @selector(capturePhotoWithSettings:delegate:);
        SEL swizzledSelector = @selector(swizzled_capturePhotoWithSettings:delegate:);

        Method originalMethod = class_getInstanceMethod([self class], originalSelector);
        Method swizzledMethod = class_getInstanceMethod([self class], swizzledSelector);

        if (!originalMethod || !swizzledMethod) {
            NSLog(@"[AppCloner][Camera] Swizzle failed: method(s) not found for capturePhotoWithSettings:delegate:");
            return;
        }

        g_originalCapturePhotoImp = method_getImplementation(originalMethod);

        BOOL didAddMethod = class_addMethod([self class],
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod([self class],
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
        NSLog(@"[AppCloner][Camera] Swizzled capturePhotoWithSettings:delegate:");
    });
}

- (void)swizzled_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings
                                  delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (g_cachedPhoto) {
        if (delegate && [delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
            FakeCapturePhoto *photoToUse = g_cachedPhoto;
            BOOL applyEditsThisTime = g_isVerifierModeEnabled ? g_shouldApplyEdits : NO;

            if (applyEditsThisTime) {
                NSData *originalData = g_cachedPhoto.jpegData;
                UIImage *image = [UIImage imageWithData:originalData];
                if (image) {
                    UIImage *brightenedImage = adjustBrightness(image, 1.025);
                    UIImage *finalImage = rotateImageDegrees(brightenedImage ?: image, 1.0);
                    NSData *modifiedData = UIImageJPEGRepresentation(finalImage ?: image, 1.0);
                    if (modifiedData) {
                        photoToUse = [[FakeCapturePhoto alloc] initWithData:modifiedData];
                    }
                }
            }

            if (g_isVerifierModeEnabled) {
                g_shouldApplyEdits = !g_shouldApplyEdits;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate captureOutput:self
                 didFinishProcessingPhoto:(AVCapturePhoto *)photoToUse
                                   error:nil];
            });
        }
        return;
    }

    callOriginalCapturePhoto(self, settings, delegate);
}

@end

#pragma mark - AVCaptureSession Swizzling

@implementation AVCaptureSession (Swizzling)

- (BOOL)swizzled_isRunning {
    BOOL running = ((BOOL (*)(id, SEL))g_originalIsRunningImp)(self, @selector(isRunning));

    if (!g_cameraFloatingButton) {
        return running;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (running) {
            UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
            if (keyWindow) {
                if (g_cameraFloatingButton.window != keyWindow) {
                    [g_cameraFloatingButton removeFromSuperview];
                    [keyWindow addSubview:g_cameraFloatingButton];
                }
                [keyWindow bringSubviewToFront:g_cameraFloatingButton];
                g_cameraFloatingButton.hidden = NO;
            } else {
                g_cameraFloatingButton.hidden = YES;
            }
        } else {
            g_cameraFloatingButton.hidden = YES;
        }
    });

    return running;
}

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SEL originalSelector = @selector(isRunning);
        SEL swizzledSelector = @selector(swizzled_isRunning);

        Method originalMethod = class_getInstanceMethod([self class], originalSelector);
        Method swizzledMethod = class_getInstanceMethod([self class], swizzledSelector);

        if (!originalMethod || !swizzledMethod) {
            NSLog(@"[AppCloner][Camera] Swizzle failed: method(s) not found for isRunning");
            return;
        }

        g_originalIsRunningImp = method_getImplementation(originalMethod);

        BOOL didAddMethod = class_addMethod([self class],
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod([self class],
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
        NSLog(@"[AppCloner][Camera] Swizzled AVCaptureSession isRunning");
    });
}

@end
