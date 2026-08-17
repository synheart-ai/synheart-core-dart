# PR #73 — Required Fixes

## 1. Breaking changes are published as a patch release

### Issue

The package version is changing from `0.10.1` to `0.10.2`, but the PR also changes or removes existing public APIs.

For example, `CoreRuntimeBridge.flushUploads()` changes from returning a result immediately to returning a `Future`:

```dart
// Before
final result = bridge.flushUploads();

// After
final result = await bridge.flushUploads();
```

The PR also removes public types such as `HsiWindowArtifact` and `TombstoneArtifact`.

An app using `synheart_core: ^0.10.1` can automatically receive `0.10.2`. If it uses one of these APIs, its next dependency update may stop compiling.

### Fix

Choose one of these options:

1. Release these breaking changes as `0.11.0`.
2. Keep version `0.10.2`, but preserve the old APIs with compatibility wrappers and deprecate them for removal in `0.11.0`.

## 2. Android may receive every HSI update twice

### Issue

When `pushWearHr()` or `pushVendorHrv()` completes an HSI window, Dart now delivers the result directly to the HSI stream:

```dart
final hsi = runtime.ingestBatch(batchJson, nowMs);
if (hsi != null) {
  shared._deliverHsiWindow(hsi);
}
```

The native runtime also broadcasts the same completed window through the registered HSI callback. On Android, both paths can run for the same HSI window.

This can cause:

- `onHSIUpdate` and `onStateUpdate` to fire twice.
- Session buffers to store the same window twice.
- UI counters and analytics to be doubled.
- Behavior processing to run twice for one window.

### Fix

Use only one delivery path on platforms where the native callback works. If the direct Dart delivery is required as an iOS fallback, apply it only on iOS.

Another safe option is to deduplicate before delivery using the HSI ID:

```dart
if (hsiId != lastDeliveredHsiId) {
  lastDeliveredHsiId = hsiId;
  _deliverHsiWindow(hsiJson);
}
```

Add a test that sends one completed window and verifies that each public HSI stream emits exactly once.

## 3. A session can start without collection consent

### Issue

The rewritten example enables the Start button even when the user has not granted a collection permission.

It also uses `hasAnyGrant`, which includes permissions such as cloud upload, vendor sync, research, and Syni. Those permissions do not provide sensor data by themselves.

For example, a user could grant only cloud upload and start a session. The UI may show `collecting`, but biosignal, behavior, and phone-context modules have no permission to collect anything.

### Fix

Create a check that includes only actual collection permissions:

```dart
bool get hasCollectionConsent {
  final consent = consentState;
  return consent?.biosignals == true ||
      consent?.behavior == true ||
      consent?.phoneContext == true;
}
```

Disable the Start button when that check is false:

```dart
FilledButton.icon(
  onPressed: controller.hasCollectionConsent
      ? controller.startSession
      : null,
  icon: const Icon(Icons.play_arrow),
  label: const Text('Start session'),
)
```

The SDK's `startSession()` method should also perform the same validation. UI validation alone is not enough because other applications can call the SDK directly.

## 4. The example documentation does not match the rewritten example

### Issue

The example documentation still:

- References deleted files such as `lib/providers/synheart_provider.dart` and `canonical_example.dart`.
- Recommends deprecated bundle secrets such as `appApiKey`.
- Shows a `CloudConfig` without `orgId`, even though this PR disables cloud ingest when `orgId` is empty.
- Tells iOS developers to install only the core runtime, although the Syni runtime is also required for `pod install`.

A developer following these instructions will either be unable to find the referenced files or will configure an app whose cloud upload remains disabled.

### Fix

Update `example/README.md` and `example/SETUP.md` to use the new files and configuration flow.

The cloud example should include the required organization and device-auth configuration:

```dart
SynheartConfig(
  appId: 'com.example.my_app',
  subjectId: 'user-123',
  deviceAuthConfig: const DeviceAuthConfig(
    authBaseUrl: 'https://api.synheart.ai',
    packageName: 'com.example.my_app',
  ),
  cloudConfig: CloudConfig(
    subjectId: 'user-123',
    instanceId: 'stable-installation-id',
    orgId: 'organization-id',
  ),
)
```

The iOS setup commands should include both native runtimes:

```bash
synheart install runtime
synheart install syni
flutter pub get
cd ios && pod install
```

Remove instructions for deleted files and deprecated API-key fields, then verify every documented command and code example against a clean checkout.
