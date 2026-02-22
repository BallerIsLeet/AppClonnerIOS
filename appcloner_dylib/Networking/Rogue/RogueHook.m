//
//  RogueHook.m
//  Created on 8/4/19
//

@import Foundation;
@import ObjectiveC.runtime;
@import MachO.dyld;
@import Darwin.POSIX.dlfcn;
@import Darwin.POSIX.pthread.pthread;

#import "RogueHook-Private.h"
#import "RGEProxy.h"
#import "RGELog.h"

static const int MaxHooks = 1024;
static int storedHookCount = 0;
typedef struct {
    void *hookImplementation;
    void *originalImplementation;
} StoredHook;

StoredHook storedHooks[MaxHooks];

@implementation RogueHookImplementor

static Protocol *hookProtocol;

+ (void)load {
    bzero(storedHooks, sizeof(StoredHook) * MaxHooks);

    hookProtocol = @protocol(RogueHook);
    [self implementAllMethodHooksForCurrentImage];
}

+ (BOOL)implementAllMethodHooksForCurrentImage {
    const char *image = [self currentImage];
    if (!image) {
        [RGELog log:@"Couldn't find image for class %@", NSStringFromClass(self.class)];
        return FALSE;
    }

    return [self implementAllMethodHooksForImage:image];
}

+ (BOOL)implementAllMethodHooksForImage:(const char *)image {
    unsigned int classCount = 0;
    const char **classNames;
    classNames = objc_copyClassNamesForImage(image, &classCount);

    for (unsigned int index = 0; index < classCount; index += 1) {
        const char *className = classNames[index];
        Class metaClass = objc_getMetaClass(className);
        if (!metaClass) {
            [RGELog log:@"Couldn't get MetaClass %s", className];
            continue;
        }

        Class hookClass = objc_getClass(className);
        if (!hookClass) {
            [RGELog log:@"Couldn't get class %s", className];
            continue;
        }

        if (class_conformsToProtocol(hookClass, hookProtocol) == FALSE) {
            continue;
        }
        [self implementHooksForMetaClassOnLoad:metaClass hookClass:hookClass className:className];
    }

    free(classNames);
    return TRUE;
}

// MARK: - Hooking

+ (BOOL)implementHooksForMetaClassOnLoad:(Class)metaClass
                               hookClass:(Class)hookClass
                               className:(const char *)className {
    if ([hookClass respondsToSelector:@selector(hookOnLoad)]) {
        if ([hookClass hookOnLoad] == FALSE) {
            Method hookMethod = class_getClassMethod(self.class, @selector(hookClass_hook));
            [self addMethodToClass:metaClass fromClass:self.class method:hookMethod newName:@selector(hook)];
            return FALSE;
        }
    }

    [self implementHooksForMetaClass:metaClass hookClass:hookClass className:className];
    return TRUE;
}

+ (BOOL)implementHooksForClass:(Class)targetClass {
    const char *className = class_getName(targetClass);
    Class metaClass = objc_getMetaClass(className);
    Class hookClass = objc_getClass(className);
    return [self implementHooksForMetaClass:metaClass hookClass:hookClass className:className];
}

