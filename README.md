🌐 Official website: [synheart.ai](https://synheart.ai) — Human State Interface (HSI) infrastructure for developers and AI systems.

# Synheart Core SDK - Dart/Flutter

[![Pub Version](https://img.shields.io/pub/v/synheart_core.svg)](https://pub.dev/packages/synheart_core)
[![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.32.0-blue.svg)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)


> **Source-available.** This repository is open for reading, auditing, and
> filing issues. We do **not** accept pull requests — see
> [CONTRIBUTING.md](CONTRIBUTING.md) for the rationale and how to contribute
> via issues. Security reports go through [SECURITY.md](SECURITY.md).
Flutter platform SDK for Synheart. This is a thin wrapper around the Synheart runtime — a native binary that owns the on-device business logic and is loaded by this SDK at startup.

Human state inference is computed on-device by the runtime.

**This SDK handles platform-specific concerns only:** sensor collection (HealthKit, Health Connect), UI consent flows, secure storage (Keychain, EncryptedSharedPreferences), and Flutter-native reactive streams.

## Architecture diagram

```text
Flutter App
    |
synheart-core-flutter (this SDK)
    |-- Wear/Phone/Behavior modules (platform sensor collection)
    |-- CoreRuntimeBridge (loads the runtime native binary)
    |
Synheart runtime native binary
    |-- HSI computation
    |-- Storage, Crypto, Sync, Auth, Consent, Capabilities
```

For the implementation principles — what each layer is responsible for and why — see the [Architecture](#architecture) section below.

## Repositories

| Repository | Purpose |
|------------|---------|
| **[synheart-core-flutter](https://github.com/synheart-ai/synheart-core-flutter)** | Flutter/Dart platform SDK (this repository) |
| **[synheart-core-kotlin](https://github.com/synheart-ai/synheart-core-kotlin)** | Android/Kotlin platform SDK |
| **[synheart-core-swift](https://github.com/synheart-ai/synheart-core-swift)** | iOS/Swift platform SDK |

## Overview

The Synheart Core SDK consolidates all Synheart signal channels into one SDK:

- **Wear Module** → Biosignals (HR, HRV, sleep, motion)
- **Phone Module** → Motion + context signals
- **Behavior Module** → Digital interaction patterns
- **HSI Runtime** → Signal fusion + state computation
- **Consent Module** → User permission management
- **Cloud Connector** → Secure HSI snapshot uploads

**Key principle:**
> One SDK, many modules, unified human-state model

## Features

- **Modular signal collection** — Wear (biosignals), Phone (motion/context), Behavior (interaction patterns)
- **On-device state computation** — the runtime fuses signals into HSI 1.3 frames; per-head inference detail lives inside the runtime and is not surfaced individually by this SDK
- **HSI 1.3 export** — canonical JSON wire format
- **Consent-first architecture** — All data collection respects explicit user consent; revocation stops modules immediately
- **Capability-gated features** — Server-signed tokens control which SDK features are available (core/extended/research)
- **On-demand collection** — Granular start/stop control per module, custom collection intervals
- **Raw data streams** — Direct access to wear samples and behavior events
- **SRM baseline export/import** — `Synheart.exportRuntimeSRMSnapshot()` / `loadRuntimeSRMSnapshot(...)` let hosts persist Self-Reference Model snapshots wherever they store other secure state
- **Device authentication** — Hardware-backed ECDSA signing via synheart-auth (Secure Enclave / Android Keystore)
- **Secure cloud upload** — Device-signed HSI snapshot uploads with offline queue
- **Reactive streams** — `Stream<HSIState>` and `Stream<String>` HSI updates via `dart:async`
- **RAMEN gRPC streaming + device-first E2EE sync** — both real-time streaming and the device-first E2EE sync layer ship in the runtime and are reachable from this SDK; no extra wiring required.

## Architecture

### Core Principle

> **All inference is computed by synheart-engine.**
>
> **SDKs coordinate data collection and distribution.**

The Core SDK strictly separates:
- **Computation** — synheart-engine computes HSV
- **Collection** — Core SDK modules (Wear, Phone, Behavior, Consent, Capability)
- **Distribution** — HSI JSON export, cloud upload, raw HSV diagnostics

### HSI is the public output

The runtime emits **HSI 1.3 JSON** via `Synheart.onHSIUpdate` (raw string) or `Synheart.onStateUpdate` (typed `HSIState`). The internal head-level representation (HSV) is not part of the public SDK API.

### Core Modules

1. **Device Auth** — Hardware-backed ECDSA device identity (via synheart-auth)
2. **Capabilities Module** — Feature gating via server-signed tokens (core/extended/research)
3. **Consent Module** — Consent enforcement and token issuance
4. **Wear Module** — Biosignal collection (HR, HRV, sleep, motion)
5. **Phone Module** — Device motion and context signals
6. **Behavior Module** — Consent-gated interaction patterns with runtime push
7. **Runtime bridge** — Loads the runtime native binary and routes signals to it
8. **Cloud Connector** — Device-signed HSI uploads (`X-Synheart-Signature` ECDSA P-256), offline-queue, schema validation

### Data Flow

```text
SynheartAuth (device registration + ECDSA signing)
    ↓
DeviceAuthProvider → RemoteCapabilityTokenFetcher
    ↓ (fetches capability token, gates features)
    ↓
Wear, Phone, Behavior Modules (raw signals)
    ↓ (consent & capability gated)
    ↓
CoreRuntimeBridge → Synheart runtime native binary
  ├─ Signal processing
  ├─ Feature extraction
  ├─ Multi-head inference
  └─ HSI 1.3 envelope build
    ↓
HSI JSON Output
  ├─ Synheart.onHSIUpdate (raw JSON)
  ├─ Synheart.onStateUpdate (typed projection)
  └─ Cloud upload (ECDSA P-256 + `X-Synheart-Proof` JWS + `X-Consent-Token` JWT, consent-gated)
```

## Installation

Add `synheart_core` to your `pubspec.yaml`:

```yaml
dependencies:
  synheart_core: ^0.2.0
```

Or:

```bash
flutter pub add synheart_core
```

Then run:

```bash
flutter pub get
```

### Native Runtime Setup

This SDK is a thin FFI shell over the **Synheart Runtime** native
binary. The binary is not bundled with the pub.dev package — install
it once per project with the [Synheart CLI](https://docs.synheart.ai/synheart-cli):

```bash
# Once, on your machine:
curl -fsSL https://synheart.sh/install | sh
synheart login

# In your project root:
synheart install runtime    # downloads + installs the native runtime
synheart sync               # reinstall what synheart.lock pins (CI-safe)
```

`synheart install runtime` auto-detects your project type (Flutter,
Swift Package, Gradle) and drops the runtime into the right slot:

- iOS: `ios/Frameworks/SynheartRuntime.xcframework/`
- Android: `android/src/main/jniLibs/<abi>/libsynheart_runtime.so`

It also writes `synheart.lock`, which pins the exact runtime version
and per-platform artifact hashes. Commit the lockfile so CI and
teammates get byte-identical builds via `synheart sync`.

The iOS podspec uses `-force_load` so all FFI symbols are preserved
for Dart's `dlsym`. Both the xcframework and the `.so` files are
gitignored — they're CLI-managed, not hand-edited.

> **Note:** If your app also uses another native static library that
> exports `_rust_eh_personality`, you may hit a duplicate-symbol link
> error. Resolve by linking one of them as a dynamic framework
> instead — see the CLI's
> [troubleshooting](https://docs.synheart.ai/synheart-cli#troubleshooting).

## Pointing at the Synheart Platform (optional)

The SDK works fully **on-device** without any cloud connection — HSI
inference, consent, capabilities, and the local artifact pipeline all
run with no platform dependency. You only need to configure platform
endpoints if you want to opt into:

- **Cloud HSI upload** (`SynheartFeature.cloud`)
- **Server-issued consent tokens** (the consent service API)
- **Server-issued capability tokens** (the auth/account API)
- **Lab session export** (the platform ingest service)

Defaults point at `https://api.synheart.ai`. If you're targeting a
different environment (a self-hosted platform, a staging tenant, or a
local `synheart local` server), inject the URLs at compile time:

```bash
flutter run --dart-define-from-file=env/synheart.endpoints.local.json
```

**File shape** (use `env/synheart.endpoints.example.json` as a starting
point):

```json
{
  "SYNHEART_CLOUD_BASE_URL": "https://api.your-platform.example",
  "SYNHEART_CONSENT_BASE_URL": "https://api.your-platform.example",
  "SYNHEART_INGEST_BASE_URL": "https://api.your-platform.example",
  "SYNHEART_LAB_INGEST_BASE_URL": "https://api.your-platform.example",
  "SYNHEART_AUTH_BASE_URL": "https://api.your-platform.example"
}
```

| Define key | Used for |
|---|---|
| `SYNHEART_CLOUD_BASE_URL` | HSI cloud ingest (`ApiEndpoints.defaultCloudBaseUrl`) |
| `SYNHEART_CONSENT_BASE_URL` | Consent service API (`ApiEndpoints.defaultConsentBaseUrl`) |
| `SYNHEART_INGEST_BASE_URL` | HSI snapshot ingest (`ApiEndpoints.defaultIngestBaseUrl`) |
| `SYNHEART_LAB_INGEST_BASE_URL` | Lab session/metadata ingest (`ApiEndpoints.defaultLabIngestBaseUrl`) |
| `SYNHEART_AUTH_BASE_URL` | Auth/account API (exchange, refresh, account delete) |

Values are read at compile time via `String.fromEnvironment` in
`lib/src/config/api_endpoints.dart`. Gitignore your local file so the
URLs aren't committed if you're targeting a private environment.

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
      authBaseUrl: 'https://api.synheart.ai/auth',
    ),
    cloudConfig: CloudConfig(
      subjectId: 'anon_user_123',
      instanceId: 'instance-uuid',
      // Request signing is handled by the runtime's hardware-backed
      // ECDSA key — no shared secret needed in CloudConfig.
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

// Activate the features your app needs.
//   SynheartFeature.wear / .behavior / .phoneContext / .cloud
Synheart.activate(SynheartFeature.wear);
Synheart.activate(SynheartFeature.cloud);
```

State signals (focus, emotion, recovery, etc.) are not separate
features — they're axes inside the HSI JSON emitted by
`Synheart.onHSIUpdate`. Parse the JSON or use `Synheart.onStateUpdate`
to read them.

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

### HSI access

The SDK exposes HSI 1.3 JSON frames produced by the engine — that's
the canonical wire format consumers integrate against:

```dart
import 'package:synheart_core/synheart_core.dart';

// Subscribe to HSI updates (raw JSON string from synheart-engine).
Synheart.onHSIUpdate.listen((hsiJson) {
  // hsiJson is already a canonical HSI 1.3 JSON string —
  // send to an external system, validate against the spec, etc.
  print(hsiJson);
});

// Or use the typed projection.
Synheart.onStateUpdate.listen((state) {
  print('Arousal: ${state.axes.affect?.arousalIndex}');
});
```

`HSV` (the engine's internal head-shaped representation) does not
cross the FFI boundary — it stays inside the Synheart Runtime. All
host language SDKs (Dart, Kotlin, Swift) consume **HSI** uniformly;
HSV details live in the engine and are not surfaced individually.

See the [example app](example/) for a complete integration walkthrough.

## Batch Ingest Mode

By default, the runtime module streams wear and behavior data to the native engine in real-time, producing HSI frames as windows complete. **Batch ingest mode** buffers all events during a session and runs a single `ingestBatch` call on stop, producing all HSI frames at once.

This is useful for:
- Offline-first apps that collect data without connectivity
- Background recording where real-time HSI isn't needed
- Reducing CPU usage during active sessions

### Configuration

```dart
await Synheart.initialize(
  config: SynheartConfig(
    appId: 'your_app_id',
    subjectId: 'sub_user_123',
    batchIngestOnStop: true, // Enable batch mode
  ),
);
```

### Runtime toggle

Batch mode can be toggled between sessions (the setter is static —
`Synheart.initialize` returns `Future<void>`, so don't assign it to a
variable):

```dart
Synheart.setBatchIngestOnStop(true);  // Next session uses batch
Synheart.setBatchIngestOnStop(false); // Back to streaming
```

## Lab ingestion

The SDK can send structured session and metadata payloads to the
Synheart platform — useful for research workflows where the host app
needs to record protocol windows and submit them alongside the usual
HSI stream.

### Driving a lab protocol

Lab protocols are driven by the static `Synheart.lab*` API. The runtime
keeps the open protocol state and emits a serializable payload at
`labFinalize`:

```dart
final now = () => DateTime.now().millisecondsSinceEpoch;

// 1. Start a protocol (returns a session id).
final sessionId = Synheart.labStart(protocolJson, now());

// 2. Open windows during the session.
final windowId = Synheart.labOpenWindow(
  windowType: 'baseline',
  startedAtMs: now(),
);
//    ... collect data ...
Synheart.labCloseWindow(windowId, now());

// 3. Finalize the session — returns the JSON payload.
final payload = Synheart.labFinalize(now());
```

### Auto-ingest on finalize

When the host has been granted `research` consent and the
`cloudConfig` is wired up, the runtime auto-enqueues the
`labFinalize` payload for upload alongside the HSI snapshots — no
extra config object is needed:

```dart
await Synheart.initialize(
  config: SynheartConfig(
    appId: 'your_app_id',
    subjectId: 'sub_user_123',
    cloudConfig: CloudConfig(
      // apiKey is legacy/optional — production hosts wire request
      // signing through the device's hardware-backed ECDSA key
      // (see CloudConfig comment above). Pass it only if your
      // platform deployment still requires a shared secret.
      apiKey: 'your_platform_api_key',
      baseUrl: 'https://api.synheart.ai',
      subjectId: 'sub_user_123',
      instanceId: 'device_abc',
    ),
  ),
);

await Synheart.grantConsent(
  biosignals: true,
  behavior: true,
  phoneContext: false,
  cloudUpload: true,
  research: true,
);
```

### Manual ingestion

For custom workflows that build payloads outside the `lab*` API, post
through the `Synheart.ingestion` accessor:

```dart
final response = await Synheart.ingestion.submitSessionArtifacts(payload);
final metaResponse = await Synheart.ingestion.submitMetadata(metadataJson);
```

`submitSessionArtifacts` requires `behavior` consent;
`submitMetadata` requires `biosignals` consent. Both return a typed
response with `success`, `statusCode`, and an optional
`errorMessage`.

### Consent Management

The SDK requires explicit user consent for data collection. **All data collection respects consent** - no data is collected or streamed without explicit user consent.

The six canonical consent types are:
`biosignals`, `phoneContext`, `behavior`, `cloudUpload`, `vendorSync`,
`research`.

#### Granting Consent

```dart
// Grant consent for specific data types (all parameters required)
await Synheart.grantConsent(
  biosignals: true,
  behavior: true,
  phoneContext: true,
  cloudUpload: false,  // User must explicitly opt-in
  profileId: 'profile-123', // Optional: for consent service integration
);

// If using consent service with profiles
final profiles = await Synheart.getAvailableConsentProfiles();
final selectedProfile = profiles.first; // User selects a profile
await Synheart.grantConsent(
  biosignals: true,
  behavior: true,
  phoneContext: true,
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
bool hasPhoneContextConsent = consentStatus['phoneContext'] ?? false;
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
  phoneContext: true,
  cloudUpload: true,
  profileId: selectedProfile.id,
);
```

#### Revoking Consent

```dart
// Revoke consent for a specific type (stops data collection immediately)
await Synheart.revokeConsentType('biosignals');
await Synheart.revokeConsentType('behavior');
await Synheart.revokeConsentType('phoneContext');
await Synheart.revokeConsentType('cloudUpload');

// Revoke all consent
await Synheart.revokeConsent();
```

**Important**: 
- Consent is checked before starting any data collection
- If consent is revoked, data collection stops immediately
- Raw data streams (`wearSampleStream`, `behaviorEventStream`) only emit data when consent is granted
- All module start methods respect consent - they won't start if consent is denied

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
| `initialize({config, userId, autoStart})` | Initialize the SDK (named-arg form) |
| `startSession()` / `stopSession()` | Start/stop data collection |
| `startWearCollection()` / `stopWearCollection()` | Control wear module |
| `startBehaviorCollection()` / `stopBehaviorCollection()` | Control behavior module |
| `startPhoneCollection()` / `stopPhoneCollection()` | Control phone module |
| `activate(feature)` / `deactivate(feature)` | Enable/disable a `SynheartFeature` (`wear`, `behavior`, `phoneContext`, `cloud`) |
| `grantConsent({biosignals, behavior, phoneContext, cloudUpload, ...})` | Grant consent per channel |
| `revokeConsent()` / `revokeConsentType(type)` | Revoke consent |
| `Synheart.ingestion.flushIfEligible()` | Drain pending HSI uploads when the queue is eligible (canonical) |
| `Synheart.runtimeDiagnostics()` | Snapshot runtime diagnostics (FFI / engine state) |
| `Synheart.uploadQueueLength` | Sync getter — pending HSI uploads in the local queue |
| `Synheart.lastIngestSuccessAtMs` | Sync getter — epoch-ms of the last successful ingest |
| `Synheart.ingestion.enqueueHsiWindows(...)` | Enqueue HSI windows for cloud upload |
| `checkNotificationListenerEnabled()` | Check notification access for behavior metrics |
| `dispose()` | Release all resources |

### Streams

| Stream | Type | Description |
|--------|------|-------------|
| `onHSIUpdate` | `Stream<String>` | HSI JSON frames from synheart-engine |
| `onStateUpdate` | `Stream<HSIState>` | Typed projection of `onHSIUpdate` |
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

The plugin ships only a library manifest — no permissions are merged
into the consumer app automatically. Declare every permission and
component below yourself, or the corresponding module will silently
fail at runtime (Health Connect reads return empty, the notification
listener won't bind, phone-call state events won't fire).

**AndroidManifest.xml** — add the following permissions and services:

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

The Core SDK supports all devices that [synheart_wear](https://pub.dev/packages/synheart_wear) supports (Apple Watch, Fitbit, Garmin, etc.). Garmin **real-time streaming** requires a separate Garmin Health SDK license — see [`synheart-wear-flutter/docs/GARMIN_SETUP.md`](https://github.com/synheart-ai/synheart-wear-flutter/blob/main/docs/GARMIN_SETUP.md) for the integrator workflow.

### Quick Start

The example app (`example/`) includes all required configurations. You can copy the relevant sections from:
- `example/ios/Runner/Info.plist` for iOS
- `example/android/app/src/main/AndroidManifest.xml` for Android
- `example/android/app/src/main/kotlin/com/example/synheart_core/MainActivity.kt` for MainActivity

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
| `GET` | `/v1/apps/{id}/consent-profiles` | Fetch consent profiles |
| `POST` | `/v1/sdk/consent-token` | Issue consent token |
| `POST` | `/v1/sdk/consent-revoke` | Revoke consent |
| `POST` | `/v1/hsi/ingest` | Ingest HSI snapshots |
| `POST` | `/v1/lab/session/ingest` | Ingest lab session payload |
| `POST` | `/v1/lab/metadata/ingest` | Ingest lab metadata |
| `GET` | `/status` | Server status and stats |

### Default credentials

The `synheart local` server provides default API keys for development. Run `synheart local --help` to see defaults. Use `allowUnsignedCapabilities: true` in your SDK config to skip device attestation locally.

### Testing consent flow

```dart
// In local mode, consent profiles are served from data/profiles.json
// 3 presets are included: Personal Wellness, Research (Full), Biosignals + Cloud

final profiles = await Synheart.getAvailableConsentProfiles();
// Returns the 3 preset profiles from the local server

await Synheart.grantConsent(
  biosignals: true,
  behavior: true,
  phoneContext: true,
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

## Contributing

This repository is **source-available** under Apache-2.0. Issues are welcome — bug reports, feature requests, and questions help shape the roadmap. **Pull requests are not accepted at this time**; the SDK is mirrored from an internal monorepo and external PRs are auto-closed.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the rationale and the issue-filing process. Security reports go through [SECURITY.md](SECURITY.md).


## Module Overview

The Synheart Core SDK consists of 9 core modules:

1. **Device Auth** - Hardware-backed ECDSA device identity (via synheart-auth)
2. **Capabilities Module** - Server-signed feature gating (core/extended/research)
3. **Consent Module** - Consent enforcement + token issuance
4. **Wear Module** - Biosignal collection from wearables
5. **Phone Module** - Device motion and context signals
6. **Behavior Module** - Consent-gated interaction patterns
7. **HSI Runtime** - Signal fusion and state computation
8. **Cloud Connector** - Device-signed HSI snapshot uploads
9. **Lab Ingest** - Session and metadata ingestion

## Privacy & Security

- All processing is **on-device** by default
- No raw biosignals leave the device (unconditionally denied by consent service)
- **Device authentication** — ECDSA P-256 keys in hardware enclave, never exportable
- **3-layer consent** — Platform, app, and user consent must all allow before any upload
- **Consent enforced at every level** — collection, caching, streaming, and local HSI delivery all respect consent
- **HSI stream is consent-gated** — `onHSIUpdate` only emits frames when `biosignals` consent is granted
- **On-demand collection** — apps can minimize data collection to only when needed
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

## Not a Medical Device

This SDK is intended for wellness and research use only. It is not a medical device, is not intended to diagnose, treat, cure, or prevent any disease or condition, and has not been evaluated by the FDA or any other regulatory body.

## License

Apache 2.0 — see [LICENSE](LICENSE).

Copyright 2025-2026 Synheart AI Inc.

## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.