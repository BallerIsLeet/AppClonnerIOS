#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "ClonerConfig.h"

%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    static CLLocationCoordinate2D cachedCoordinates;
    static NSDate *lastUpdateTime;

    if (!lastUpdateTime || [[NSDate date] timeIntervalSinceDate:lastUpdateTime] >= 20 * 60) {
        NSLog(@"[AppCloner][Location] Updating location after 20 minutes");

        CLLocationCoordinate2D modifiedCoordinates;
        BOOL isLocationFromIP = NO;

        if (ClonerConfig.hasValidLocation) {
            modifiedCoordinates.latitude = ClonerConfig.locationLat;
            modifiedCoordinates.longitude = ClonerConfig.locationLon;
            NSLog(@"[AppCloner][Location] Using configured coordinates");
        } else {
            NSLog(@"[AppCloner][Location] No valid config, attempting IP location");
            isLocationFromIP = YES;
        }

        if (isLocationFromIP) {
            NSURL *url = [NSURL URLWithString:@"https://ipinfo.io/json"];
            NSURLRequest *request = [NSURLRequest requestWithURL:url];
            NSURLSession *session = [NSURLSession sharedSession];
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

            __block NSDictionary *responseDict = nil;

            NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (!error && data) {
                    responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                }
                dispatch_semaphore_signal(semaphore);
            }];

            [task resume];
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

            if (responseDict && responseDict[@"loc"]) {
                NSArray *coordinates = [responseDict[@"loc"] componentsSeparatedByString:@","];
                if (coordinates.count == 2) {
                    modifiedCoordinates.latitude = [coordinates[0] doubleValue];
                    modifiedCoordinates.longitude = [coordinates[1] doubleValue];
                } else {
                    modifiedCoordinates.latitude = 40.7128;
                    modifiedCoordinates.longitude = -74.0060;
                }
            } else {
                modifiedCoordinates.latitude = 40.7128;
                modifiedCoordinates.longitude = -74.0060;
            }
        }

        // Add randomization (32m radius)
        double radiusMeters = 32.0;
        double randomAngle = ((double)arc4random() / UINT32_MAX) * 2.0 * M_PI;

        double latInDegreesPerMeter = 1.0 / 111320.0;
        double lonInDegreesPerMeter = 1.0 / (111320.0 * cos(modifiedCoordinates.latitude * M_PI / 180.0));

        modifiedCoordinates.latitude += (radiusMeters * latInDegreesPerMeter) * cos(randomAngle);
        modifiedCoordinates.longitude += (radiusMeters * lonInDegreesPerMeter) * sin(randomAngle);

        cachedCoordinates = modifiedCoordinates;
        lastUpdateTime = [NSDate date];
    }

    return cachedCoordinates;
}
%end

%ctor {
    NSLog(@"[AppCloner][Location] Location spoofer initialized");
}
