#import "Rogue/RGELog.h"
#import "BBProxy.h"
#import <xpc/xpc.h>
#import <arpa/inet.h>
#import "Rogue/RGEProxy.h"
#import "substrate.h"
#include <dlfcn.h>
#import "../ClonerConfig.h"

@import Network;

NW_RETURNS_RETAINED _Nullable nw_endpoint_t nw_path_copy_endpoint(nw_path_t path);
extern CFURLRef nw_endpoint_proxy_copy_synthesized_url(nw_endpoint_t endpoint);

CFN_EXPORT void
_CFNetworkSetOverrideSystemProxySettings(CFDictionaryRef) CF_AVAILABLE(10_6, 2_0);

enum network_proxy_type {
    network_proxy_type_direct = 1,
    network_proxy_type_pac_script = 1001,
    network_proxy_type_pac_url = 1002,
    network_proxy_type_http = 2001,
    network_proxy_type_https = 2002,
    network_proxy_type_ftp = 2003,
    network_proxy_type_gopher = 2004,
    network_proxy_type_socks_v4 = 3001,
    network_proxy_type_socks_v5 = 3002,
};

bool (*nw_path_should_use_proxy_original)(nw_path_t path, int64_t *arg2) = nil;
bool nw_path_should_use_proxy_replacement(nw_path_t path, int64_t *arg2) {
    nw_endpoint_t endpoint = nw_path_copy_endpoint(path);
    if (!endpoint) {
        return nw_path_should_use_proxy_original(path, arg2);
    }

    const char *hostname = nw_endpoint_get_hostname(endpoint);

    if (strstr(hostname, "bumble") == NULL) {
        return nw_path_should_use_proxy_original(path, arg2);
    }

    return true;
}

xpc_object_t (*nw_path_copy_proxy_settings_original)(nw_path_t path) = nil;

NW_RETURNS_RETAINED xpc_object_t nw_path_copy_proxy_settings_replacement(nw_path_t path) {
    xpc_object_t proxy_dictionary = xpc_dictionary_create(NULL, NULL, 0);
    if (BBProxy.socksProxy) {
        xpc_dictionary_set_int64(proxy_dictionary, "SOCKSEnable", 1);
        xpc_dictionary_set_string(proxy_dictionary, "SOCKSProxy", BBProxy.host.UTF8String);
        xpc_dictionary_set_int64(proxy_dictionary, "SOCKSPort", BBProxy.port.intValue);
        xpc_dictionary_set_int64(proxy_dictionary, "proxy_type", network_proxy_type_socks_v5);
        if (BBProxy.username) {
            xpc_dictionary_set_string(proxy_dictionary, "SOCKSUser", BBProxy.username.UTF8String);
            xpc_dictionary_set_string(proxy_dictionary, "SOCKSPassword", BBProxy.password.UTF8String);
        }
    } else {
        xpc_dictionary_set_string(proxy_dictionary, "HTTPSProxy", BBProxy.host.UTF8String);
        xpc_dictionary_set_string(proxy_dictionary, "HTTPProxy", BBProxy.host.UTF8String);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPPort", BBProxy.port.intValue);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPSPort", BBProxy.port.intValue);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPEnable", 1);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPSEnable", 1);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPProxyAuthenticated", 1);
        if (BBProxy.username) {
            xpc_dictionary_set_string(proxy_dictionary, "HTTPProxyUsername", BBProxy.username.UTF8String);
            xpc_dictionary_set_string(proxy_dictionary, "HTTPProxyPassword", BBProxy.password.UTF8String);
        }
    }

    xpc_object_t proxies_array = xpc_array_create(&proxy_dictionary, 1);
    xpc_object_t outer_array = xpc_array_create(&proxies_array, 1);
    return outer_array;
}

typedef nw_object_t nw_array_t;
typedef nw_object_t nw_proxy_config;
typedef nw_object_t OS_nw_dictionary;

nw_object_t nw_array_get_object_at_index(nw_array_t array, int index);
int nw_dictionary_get_count(OS_nw_dictionary dict);

extern void nw_path_set_proxy_settings(nw_path_t path, xpc_object_t settings);

nw_array_t (*nw_path_copy_proxy_configs_original)(nw_path_t path) = nil;

