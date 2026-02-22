//
//  FakeCapturePhoto.m
//  Created by YourName on 2025-01-20
//

#import "FakeCapturePhoto.h"
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h> // For extracting EXIF metadata

@implementation FakeCapturePhoto

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        _jpegData = data;
    }
    return self;
}

#pragma mark - Mimicking AVCapturePhoto
- (NSData *)fileDataRepresentation {
    return self.jpegData;
}

- (CVPixelBufferRef)pixelBuffer {
    if (!self.jpegData) {
        return NULL;
    }
    
    UIImage *image = [UIImage imageWithData:self.jpegData];
    if (!image) {
        NSLog(@"[FakeCapturePhoto] Error: Could not create UIImage from JPEG data.");
        return NULL;
    }
    
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) {
        NSLog(@"[FakeCapturePhoto] Error: Could not get CGImage from UIImage.");
        return NULL;
    }
    
    // Prepare pixel buffer attributes
    NSDictionary *options = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{} // needed on iOS
    };
    
    CVPixelBufferRef pxbuffer = NULL;
    size_t width  = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    OSType pixelFormat = kCVPixelFormatType_32ARGB;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          width,
                                          height,
                                          pixelFormat,
                                          (__bridge CFDictionaryRef)options,
                                          &pxbuffer);
    
    if (status != kCVReturnSuccess || pxbuffer == NULL) {
        NSLog(@"[FakeCapturePhoto] Error: CVPixelBufferCreate failed with status %d", status);
        return NULL;
    }
    
    // Draw the CGImage into the pixel buffer
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    if (!pxdata) {
        NSLog(@"[FakeCapturePhoto] Error: Could not get base address of pixel buffer.");
        CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
        CVPixelBufferRelease(pxbuffer);
        return NULL;
    }
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata,
                                                 width,
                                                 height,
                                                 8, // bits per component
                                                 CVPixelBufferGetBytesPerRow(pxbuffer),
                                                 rgbColorSpace,
                                                 kCGImageAlphaNoneSkipFirst);
    if (!context) {
        NSLog(@"[FakeCapturePhoto] Error: Could not create CGBitmapContext.");
        CGColorSpaceRelease(rgbColorSpace);
        CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
        CVPixelBufferRelease(pxbuffer);
        return NULL;
    }
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    
    CGContextRelease(context);
    CGColorSpaceRelease(rgbColorSpace);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    // pxbuffer is retained for the caller. They must call CFRelease or CVPixelBufferRelease later.
    return pxbuffer;
}

// Minimal implementation to return an EXIF dictionary from jpegData
- (NSDictionary *)metadata {
    if (!self.jpegData) {
        return @{};
    }
    
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)(self.jpegData), NULL);
    if (!source) {
        return @{};
    }
    CFDictionaryRef cfMetadata = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    if (!cfMetadata) {
        CFRelease(source);
        return @{};
    }
    NSDictionary *metadataDict = [NSDictionary dictionaryWithDictionary:(__bridge NSDictionary *)cfMetadata];
    CFRelease(cfMetadata);
    CFRelease(source);
    
    return metadataDict ?: @{};
}

@end
