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

## Supplying credentials

Credentials issued at platform.synheart.ai arrive as a small JSON file:

```json
{ "org_id": "org_…", "tenant_id": "ten_…", "project_id": "prj_…", "app_id": "app_…" }
```

Copy the template and fill in the values you were issued:

```bash
cp env/defines.example.json env/defines.dev.json
```

```jsonc
{
  "SYNHEART_BASE_URL":     "https://api.synheart.io",  // dev endpoints are .io
  "SYNHEART_AUTH_URL":     "https://api.synheart.io",

  "SYNHEART_APP_ID":       "app_…",                    // from app_id
  "SYNHEART_ORG_ID":       "org_…",                    // from org_id
  "SYNHEART_PACKAGE_NAME": "ai.synheart.core.example"
}
```

**Set both URLs.** They are not redundant. `SYNHEART_AUTH_URL` only reaches
`DeviceAuthConfig`, so on its own it points attestation at dev while consent and
ingest keep resolving through `ApiEndpoints.defaultBaseUrl` — which ships as
`https://api.synheart.ai`, production. `SYNHEART_BASE_URL` is what moves that
default, and every per-service URL falls back to it. Setting one and not the
other splits a single run across two environments.

Then build with it:

```bash
flutter run --dart-define-from-file=env/defines.dev.json
```

`env/*.json` is gitignored apart from the template, so a populated file stays
on your machine. This mirrors how the other Synheart apps are built.

Two notes on the credential file:

- **`tenant_id` and `project_id` are not used by this SDK.** The runtime config
  carries `app_id` and `org_id` and nothing else, and `CloudConfig` has no field
  for either. The template lists them so a credential file can be transcribed
  whole, but setting them changes no behavior here.
- **`SYNHEART_APP_ID` and `SYNHEART_PACKAGE_NAME` are different things.**
  `app_id` is the platform-issued `app_…` identifier that an ingest scope
  resolves from. The package name is the real installed bundle id, which Play
  Integrity and App Attest verify against. Passing the `app_…` value as the
  package name fails attestation.

Both default to `ai.synheart.core.example`, so the app still runs with no
credentials at all.

## Enabling device attestation and cloud upload

These are **two independent opt-ins**, and attestation does not need an org id.
With individual flags rather than a defines file:

```bash
# Attestation only — enough to exercise device registration.
flutter run \
  --dart-define=SYNHEART_BASE_URL=https://api.synheart.io \
  --dart-define=SYNHEART_AUTH_URL=https://api.synheart.io

# Attestation + HSI upload.
flutter run \
  --dart-define=SYNHEART_BASE_URL=https://api.synheart.io \
  --dart-define=SYNHEART_AUTH_URL=https://api.synheart.io \
  --dart-define=SYNHEART_ORG_ID=your-org-id
```

`SYNHEART_AUTH_URL` adds a `DeviceAuthConfig`, and that is all attestation
needs — every registration trigger in the SDK keys off `DeviceAuthConfig` and
none of them consults the cloud config.

`SYNHEART_ORG_ID` adds a `CloudConfig` on top, which is what enables HSI upload.
Cloud ingest stays disabled without a non-empty org id, because the runtime
rejects an entire configuration whose ingest is enabled without one.

Upload also depends on attestation: the runtime signs every ingest request with
the device key, so an org id alone does nothing.

### When attestation actually runs

**Registration is triggered by cloud-upload consent, not by `initialize()`.**
Configuring `DeviceAuthConfig` only makes it *possible*. The flow starts at
whichever of these happens first:

| Stage | Trigger |
| --- | --- |
| `initialize()` | only if cloud consent was already granted in a previous launch |
| `grantConsent(cloudUpload: true, …)` | starts registration in the background |
| `consentSubmitFormTyped(…allowCloud: true)` | same, via the runtime consent form |
| `startSession()` | preflight; skipped entirely when cloud consent is off |
| `ensureDeviceAuthRegistered()` | explicit and idempotent |
| `reregisterDeviceAuth()` | forced re-attestation |

The two consent paths deliberately **do not await** registration. The flow binds
the platform attestation service, mints a key, and performs an HTTPS round-trip;
awaiting it on a consent handler can block long enough to trip the OS
watchdog. Poll `Synheart.coreDeviceAuthStatus()` instead of waiting on a Future.

### Testing it

1. Launch with `--dart-define=SYNHEART_AUTH_URL=...` (an org id is not needed
   to test attestation).
2. **Setup** tab → Initialize SDK. The *Device attestation* card shows
   `pending`, with `status` from the runtime.
3. **Consent** tab → enable **Cloud upload** → Submit. This is the moment
   registration begins.
4. Back on **Setup**, the card moves to `registered` and shows the device id.

*Register now* forces an attempt without changing consent (idempotent — it
no-ops when already registered). *Re-attest* bypasses locally restored state,
which is what you want when the server has lost or revoked the device record.

### What it needs to succeed

Registration throws a distinct `StateError` for each missing precondition:

- the native runtime bridge must be loaded,
- the runtime must export the `synheart_core_sdk_*` symbols,
- crypto callbacks must be attached — which requires the `synheart_auth` plugin
  registered and its native crypto library bundled.

On a device that cannot attest, the runtime reports
`ERR_DEVICE_AUTH: attestation unavailable` and stays local-only rather than
failing the session. That is expected on simulators, on rooted or jailbroken
devices, and on builds without the platform attestation entitlement.

> Never put an API key or signing secret in an app bundle. `CloudConfig.apiKey`
> and `ConsentConfig.appApiKey` are deprecated and are not forwarded to the
> runtime — requests are signed with the attested device identity instead.

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

**Attestation stays `pending`.** Check the *Device attestation* card's
`ABI available` row first — false means the loaded runtime does not export the
device-auth symbols, so run `synheart install runtime`. If it is true and status
never advances, the device cannot attest (simulator, rooted/jailbroken, or a
build without the platform attestation entitlement); the SDK stays local-only by
design rather than failing the session.

## Security notes

- Never commit credentials. Put them in `env/defines.dev.json`, which is
  gitignored, and pass it with `--dart-define-from-file`. Only
  `env/defines.example.json` — placeholders — is checked in.
- `allowUnsignedCapabilities: true` is development-only. It disables the
  capability lattice; production drives it from a verified consent token.
- The Runtime tab's **Wipe local data** clears the runtime SQLite store, the SRM
  snapshot, and cached consent records for the current subject.