+ (BOOL)implementHooksForMetaClass:(Class)metaClass
                         hookClass:(Class)hookClass
                         className:(const char *)classNameCString {
    NSString *className = @(classNameCString);

    NSArray *targetClasses;
    NSString *hookClassPrefix = @"HOOK_";
    if ([hookClass respondsToSelector:@selector(targetClasses)]) {
        targetClasses = [hookClass targetClasses];
    } else if ([hookClass respondsToSelector:@selector(targetClass)]) {
        targetClasses = @[[hookClass targetClass]];
    } else if ([className hasPrefix:hookClassPrefix]) {
        targetClasses = @[[className substringFromIndex:hookClassPrefix.length]];
    } else {
        [RGELog log:@"%@ must implement a target class method.", className];
        return FALSE;
    }

    BOOL enforceTypeEncodingChecks = TRUE;
    if ([hookClass respondsToSelector:@selector(enforceTypeEncodingChecks)]) {
        enforceTypeEncodingChecks = [hookClass enforceTypeEncodingChecks];
    }

    for (NSString *targetClassName in targetClasses) {
        void (^handleHook)(Class targetClass) = ^(Class targetClass) {
            [RGELog log:@"Class: %@, target: %@", className, targetClassName];
            [self implementMethodHooksForClass:hookClass
                                   isMetaClass:FALSE
                                   targetClass:targetClass
                                     className:className.UTF8String
                     enforceTypeEncodingChecks:enforceTypeEncodingChecks];
            Class targetMetaClass = objc_getMetaClass(class_getName(targetClass));
            if (!targetMetaClass) {
                return;
            }

            [self implementMethodHooksForClass:metaClass
                                   isMetaClass:TRUE
                                   targetClass:targetMetaClass
                                     className:className.UTF8String
                     enforceTypeEncodingChecks:enforceTypeEncodingChecks];
        };

        Class targetClass = objc_getClass(targetClassName.UTF8String);
        if (!targetClass) {
            [RGELog log:@"Couldn't find target class %@, trying in 2 seconds", targetClassName];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                Class targetClass = objc_getClass(targetClassName.UTF8String);
                if (targetClass) {
                    handleHook(targetClass);
                }
            });
            continue;
        }

        handleHook(targetClass);
    }

    return TRUE;
}

+ (void)implementMethodHooksForClass:(Class)hookClass
                         isMetaClass:(BOOL)isMetaClass
                         targetClass:(Class)targetClass
                           className:(const char *)className
           enforceTypeEncodingChecks:(BOOL)enforceTypeEncodingChecks {
    unsigned int methodCount;
    Method *methods = class_copyMethodList(hookClass, &methodCount);
    if (!methods) {
        [RGELog log:@"Couldn't get method list for class: %s", className];
        return;
    }

    Method originalMethod = class_getClassMethod(self.class, @selector(targetClass_original));
    [self addMethodToClass:targetClass fromClass:self.class method:originalMethod newName:@selector(original)];

    NSArray <NSString *> *blacklistedMethods = @[@".cxx_destruct"];

    for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex += 1) {
        Method hookMethod = methods[methodIndex];
        if (!hookMethod) {
            [RGELog log:@"Unable to get method at index: %d for %s", methodIndex, className];
            continue;
        }

        SEL hookMethodSelector = method_getName(hookMethod);
        if (!hookMethodSelector) {
            [RGELog log:@"Unable to get method method name index: %d for %s", methodIndex, className];
            continue;
        }

        NSString *hookMethodName = NSStringFromSelector(hookMethodSelector);

        if ([blacklistedMethods containsObject:hookMethodName]) {
            continue;
        }

        NSString *originalStorePrefix = @"original_";
        if ([hookMethodName hasPrefix:originalStorePrefix]) {
            continue;
        }

        NSString *targetMethodName = hookMethodName;
        SEL targetMethodSelector = NSSelectorFromString(targetMethodName);
        Method targetMethod = class_getInstanceMethod(targetClass, targetMethodSelector);

        BOOL isHookProtocolMethod = FALSE;
        BOOL isInstance = isMetaClass == FALSE;
        struct objc_method_description protocolMethod;
        protocolMethod = protocol_getMethodDescription(hookProtocol, targetMethodSelector, FALSE, isInstance);
        isHookProtocolMethod = protocolMethod.name != NULL;

        if (isHookProtocolMethod) {
            continue;
        }

        if (targetMethod == NULL) {
            [RGELog log:@"adding new method to %@: %@", NSStringFromClass(targetClass), targetMethodName];
            [self addMethodToClass:targetClass fromClass:hookClass method:hookMethod];
            continue;
        }

        const char *targetTypeEncoding = method_getTypeEncoding(targetMethod);

        const char *hookedTypeEncoding = method_getTypeEncoding(hookMethod);
        if (strcmp(targetTypeEncoding, hookedTypeEncoding) != 0) {
            if (enforceTypeEncodingChecks) {
                [RGELog log:@"Error: Not implementing hook for [%s %s]: target type encoding %s doesn't match hook type encoding: %s",
                 className, sel_getName(targetMethodSelector), targetTypeEncoding, hookedTypeEncoding];
                continue;
            } else {
                [RGELog log:@"Warning: [%s %s] target type encoding %s doesn't match hook type encoding: %s",
                 className, sel_getName(targetMethodSelector), targetTypeEncoding, hookedTypeEncoding];
            }
        }


        IMP hookImplementation = method_getImplementation(hookMethod);
        if (!hookImplementation) {
            [RGELog log:@"Error: Couldn't get implementation for method [%s %@]", className, hookMethodName];
            continue;
        }

        NSString *originalStoreMethodName = [originalStorePrefix stringByAppendingString:targetMethodName];
        SEL originalStoreSelector = NSSelectorFromString(originalStoreMethodName);
        class_getClassMethod(hookClass, originalStoreSelector);

        IMP originalImplementation = method_getImplementation(targetMethod);
        if (!originalImplementation) {
            [RGELog log:@"Error: Couldn't get implementation for method [%s %@]", className, targetMethodName];
            continue;
        }

        class_addMethod(targetClass, originalStoreSelector, originalImplementation, targetTypeEncoding);

        IMP previousImplementation = class_replaceMethod(targetClass,
                                                         targetMethodSelector,
                                                         hookImplementation,
                                                         targetTypeEncoding);
        if (previousImplementation != NULL) {
            [self storeHook:hookImplementation originalImplementation:previousImplementation];
            [RGELog log:@"Implemented hook for [%s %@]", className, targetMethodName];
        } else {
            [RGELog log:@"Failed to implement hook for [%s %@]", className, targetMethodName];
        }

    }

    free(methods);
}

