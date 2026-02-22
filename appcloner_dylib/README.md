# iOS App Cloner Documentation

## Overview
An iOS app cloning system that enables running multiple instances of the same app with different configurations. It implements various hooks and patches to handle bundle identifiers, security groups, location spoofing, and proxy settings.

## Architecture (SOLID)

Each module has a single responsibility:

| Module | File(s) | Responsibility |
|--------|---------|----------------|
| **Config** | `ClonerConfig.m` | Reads `clonerConfig` from Info.plist once, exposes typed properties |
| **Entry** | `EntryPoint.x` | Constructor — wires modules together |
| **Bundle** | `BundleHooks.x` | NSBundle identity spoofing, YouTube fix, FaceTecSDK bypass |
| **Keychain** | `KeychainHooks.x` | SecItem hooks, keychain access group redirection |
| **Container** | `ContainerHooks.x` | NSFileManager + NSUserDefaults group container hooks |
| **Device** | `DeviceSpoofer.x` | Device model/version/IDFV spoofing |
| **Location** | `LocationSpoofer.x` | CLLocation coordinate spoofing |
| **Background** | `BackgroundKiller.x` | Prevents background task execution |
| **Camera** | `CameraHooks.m` | AVCapturePhotoOutput + AVCaptureSession swizzling |
| **Camera UI** | `CameraFloatingButton.m` | Floating button + edit action sheet |
| **Image** | `ImageTransforms.m` | Pure image functions (rotate, mirror, brightness) |
| **IG Dumper** | `igdumper.x` | Instagram credential extraction |
| **Proxy** | `Networking/BBProxy.m` | HTTP/SOCKS proxy configuration |
| **NSURLSession** | `Networking/NSHook.m` | NSURLSession proxy hooking |

## Configuration

### Info.plist Configuration
The app requires a `clonerConfig` dictionary in Info.plist:

```xml
<dict>
    <key>clonerConfig</key>
    <dict>
        <key>originalBundleId</key>
        <string>com.example.app</string>
        <key>bundleName</key>
        <string>App Name</string>
        <key>original_team_id</key>
        <string>TEAM_ID</string>
        <key>cloneUUID</key>
        <string>unique-identifier</string>
        <key>keychainAccessGroup</key>
        <string>GROUP_ID</string>

        <key>location</key>
        <dict>
            <key>Lat</key>
            <real>40.7128</real>
            <key>Lon</key>
            <real>-74.0060</real>
        </dict>

        <key>Proxy</key>
        <dict>
            <key>host</key>
            <string>proxy.example.com</string>
            <key>Port</key>
            <string>5001</string>
            <key>Username</key>
            <string>user</string>
            <key>Password</key>
            <string>pass</string>
        </dict>

        <key>is_device_spoofing_enabled</key>
        <true/>
        <key>is_ig_dumper_enabled</key>
        <false/>
        <key>backgroundprocess_enabled</key>
        <false/>
    </dict>
</dict>
```

## Hook Techniques
- Method swizzling for Objective-C methods
- Function hooking using `fishhook` (Facebook's dynamic symbol rebinding)
- MSHookFunction for low-level C function hooks
- Rogue framework for advanced method hooking
