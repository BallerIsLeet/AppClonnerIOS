//
//  TweakImagePickerDelegate.m
//  Created by YourName on 2025-01-20
//

#import "TweakImagePickerDelegate.h"
#import "FakeCapturePhoto.h"
#import "CameraHooks.h"
#import <AVFoundation/AVFoundation.h>

extern FakeCapturePhoto *g_cachedPhoto; // Global for caching

@implementation TweakImagePickerDelegate

- (void)cleanupStoredContext {
    self.storedDelegate = nil;
    self.storedSettings = nil;
    self.storedPhotoOutput = nil;
    NSLog(@"[TweakDelegate] Cleaned up stored context.");
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *selectedImage = info[UIImagePickerControllerOriginalImage];
    if (!selectedImage) {
        NSLog(@"[TweakDelegate] No valid image picked.");
        [picker dismissViewControllerAnimated:YES completion:^{
            [self handleCancel];
        }];
        return;
    }
    NSLog(@"[TweakDelegate] Image picked successfully.");
    
    // Store the image as-is (no randomization edits here)
    NSData *jpegData = UIImageJPEGRepresentation(selectedImage, 1.0);
    FakeCapturePhoto *mockPhoto = [[FakeCapturePhoto alloc] initWithData:jpegData];
    g_cachedPhoto = mockPhoto;
    NSLog(@"[TweakDelegate] Cached photo updated (no randomization applied).");
    
    id<AVCapturePhotoCaptureDelegate> delegate = self.storedDelegate;
    AVCapturePhotoOutput *output = self.storedPhotoOutput;
    BOOL hasStoredContext = (delegate != nil && output != nil);
    
    [picker dismissViewControllerAnimated:YES completion:^{
        if (hasStoredContext) {
            if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                NSLog(@"[TweakDelegate] Has context. Calling original delegate's didFinishProcessingPhoto.");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [delegate captureOutput:output
                       didFinishProcessingPhoto:(AVCapturePhoto *)mockPhoto
                                         error:nil];
                    [self cleanupStoredContext];
                });
            } else {
                NSLog(@"[TweakDelegate] Has context, but delegate doesn't respond to selector.");
                [self cleanupStoredContext];
            }
        } else {
            NSLog(@"[TweakDelegate] No context. Cached photo updated. Doing nothing further.");
        }
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    NSLog(@"[TweakDelegate] User cancelled picking an image.");
    [picker dismissViewControllerAnimated:YES completion:^{
        [self handleCancel];
    }];
}

- (void)handleCancel {
    NSLog(@"[TweakDelegate] Handling cancellation.");
    id<AVCapturePhotoCaptureDelegate> delegate = self.storedDelegate;
    AVCapturePhotoSettings *settings = self.storedSettings;
    AVCapturePhotoOutput *output = self.storedPhotoOutput;
    BOOL hasStoredContext = (delegate != nil && settings != nil && output != nil);
    
    if (hasStoredContext) {
        NSLog(@"[TweakDelegate] Has context. Calling original capture implementation via helper on cancel.");
        callOriginalCapturePhoto(output, settings, delegate);
    } else {
        NSLog(@"[TweakDelegate] No context on cancel. Doing nothing.");
    }
    
    if (hasStoredContext) {
        [self cleanupStoredContext];
    }
}

@end
