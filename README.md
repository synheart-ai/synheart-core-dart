# Human State Interface (HSI) - Flutter

**HSI** is Synheart's unified, on-device pipeline for understanding human internal state in real time.

## Overview

HSI:
- Ingests **biosignals**, **behavioral signals**, and **context signals**
- Cleans, normalizes, and fuses them into a **base state representation**
- Exposes this as a **Human State Vector (HSV)** stream
- Feeds higher-level models:
  - **Synheart Emotion (Emotion Engine)**
  - **Synheart Focus (Focus Engine)**
  - **Syni (LLM layer)**

**Key principle:**
> HSI = how we *measure and represent*  
> Emotion & Focus = models that sit *on top*

## Architecture

The stack is structured in **three model layers** plus the LLM layer:

1. **HSI Core (State Engine)** - Ingestion, processing, fusion
2. **Emotion Engine (Synheart Emotion)** - Model head for emotion detection
3. **Focus Engine (Synheart Focus)** - Model head for focus detection
4. **Syni LLM Layer** - Consumes final HSV for human-aware AI

## Usage

### Basic Usage (Mock Data)

HSI works out of the box with mock biosignal data for testing and development:

```dart
import 'package:hsi_flutter/hsi_flutter.dart';

// Initialize HSI with mock data
final hsi = HSI.shared;
await hsi.configure(appKey: 'YOUR_APP_KEY');
await hsi.start();

// Listen to HSV updates
hsi.onStateUpdate.listen((hsv) {
  print('Stress: ${hsv.emotion.stress}');
  print('Focus: ${hsv.focus.score}');
  print('Heart Rate: ${hsv.meta.hsiEmbedding[0]}');
});

// Optional: Enable cloud sync (aggregated HSV only)
await hsi.enableCloudSync();
```

### Advanced Usage (Real Wearable Data)

To integrate with real wearable devices, add the optional synheart_wear package:

**1. Add synheart_wear to your pubspec.yaml:**

```yaml
dependencies:
  hsi_flutter:
    path: ../hsi-flutter
  synheart_wear: ^0.1.2  # Optional - for real wearable data
```

**2. Create a custom data source adapter:**

```dart
import 'package:hsi_flutter/hsi_flutter.dart';
import 'package:synheart_wear/synheart_wear.dart' as wear;

// Create adapter (see lib/src/integrations/synheart_wear_adapter.dart for full implementation)
class SynheartWearDataSource implements BiosignalDataSource {
  // Implementation bridges synheart_wear to HSI...
}

// Configure HSI with real wearable data
final wearAdapter = SynheartWearDataSource();
await hsi.configure(
  appKey: 'YOUR_APP_KEY',
  biosignalSource: wearAdapter,  // Real wearable data
);
await hsi.start();
```

### Custom Data Sources

You can also implement your own data sources:

```dart
class MyCustomBiosignalSource implements BiosignalDataSource {
  @override
  Future<void> initialize() async {
    // Your initialization logic
  }

  @override
  Stream<Biosignals> get biosignalStream {
    // Your custom biosignal stream
  }

  @override
  Future<void> dispose() async {
    // Cleanup
  }
}

await hsi.configure(
  appKey: 'YOUR_APP_KEY',
  biosignalSource: MyCustomBiosignalSource(),
);
```

## Prerequisites

### iOS - HealthKit Permissions

Add the following to your `Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>This app needs access to your health data to monitor your wellbeing</string>
<key>NSHealthUpdateUsageDescription</key>
<string>This app needs to update your health data</string>
```

### Android - Health Connect

Add permissions to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
<uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
```

## Privacy & Security

- All processing is **on-device** by default
- No raw biosignals leave the device without explicit consent
- Cloud sync uses **aggregated HSV** only
- HSI is strictly **non-medical**; no diagnoses or clinical labels

## License

Proprietary - Synheart

## Author

Israel Goytom