NW_RETURNS_RETAINED nw_array_t nw_path_copy_proxy_configs_replacement(nw_path_t path) {
    xpc_object_t proxy_dictionary = xpc_dictionary_create(NULL, NULL, 0);
    if (BBProxy.socksProxy) {
        xpc_dictionary_set_int64(proxy_dictionary, "SOCKSEnable", 1);
        xpc_dictionary_set_string(proxy_dictionary, "SOCKSProxy", BBProxy.host.UTF8String);
        xpc_dictionary_set_int64(proxy_dictionary, "SOCKSPort", BBProxy.port.intValue);
        xpc_dictionary_set_int64(proxy_dictionary, "proxy_type", network_proxy_type_socks_v5);
        if (BBProxy.username) {
            xpc_dictionary_set_string(proxy_dictionary, "SOCKSUser", BBProxy.username.UTF8String);
            xpc_dictionary_set_string(proxy_dictionary, "SOCKSPassword", BBProxy.password.UTF8String);
        }
    } else {
        xpc_dictionary_set_string(proxy_dictionary, "HTTPSProxy", BBProxy.host.UTF8String);
        xpc_dictionary_set_string(proxy_dictionary, "HTTPProxy", BBProxy.host.UTF8String);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPPort", BBProxy.port.intValue);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPSPort", BBProxy.port.intValue);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPEnable", 1);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPSEnable", 1);
        xpc_dictionary_set_int64(proxy_dictionary, "HTTPProxyAuthenticated", 1);
        if (BBProxy.username) {
            xpc_dictionary_set_string(proxy_dictionary, "HTTPProxyUsername", BBProxy.username.UTF8String);
            xpc_dictionary_set_string(proxy_dictionary, "HTTPProxyPassword", BBProxy.password.UTF8String);
        }
    }

    xpc_object_t proxies_array = xpc_array_create(&proxy_dictionary, 1);
    xpc_object_t outer_array = xpc_array_create(&proxies_array, 1);
    nw_path_set_proxy_settings(path, outer_array);

    nw_array_t original = nw_path_copy_proxy_configs_original(path);

    nw_proxy_config config = nw_array_get_object_at_index(original, 0);
    uintptr_t **stacks = nil;
    if ([RGEProxy instance:config getVariabledNamed:@"stacks" outValue:(void *)&stacks]) {
        NSLog(@"stacks: %@", (__bridge id)(void *)stacks);
        uintptr_t *dict_ptr = *(stacks + 2);
        xpc_object_t xpc_dict = (__bridge xpc_object_t)(void *)dict_ptr;
        xpc_dictionary_apply(xpc_dict, ^bool(const char * _Nonnull key, xpc_object_t  _Nonnull value) {
            NSLog(@"%s : %@", key, value);
            return true;
        });
    }

    [RGELog log:@"nw_path_copy_proxy_configs %@", original];
    return original;
}

@implementation BBProxy

+ (NSDictionary *)loadProxyConfig {
    return ClonerConfig.proxyConfig;
}

+ (NSString *)host {
    NSDictionary *proxyConfig = [self loadProxyConfig];
    return proxyConfig[@"host"] ?: @"";
}

+ (NSNumber *)port {
    NSDictionary *proxyConfig = [self loadProxyConfig];
    NSString *portString = proxyConfig[@"Port"];
    return portString ? @([portString integerValue]) : @(0);
}

+ (NSString *)username {
    NSDictionary *proxyConfig = [self loadProxyConfig];
    return proxyConfig[@"Username"] ?: @"";
}

+ (NSString *)password {
    NSDictionary *proxyConfig = [self loadProxyConfig];
    return proxyConfig[@"Password"] ?: @"";
}

+ (BOOL)socksProxy { return TRUE; }

+ (NSDictionary *)proxyDictionary {
    NSMutableDictionary *proxyDict;

    if ([self socksProxy]) {
        proxyDict = @{
            @"SOCKSEnable": @1,
            @"SOCKSProxy": BBProxy.host,
            @"SOCKSPort": BBProxy.port,
            @"proxy_type": @(3002),
            (NSString *)kCFStreamPropertySOCKSVersion: (NSString *)kCFStreamSocketSOCKSVersion5
        }.mutableCopy;

        if (BBProxy.username) {
            proxyDict[@"SOCKSUser"] = BBProxy.username;
            proxyDict[@"SOCKSPassword"] = BBProxy.password;
        }
    } else {
        proxyDict = @{
            (NSString *)kCFStreamPropertyHTTPSProxyHost: BBProxy.host,
            (NSString *)kCFStreamPropertyHTTPSProxyPort: BBProxy.port,
            (NSString *)kCFStreamPropertyHTTPProxyHost: BBProxy.host,
            (NSString *)kCFStreamPropertyHTTPProxyPort: BBProxy.port,
            @"HTTPEnable": @1,
            @"HTTPSEnable": @1,
            @"HTTPProxyAuthenticated": @1
        }.mutableCopy;

        if (BBProxy.username) {
            proxyDict[@"HTTPProxyUsername"] = BBProxy.username;
            proxyDict[@"HTTPProxyPassword"] = BBProxy.password;
        }
    }

    return proxyDict;
}

+ (void)load {
    [self setProxy];
}

+ (void)setProxy {
    NSDictionary *proxyDict = [self proxyDictionary];

    [RGELog log:@"--Setting proxy to %@", proxyDict];
    [[NSURLSessionConfiguration defaultSessionConfiguration] setConnectionProxyDictionary:proxyDict];

    _CFNetworkSetOverrideSystemProxySettings((__bridge CFDictionaryRef)proxyDict);

    void *handle = dlopen("/usr/lib/libnetwork.dylib", RTLD_NOW);

    if (@available(iOS 15, *)) {
        nw_path_copy_proxy_configs_original = dlsym(handle, "nw_path_copy_proxy_configs");
        if (nw_path_copy_proxy_configs_original) {
            MSHookFunction((void *)nw_path_copy_proxy_configs_original, (void *)&nw_path_copy_proxy_configs_replacement, (void **)&nw_path_copy_proxy_configs_original);
        }
    } else {
        nw_path_copy_proxy_settings_original = dlsym(handle, "nw_path_copy_proxy_settings");
        if (nw_path_copy_proxy_settings_original) {
            MSHookFunction((void *)nw_path_copy_proxy_settings_original, (void *)&nw_path_copy_proxy_settings_replacement, (void **)&nw_path_copy_proxy_settings_original);
        }
    }

    nw_path_should_use_proxy_original = dlsym(handle, "nw_path_should_use_proxy");
    if (nw_path_should_use_proxy_original) {
        MSHookFunction((void *)nw_path_should_use_proxy_original, (void *)&nw_path_should_use_proxy_replacement, (void **)&nw_path_should_use_proxy_original);
    }

    dlclose(handle);
}

@end
