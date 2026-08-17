# Example app setup

The example runs **local-only by default** — no credentials, nothing leaves the
device. This guide covers that baseline and how to opt into cloud upload.

## Baseline: no credentials

```bash
synheart install runtime
synheart install syni     # required on iOS; pod install fails without it
flutter pub get
flutter run
```

The config the app builds is in `lib/sdk/synheart_controller.dart`
(`buildConfig()`), and the Setup screen prints it verbatim so you can copy it:

```dart
SynheartConfig(
  appId: 'ai.synheart.core.example',   // required
  subjectId: <persisted, stable>,      // required
  appVersion: '1.0.0',
  deviceId: <persisted>,
  mode: SynheartMode.personal,

  // Development only. Production gates capabilities on a verified consent token.
  allowUnsignedCapabilities: true,

  // Declaring a module config activates that feature.
  wearConfig: WearConfig(),
  phoneConfig: PhoneConfig(),
  behaviorConfig: BehaviorConfig(),

  // Required for the runtime consent-form flow — consentSubmitFormTyped needs a
  // non-empty deviceId and platform, or consent can never be written.
  consentConfig: ConsentConfig(
    deviceId: <persisted>,
    platform: 'flutter',
    userId: <subjectId>,
  ),
)
```

Two fields are non-negotiable:

- **`appId`** and **`subjectId`** are required. `validate()` rejects an empty
  value before any native work happens.
- **`subjectId` must be stable across restarts.** The runtime scopes storage,
  baselines, and device identity to it, so a value that changes per launch looks
  like a new person every time and baselines never mature. Passing `userId:` to
  `initialize()` does **not** populate it — set it on the config.

Override the app id at build time if you have one issued at
platform.synheart.ai:

```bash
flutter run --dart-define=SYNHEART_APP_ID=your-app-id
```

## Enabling cloud upload

Cloud requires a provisioned organization. Add both `deviceAuthConfig` and
`cloudConfig` to `buildConfig()`:

```dart
SynheartConfig(
  appId: 'your-app-id',
  subjectId: 'your-stable-user-id',

  // Hardware-backed device identity. Required — the runtime signs every ingest
  // request with it. Without this, uploads are rejected.
  deviceAuthConfig: const DeviceAuthConfig(
    authBaseUrl: 'https://api.synheart.ai',
    packageName: 'ai.synheart.core.example',
  ),

  cloudConfig: CloudConfig(
    subjectId: 'your-stable-user-id',
    instanceId: 'stable-installation-id',
    orgId: 'your-org-id',              // REQUIRED — see below
  ),

  consentConfig: ConsentConfig(
    deviceId: 'your-device-id',
    platform: 'flutter',
    userId: 'your-stable-user-id',
  ),
)
```

**`orgId` must be non-empty.** Cloud ingest is gated on it: with an empty
`orgId` the SDK disables ingest entirely rather than letting the native runtime
reject the whole configuration. You get a working local-only app and a log line
saying cloud stayed off — not an upload failure you have to trace.

Then grant cloud upload on the Consent screen. Submitting with cloud enabled
makes the runtime fetch the default profile and issue a consent token; the
response reports `synced` and `token`, and both must be true before uploads
flow.

> Never put an API key or signing secret in an app bundle. `CloudConfig.apiKey`
> and `ConsentConfig.appApiKey` are deprecated and are not forwarded to the
> runtime — it removed bundle-secret configuration as a security fix. Requests
> are signed with the device identity instead.

## Troubleshooting

**`ERR_NOT_CONFIGURED` on Initialize.** The message names the field and the fix.
The usual cause is a missing `appId` or `subjectId`, or passing `userId:` to
`initialize()` and expecting it to populate `config.subjectId`.

**`pod install` fails with `could not locate .../SyniRuntime.xcframework`.** Run
`synheart install syni`. Also confirm `ios/Podfile` sets `SYNHEART_APP_ROOT` —
without it the podspec walks up from the pod's own source directory, which
resolves into `~/.pub-cache` for pub.dev dependencies and never finds your app.

**Native runtime reports "missing" on the Runtime tab.** Run
`synheart install runtime`, then `flutter clean && flutter run`.

**Symbols listed under Native symbols.** The vendored runtime predates this SDK
release. The features behind those symbols return `null` / `-1` / empty rather
than throwing. Run `synheart install runtime` to update it.

**Session starts but no HSI.** Check the Signal sources card. HSI physiology is
built from heart rate and HRV, so with no wearable paired and no health-data
access, `arousal`, `stress`, and `sleep` stay empty by design. Focus and
capacity can still be computed from behavior and motion. Watch the
**carrying data** count, not **samples emitted** — the wear source emits an
empty sample every poll tick either way.

**Start session is disabled.** Grant biosignals, behavior, or phone context.
Cloud upload, vendor sync, and research do not make any sensor readable on their
own, so a session granted only those would collect nothing — the SDK rejects it.

**No heart rate on iOS.** HealthKit needs the capability enabled in Xcode, which
requires a paid Apple developer account. This example ships without it.

## Security notes

- Never commit credentials. Pass them with `--dart-define` or a
  `--dart-define-from-file` JSON.
- `allowUnsignedCapabilities: true` is development-only. It disables the
  capability lattice; production drives it from a verified consent token.
- The Runtime tab's **Wipe local data** clears the runtime SQLite store, the SRM
  snapshot, and cached consent records for the current subject.
