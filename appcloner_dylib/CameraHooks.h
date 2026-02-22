#ifndef CameraHooks_h
#define CameraHooks_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

void callOriginalCapturePhoto(AVCapturePhotoOutput *output, AVCapturePhotoSettings *settings, id<AVCapturePhotoCaptureDelegate> delegate);

extern BOOL g_shouldApplyEdits;
extern BOOL g_isVerifierModeEnabled;

#endif
