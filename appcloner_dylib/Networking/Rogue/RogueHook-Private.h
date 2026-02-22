//
//  RogueHook-Testing.h
//  Created on 8/4/19
//

typedef void (^HookImplemetationEnumerationBlock)(void *hookImplementation, void *originalImplementation, BOOL *stop);

@interface RogueHookImplementor : NSObject

+ (const char *)currentImage;

+ (BOOL)implementAllMethodHooksForImage:(const char *)image;
+ (void)enumerateHookImplementationsWithBlock:(HookImplemetationEnumerationBlock)block;

@end

#import "RogueHook.h"
