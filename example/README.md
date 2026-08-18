# Synheart Core SDK example

A small reference app that walks the SDK lifecycle in the order a host app
performs it. Every SDK call lives in one file, so the integration reads
top-to-bottom rather than being scattered across screens.

**It runs with no credentials.** No `CloudConfig`, no `DeviceAuthConfig` —
collection, HSI computation, consent, and local storage all work offline.

Cloud upload and device attestation are opt-in via two dart-defines; the Setup
tab then shows attestation progress live. Note that registration is triggered by
**cloud-upload consent**, not by `initialize()`. See [SETUP.md](SETUP.md).

## Prerequisites

Flutter `>=3.32.0`, and the native runtimes installed into this directory:

```bash
# Install the CLI once.
curl -fsSL https://synheart.sh/install | sh
synheart login

# Run from this directory (example/).
synheart install runtime
synheart install syni     # required on iOS — see below
```

`synheart install syni` is not optional on iOS. `synheart_core` depends on the
`syni` package, whose iOS pod links its own vendored framework and **fails
`pod install`** without it, even though this example never uses Syni.

Then:

```bash
flutter pub get
flutter run
```

### iOS

`ios/Podfile` sets `SYNHEART_APP_ROOT`, which the Synheart podspecs need to
locate this app's vendored frameworks. Without it `pod install` either fails or
silently links a different project's runtime. Keep it when copying this Podfile.

HealthKit is **not** enabled here — that capability needs a paid Apple developer
account. Without it the wear module cannot start, so heart rate and HRV are
unavailable and the physiological HSI axes stay empty. Behavior and phone
context still feed the runtime, and the Session screen reports exactly which
sources are live.

### Android

Health Connect permissions are declared in
`android/app/src/main/AndroidManifest.xml`. Grant them at first launch to let
the wear module read heart rate. With no wearable paired, Health Connect has no
data to give and the app says so rather than inventing values.

## Code map

```
lib/
  main.dart                     app shell, tab navigation
  sdk/
    synheart_controller.dart    THE ONLY FILE THAT CALLS THE SDK
  screens/
    setup_screen.dart           config + initialize
    consent_screen.dart         runtime editable-form consent flow
    session_screen.dart         start/stop, live HSI, signal sources
    diagnostics_screen.dart     runtime version, native symbol audit
  widgets/ui.dart               shared building blocks
example.dart                    minimal standalone snippet
```

Start with `sdk/synheart_controller.dart`. No screen imports
`package:synheart_core` — they read state from the controller and call its
methods, so the whole integration is one readable file.

## What it demonstrates

- **The lifecycle** — initialize → consent → session → diagnostics, in order,
  with each step gated on the previous one.
- **Canonical consent** — `consentGetEditableFormTyped` →
  `consentSubmitFormTyped` → `consentEffectiveStateTyped`. The runtime persists
  the choice offline-first and reconciles with the cloud profile when cloud is
  on. It intersects the submitted form against that profile, so asking for a
  channel does not guarantee getting it — gate features on the **effective
  state**, never on the form you submitted.
- **Honest signal reporting** — the app never fabricates biosignals. Pushed
  samples feed the runtime's longitudinal baselines, so synthetic beats would
  corrupt real reference ranges on whatever device ran the demo. It shows which
  sources are attached, which actually feed the runtime, and says plainly when
  none is.
- **Runtime diagnostics** — `runtimeDiagnostics(probeAll: true)` reports which
  optional native symbols the loaded runtime exports. Optional bindings resolve
  lazily, so a screen that just reads `missingSymbols` looks healthy while
  having checked nothing.
