#import "ImageTransforms.h"
#import <CoreImage/CoreImage.h>

UIImage *rotateImage(UIImage *image, CGFloat angle) {
    CGAffineTransform transform = CGAffineTransformMakeRotation(angle);
    CGRect newRect = CGRectApplyAffineTransform(CGRectMake(0, 0, image.size.width, image.size.height), transform);

    UIGraphicsBeginImageContextWithOptions(newRect.size, NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextTranslateCTM(context, newRect.size.width / 2, newRect.size.height / 2);
    CGContextRotateCTM(context, angle);

    [image drawInRect:CGRectMake(-image.size.width / 2, -image.size.height / 2, image.size.width, image.size.height)];

    UIImage *rotatedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return rotatedImage;
}

UIImage *mirrorImage(UIImage *image) {
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextTranslateCTM(context, image.size.width, 0);
    CGContextScaleCTM(context, -1.0, 1.0);

    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];

    UIImage *mirroredImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return mirroredImage;
}

UIImage *adjustBrightness(UIImage *image, CGFloat brightnessFactor) {
    CIImage *ciImage = [[CIImage alloc] initWithImage:image];
    CIFilter *filter = [CIFilter filterWithName:@"CIColorControls"];
    [filter setValue:ciImage forKey:kCIInputImageKey];
    [filter setValue:@(brightnessFactor - 1.0) forKey:kCIInputBrightnessKey];

    CIContext *context = [CIContext contextWithOptions:nil];
    CIImage *outputImage = [filter outputImage];
    CGImageRef cgImage = [context createCGImage:outputImage fromRect:[outputImage extent]];

    UIImage *resultImage = [UIImage imageWithCGImage:cgImage scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(cgImage);

    return resultImage;
}

UIImage *rotateImageDegrees(UIImage *image, CGFloat degrees) {
    CGFloat radians = degrees * M_PI / 180.0;

    UIView *rotatedViewBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, image.size.width, image.size.height)];
    CGAffineTransform t = CGAffineTransformMakeRotation(radians);
    rotatedViewBox.transform = t;
    CGSize rotatedSize = rotatedViewBox.frame.size;

    UIGraphicsBeginImageContextWithOptions(rotatedSize, NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextTranslateCTM(context, rotatedSize.width / 2.0, rotatedSize.height / 2.0);
    CGContextRotateCTM(context, radians);
    [image drawInRect:CGRectMake(-image.size.width / 2.0,
                                 -image.size.height / 2.0,
                                  image.size.width,
                                  image.size.height)];

    UIImage *rotatedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    // Calculate the largest inscribed rectangle
    CGFloat W = image.size.width;
    CGFloat H = image.size.height;
    CGFloat absRadians = fmod(fabs(radians), M_PI);
    CGFloat calcAngle = absRadians;
    if (calcAngle > M_PI_2) {
        calcAngle = M_PI - calcAngle;
    }

    CGFloat sinTheta = sin(calcAngle);
    CGFloat cosTheta = cos(calcAngle);
    CGRect cropRect;

    if (calcAngle == 0) {
        cropRect = CGRectMake((rotatedSize.width - W) / 2.0, (rotatedSize.height - H) / 2.0, W, H);
    } else if (calcAngle == M_PI_2) {
        cropRect = CGRectMake((rotatedSize.width - H) / 2.0, (rotatedSize.height - W) / 2.0, H, W);
    } else {
        CGFloat W_rot = W * cosTheta + H * sinTheta;
        CGFloat H_rot = W * sinTheta + H * cosTheta;
        CGFloat scaleFactor;
        if ((W / H) >= (W_rot / H_rot)) {
            scaleFactor = W / (W * cosTheta + H * sinTheta);
        } else {
            scaleFactor = H / (W * sinTheta + H * cosTheta);
        }

        CGFloat cropWidth = W * scaleFactor;
        CGFloat cropHeight = H * scaleFactor;
        CGFloat cropX = (rotatedSize.width - cropWidth) / 2.0;
        CGFloat cropY = (rotatedSize.height - cropHeight) / 2.0;
        cropRect = CGRectMake(cropX, cropY, cropWidth, cropHeight);
    }

    // Zoom crop
    CGFloat zoomCropFactor = 0.95;
    cropRect = CGRectInset(cropRect,
                           cropRect.size.width * (1 - zoomCropFactor) / 2.0,
                           cropRect.size.height * (1 - zoomCropFactor) / 2.0);

    CGImageRef imageRef = rotatedImage.CGImage;
    if (!imageRef) {
        NSLog(@"[AppCloner][ImageTransforms] Failed to get CGImageRef from rotated image.");
        return rotatedImage;
    }

    CGRect scaledCropRect = CGRectMake(cropRect.origin.x * rotatedImage.scale,
                                       cropRect.origin.y * rotatedImage.scale,
                                       cropRect.size.width * rotatedImage.scale,
                                       cropRect.size.height * rotatedImage.scale);

    CGImageRef croppedImageRef = CGImageCreateWithImageInRect(imageRef, scaledCropRect);
    if (!croppedImageRef) {
        NSLog(@"[AppCloner][ImageTransforms] Failed to crop image.");
        return rotatedImage;
    }

    UIImage *croppedImage = [UIImage imageWithCGImage:croppedImageRef scale:rotatedImage.scale orientation:UIImageOrientationUp];
    CGImageRelease(croppedImageRef);

    return croppedImage;
}
