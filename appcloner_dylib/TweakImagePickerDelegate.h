//
//  TweakImagePickerDelegate.h
//  Created by YourName on 2025-01-20
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <AVFoundation/AVFoundation.h> // Import necessary framework

NS_ASSUME_NONNULL_BEGIN

@interface TweakImagePickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>

// Properties to store the original context
@property (nonatomic, weak) id<AVCapturePhotoCaptureDelegate> storedDelegate;
@property (nonatomic, strong) AVCapturePhotoSettings *storedSettings;
@property (nonatomic, weak) AVCapturePhotoOutput *storedPhotoOutput;

@end

NS_ASSUME_NONNULL_END
