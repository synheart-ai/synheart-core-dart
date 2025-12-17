# Synheart Core SDK - Flutter

**Synheart Core SDK** is the single, unified integration point for developers who want to collect HSI-compatible data, process human state on-device, generate focus/emotion signals, and integrate with Syni.

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

The Core SDK consists of **7 core modules** working together:

1. **Capabilities Module** - Feature gating (core/extended/research)
2. **Consent Module** - User permission management
3. **Wear Module** - Biosignal collection from wearables
4. **Phone Module** - Device motion and context signals
5. **Behavior Module** - User-device interaction patterns
6. **HSI Runtime** - Signal fusion and state computation (produces Human State Vector)
7. **Cloud Connector** - Secure HSI snapshot uploads

The **HSI Runtime** module:
- Ingests signals from Wear, Phone, and Behavior modules
- Fuses them into a unified **Human State Vector (HSV)**
- Feeds higher-level models (Emotion Engine, Focus Engine)
- Powers Syni's LLM layer for human-aware AI

## Usage

### Basic Usage

The Core SDK works out of the box with mock data for testing and development:

```dart
import 'package:hsi_flutter/hsi_flutter.dart';

// Initialize the Core SDK
// Note: Class is named HSI for backward compatibility, but represents the full Core SDK
final synheart = HSI.shared;
await synheart.configure(
  appKey: 'YOUR_APP_KEY',
  userId: 'user123',
);

// Start the SDK
await synheart.start();

// Listen to HSI state updates
synheart.onStateUpdate.listen((state) {
  print('Focus Score: ${state.focus.score}');
  print('Stress Level: ${state.emotion.stress}');
  print('Behavior Distraction: ${state.behavior.distractionScore}');
});

// Optional: Enable cloud sync (requires consent)
await synheart.enableCloudUploads();
```

### Module Configuration

Configure which modules to enable:

```dart
final config = SynheartConfig(
  enableWearModule: true,
  enablePhoneModule: true,
  enableBehaviorModule: true,
  enableCloudSync: false,  // Enable after user consent
  logLevel: LogLevel.info,
);

final synheart = HSI.shared;
await synheart.configure(
  appKey: 'YOUR_APP_KEY',
  userId: 'user123',
  config: config,
);
```

### Consent Management

The SDK requires user consent for data collection:

```dart
// Request consent from user
final consent = ConsentSnapshot(
  biosignals: true,
  behavior: true,
  motion: true,
  cloudUpload: false,  // User must explicitly opt-in
  syni: false,
);

final synheart = HSI.shared;
await synheart.updateConsent(consent);
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

The Core SDK supports all devices that [synheart_wear](https://pub.dev/packages/synheart_wear) supports:
- ✅ **Apple Watch** (via HealthKit)
- 🔄 **Fitbit** (via REST API - In Development)
- 📋 **Garmin** (Planned)
- 📋 **Whoop** (Planned)
- 📋 **Samsung Watch** (Planned)

## Privacy & Security

- All processing is **on-device** by default
- No raw biosignals leave the device without explicit consent
- Cloud sync uses **aggregated HSV** only
- HSI is strictly **non-medical**; no diagnoses or clinical labels

## 📚 Documentation

- **[Product Requirements](docs/core-sdk-prd.md)** - Complete PRD for Synheart Core SDK
- **[Module Specifications](docs/core-sdk-module.md)** - Technical module specifications
- **[Internal Architecture](docs/internal-module.md)** - Internal module documentation
- **[Implementation Roadmap](docs/implementation-roadmap.md)** - Roadmap to v1.0
- **[Native Implementations](docs/NATIVE_IMPLEMENTATIONS.md)** - iOS & Android implementations
- **[Native Mirroring Status](docs/native-module-mirror-status.md)** - Cross-platform status
- **[Synheart Wear Integration](docs/SYNHEART_WEAR_INTEGRATION.md)** - Wearable data integration

## 👥 Contributing

We welcome contributions! Here's how to get started:

1. **Read the guides:**
   - [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
   - [DEVELOPMENT.md](DEVELOPMENT.md) - Development setup guide
   - [TASKS.md](TASKS.md) - Available tasks to work on

2. **Pick a task:**
   - Check [TASKS.md](TASKS.md) for available tasks
   - Look for tasks marked `[ ]` (available)
   - Comment on the task or create an issue to claim it

3. **Make your changes:**
   - Follow our [coding standards](CONTRIBUTING.md#coding-standards)
   - Add tests for your changes
   - Update documentation

4. **Submit a Pull Request:**
   - Follow the [PR checklist](CONTRIBUTING.md#pull-request-checklist)
   - Reference the task or issue you're addressing

## 🎯 Project Status

**Current Version:** Pre-v1.0 (Development)

**Target Release:** v1.0 (March 2025)

**Progress:** See [TASKS.md](TASKS.md) for current task status

## 📋 Module Overview

The Synheart Core SDK consists of 7 core modules:

1. **Capabilities Module** - Feature gating (core/extended/research)
2. **Consent Module** - User permission management
3. **Wear Module** - Biosignal collection from wearables
4. **Phone Module** - Device motion and context signals
5. **Behavior Module** - User-device interaction patterns
6. **HSI Runtime** - Signal fusion and state computation
7. **Cloud Connector** - Secure HSI snapshot uploads

See [docs/core-sdk-module.md](docs/core-sdk-module.md) for detailed specifications.

## 🔒 Privacy & Security

- All processing is **on-device** by default
- No raw biosignals leave the device without explicit consent
- Cloud sync uses **aggregated HSV** only
- HSI is strictly **non-medical**; no diagnoses or clinical labels
- Zero raw data policy enforced throughout

## 📄 License

Proprietary - Synheart

## 👤 Author

Israel Goytom



## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.
