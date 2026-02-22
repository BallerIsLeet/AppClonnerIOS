//
//  Hook NSURLSession
//
//  10/18/23
//

@import Foundation;

#import "Rogue/RogueHook.h"
#import "BBProxy.h"
#import "NSHook.h"


@implementation HOOK_NSURLSession

+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    NSDictionary *proxyDict = [BBProxy proxyDictionary];
    
    [configuration setConnectionProxyDictionary:proxyDict];
    
    return [self.original sessionWithConfiguration:configuration];
}

+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(nullable id <NSURLSessionDelegate>)delegate delegateQueue:(nullable NSOperationQueue *)queue {
    
    NSDictionary *proxyDict = [BBProxy proxyDictionary];
    
    [configuration setConnectionProxyDictionary:proxyDict];
    
    return [self.original sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}

+ (NSURLSession *)sharedSession {
    NSDictionary *proxyDict = [BBProxy proxyDictionary];
    
    NSLog(@"Setting proxy to %@", proxyDict);
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [config setConnectionProxyDictionary:proxyDict];
    
    return [self.original sessionWithConfiguration:config];
}

@end
