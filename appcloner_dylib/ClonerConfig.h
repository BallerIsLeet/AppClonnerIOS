#ifndef ClonerConfig_h
#define ClonerConfig_h

#import <Foundation/Foundation.h>

@interface ClonerConfig : NSObject

// Bundle
@property (class, readonly) NSString *originalBundleId;
@property (class, readonly) NSString *bundleName;
@property (class, readonly) NSString *originalTeamId;
@property (class, readonly) NSString *cloneUUID;
@property (class, readonly) NSString *keychainAccessGroup;

// Feature flags
@property (class, readonly) BOOL deviceSpoofingEnabled;
@property (class, readonly) BOOL igDumperEnabled;
@property (class, readonly) BOOL backgroundProcessEnabled;

// Location
@property (class, readonly) double locationLat;
@property (class, readonly) double locationLon;
@property (class, readonly) BOOL hasValidLocation;

// Proxy
@property (class, readonly) NSDictionary *proxyConfig;

// Raw config access (for edge cases)
@property (class, readonly) NSDictionary *rawConfig;

+ (void)loadConfig;

@end

#endif
