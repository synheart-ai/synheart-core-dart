# Synheart Core SDK - Flutter

[![Version](https://img.shields.io/badge/version-0.0.1-blue.svg)](https://github.com/synheart-ai/synheart-core-dart)
[![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.22.0-blue.svg)](https://flutter.dev)
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
    enableWear: true,
    enablePhone: true,
    enableBehavior: true,
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

The SDK requires explicit user consent for data collection:

```dart
// Grant consent for specific data types
await Synheart.grantConsent('biosignals');
await Synheart.grantConsent('behavior');
await Synheart.grantConsent('phoneContext');

// Check consent status
bool hasConsent = await Synheart.hasConsent('biosignals');

// Revoke consent
await Synheart.revokeConsent('biosignals');

// Alternatively, update all consents at once
await Synheart.updateConsent(ConsentSnapshot(
  biosignals: true,
  behavior: true,
  motion: true,
  cloudUpload: false,  // User must explicitly opt-in
  syni: false,
));
```

## Prerequisites

### Wearable Data Collection

The Core SDK uses the [synheart_wear](https://pub.dev/packages/synheart_wear) package for wearable data collection. This package handles all device integrations (Apple Watch, Fitbit, Garmin, etc.) and provides a unified API.

### iOS - HealthKit Permissions

The `synheart_wear` package handles HealthKit permissions automatically. Add the following to your `Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>This app needs access to your health data to monitor your wellbeing</string>
<key>NSHealthUpdateUsageDescription</key>
<string>This app needs to update your health data</string>
```

### Android - Health Connect

The `synheart_wear` package handles Health Connect permissions automatically. Add permissions to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
<uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
```

### Supported Devices

The Core SDK supports all devices that [synheart_wear](https://pub.dev/packages/synheart_wear) supports.

## Privacy & Security

- All processing is **on-device** by default
- No raw biosignals leave the device without explicit consent
- Cloud sync uses **aggregated HSV** only
- HSI is strictly **non-medical**; no diagnoses or clinical labels

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

