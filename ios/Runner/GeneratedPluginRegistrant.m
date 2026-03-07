//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<connectivity_plus/ConnectivityPlusPlugin.h>)
#import <connectivity_plus/ConnectivityPlusPlugin.h>
#else
@import connectivity_plus;
#endif

#if __has_include(<device_info_plus/FPPDeviceInfoPlusPlugin.h>)
#import <device_info_plus/FPPDeviceInfoPlusPlugin.h>
#else
@import device_info_plus;
#endif

#if __has_include(<flutter_onnxruntime/FlutterOnnxruntimePlugin.h>)
#import <flutter_onnxruntime/FlutterOnnxruntimePlugin.h>
#else
@import flutter_onnxruntime;
#endif

#if __has_include(<flutter_secure_storage/FlutterSecureStoragePlugin.h>)
#import <flutter_secure_storage/FlutterSecureStoragePlugin.h>
#else
@import flutter_secure_storage;
#endif

#if __has_include(<health/HealthPlugin.h>)
#import <health/HealthPlugin.h>
#else
@import health;
#endif

#if __has_include(<path_provider_foundation/PathProviderPlugin.h>)
#import <path_provider_foundation/PathProviderPlugin.h>
#else
@import path_provider_foundation;
#endif

#if __has_include(<shared_preferences_foundation/SharedPreferencesPlugin.h>)
#import <shared_preferences_foundation/SharedPreferencesPlugin.h>
#else
@import shared_preferences_foundation;
#endif

#if __has_include(<sqflite_darwin/SqflitePlugin.h>)
#import <sqflite_darwin/SqflitePlugin.h>
#else
@import sqflite_darwin;
#endif

#if __has_include(<synheart_behavior/SynheartBehaviorPlugin.h>)
#import <synheart_behavior/SynheartBehaviorPlugin.h>
#else
@import synheart_behavior;
#endif

#if __has_include(<synheart_session/SynheartSessionPlugin.h>)
#import <synheart_session/SynheartSessionPlugin.h>
#else
@import synheart_session;
#endif

#if __has_include(<synheart_wear/SynheartWearPlugin.h>)
#import <synheart_wear/SynheartWearPlugin.h>
#else
@import synheart_wear;
#endif

#if __has_include(<url_launcher_ios/URLLauncherPlugin.h>)
#import <url_launcher_ios/URLLauncherPlugin.h>
#else
@import url_launcher_ios;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [ConnectivityPlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"ConnectivityPlusPlugin"]];
  [FPPDeviceInfoPlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FPPDeviceInfoPlusPlugin"]];
  [FlutterOnnxruntimePlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterOnnxruntimePlugin"]];
  [FlutterSecureStoragePlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterSecureStoragePlugin"]];
  [HealthPlugin registerWithRegistrar:[registry registrarForPlugin:@"HealthPlugin"]];
  [PathProviderPlugin registerWithRegistrar:[registry registrarForPlugin:@"PathProviderPlugin"]];
  [SharedPreferencesPlugin registerWithRegistrar:[registry registrarForPlugin:@"SharedPreferencesPlugin"]];
  [SqflitePlugin registerWithRegistrar:[registry registrarForPlugin:@"SqflitePlugin"]];
  [SynheartBehaviorPlugin registerWithRegistrar:[registry registrarForPlugin:@"SynheartBehaviorPlugin"]];
  [SynheartSessionPlugin registerWithRegistrar:[registry registrarForPlugin:@"SynheartSessionPlugin"]];
  [SynheartWearPlugin registerWithRegistrar:[registry registrarForPlugin:@"SynheartWearPlugin"]];
  [URLLauncherPlugin registerWithRegistrar:[registry registrarForPlugin:@"URLLauncherPlugin"]];
}

@end
