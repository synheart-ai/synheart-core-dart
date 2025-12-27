# Synheart Core Dart SDK - Architecture

This document describes the architecture of the Synheart Core SDK Dart/Flutter implementation, aligned with the [Product Requirements Document (PRD)](https://github.com/synheart-ai/synheart-core/blob/main/docs/PRD.md).

## Overview

The Synheart Core SDK implements a strict separation between:

1. **HSI Runtime** - State representation (axes, indices, embeddings)
2. **Interpretation Modules** - Optional, explicit modules (Focus, Emotion)
3. **Application Logic** - Developer code consuming HSI/interpretations

> **Core Principle:** HSI represents human state. Interpretation is downstream and optional.

## Architecture Layers

### 1. Core Modules (`lib/src/modules/`)

#### Capabilities Module
- Enforces feature access based on app tier (Core/Extended/Research)
- Validates capability tokens from Synheart Platform
- Gates module features at runtime

#### Consent Module
- Manages user permissions for data collection
- Enforces consent boundaries
- Emits consent change events

#### Wear Module
- Collects biosignals from wearables (via `synheart_wear`)
- Provides derived signals only (HR, HRV, sleep, motion)
- No raw ECG/PPG externally

#### Phone Module
- Collects device motion and screen state
- Provides coarse app context (hashed)
- No content or identifiers

#### Behavior Module
- Collects interaction patterns (taps, scrolls, cadence)
- Provides timing patterns only
- No content

#### HSI Runtime Module
- Fuses signals from Wear, Phone, Behavior
- Computes state axes and indices
- Generates 64D state embeddings
- **IMPORTANT: Does NOT run interpretation modules**

#### Cloud Connector Module
- Securely uploads HSI snapshots (with consent)
- HMAC-based authentication
- Tenant-isolated routing

### 2. Optional Interpretation Modules (`lib/src/heads/`)

#### Emotion Head
- **Optional** - Requires explicit `enableEmotion()` call
- Subscribes to HSI stream
- Produces emotion estimates (stress, calm, etc.)
- Model-specific, versioned

#### Focus Head
- **Optional** - Requires explicit `enableFocus()` call
- Subscribes to HSI stream
- Produces focus estimates (score, cognitive load, etc.)
- Model-specific, versioned

### 3. Main Entry Point (`lib/src/synheart.dart`)

The `Synheart` class orchestrates all modules and provides the public API:

```dart
class Synheart {
  // Initialization
  static Future<void> initialize({...});

  // HSI stream (core state representation)
  static Stream<HumanStateVector> get onHSIUpdate;

  // Optional interpretation streams
  static Stream<EmotionState> get onEmotionUpdate;
  static Stream<FocusState> get onFocusUpdate;

  // Enable optional modules
  static Future<void> enableFocus();
  static Future<void> enableEmotion();
  static Future<void> enableCloud();

  // Consent management
  static Future<void> grantConsent(String type);
  static Future<void> revokeConsent(String type);
  static Future<bool> hasConsent(String type);
}
```

## Data Flow

```
Raw Signals
    ↓
Wear, Phone, Behavior Modules
    ↓
Channel Collector
    ↓
HSI Runtime (Fusion Engine)
    ↓
HSI Stream (state representation)
    ↓
Applications (via onHSIUpdate)

Optional:
HSI Stream
    ↓
Emotion Head → onEmotionUpdate
    ↓
Focus Head → onFocusUpdate
```

## Separation of Concerns

### What HSI Runtime Outputs

**HSI (State Representation):**
- State axes: affect, engagement, activity, context
- State indices: arousalIndex, engagementStability, etc.
- 64D state embedding
- Time window metadata

**HSI does NOT include:**
- Emotion labels or scores
- Focus estimates
- Cognitive assessments
- Semantic interpretations

### What Interpretation Modules Output

**Emotion Module (Optional):**
- Stress index
- Calm level
- Valence
- Arousal

**Focus Module (Optional):**
- Focus score
- Cognitive load
- Clarity
- Distraction

## Privacy & Security

- All processing is on-device by default
- No raw biosignals exposed externally
- Consent-gated data collection
- Capability-based feature access
- Cloud sync only for derived HSI snapshots

## Module Dependencies

```
Synheart
  ↓
├─ Capability Module (no dependencies)
├─ Consent Module (no dependencies)
├─ Wear Module → [Capability, Consent]
├─ Phone Module → [Capability, Consent]
├─ Behavior Module → [Capability, Consent]
├─ HSI Runtime → [Wear, Phone, Behavior]
├─ Emotion Head (optional) → [HSI Runtime]
└─ Focus Head (optional) → [HSI Runtime]
```

## Integration Points

### HSI Runtime → Interpretation Modules

Interpretation modules consume HSI via stream subscription:

```dart
// In Synheart class
_hsiRuntimeModule!.hsiStream.listen(
  (hsi) => _hsiStream.add(hsi),
);

// When enableFocus() is called:
_focusHead!.start(_hsiStream.stream);
```

### HSI Runtime → Applications

Applications consume HSI directly:

```dart
Synheart.onHSIUpdate.listen((hsi) {
  print('Arousal: ${hsi.affect.arousalIndex}');
  print('Engagement: ${hsi.engagement.engagementStability}');
});
```

## Implementation Notes

### Current State (v1.0)

- ✅ Core modules implemented
- ✅ HSI Runtime (no interpretation)
- ✅ Consent management
- ✅ Capability enforcement
- ✅ Optional Focus/Emotion modules
- ✅ Separate streams (HSI, Focus, Emotion)
- ⚠️ Mock data sources (for development)
- ⚠️ Placeholder fusion model
- ❌ Cloud Connector (not yet implemented)
- ❌ Syni Hooks (not yet implemented)

### Next Steps

1. Connect real data sources (synheart_wear, etc.)
2. Implement production fusion model
3. Add Cloud Connector module
4. Add Syni Hooks module
5. Performance optimization
6. Testing and validation

## Related Documentation

- [PRD](https://github.com/synheart-ai/synheart-core/blob/main/docs/PRD.md)
- [HSI Specification](https://github.com/synheart-ai/synheart-core/blob/main/docs/HSI_SPECIFICATION.md)
- [Capability System](https://github.com/synheart-ai/synheart-core/blob/main/docs/CAPABILITY_SYSTEM.md)
- [Consent System](https://github.com/synheart-ai/synheart-core/blob/main/docs/CONSENT_SYSTEM.md)
- [Cloud Protocol](https://github.com/synheart-ai/synheart-core/blob/main/docs/CLOUD_PROTOCOL.md)

---

**Last Updated:** 2025-12-25
**Version:** 1.0.0
**Maintained by:** Synheart AI
