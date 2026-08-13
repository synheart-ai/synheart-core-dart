# Synheart Core SDK for Flutter

[![Pub Version](https://img.shields.io/pub/v/synheart_core.svg)](https://pub.dev/packages/synheart_core)
[![Flutter](https://img.shields.io/badge/Flutter-3.32%2B-02569B.svg)](https://flutter.dev)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Synheart Core is the Flutter integration SDK for the Human State Interface
(HSI). It collects consented wearable, phone, and behavior signals, passes them
to the on-device Synheart Runtime, and exposes HSI 1.3 output as Dart streams.

The package is a platform wrapper. Signal processing, state computation,
storage, device authentication, and sync are implemented by the separately
installed native Synheart Runtime.

> Synheart Core is intended for wellness and research use. It is not a medical
> device and must not be used to diagnose, treat, cure, or prevent disease.

## Contents

- [What the SDK provides](#what-the-sdk-provides)
- [Requirements](#requirements)
- [Install](#install)
- [Platform setup](#platform-setup)
- [Quick start](#quick-start)
- [Initialization and configuration](#initialization-and-configuration)
- [Consent](#consent)
- [Sessions and collection](#sessions-and-collection)
- [Reading HSI and raw signals](#reading-hsi-and-raw-signals)
- [Cloud, authentication, and endpoints](#cloud-authentication-and-endpoints)
- [Storage and sync](#storage-and-sync)
- [Advanced workflows](#advanced-workflows)
- [API map](#api-map)
- [Errors and diagnostics](#errors-and-diagnostics)
- [Testing and example app](#testing-and-example-app)

## What the SDK provides

| Area | Purpose |
| --- | --- |
| Wear | Heart rate, HRV, sleep, motion, and wearable-provider integration |
| Phone | Device motion, screen state, and app context |
| Behavior | Consent-gated taps, typing, gestures, notifications, and motion events |
| HSI Runtime | On-device signal fusion and HSI 1.3 generation |
| Consent | Local consent state, server-issued consent tokens, and revocation |
| Capabilities | Signed feature gating for production deployments |
| Cloud | Device-signed HSI and lab uploads with an offline queue |
| Synsync | Cross-device synchronization and baseline restoration |
| Research | Lab windows, study enrolment, study consent, and separate runtime instances |
| Syni | Consent- and capability-gated adaptive AI integration |

### Data flow

```text
Wear / Phone / Behavior sources
              │
              ▼
      Consent + capability gates
              │
              ▼
       Synheart Core Flutter
              │ FFI
              ▼
      Synheart native runtime
       ├─ signal processing
       ├─ HSI 1.3 computation
       ├─ encrypted local storage
       ├─ device authentication
       └─ cloud and device sync
              │
              ▼
    Stream<String> / Stream<HSIState>
```

HSI is the public state output. Internal engine representations do not cross
the FFI boundary.

## Requirements

- Dart `>=3.8.0 <4.0.0`
- Flutter `>=3.32.0`
- Android API 24+ for the package
- iOS 15.0+ for the package
- A Synheart Runtime binary installed in the host application

Individual data sources may impose stricter OS, permission, hardware, or vendor
requirements. The example Android application currently targets API 28+.

## Install

Add the package:

```bash
flutter pub add synheart_core
```

Or declare the current package line explicitly:

```yaml
dependencies:
  synheart_core: ^0.10.2
```

Then install the native runtime:

```bash
# Install the CLI once.
curl -fsSL https://synheart.sh/install | sh
synheart login

# Run in the Flutter project root.
synheart install runtime
```

The CLI installs the native artifact in the platform project and writes
`synheart.lock`. Commit `synheart.lock`; CI and other developers can restore the
pinned artifact with:

```bash
synheart sync
```

Typical installed locations:

- iOS: `synheart/vendor/runtime/ios/SynheartCoreRuntime.xcframework/`
- Android: `synheart/vendor/runtime/android/jniLibs/<abi>/`

The iOS plugin links ONNX Runtime separately through `onnxruntime-c`. If
CocoaPods cannot locate the application root (most commonly in a monorepo), set
it near the top of the host application's `ios/Podfile`:

```ruby
ENV['SYNHEART_APP_ROOT'] = File.expand_path('..', __dir__)
```

Then rerun `pod install` or rebuild the Flutter application.

## Platform setup

Only declare permissions for modules your application enables. Permission
declarations do not replace an in-app explanation and runtime permission flow.

### iOS

Enable the HealthKit capability in Xcode when using wearable or Apple Health
data. Add usage descriptions to `ios/Runner/Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>This app reads health data to calculate consented wellbeing insights.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>This app writes supported health data when you enable health synchronization.</string>
```

Use wording that accurately describes your application. See
`example/ios/Runner/Info.plist` for a working project configuration.

### Android

The package does not merge all consumer permissions automatically. Add the
permissions needed by your enabled sources to
`android/app/src/main/AndroidManifest.xml`.

Common declarations are:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.READ_PHONE_STATE" />

<!-- Health Connect: include only the record types your app reads or writes. -->
<uses-permission android:name="android.permission.health.READ_HEART_RATE" />
<uses-permission android:name="android.permission.health.READ_HEART_RATE_VARIABILITY" />
<uses-permission android:name="android.permission.health.READ_STEPS" />
<uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED" />
<uses-permission android:name="android.permission.health.READ_DISTANCE" />
<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_HISTORY" />
```

For behavior notification access, declare the listener inside `<application>`:

```xml
<service
    android:name="ai.synheart.behavior.SynheartNotificationListenerService"
    android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
    android:exported="true">
    <intent-filter>
        <action android:name="android.service.notification.NotificationListenerService" />
    </intent-filter>
</service>
```

Health Connect also requires package queries, a permission-rationale intent,
and a privacy-policy activity alias. Copy the relevant declarations from
`example/android/app/src/main/AndroidManifest.xml`. On Android 14+, use
`FlutterFragmentActivity` for the host activity:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

## Quick start

The following is a local-development setup. Unsigned capabilities must not be
enabled in production.

```dart
import 'dart:async';
import 'package:synheart_core/synheart_core.dart';

late final StreamSubscription<HSIState> hsiSubscription;

Future<void> startSynheart() async {
  await Synheart.initialize(
    config: SynheartConfig(
      appId: 'com.example.my_app',
      subjectId: 'user-123',
      appVersion: '1.0.0',
      allowUnsignedCapabilities: true, // Development only.
      wearConfig: const WearConfig(),
      phoneConfig: const PhoneConfig(),
      behaviorConfig: const BehaviorConfig(),
    ),
  );

  await Synheart.grantConsent(
    biosignals: true,
    phoneContext: false,
    behavior: true,
    cloudUpload: false,
  );

  hsiSubscription = Synheart.onStateUpdate.listen((state) {
    print('Stress: ${state.hsi.stress?.value}');
  });

  await Synheart.startSession();
}

Future<void> stopSynheart() async {
  await Synheart.stopSession();
  await hsiSubscription.cancel();
  await Synheart.dispose();
}
```

`initialize()` configures the SDK but does not collect data by default.
Collection starts with `startSession()`. Set `autoStart: true` only when the
application has already completed its consent flow.

## Initialization and configuration

### Required identity

For validated configuration, both `appId` and `subjectId` must be non-empty.
`subjectId` must be stable for the signed-in or pseudonymous user and cannot
contain `|`.

```dart
final config = SynheartConfig(
  appId: 'com.example.my_app',
  subjectId: 'pseudonymous-user-id',
  mode: SynheartMode.personal,
  appVersion: '2.3.0',
  appName: 'Example',
  category: 'Wellness',
  developer: 'Example Inc.',
);
```

`initialize()` is idempotent while initialized: concurrent callers share the
same initialization, and later calls are no-ops. To initialize a different
configuration after teardown, first call `Synheart.dispose()`.

When the signed-in identity changes without teardown, use:

```dart
final changed = await Synheart.rebindSubjectId('new-subject-id');
```

This keeps the native runtime, consent scope, and cloud upload identity aligned.

### Modes

| Mode | Persistence behavior |
| --- | --- |
| `personal` | HSI, session summaries, and baselines; no raw biosignals or app metrics |
| `insight` | Personal-mode data plus application metrics |
| `research` | May persist raw biosignals; requires `PrivacyConfig(allowResearch: true)` and explicit research consent |

Research mode configuration:

```dart
SynheartConfig(
  appId: 'com.example.study',
  subjectId: 'research-participant-id',
  mode: SynheartMode.research,
  privacy: const PrivacyConfig(allowResearch: true),
  allowUnsignedCapabilities: true, // Replace in production.
);
```

### Module configuration

Modules are activated when their corresponding config is present:

```dart
SynheartConfig(
  appId: 'com.example.my_app',
  subjectId: 'user-123',
  wearConfig: const WearConfig(
    sampleRateHz: 1,
    enableCaching: true,
  ),
  phoneConfig: const PhoneConfig(
    enableMotion: true,
    enableScreenState: true,
    enableAppTracking: false,
  ),
  behaviorConfig: const BehaviorConfig(
    enableGestureTracking: true,
    enableTypingTracking: true,
    enableMotionLite: false,
    emitRawMotionSamples: false,
  ),
  allowUnsignedCapabilities: true,
);
```

Features can also be activated explicitly before a session:

```dart
Synheart.activate(SynheartFeature.wear);
Synheart.activate(SynheartFeature.behavior);

final requested = Synheart.isActivated(SynheartFeature.wear);
final operational = Synheart.isFeatureOperational(SynheartFeature.wear);
```

Activation alone does not permit collection. A feature is operational only
when activation, consent, capability, and session gates all allow it.

## Consent

Consent is required before collection or cloud upload. The canonical channels
include:

- `biosignals`
- `phoneContext`
- `behavior`
- `cloudUpload`
- `vendorSync`
- `research`
- `syni`

### Local consent

Use local consent for offline applications or development:

```dart
await Synheart.grantConsent(
  biosignals: true,
  phoneContext: true,
  behavior: true,
  cloudUpload: false,
  vendorSync: false,
  research: false,
  syni: false,
);

final status = Synheart.getConsentStatusMap();
final canCollectWear = status['biosignals'] ?? false;
```

Observe changes instead of polling:

```dart
final subscription = Synheart.consentChanges.listen((snapshot) {
  print('Biosignals: ${snapshot.biosignals}');
  print('Cloud: ${snapshot.cloudUpload}');
});
```

Revoke one channel or all channels:

```dart
await Synheart.revokeConsentType('behavior');
await Synheart.revokeConsent();
```

Revocation closes the corresponding collection and delivery gates.

### Hosted consent service

Configure the consent service to load profiles and issue a server token:

```dart
final consent = ConsentConfig(
  appId: 'com.example.my_app',
  appApiKey: 'app-api-key',
  userId: 'user-123',
  region: 'US',
);
```

Then integrate the profile selection into your own UI:

```dart
final profiles = await Synheart.getAvailableConsentProfiles();

Synheart.setConsentUIProvider((availableProfiles) async {
  // Present application UI and return the selected profile.
  return availableProfiles.first;
});

final token = await Synheart.requestConsent();
```

Never ship API keys in source control. Inject deployment values through your
build or secret-management system.

## Sessions and collection

### Full session lifecycle

```dart
final handle = await Synheart.startSession(durationSec: 30 * 60);
print(handle?.sessionId);

// Collection runs until the duration expires or the app stops it.
await Synheart.stopSession();
```

At least one feature must be activated and consented. Use
`Synheart.isSessionRunning` and `Synheart.currentSession` to inspect state.

### Module-level control

```dart
await Synheart.startWearCollection(
  interval: const Duration(seconds: 1),
);
await Synheart.startBehaviorCollection();
await Synheart.startPhoneCollection();

print(Synheart.isWearCollecting);
print(Synheart.isBehaviorCollecting);
print(Synheart.isPhoneCollecting);

await Synheart.stopPhoneCollection();
await Synheart.stopBehaviorCollection();
await Synheart.stopWearCollection();
```

Module methods still enforce consent and capabilities.

### Batch ingest on stop

For background or offline-first sessions, buffer events and compute the session
when it stops:

```dart
final config = SynheartConfig(
  appId: 'com.example.my_app',
  subjectId: 'user-123',
  batchIngestOnStop: true,
  allowUnsignedCapabilities: true,
);
```

The setting may be changed between sessions:

```dart
Synheart.setBatchIngestOnStop(true);
```

In batch mode, HSI output is produced after the session is stopped rather than
continuously during collection.

## Reading HSI and raw signals

### Canonical JSON

`onHSIUpdate` emits the canonical HSI 1.3 JSON generated by the runtime:

```dart
final subscription = Synheart.onHSIUpdate.listen((hsiJson) {
  sendToYourConsumer(hsiJson);
});
```

### Typed state

`onStateUpdate` parses each JSON frame into `HSIState`:

```dart
final subscription = Synheart.onStateUpdate.listen((state) {
  print(state.hsi.stress?.value);
  print(state.rawJson);
});

final latest = Synheart.currentHSIState;
```

Fields may be null when the runtime lacks sufficient input or an older HSI
payload does not contain that axis. Keep the raw JSON when exact wire-format
forwarding or schema validation is required.

### Raw streams and session buffers

```dart
final wearSub = Synheart.wearSampleStream.listen((sample) {
  print('HR: ${sample.hr}');
  print('RR: ${sample.rrIntervals}');
});

final behaviorSub = Synheart.behaviorEventStream.listen((event) {
  print('${event.type} at ${event.timestamp}');
});

final hsiWindows = Synheart.getSessionHsiWindows();
final wearSamples = Synheart.getSessionWearSamples();
```

Raw streams are consent-gated. Cancel subscriptions when their owner is
disposed.

### Application metrics

Metrics are persisted in `insight` and `research` modes and dropped in
`personal` mode:

```dart
await Synheart.recordMetric(
  MetricEvent(
    name: 'reaction_time_ms',
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    value: 318,
    tags: const {'level': 'tutorial'},
  ),
);
```

## Cloud, authentication, and endpoints

### Production authentication

Production applications should configure device authentication. The runtime
registers a hardware-backed device identity and signs supported requests.

```dart
final config = SynheartConfig(
  appId: 'com.example.my_app',
  subjectId: 'user-123',
  deviceAuthConfig: const DeviceAuthConfig(
    authBaseUrl: 'https://api.synheart.ai',
    packageName: 'com.example.my_app',
  ),
  cloudConfig: CloudConfig(
    subjectId: 'user-123',
    instanceId: 'stable-installation-uuid',
    orgId: 'organization-id',
  ),
);
```

Device registration is deferred until a cloud-bound operation needs it. The
following recovery helpers are available:

```dart
final registered = await Synheart.ensureDeviceAuthRegistered();
final repaired = await Synheart.reregisterDeviceAuth();
final authStatus = Synheart.coreDeviceAuthStatus();
```

`allowUnsignedCapabilities` is a development escape hatch, not a production
authentication strategy.

### Endpoint configuration

The default platform origin is `https://api.synheart.ai`. Override it at
compile time:

```bash
flutter run \
  --dart-define=SYNHEART_BASE_URL=https://api.example.com
```

Optional per-service overrides:

- `SYNHEART_AUTH_BASE_URL`
- `SYNHEART_CONSENT_BASE_URL`
- `SYNHEART_INGEST_BASE_URL`

Use `env/synheart.endpoints.example.json` with:

```bash
flutter run --dart-define-from-file=env/synheart.endpoints.local.json
```

Base URLs must be origins. The runtime appends service paths.

### Upload state

Cloud upload requires `cloudUpload` consent, a cloud configuration, and a valid
device/consent credential:

```dart
print(Synheart.uploadQueueLength);
print(Synheart.lastUploadBatchId);
print(Synheart.lastUploadAt);
print(Synheart.lastUploadError);

final ready = await Synheart.ensureCloudConsentReady();
await Synheart.ingestion.flushIfEligible();
```

## Storage and sync

### Local sessions

```dart
final sessions = await Synheart.listSessions();
final summary = await Synheart.getSessionSummary(sessions.first.sessionId);
final windows = await Synheart.getHSIWindows(sessions.first.sessionId);
final usage = await Synheart.getStorageUsage();

await Synheart.setRetentionDays(30);
await Synheart.deleteLocalSession(sessions.first.sessionId);
```

Clean up sessions left active after process termination:

```dart
await Synheart.sweepOrphanSessions(
  olderThan: const Duration(hours: 6),
);
```

Local erasure:

```dart
await Synheart.wipeLocalData();
```

### Cross-device sync

Enable sync in configuration:

```dart
SynheartConfig(
  appId: 'com.example.my_app',
  subjectId: 'user-123',
  sync: const SyncConfig(
    enabled: true,
    baseUrl: 'https://api.synheart.ai',
  ),
);
```

Check readiness before presenting sync actions:

```dart
final readiness = await Synheart.checkSyncReadiness();
final result = await Synheart.syncNow();
final status = await Synheart.getSyncStatus();
```

The SDK also exposes space creation, pairing, recovery, device listing,
revocation, leave, and delete operations through the `Synheart.sync*` methods.
Native sync failures may throw `SyncNativeException`; inspect `code`,
`message`, and `retryable`.

## Advanced workflows

### Behavior tracking wrapper

Wrap the app root to capture consented gestures:

```dart
return Synheart.wrapWithBehaviorDetector(
  MaterialApp(home: const HomeScreen()),
);
```

Behavior sessions provide aggregated interaction results:

```dart
final sessionId = await Synheart.startBehaviorSession();
final results = await Synheart.stopBehaviorSession(sessionId);
print(results.tapRate);
```

On Android, notification access is a special settings grant:

```dart
final enabled = await Synheart.checkNotificationListenerEnabled();
if (!enabled) {
  await Synheart.openNotificationListenerSettings();
}
```

### Watch sessions

The SDK re-exports `synheart_session` types and provides a watch-session stream:

```dart
final events = Synheart.startWatchSession(
  SessionConfig(
    mode: SessionMode.focus,
    durationSec: 300,
    profile: const ComputeProfile(
      windowSec: 60,
      emitIntervalSec: 5,
    ),
  ),
);

final subscription = events.listen((event) {
  // Handle SessionStarted, SessionFrame, SessionSummary, and SessionError.
});
```

### Baselines and scores

The package exposes:

- typed baseline snapshots through `Synheart.baselineSnapshots`
- vendor-sleep baseline orchestration through `Baselines`
- sleep, recovery, readiness, and resilience score models
- offline baseline export/import
- Apple Health XML and Health Connect backfill sinks

These are advanced, source-specific APIs. Consult their exported Dartdoc and
the example application before integrating them.

### Edge ingest: watch to phone

`EdgeIngest` is a pure-Dart, transport-independent consumer for Synheart edge
messages. It verifies artifact hashes and HSI versions, deduplicates artifacts,
and builds acknowledgement bodies:

```dart
final ingest = EdgeIngest();
final subscription = ingest.events.listen((event) {
  switch (event) {
    case HrEvent(:final sample):
      print(sample);
    case BioEvent(:final sample):
      print(sample);
    case ArtifactEvent(:final artifact):
      print(artifact.payloadJson);
    case SessionEventWrap():
      break;
  }
});

final outcome = ingest.ingest(decodedMessage);
final ack = ingest.drainAckBody();
if (ack != null) {
  sendOnCommandChannel(ack);
}

await subscription.cancel();
await ingest.dispose();
```

The host supplies the WatchConnectivity or Wear Data Layer transport.

### Lab and research

The static lab API controls a protocol and its nested windows:

```dart
final now = DateTime.now().millisecondsSinceEpoch;
final error = Synheart.labStart(protocolJson, now);
if (error != null) {
  throw StateError(error);
}

final windowId = Synheart.labOpenWindow(
  windowType: 'trial',
  label: 'baseline-rest',
  startedAtMs: DateTime.now().millisecondsSinceEpoch,
);

if (windowId != null) {
  Synheart.labSetWindowValues(windowId, '{"score": 0.8}');
  Synheart.labCloseWindow(
    windowId,
    DateTime.now().millisecondsSinceEpoch,
  );
}

final sessionJson = Synheart.labFinalize(
  DateTime.now().millisecondsSinceEpoch,
);
```

Research-study helpers include:

- `validateResearchStudyCodes(...)`
- `enrolResearchStudy(...)`
- `researchStudyStatus()`
- `recordStudyConsent(...)`
- `withdrawResearchStudy()`
- `requestStudyDataDeletion(...)`

For a separate research identity alongside the personal singleton, create a
`SynheartInstance` with a unique `subjectId` and durable `dataDir`. Never share
a data directory between instances:

```dart
final research = SynheartInstance.create(
  config: researchConfig,
  dataDir: researchDataDirectory,
);

try {
  research?.startSession();
  // Run the research protocol on this instance.
} finally {
  research?.stopSession();
  research?.dispose();
}
```

On study withdrawal, call `wipeLocalData()` before `dispose()` when local
research data must also be erased.

## API map

The package exports all public APIs from:

```dart
import 'package:synheart_core/synheart_core.dart';
```

### Lifecycle and feature gates

- `Synheart.initialize(...)`, `dispose()`
- `startSession(...)`, `stopSession()`
- `activate(...)`, `deactivate(...)`
- `isInitialized`, `isSessionRunning`, `currentSession`
- `isActivated(...)`, `isFeatureOperational(...)`

### Streams

| API | Type |
| --- | --- |
| `Synheart.onHSIUpdate` | `Stream<String>` |
| `Synheart.onStateUpdate` | `Stream<HSIState>` |
| `Synheart.wearSampleStream` | `Stream<WearSample>` |
| `Synheart.behaviorEventStream` | `Stream<BehaviorEvent>` |
| `Synheart.consentChanges` | `Stream<ConsentSnapshot>` |
| `Synheart.watchSessionEvents` | `Stream<SessionEvent>` |

### Major API groups

- Consent: `grantConsent`, `requestConsent`, `revokeConsent`,
  `consentEffectiveStateTyped`
- Collection: `startWearCollection`, `startBehaviorCollection`,
  `startPhoneCollection`
- Storage: `listSessions`, `getSessionSummary`, `getHSIWindows`,
  `getStorageUsage`, `wipeLocalData`
- Sync: `checkSyncReadiness`, `syncNow`, `syncCreateSpace`,
  `syncGeneratePairing`, `syncJoinSpace`
- Cloud: `Synheart.ingestion`, upload queue and last-attempt getters
- Research: `lab*`, research-study helpers, and `SynheartInstance`
- Models: HSI state/axes, artifacts, baselines, scores, sessions, metrics,
  consent, sync, edge, and deletion models

Generate browsable API documentation from the source with:

```bash
dart doc
```

## Errors and diagnostics

Configuration validation throws `SynheartError` with a stable `code`.
Lifecycle preconditions commonly throw `StateError`; invalid arguments throw
`ArgumentError`; native sync failures throw `SyncNativeException`.

```dart
try {
  await Synheart.startSession();
} on SynheartError catch (error) {
  print('${error.code}: ${error.message}');
} on SyncNativeException catch (error) {
  if (error.retryable) {
    // Offer a retry.
  }
} on StateError catch (error) {
  print(error.message);
}
```

Runtime health:

```dart
final diagnostics = Synheart.runtimeDiagnostics();
print(diagnostics['isAvailable']);    // bool   — native bridge loaded
print(diagnostics['version']);        // String? — native runtime version
print(diagnostics['frameCount']);     // int    — HSI frames this session
print(diagnostics['missingSymbols']); // List<String>
```

`missingSymbols` lists optional native symbols the loaded runtime does not
export. Empty is the healthy state. Anything in it means the vendored runtime
predates this SDK release, so the features behind those symbols are disabled
and return `null`, `-1`, or an empty list rather than throwing. Each miss is
also logged once, naming the symbol. Update the runtime with:

```bash
synheart install runtime   # or: synheart sync
```

The list fills lazily — a symbol is probed the first time the feature that
needs it is used — so check it after exercising the features you depend on.

If `isAvailable` is false, confirm the runtime was installed for the active
platform, run a clean build, and inspect native linker output:

```bash
flutter clean
flutter pub get
synheart sync
flutter run
```

## Testing and example app

Run the package tests:

```bash
flutter test
```

Run static analysis:

```bash
flutter analyze
```

The application in `example/` demonstrates initialization, consent, module
control, HSI display, runtime diagnostics, behavior sessions, watch sessions,
and lab windows:

```bash
cd example
flutter pub get
flutter run
```

The example uses unsigned capabilities and placeholder service credentials for
development. Replace those settings before using it as a production template.

## Privacy and security

- Collection and delivery are consent-gated.
- State computation is on-device by default.
- Production cloud requests use a hardware-backed device identity.
- Cloud upload is independently consented.
- Personal mode does not persist raw biosignals.
- Research persistence requires explicit configuration and consent.
- Applications are responsible for accurate permission copy, data-retention
  controls, account deletion, and regional compliance.

## Support and contributing

File bugs and feature requests in
[GitHub Issues](https://github.com/synheart-ai/synheart-core-flutter/issues).
External pull requests are not currently accepted; see
[CONTRIBUTING.md](CONTRIBUTING.md). Report security issues using
[SECURITY.md](SECURITY.md), not a public issue.

Additional protocol documentation is available at
[docs.synheart.ai/synheart-core](https://docs.synheart.ai/synheart-core).

## License

Apache 2.0. See [LICENSE](LICENSE).

Copyright 2025-2026 Synheart AI Inc.
