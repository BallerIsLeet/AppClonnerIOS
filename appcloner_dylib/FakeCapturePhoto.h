//
//  FakeCapturePhoto.h
//  Created by YourName on 2025-01-20
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>


@interface FakeCapturePhoto : NSObject


@property (nonatomic, strong) NSData *jpegData;


@property (nonatomic, readonly) NSDictionary *metadata;


- (CVPixelBufferRef)pixelBuffer;


- (NSData *)fileDataRepresentation;


- (instancetype)initWithData:(NSData *)data;

@end
