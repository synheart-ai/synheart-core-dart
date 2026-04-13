# Synheart Core SDK - Dart/Flutter

[![Version](https://img.shields.io/badge/version-1.3.0-blue.svg)](https://github.com/synheart-ai/synheart-core-flutter)
[![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.32.0-blue.svg)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)

Flutter/Dart platform SDK for Synheart. This is a thin wrapper around **[synheart-core-runtime](https://github.com/synheart-ai/synheart-core-runtime)** — the shared implementation that owns all business logic (storage, crypto, sync, consent, capabilities, artifact pipeline, session orchestration, and cloud integration).

Human state inference is computed on-device by `synheart-engine` (deterministic signal processing pipeline), which runs inside `synheart-core-runtime`. This SDK communicates with the runtime via a C ABI FFI bridge (`libsynheart_core_runtime`).

**This SDK handles platform-specific concerns only:** sensor collection (HealthKit, Health Connect), UI consent flows, secure storage (Keychain, EncryptedSharedPreferences), and Flutter-native reactive streams.

## Architecture

```
Flutter App
    |
synheart-core-flutter (this SDK)
    |-- Wear/Phone/Behavior modules (platform sensor collection)
    |-- CoreRuntimeBridge (FFI)
    |
libsynheart_core_runtime.{dylib,so,a}
    |-- synheart-engine (HSI computation)
    |-- Storage, Crypto, Sync, Auth, Consent, Capabilities
    |-- 67 C ABI functions
```

## Repositories

| Repository | Purpose |
|------------|---------|
| **[synheart-core-runtime](https://github.com/synheart-ai/synheart-core-runtime)** | Shared implementation (all business logic) |
| **[synheart-core-flutter](https://github.com/synheart-ai/synheart-core-flutter)** | Flutter/Dart platform SDK (this repository) |
| **[synheart-core-kotlin](https://github.com/synheart-ai/synheart-core-kotlin)** | Android/Kotlin platform SDK |
| **[synheart-core-swift](https://github.com/synheart-ai/synheart-core-swift)** | iOS/Swift platform SDK |

## Overview

The Synheart Core SDK consolidates all Synheart signal channels into one SDK:

- **Wear Module** → Biosignals (HR, HRV, sleep, motion)
- **Phone Module** → Motion + context signals
- **Behavior Module** → Digital interaction patterns
- **HSI Runtime** → Signal fusion + state computation (via synheart-engine)
- **Consent Module** → User permission management
- **Cloud Connector** → Secure HSI snapshot uploads

**Key principle:**
> One SDK, many modules, unified human-state model

## Features

- **Modular signal collection** — Wear (biosignals), Phone (motion/context), Behavior (interaction patterns)
- **On-device state computation** — synheart-engine fuses signals into HSV (6-head inference: emotion, focus, capacity, recovery, strain, sleep)
- **HSI 1.1 export** — Cross-platform canonical JSON format mapping HSV to domain axes
- **Direct HSV access** — Query raw inference results via `RuntimeBridge.lastHsv()` for diagnostics
- **Consent-first architecture** — All data collection respects explicit user consent; revocation stops modules immediately
- **Capability-gated features** — Server-signed tokens control which SDK features are available (core/extended/research)
- **On-demand collection** — Granular start/stop control per module, custom collection intervals
- **Raw data streams** — Direct access to wear samples and behavior events
- **SRM baseline persistence** — Self-Reference Model snapshots automatically saved to encrypted storage and restored on startup, preserving learned baselines across app restarts
- **Device authentication** — Hardware-backed ECDSA signing via synheart-auth (Secure Enclave / Android Keystore)
- **Secure cloud upload** — Device-signed or HMAC-signed HSI snapshot uploads with offline queue
- **Reactive streams** — RxDart-based real-time updates

## Architecture

### Core Principle

> **All inference is computed by synheart-engine.**
>
> **SDKs coordinate data collection and distribution.**

The Core SDK strictly separates:
- **Computation** — synheart-engine computes HSV
- **Collection** — Core SDK modules (Wear, Phone, Behavior, Consent, Capability)
- **Distribution** — HSI JSON export, cloud upload, raw HSV diagnostics

### HSV vs HSI

- **HSV (Human State Vector)**: Internal runtime representation
  - Computed by synheart-engine
  - 6 heads: emotion, focus, capacity, recovery, strain, sleep
  - Per-head: value, confidence, inference metadata
  - Accessed via `RuntimeBridge.lastHsv()` for diagnostics
  - NOT part of public SDK API (internal use only)

- **HSI 1.1 (Human State Interface)**: Cross-platform JSON wire format
  - Reorganizes HSV into domain axes (physiological, engagement, behavior, context)
  - Primary output format (`onHSIUpdate` stream)
  - For external systems and cross-platform communication
  - HMAC-signed upload to platform

The SDK uses clean separation: **runtime computes HSV**, **SDK exports HSI**, **consumers parse HSI**.

### Core Modules

1. **Device Auth** - Hardware-backed ECDSA device identity (via synheart-auth)
2. **Capabilities Module** - Feature gating via server-signed tokens (core/extended/research)
3. **Consent Module** - 3-layer consent enforcement (platform/app/user), token issuance
4. **Wear Module** - Biosignal collection (HR, HRV, sleep, motion)
5. **Phone Module** - Device motion and context signals
6. **Behavior Module** - Consent-gated interaction patterns with runtime push
7. **Runtime Module** - FFI bridge to synheart-engine (HSV computation & HSI export)
8. **SRM Module** - Self-Reference Model baselines (persistent snapshots)
9. **Cloud Connector** - Device-signed HSI uploads with HSI 1.1 schema validation

### Data Flow

```
SynheartAuth (device registration + ECDSA signing)
    ↓
DeviceAuthProvider → RemoteCapabilityTokenFetcher
    ↓ (fetches capability token, gates features)
    ↓
Wear, Phone, Behavior Modules (raw signals)
    ↓ (consent & capability gated)
    ↓
RuntimeModule → RuntimeBridge (dart:ffi)
    ↓
synheart-engine (C ABI)
  ├─ Signal processing
  ├─ Feature extraction
  ├─ HSV computation (6 heads)
  └─ Flux mapping → HSI 1.1
    ↓
HSI JSON Output
  ├─ onHSIUpdate stream (main output)
  ├─ HsiSchemaTransformer (validates against hsi-1.1.schema.json)
  ├─ lastQuality() (confidence metrics)
  └─ Cloud upload (device-signed, consent-gated)
```

## Installation

Add `synheart_core` to your `pubspec.yaml`:

```yaml
dependencies:
  synheart_core:
    path: ../synheart-core-flutter
```

Then run:

```bash
flutter pub get
```

### Native Runtime Setup

This SDK requires the **synheart-core-runtime** native library. The library is NOT committed to this repo — you must build it from [synheart-core-runtime](https://github.com/synheart-ai/synheart-core-runtime) and copy it into the plugin's `ios/Frameworks/` directory.

```bash
# From the synheart-core-runtime repo:
make ios          # Builds iOS XCFramework
make android      # Builds Android .so files

# Copy to this plugin:
cp -R build/ios/SynheartCoreRuntime.xcframework ../synheart-core-flutter/ios/Frameworks/

# Copy to your Flutter app (Android):
cp -R build/android/jniLibs/* ../your-app/android/app/src/main/jniLibs/
```

The iOS podspec uses `-force_load` to ensure all FFI symbols are preserved for Dart's `dlsym`. The xcframework is gitignored — each developer must build or download it.

> **Note:** If your app also uses another Rust static library (e.g. isar), you may hit duplicate `_rust_eh_personality` symbols. Remove the other Rust dependency or build this runtime as a dynamic framework instead.

## Endpoint Configuration (No Hardcoded URLs)

This SDK supports endpoint injection via `--dart-define` / `--dart-define-from-file`.
To avoid committing real endpoints:

1. Copy `env/synheart.endpoints.example.json` to a local file such as
   `env/synheart.endpoints.local.json` (gitignored).
2. Put your real endpoint URLs in the local file.
3. Run your app with:

```bash
flutter run --dart-define-from-file=env/synheart.endpoints.local.json
```

**Example file shape** (`env/synheart.endpoints.example.json` — placeholders only; do not commit secrets):

```json
{
  "SYNHEART_CLOUD_BASE_URL": "https://your-cloud.example.com",
  "SYNHEART_CONSENT_BASE_URL": "https://your-consent.example.com",
  "SYNHEART_PLATFORM_INGEST_BASE_URL": "https://your-platform.example.com",
  "SYNHEART_AUTH_BASE_URL": "https://your-auth.example.com"
}
```

| Define key | Used for |
|------------|----------|
| `SYNHEART_CLOUD_BASE_URL` | HSI cloud ingest (`ApiEndpoints.defaultCloudBaseUrl`) |
| `SYNHEART_CONSENT_BASE_URL` | Consent service API (`ApiEndpoints.defaultConsentBaseUrl`) |
| `SYNHEART_PLATFORM_INGEST_BASE_URL` | Platform session/metadata ingest |
| `SYNHEART_AUTH_BASE_URL` | Auth/account API (exchange, refresh, account delete) |

Values are read at compile time via `String.fromEnvironment` in `lib/src/config/api_endpoints.dart`.

## Usage

### Basic Usage (Production)

The Core SDK automatically handles device registration, capability token fetching, and request signing when `DeviceAuthConfig` is provided:

```dart
import 'package:synheart_core/synheart_core.dart';

// Initialize with device authentication (production)
await Synheart.initialize(
  userId: 'anon_user_123',
  config: SynheartConfig(
    appId: 'com.myapp',
    subjectId: 'anon_user_123',
    deviceAuthConfig: DeviceAuthConfig(
      authBaseUrl: 'https://auth.synheart.ai',
    ),
    cloudConfig: CloudConfig(
      tenantId: 'my-tenant',
      subjectId: 'anon_user_123',
      instanceId: 'instance-uuid',
      // No hmacSecret needed — DeviceAuthProvider is injected automatically
    ),
    consentConfig: ConsentConfig(
      appId: 'com.myapp',
      appApiKey: 'your-consent-api-key',
    ),
    wearConfig: WearConfig(),
    behaviorConfig: BehaviorConfig(),
  ),
);
```

### Basic Usage (Development)

For development without a device auth server, use `allowUnsignedCapabilities`:

```dart
await Synheart.initialize(
  userId: 'anon_user_123',
  config: SynheartConfig(
    appId: 'com.myapp',
    subjectId: 'anon_user_123',
    allowUnsignedCapabilities: true,  // Dev mode — no token needed
    wearConfig: WearConfig(),
    behaviorConfig: BehaviorConfig(),
  ),
);

// Subscribe to HSI updates (core state representation — raw JSON from synheart-engine)
Synheart.onHSIUpdate.listen((hsiJson) {
  print('HSI JSON: $hsiJson');
});

// Optional: Enable interpretation modules (activate API preferred)
Synheart.activate(SynheartFeature.focus);
Synheart.onFocusUpdate.listen((focus) {
  print('Focus Score: ${focus.estimate.score}');
});

Synheart.activate(SynheartFeature.emotion);
Synheart.onEmotionUpdate.listen((emotion) {
  print('Stress Index: ${emotion.stressIndex}');
});

// Optional: Enable cloud sync (requires consent)
Synheart.activate(SynheartFeature.cloud);
```

### On-Demand Data Collection

The SDK supports granular control over when data collection starts and stops, allowing apps to collect data only when needed (e.g., during gameplay, focus sessions, etc.).

#### Manual Initialization

By default, `initialize()` does not start data collection (`autoStart: false`). To control when collection starts:

```dart
// Initialize without auto-starting collection
await Synheart.initialize(
  userId: 'anon_user_123',
  autoStart: false,
  config: SynheartConfig(
    appId: 'com.myapp',
    subjectId: 'anon_user_123',
    allowUnsignedCapabilities: true,  // or use deviceAuthConfig in production
    wearConfig: WearConfig(),
    behaviorConfig: BehaviorConfig(),
  ),
);

// Start collection when needed (e.g., when game starts)
await Synheart.startSession();

// Stop collection when done (e.g., when game ends)
await Synheart.stopSession();
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

#### Use Cases

**Game App Example:**
```dart
// Initialize without auto-start
await Synheart.initialize(userId: 'user', config: SynheartConfig(allowUnsignedCapabilities: true), autoStart: false);

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

### HSI 1.1 Export

The SDK supports exporting HSV to the canonical HSI 1.1 format for external interoperability:

```dart
import 'package:synheart_core/synheart_core.dart';
import 'dart:convert';

// Subscribe to HSI updates (raw JSON string from synheart-engine)
Synheart.onHSIUpdate.listen((hsiJson) {
  // hsiJson is already a canonical HSI 1.x JSON string
  // Send to external system, validate against schema, etc.
  print(hsiJson);
});
```

The SDK uses a hybrid architecture:
- **HSV (Human State Vector)**: Language-agnostic model implemented in Dart classes
- **HSI 1.1 (Human State Interface)**: Cross-platform JSON format for interoperability

**Note**: All Synheart SDKs (Dart, Kotlin, Swift) implement the same HSV model, ensuring consistent state representation across platforms.

See the [hsi_export_example.dart](example/hsi_export_example.dart) for a complete example.

## Batch Ingest Mode

By default, the runtime module streams wear and behavior data to the native engine in real-time, producing HSI frames as windows complete. **Batch ingest mode** buffers all events during a session and runs a single `ingestBatch` call on stop, producing all HSI frames at once.

This is useful for:
- Offline-first apps that collect data without connectivity
- Background recording where real-time HSI isn't needed
- Reducing CPU usage during active sessions

### Configuration

```dart
final synheart = await Synheart.initialize(
  config: SynheartConfig(
    appId: 'your_app_id',
    apiKey: 'your_api_key',
    subjectId: 'sub_user_123',
    batchIngestOnStop: true, // Enable batch mode
  ),
);
```

### Runtime Toggle

Batch mode can be toggled between sessions:

```dart
synheart.setBatchIngestOnStop(true);  // Next session uses batch
synheart.setBatchIngestOnStop(false); // Back to streaming
```

## Lab Ingestion

The SDK can send structured session and metadata payloads to the Synheart platform API, independent of the HSI cloud connector.

### Auto-Ingest

Enable automatic ingestion when sessions end:

```dart
final synheart = await Synheart.initialize(
  config: SynheartConfig(
    appId: 'your_app_id',
    apiKey: 'your_api_key',
    subjectId: 'sub_user_123',
    labIngestConfig: LabIngestConfig(
      apiKey: 'your_platform_api_key',
      autoIngest: true,
    ),
  ),
);
```

### Manual Ingestion

```dart
// Ingest current session data
await synheart.ingestSession();

// Ingest app/user metadata
await synheart.ingestMetadata();
```

### Standalone Client

For custom integrations, use `LabPayloadBuilder` and `LabIngestClient` directly:

```dart
final payload = LabPayloadBuilder.buildSession(
  sessionId: 'sess_123',
  // ... other params
);

final client = synheart.labIngestClient;
final response = await client?.ingestSession(payload);
```

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

## Error Handling

The SDK uses Dart exceptions. Most methods throw `StateError` for precondition failures:

```dart
try {
  await Synheart.initialize(
    userId: 'user_123',
    config: SynheartConfig(allowUnsignedCapabilities: true),
  );
  await Synheart.startSession();
} on StateError catch (e) {
  if (e.message.contains('already configured')) {
    print('SDK already initialized');
  } else if (e.message.contains('Capability token')) {
    print('Provide a valid token or set allowUnsignedCapabilities: true');
  } else {
    print('Error: ${e.message}');
  }
}
```

### Common Exceptions

| Exception | When |
|-----------|------|
| `StateError('Synheart already configured')` | `initialize()` called twice |
| `StateError('Capability token and secret are required...')` | No token/deviceAuthConfig and `allowUnsignedCapabilities` is false |
| `StateError('Device registration failed...')` | Device attestation failed and `allowUnsignedCapabilities` is false |
| `ArgumentError('... is not configured')` | Base URL still set to placeholder `example.invalid` |
| `StateError('Synheart must be initialized...')` | Method called before `initialize()` |
| `StateError('cloudUpload consent required')` | Cloud operation without consent |

## API Reference

### Synheart (Main Entry Point)

| Method | Description |
|--------|-------------|
| `initialize(userId, config, appKey, autoStart)` | Initialize the SDK |
| `startSession()` / `stopSession()` | Start/stop data collection |
| `startWearCollection()` / `stopWearCollection()` | Control wear module |
| `startBehaviorCollection()` / `stopBehaviorCollection()` | Control behavior module |
| `startPhoneCollection()` / `stopPhoneCollection()` | Control phone module |
| `activate(feature)` / `deactivate(feature)` | Enable/disable features (focus, emotion, cloud, etc.) |
| `grantConsent(...)` | Grant consent for data types |
| `revokeConsent()` / `revokeConsentType(type)` | Revoke consent |
| `uploadHsiNow()` | Force-upload queued HSI snapshots |
| `checkNotificationListenerEnabled()` | Check notification access for behavior metrics |
| `dispose()` | Release all resources |

### Streams

| Stream | Type | Description |
|--------|------|-------------|
| `onHSIUpdate` | `Stream<String>` | HSI JSON frames from synheart-engine |
| `onEmotionUpdate` | `Stream<EmotionState>` | Emotion estimates |
| `onFocusUpdate` | `Stream<FocusState>` | Focus estimates |
| `wearSampleStream` | `Stream<WearSample>` | Raw wear samples |
| `behaviorEventStream` | `Stream<BehaviorEvent>` | Raw behavior events |

## Prerequisites

### Platform Configuration

The Core SDK requires platform-specific configuration for data collection modules. The example app includes all required configurations - use it as a reference.

#### iOS Configuration

**Info.plist** - Add HealthKit usage descriptions (required for synheart-wear-flutter):

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
- **Consent is enforced at every level** — collection, caching, streaming, and local HSI delivery all respect consent
- **HSI stream is consent-gated** — `onHSIUpdate` only emits frames when `biosignals` consent is granted
- Cloud sync uses **aggregated HSI** only
- HSI is strictly **non-medical**; no diagnoses or clinical labels
- **On-demand collection** allows apps to minimize data collection to only when needed

## Testing

### Running Tests

```bash
flutter test
```

### Testing with Mock Providers

The SDK ships with `MockWearSourceHandler` and mock collectors for testing without hardware:

```dart
// Initialize with default capabilities (no real token needed)
await Synheart.initialize(
  userId: 'test_user',
  config: SynheartConfig(allowUnsignedCapabilities: true),
  autoStart: false,
);

// Start session — mock data flows through all streams
await Synheart.startSession();

// Subscribe and verify
Synheart.onHSIUpdate.listen((hsiJson) {
  // Validate HSI JSON from synheart-engine
  print('HSI: $hsiJson');
});
```

## Local Development with `synheart local`

For offline SDK development and testing, use the **Synheart CLI** local platform server. It replicates the cloud consent and ingest APIs locally, so you can develop without a network connection or production credentials.

### Setup

1. Install the [Synheart CLI](https://github.com/synheart-ai/synheart-cli):

```bash
git clone https://github.com/synheart-ai/synheart-cli
cd synheart-cli
make build && make install
```

2. Start the local platform:

```bash
synheart local
```

This starts an HTTP server on `localhost:8083` with mock consent profiles, token issuance, and ingest endpoints.

### Connecting your app

Point your Flutter app at the local server using `--dart-define`:

```bash
flutter run --dart-define=SYNHEART_ENV=local
```

Or specify a custom URL:

```bash
flutter run \
  --dart-define=SYNHEART_ENV=local \
  --dart-define=SYNHEART_LOCAL_URL=http://192.168.1.100:8083
```

### Available endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/apps/{id}/consent-profiles` | Fetch consent profiles |
| `POST` | `/api/v1/sdk/consent-token` | Issue consent token |
| `POST` | `/api/v1/sdk/consent-revoke` | Revoke consent |
| `POST` | `/v1/hsi/ingest` | Ingest HSI snapshots |
| `POST` | `/v1/platform/session/ingest` | Ingest session data |
| `POST` | `/v1/platform/metadata/ingest` | Ingest metadata |
| `GET` | `/status` | Server status and stats |

### Default credentials

The `synheart local` server provides default API keys and HMAC secrets for development. Run `synheart local --help` to see defaults. Use `allowUnsignedCapabilities: true` in your SDK config to skip device attestation locally.

### Testing consent flow

```dart
// In local mode, consent profiles are served from data/profiles.json
// 3 presets are included: Personal Wellness, Research (Full), Biosignals + Cloud

final profiles = await Synheart.getAvailableConsentProfiles();
// Returns the 3 preset profiles from the local server

await Synheart.grantConsent(
  biosignals: true,
  behavior: true,
  motion: true,
  cloudUpload: true,
  profileId: profiles.first.id,
);
```

### Testing lab ingest

Ingested payloads are persisted as JSON files in the local server's data directory (`{data-dir}/ingested/`), making it easy to inspect what your app is sending.

## 📚 Documentation

For complete documentation, see the [main Synheart Core repository](https://github.com/synheart-ai/synheart-core):

- **[HSI Specification](https://github.com/synheart-ai/synheart-core/blob/main/docs/HSI_SPECIFICATION.md)** - State axes, indices, and embeddings
- **[Consent System](https://github.com/synheart-ai/synheart-core/blob/main/docs/CONSENT_SYSTEM.md)** - Permission model and enforcement
- **[Cloud Protocol](https://github.com/synheart-ai/synheart-core/blob/main/docs/CLOUD_PROTOCOL.md)** - Secure ingestion protocol

### Dart-Specific Documentation

- **[ARCHITECTURE](docs/ARCHITECTURE.md)** - Dart implementation architecture

## 👥 Contributing

We welcome contributions! Here's how to get started:

1. **Read the guides:**
   - [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
 


## 📋 Module Overview

The Synheart Core SDK consists of 9 core modules:

1. **Device Auth** - Hardware-backed ECDSA device identity (via synheart-auth)
2. **Capabilities Module** - Server-signed feature gating (core/extended/research)
3. **Consent Module** - 3-layer consent enforcement + token issuance
4. **Wear Module** - Biosignal collection from wearables
5. **Phone Module** - Device motion and context signals
6. **Behavior Module** - Consent-gated interaction patterns
7. **HSI Runtime** - Signal fusion and state computation
8. **Cloud Connector** - Device-signed HSI snapshot uploads
9. **Lab Ingest** - Session and metadata ingestion

See [ARCHITECTURE](docs/ARCHITECTURE.md) for detailed implementation specifications.

## 🔒 Privacy & Security

- All processing is **on-device** by default
- No raw biosignals leave the device (unconditionally denied by consent service)
- **Device authentication** — ECDSA P-256 keys in hardware enclave, never exportable
- **3-layer consent** — Platform, app, and user consent must all allow before any upload
- Cloud sync uses **aggregated HSI** only
- HSI is strictly **non-medical**; no diagnoses or clinical labels

## Related Projects

| Repository | Platform | Description |
|------------|----------|-------------|
| [synheart-core](https://github.com/synheart-ai/synheart-core) | Spec | Source of truth for documentation and API design |
| [synheart-core-flutter](https://github.com/synheart-ai/synheart-core-flutter) | Flutter/Dart | This repository |
| [synheart-core-kotlin](https://github.com/synheart-ai/synheart-core-kotlin) | Android/Kotlin | Android SDK implementation |
| [synheart-core-swift](https://github.com/synheart-ai/synheart-core-swift) | iOS/Swift | iOS SDK implementation |
| [synheart-auth-flutter](https://github.com/synheart-ai/synheart-auth-flutter) | Flutter/Dart | Device authentication (ECDSA) |
| [synheart-wear-flutter](https://github.com/synheart-ai/synheart-wear-flutter) | Flutter/Dart | Wearable signal collection |
| [synheart-behavior-flutter](https://github.com/synheart-ai/synheart-behavior-flutter) | Flutter/Dart | Behavior event capture |

## 📄 License

Apache 2.0 License - see [LICENSE](LICENSE) for details.

Copyright 2025-2026 Synheart AI Inc.

## 👤 Author

Synheart Teeam <3 

## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.

