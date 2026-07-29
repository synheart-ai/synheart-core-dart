# Synheart Core SDK example

This Flutter app demonstrates:

- SDK initialization and consent
- HSI JSON and typed state streams
- wear, phone, and behavior collection
- runtime and upload diagnostics
- behavior and watch sessions
- lab protocol windows

## Prerequisites

1. Flutter 3.32 or later
2. The Synheart CLI and an authenticated Synheart account
3. The native runtime installed in this example project
4. Platform permissions for the data sources being tested

From the repository root:

```bash
cd example
synheart install runtime
flutter pub get
flutter run
```

The CLI installs runtime artifacts under `example/synheart/vendor/runtime/`.
See the [main SDK guide](../README.md#platform-setup) for iOS and Android
permission requirements.

The app defaults to unsigned development capabilities and does not configure
cloud upload. For hosted consent or cloud testing, follow [SETUP.md](SETUP.md)
and provide your own deployment credentials.

## Code map

- `lib/main.dart` — application entry point
- `lib/providers/synheart_provider.dart` — SDK initialization and stream state
- `lib/screens/` — consent, HSI, session, behavior, and diagnostics screens
- `lib/widgets/` — reusable SDK-aware controls and viewers
- `canonical_example.dart` — compact lifecycle example

Do not copy the example's unsigned capability setting into production.
