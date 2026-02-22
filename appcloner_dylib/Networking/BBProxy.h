//
//  BBProxy.h
//  Created on 10/17/23
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BBProxy : NSObject

@property (class, readonly) NSString *host;
@property (class, readonly) NSNumber *port;
@property (class, readonly) NSString *username;
@property (class, readonly) NSString *password;
@property (class, readonly) BOOL socksProxy;

+ (void)setProxy;
+ (NSDictionary *)proxyDictionary;

@end

NS_ASSUME_NONNULL_END
