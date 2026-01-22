# Synheart Core SDK - Dart/Flutter

[![Version](https://img.shields.io/badge/version-0.0.2-blue.svg)](https://github.com/synheart-ai/synheart-core-dart)
[![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.32.0-blue.svg)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)

**Synheart Core SDK** is the single, unified integration point for developers who want to collect HSI-compatible data, process human state on-device, generate focus/emotion signals, and integrate with Syni.

> **📦 SDK Implementations**: This is the Flutter/Dart implementation. For documentation and other platforms, see the repositories below.

## 📦 Repository Structure

The Synheart Core SDK is organized across multiple repositories:

| Repository | Purpose |
|------------|---------|
| **[synheart-core](https://github.com/synheart-ai/synheart-core)** | Main repository (source of truth for documentation) |
| **[synheart-core-dart](https://github.com/synheart-ai/synheart-core-dart)** | Flutter/Dart implementation (this repository) |
| **[synheart-core-kotlin](https://github.com/synheart-ai/synheart-core-kotlin)** | Android/Kotlin implementation |
| **[synheart-core-swift](https://github.com/synheart-ai/synheart-core-swift)** | iOS/Swift implementation |

## Overview

The Synheart Core SDK consolidates all Synheart signal channels into one SDK:

- **Wear Module** → Biosignals (HR, HRV, sleep, motion)
- **Phone Module** → Motion + context signals
- **Behavior Module** → Digital interaction patterns
- **HSI Runtime** → Signal fusion + state computation
- **Consent Module** → User permission management
- **Cloud Connector** → Secure HSI snapshot uploads
- **Syni Hooks** → LLM conditioning

**Key principle:**
> One SDK, many modules, unified human-state model

## Architecture

### Core Principle

> **HSV represents human state.**
>
> **Interpretation is downstream and optional.**

The Core SDK strictly separates:
- **Representation (HSV)** - Human State Vector: state axes, indices, embeddings
- **Interpretation (Focus, Emotion)** - Optional, explicit modules
- **Application logic** - Your app

### HSV vs HSI

- **HSV (Human State Vector)**: An internal, time-scoped, multi-dimensional representation that encodes estimates of human physiological, cognitive, and behavioral state for local computation and inference
  - Language-agnostic model (same across Dart, Kotlin, Swift)
  - Implemented in Dart classes for this SDK
  - Fast, type-safe on-device processing

- **HSI 1.0 (Human State Interface)**: Cross-platform JSON wire format
  - Platform-agnostic canonical format
  - For external systems and cross-platform communication

The SDK uses a hybrid approach: HSV for local computation, HSI 1.0 for external integration.

### Core Modules

1. **Capabilities Module** - Feature gating (core/extended/research)
2. **Consent Module** - User permission management
3. **Wear Module** - Biosignal collection from wearables
4. **Phone Module** - Device motion and context signals
5. **Behavior Module** - User-device interaction patterns
6. **HSI Runtime** - Signal fusion and HSV state representation
7. **Cloud Connector** - Secure HSV snapshot uploads

### Optional Interpretation Modules

- **Synheart Focus** - Focus/engagement estimation (optional, explicit enable)
- **Synheart Emotion** - Affect modeling (optional, explicit enable)

### Data Flow

```
Wear, Phone, Behavior Modules
    ↓
HSI Runtime (Fusion Engine)
    ↓
HSV (Human State Vector)
    ↓
Optional: Focus Module → Focus Estimates
Optional: Emotion Module → Emotion Estimates
    ↓
Optional: Export to HSI 1.0 (external format)
```

## Usage

### Basic Usage

The Core SDK provides HSV (Human State Vector) as the core state representation, with optional interpretation modules for Focus and Emotion:

```dart
import 'package:synheart_core/synheart_core.dart';

// Initialize the Core SDK
await Synheart.initialize(
  userId: 'anon_user_123',
  config: SynheartConfig(
    wearConfig: WearConfig(),
    phoneConfig: PhoneConfig(),
    behaviorConfig: BehaviorConfig(),
  ),
);

// Subscribe to HSV updates (core state representation)
Synheart.onHSVUpdate.listen((hsv) {
  print('Arousal Index: ${hsv.meta.axes.affect.arousalIndex}');
  print('Engagement Stability: ${hsv.meta.axes.engagement.engagementStability}');
});

// Optional: Enable interpretation modules
await Synheart.enableFocus();
Synheart.onFocusUpdate.listen((focus) {
  print('Focus Score: ${focus.estimate.score}');
});

await Synheart.enableEmotion();
Synheart.onEmotionUpdate.listen((emotion) {
  print('Stress Index: ${emotion.stressIndex}');
});

// Optional: Enable cloud sync (requires consent)
await Synheart.enableCloud();
```

### On-Demand Data Collection

The SDK supports granular control over when data collection starts and stops, allowing apps to collect data only when needed (e.g., during gameplay, focus sessions, etc.).

#### Manual Initialization

By default, `initialize()` automatically starts all data collection modules. To control when collection starts:

```dart
// Initialize without auto-starting collection
await Synheart.initialize(
  userId: 'anon_user_123',
  autoStart: false, // Don't start collection automatically
  config: SynheartConfig(
    wearConfig: WearConfig(),
    phoneConfig: PhoneConfig(),
    behaviorConfig: BehaviorConfig(),
  ),
);

// Start collection when needed (e.g., when game starts)
await Synheart.startDataCollection();

// Stop collection when done (e.g., when game ends)
await Synheart.stopDataCollection();
```

#### Module-Level Control

Start and stop individual modules independently:

```dart
// Start/stop individual modules
await Synheart.startWearCollection();
await Synheart.stopWearCollection();

await Synheart.startBehaviorCollection();
await Synheart.stopBehaviorCollection();

await Synheart.startPhoneCollection();
await Synheart.stopPhoneCollection();

// Check if modules are collecting
bool isWearCollecting = Synheart.isWearCollecting;
bool isBehaviorCollecting = Synheart.isBehaviorCollecting;
bool isPhoneCollecting = Synheart.isPhoneCollecting;
```

#### Custom Collection Intervals

For high-frequency use cases (e.g., games), you can set custom collection intervals:

```dart
// Start wear collection with 1-second interval for real-time gameplay
await Synheart.startWearCollection(
  interval: Duration(seconds: 1),
);

// Later, stop when game ends
await Synheart.stopWearCollection();
```

#### Raw Data Streams

Access raw data samples and events in real-time:

```dart
// Stream of raw wear samples
Synheart.wearSampleStream.listen((sample) {
  print('HR: ${sample.hr} BPM');
  print('RR Intervals: ${sample.rrIntervals}');
  print('HRV RMSSD: ${sample.hrvRmssd} ms');
});

// Stream of raw behavior events
Synheart.behaviorEventStream.listen((event) {
  print('Event: ${event.type} at ${event.timestamp}');
});
```

**Note**: Streams respect consent - no data is emitted if consent is denied.

#### Behavior Session Management

Start and stop behavior tracking sessions and get aggregated results:

```dart
// Start a behavior session
final sessionId = await Synheart.startBehaviorSession();
print('Session ID: $sessionId');

// ... user interacts with app ...

// Stop session and get results
final results = await Synheart.stopBehaviorSession(sessionId);
print('Tap Rate: ${results.tapRate}');
print('Keystroke Rate: ${results.keystrokeRate}');
print('Focus Hint: ${results.focusHint}');
print('Interaction Intensity: ${results.interactionIntensity}');
```

#### On-Demand Feature Queries

Query aggregated features for specific time windows without subscribing to streams:

```dart
// Get wear features for last 30 seconds
final wearFeatures = await Synheart.getWearFeatures(WindowType.window30s);
if (wearFeatures != null) {
  print('Average HR: ${wearFeatures.hrAverage} BPM');
  print('HRV RMSSD: ${wearFeatures.hrvRmssd} ms');
  print('Motion Index: ${wearFeatures.motionIndex}');
}

// Get behavior features for last 5 minutes
final behaviorFeatures = await Synheart.getBehaviorFeatures(WindowType.window5m);
if (behaviorFeatures != null) {
  print('Tap Rate: ${behaviorFeatures.tapRateNorm}');
  print('Focus Hint: ${behaviorFeatures.focusHint}');
  print('Distraction Score: ${behaviorFeatures.distractionScore}');
}

// Get phone features for last hour
final phoneFeatures = await Synheart.getPhoneFeatures(WindowType.window1h);
if (phoneFeatures != null) {
  print('Motion Level: ${phoneFeatures.motionLevel}');
  print('Screen On Ratio: ${phoneFeatures.screenOnRatio}');
}
```

#### Use Cases

**Game App Example:**
```dart
// Initialize without auto-start
await Synheart.initialize(userId: 'user', autoStart: false);

// When game starts
await Synheart.startWearCollection(interval: Duration(seconds: 1));
Synheart.wearSampleStream.listen((sample) {
  // Adjust game difficulty based on HR
  if (sample.hr != null && sample.hr! > 100) {
    // Increase difficulty
  }
});

// When game ends
await Synheart.stopWearCollection();
```

**Focus Session Example:**
```dart
// Start behavior session when focus session begins
final sessionId = await Synheart.startBehaviorSession();

// ... user works ...

// End session and analyze focus
final results = await Synheart.stopBehaviorSession(sessionId);
if (results.focusHint > 0.7) {
  print('High focus session!');
}
```

### HSI 1.0 Export

The SDK supports exporting HSV to the canonical HSI 1.0 format for external interoperability:

```dart
import 'package:synheart_core/synheart_core.dart';
import 'dart:convert';

// Subscribe to HSV updates
Synheart.onHSVUpdate.listen((hsv) {
  // Convert HSV to HSI 1.0 canonical format
  final hsi10 = hsv.toHSI10(
    producerName: 'My App',
    producerVersion: '1.0.0',
    instanceId: 'instance-123',
  );

  // Serialize to JSON
  final json = hsi10.toJson();
  final jsonString = JsonEncoder.withIndent('  ').convert(json);

  // Send to external system, validate against schema, etc.
  print(jsonString);
});
```

The SDK uses a hybrid architecture:
- **HSV (Human State Vector)**: Language-agnostic model implemented in Dart classes
- **HSI 1.0 (Human State Interface)**: Cross-platform JSON format for interoperability

**Note**: All Synheart SDKs (Dart, Kotlin, Swift) implement the same HSV model, ensuring consistent state representation across platforms.

See the [hsi_export_example.dart](example/hsi_export_example.dart) for a complete example.

### Consent Management

The SDK requires explicit user consent for data collection. **All data collection respects consent** - no data is collected or streamed without explicit user consent.

#### Granting Consent

```dart
// Grant consent for specific data types (all parameters required)
await Synheart.grantConsent(
  biosignals: true,
  behavior: true,
  motion: true,
  cloudUpload: false,  // User must explicitly opt-in
  profileId: 'profile-123', // Optional: for consent service integration
);

// If using consent service with profiles
final profiles = await Synheart.getAvailableConsentProfiles();
final selectedProfile = profiles.first; // User selects a profile
await Synheart.grantConsent(
  biosignals: true,
  behavior: true,
  motion: true,
  cloudUpload: true,
  profileId: selectedProfile.id,
);
```

#### Checking Consent Status

```dart
// Get current consent status map
final consentStatus = Synheart.getConsentStatusMap();
bool hasBiosignalsConsent = consentStatus['biosignals'] ?? false;
bool hasBehaviorConsent = consentStatus['behavior'] ?? false;
bool hasMotionConsent = consentStatus['motion'] ?? false;
bool hasCloudUploadConsent = consentStatus['cloudUpload'] ?? false;

// Check if consent is needed (user hasn't been asked yet)
if (await Synheart.needsConsent()) {
  // Show consent UI
  final consentInfo = await Synheart.getConsentInfo();
  // consentInfo contains descriptions for each data type
}
```

#### Requesting Consent (Consent Service)

If using the consent service (requires `ConsentConfig` with `appId` and `appApiKey`):

```dart
// Request consent using consent service UI
final token = await Synheart.requestConsent();
if (token != null && token.isValid) {
  print('Consent granted with token: ${token.token}');
}

// Or use a consent profile
final profiles = await Synheart.getAvailableConsentProfiles();
final selectedProfile = profiles.first; // User selects
await Synheart.grantConsent(
  biosignals: true,
  behavior: true,
  motion: true,
  cloudUpload: true,
  profileId: selectedProfile.id,
);
```

#### Revoking Consent

```dart
// Revoke consent for a specific type (stops data collection immediately)
await Synheart.revokeConsentType('biosignals');
await Synheart.revokeConsentType('behavior');
await Synheart.revokeConsentType('motion');
await Synheart.revokeConsentType('cloudUpload');

// Revoke all consent
await Synheart.revokeConsent();
```

**Important**: 
- Consent is checked before starting any data collection
- If consent is revoked, data collection stops immediately
- Raw data streams (`wearSampleStream`, `behaviorEventStream`) only emit data when consent is granted
- All module start methods respect consent - they won't start if consent is denied
- `syni` consent is always `false` (not user-configurable)

## Prerequisites

### Platform Configuration

The Core SDK requires platform-specific configuration for data collection modules. The example app includes all required configurations - use it as a reference.

#### iOS Configuration

**Info.plist** - Add HealthKit usage descriptions (required for synheart-wear-dart):

```xml
<!-- HealthKit Permissions (Required for Wear Module) -->
<key>NSHealthShareUsageDescription</key>
<string>Synheart Core needs access to your health data to provide personalized insights and track your biometric metrics.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Synheart Core needs to update your health data to sync wearable device information.</string>
```

**Note**: The behavior module doesn't require additional Info.plist entries - it uses runtime permission requests.

#### Android Configuration

**AndroidManifest.xml** - Add the following permissions and services:

```xml
<!-- Basic permissions -->
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>

<!-- Health Connect Permissions (Required for Wear Module) -->
<uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
<uses-permission android:name="android.permission.health.WRITE_HEART_RATE"/>
<uses-permission android:name="android.permission.health.READ_HEART_RATE_VARIABILITY"/>
<uses-permission android:name="android.permission.health.WRITE_HEART_RATE_VARIABILITY"/>
<uses-permission android:name="android.permission.health.READ_STEPS"/>
<uses-permission android:name="android.permission.health.WRITE_STEPS"/>
<uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED"/>
<uses-permission android:name="android.permission.health.WRITE_ACTIVE_CALORIES_BURNED"/>
<uses-permission android:name="android.permission.health.READ_DISTANCE"/>
<uses-permission android:name="android.permission.health.WRITE_DISTANCE"/>
<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_HISTORY"/>

<!-- Behavior Module Permissions -->
<uses-permission android:name="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE" />
<uses-permission android:name="android.permission.READ_PHONE_STATE" />

<!-- Health Connect Queries -->
<queries>
    <package android:name="com.google.android.apps.healthdata" />
    <intent>
        <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
    </intent>
</queries>

<!-- In <application> tag: Health Connect Intent Filter -->
<activity android:name=".MainActivity" ...>
    <intent-filter>
        <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
    </intent-filter>
</activity>

<!-- Health Connect Privacy Policy Activity Alias -->
<activity-alias
    android:name="ViewPermissionUsageActivity"
    android:exported="true"
    android:targetActivity=".MainActivity"
    android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
    <intent-filter>
        <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
        <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
    </intent-filter>
</activity-alias>

<!-- Notification Listener Service (Required for Behavior Module) -->
<service
    android:name="ai.synheart.behavior.SynheartNotificationListenerService"
    android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
    android:exported="true">
    <intent-filter>
        <action android:name="android.service.notification.NotificationListenerService" />
    </intent-filter>
</service>
```

**MainActivity.kt** - Must extend `FlutterFragmentActivity` (required for Health Connect on Android 14+):

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

### Supported Devices

The Core SDK supports all devices that [synheart_wear](https://pub.dev/packages/synheart_wear) supports (Apple Watch, Fitbit, Garmin, etc.).

### Quick Start

The example app (`example/`) includes all required configurations. You can copy the relevant sections from:
- `example/ios/Runner/Info.plist` for iOS
- `example/android/app/src/main/AndroidManifest.xml` for Android
- `example/android/app/src/main/kotlin/com/example/synheart_core/MainActivity.kt` for MainActivity

## Privacy & Security

- All processing is **on-device** by default
- No raw biosignals leave the device without explicit consent
- **Consent is enforced at every level** - collection, caching, and streaming all respect consent
- Cloud sync uses **aggregated HSV** only
- HSI is strictly **non-medical**; no diagnoses or clinical labels
- **On-demand collection** allows apps to minimize data collection to only when needed

## 📚 Documentation

For complete documentation, see the [main Synheart Core repository](https://github.com/synheart-ai/synheart-core):

- **[HSI Specification](https://github.com/synheart-ai/synheart-core/blob/main/docs/HSI_SPECIFICATION.md)** - State axes, indices, and embeddings
- **[Consent System](https://github.com/synheart-ai/synheart-core/blob/main/docs/CONSENT_SYSTEM.md)** - Permission model and enforcement
- **[Cloud Protocol](https://github.com/synheart-ai/synheart-core/blob/main/docs/CLOUD_PROTOCOL.md)** - Secure ingestion protocol

### Dart-Specific Documentation

- **[ARCHITECTURE](doc/ARCHITECTURE.md)** - Dart implementation architecture
- **[HSV Technical Spec](doc/hsv-tech-spec.md)** - HSV data structure details

## 👥 Contributing

We welcome contributions! Here's how to get started:

1. **Read the guides:**
   - [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
 


## 📋 Module Overview

The Synheart Core SDK consists of 7 core modules:

1. **Capabilities Module** - Feature gating (core/extended/research)
2. **Consent Module** - User permission management
3. **Wear Module** - Biosignal collection from wearables
4. **Phone Module** - Device motion and context signals
5. **Behavior Module** - User-device interaction patterns
6. **HSI Runtime** - Signal fusion and state computation
7. **Cloud Connector** - Secure HSI snapshot uploads

See [ARCHITECTURE](doc/ARCHITECTURE.md) for detailed implementation specifications.

## 🔒 Privacy & Security

- All processing is **on-device** by default
- No raw biosignals leave the device without explicit consent
- Cloud sync uses **aggregated HSV** only
- HSI is strictly **non-medical**; no diagnoses or clinical labels
- Zero raw data policy enforced throughout

## 📄 License

Apache 2.0 License - see [LICENSE](LICENSE) for details.

Copyright 2025 Synheart AI Inc.

## 👤 Author

Synheart Teeam <3 

## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.

