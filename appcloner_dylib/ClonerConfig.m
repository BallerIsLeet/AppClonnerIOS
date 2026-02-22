#import "ClonerConfig.h"

static NSDictionary *_config = nil;

@implementation ClonerConfig

+ (void)loadConfig {
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    _config = infoDict[@"clonerConfig"];
    if (_config) {
        NSLog(@"[AppCloner][Config] Loaded clonerConfig from Info.plist");
    } else {
        NSLog(@"[AppCloner][Config] No clonerConfig found in Info.plist");
        _config = @{};
    }
}

+ (NSDictionary *)rawConfig {
    return _config ?: @{};
}

#pragma mark - Bundle

+ (NSString *)originalBundleId {
    return _config[@"originalBundleId"] ?: @"";
}

+ (NSString *)bundleName {
    return _config[@"bundleName"] ?: @"";
}

+ (NSString *)originalTeamId {
    return _config[@"original_team_id"] ?: @"";
}

+ (NSString *)cloneUUID {
    return _config[@"cloneUUID"] ?: @"";
}

+ (NSString *)keychainAccessGroup {
    return _config[@"keychainAccessGroup"] ?: @"";
}

#pragma mark - Feature Flags

+ (BOOL)deviceSpoofingEnabled {
    id val = _config[@"is_device_spoofing_enabled"];
    if ([val isKindOfClass:[NSNumber class]] || [val isKindOfClass:[NSString class]]) {
        return [val boolValue];
    }
    return NO;
}

+ (BOOL)igDumperEnabled {
    id val = _config[@"is_ig_dumper_enabled"];
    if ([val isKindOfClass:[NSNumber class]] || [val isKindOfClass:[NSString class]]) {
        return [val boolValue];
    }
    return NO;
}

+ (BOOL)backgroundProcessEnabled {
    id val = _config[@"backgroundprocess_enabled"];
    if ([val isKindOfClass:[NSNumber class]] || [val isKindOfClass:[NSString class]]) {
        return [val boolValue];
    }
    return NO;
}

#pragma mark - Location

+ (double)locationLat {
    NSDictionary *location = _config[@"location"];
    if (location[@"Lat"]) {
        return [location[@"Lat"] doubleValue];
    }
    return 0.0;
}

+ (double)locationLon {
    NSDictionary *location = _config[@"location"];
    if (location[@"Lon"]) {
        return [location[@"Lon"] doubleValue];
    }
    return 0.0;
}

+ (BOOL)hasValidLocation {
    NSDictionary *location = _config[@"location"];
    if (!location) return NO;
    NSString *lat = [NSString stringWithFormat:@"%@", location[@"Lat"] ?: @""];
    NSString *lon = [NSString stringWithFormat:@"%@", location[@"Lon"] ?: @""];
    return lat.length > 0 && lon.length > 0 &&
           ![lat isEqualToString:@""] && ![lon isEqualToString:@""];
}

#pragma mark - Proxy

+ (NSDictionary *)proxyConfig {
    NSDictionary *proxy = _config[@"Proxy"];
    return proxy ?: @{};
}

@end
