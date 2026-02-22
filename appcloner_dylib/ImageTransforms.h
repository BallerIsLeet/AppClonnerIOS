#ifndef ImageTransforms_h
#define ImageTransforms_h

#import <UIKit/UIKit.h>

UIImage *rotateImage(UIImage *image, CGFloat angle);
UIImage *mirrorImage(UIImage *image);
UIImage *adjustBrightness(UIImage *image, CGFloat brightnessFactor);
UIImage *rotateImageDegrees(UIImage *image, CGFloat degrees);

#endif