+ (void)addMethodToClass:(Class)targetClass fromClass:(Class)fromClass method:(Method)method {
    [self addMethodToClass:targetClass fromClass:fromClass method:method newName:NULL];
}

+ (void)addMethodToClass:(Class)targetClass fromClass:(Class)fromClass method:(Method)method newName:(SEL)name {
    SEL selector;
    if (name) {
        selector = name;
    } else {
        selector = method_getName(method);
    }

    const char *typeEncoding = method_getTypeEncoding(method);
    IMP implementation = method_getImplementation(method);
    class_addMethod(targetClass, selector, implementation, typeEncoding);
}

// MARK: - Utilities

+ (const char *)currentImage {
    static int imageSymbolMarker = 1;

    static int DLADDR_ERROR = 0;
    Dl_info result;
    if (dladdr(&imageSymbolMarker, &result) == DLADDR_ERROR) {
        return nil;
    }

    return result.dli_fname;
}

// MARK: - Methods Added To Hook Classes

+ (BOOL)hookClass_hook {
    id <RogueHook> target = (id)self;
    return [RogueHookImplementor implementHooksForClass:target.class];
}

+ (id)targetClass_original {
    return [[RGEProxy alloc] initWithTarget:self];
}

// MARK: - Hook Storage for reference

+ (void)storeHook:(void *)hook originalImplementation:(void *)originalImplementation {
    static pthread_mutex_t _mutex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pthread_mutex_init(&_mutex, NULL);
    });

    pthread_mutex_lock(&_mutex);

    StoredHook *stored = &storedHooks[storedHookCount];
    storedHookCount += 1;

    stored->hookImplementation = hook;
    stored->originalImplementation = originalImplementation;

    pthread_mutex_unlock(&_mutex);

}

+ (void)enumerateHookImplementationsWithBlock:(HookImplemetationEnumerationBlock)block {
    BOOL shouldStop = FALSE;
    int count = storedHookCount;

    for (int index = 0; index < count; index += 1) {
        StoredHook *stored = &storedHooks[index];
        block(stored->hookImplementation, stored->originalImplementation, &shouldStop);
        if (shouldStop) {
            break;
        }
    }
}

@end

