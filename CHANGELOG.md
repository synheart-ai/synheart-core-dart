# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1] - 2025-12-26

### Dependencies
- All dependencies now using pub.dev hosted versions:
  - `synheart_emotion: ^0.2.2`
  - `synheart_focus: ^0.0.1`
  - `synheart_wear: ^0.1.2`

### Added
- Initial release of Synheart Core SDK
- HSI Runtime module for signal fusion and state computation
- Wear module for biosignal collection from wearables (HR, HRV, motion)
- Phone module for device motion and context signals
- Behavior module for digital interaction pattern tracking
- Consent module for user permission management
- Cloud Connector for secure HSI snapshot uploads
- Capabilities module for feature gating (core/extended/research)
- Optional interpretation modules: Focus Head and Emotion Head
- Comprehensive HSV (Human State Vector) data model
- Modular architecture with pluggable modules
- On-device processing with privacy-first design

### Changed
- Renamed FusionEngineV2 to FusionEngine (removed misleading version suffix)

### Technical Details
- Minimum SDK: Dart 3.8.0, Flutter 3.22.0
- Dependencies: synheart_wear ^0.1.2, rxdart ^0.28.0
- Architecture: Stream-based reactive module system
- Platform support: iOS, Android

## [Unreleased]

### Added
- **HSI 1.0 Export Capability**: synheart-core-dart can now export HSI 1.0 canonical payloads
  - New `HSI10Payload` class matching canonical HSI 1.0 schema
  - `toHSI10()` extension method on `HumanStateVector`
  - Converts internal HSV representation to external HSI 1.0 contract format
  - Full JSON Schema compliance with `/hsi/schema/hsi-1.0.schema.json`
  - Producer metadata (name, version, instance_id)
  - Window-based time scoping (micro/short/medium/long)
  - Privacy-compliant assertions (no PII, derived metrics only)
  - Comprehensive test suite (16 tests) validating HSI 1.0 compliance


- **HSV State Axes**: Implemented core HSV (Human State Vector) state representation axes
  - Added `AffectAxis` (arousalIndex, valenceStability)
  - Added `EngagementAxis` (engagementStability, interactionCadence)
  - Added `ActivityAxis` (motionIndex, postureStability)
  - Added `ContextAxis` (screenActiveRatio, sessionFragmentation)
  - Added `StateEmbedding` class for 64D dense vector representation
  - Added `HSIAxes` container class grouping all state axes

- **HSV Computation in FusionEngine**: Enhanced fusion engine to compute HSV state axes
  - Computes arousal index from HR and HRV (60% HR, 40% HRV inverse)
  - Computes valence stability from HRV SDNN
  - Computes engagement stability and interaction cadence from behavioral patterns
  - Computes motion index from wear and phone sensors
  - Computes screen active ratio and session fragmentation from context
  - All indices normalized to [0.0, 1.0] range with null for missing signals

- **Interpretation Modules**: Both EmotionHead and FocusHead properly integrated
  - EmotionHead uses EmotionEngine from synheart-emotion package
  - FocusHead uses FocusEngine from synheart-focus package
  - Both consume HSI state representation and produce semantic interpretations

- Comprehensive test suite for EmotionHead module
  - Tests for EmotionEngine initialization
  - Tests for push/consumeReady API pattern
  - Tests for EmotionResult to EmotionState mapping
  - Tests for graceful handling of invalid/missing data
  - Tests for lifecycle management (start, stop, dispose)

### Changed
- **EmotionHead**: Refactored to use `EmotionEngine` from synheart-emotion package instead of direct ONNX model access
  - Now uses `EmotionEngine.fromPretrained()` for initialization
  - Changed from async `predictAsync()` to synchronous `push/consumeReady` pattern
  - Implements proper time-series emotion detection with ring buffer (10s window, 1s step)
  - Synthesizes RR intervals from derived HRV features (temporary workaround until Phase 2 adds raw RR data to HSV)
  - Improved cleanup logic to call `engine.clear()` on dispose

- **MetaState**: Updated to include HSI state axes and proper embedding structure
  - Replaced `hsiEmbedding` List<double> with `StateEmbedding` object
  - Added `HSIAxes axes` field containing all state representation axes
  - Maintains backward compatibility through factory constructors

- **HumanStateVector (HSV)**: Enhanced to support full HSV state representation
  - Includes state axes (affect, engagement, activity, context)
  - Includes 64D state embedding
  - Supports window types (micro, short, medium, long)
  - Provides structured, interpretation-agnostic state representation
  - Can export to HSI 1.0 canonical format via `toHSI10()` method

### Architecture
- **Hybrid Approach**: HSV (language-agnostic model) + HSI 1.0 (cross-platform format)
  - **HSV (Human State Vector)**: Language-agnostic state model implemented in Dart classes
    - Same conceptual model across all platforms (Dart, Kotlin, Swift)
    - Fast, type-safe on-device processing
  - **HSI 1.0 (Human State Interface)**: Cross-platform JSON wire format
    - Platform-agnostic canonical format for interoperability
  - Best of both worlds: native performance, cross-platform compliance

### Planned
- Implement actual ML embedding model (currently placeholder)
- Improve documentation and examples
- Performance optimizations
- Additional wearable device support
- Phase 2: Add raw RR intervals to HSV metadata for full EmotionEngine integration

[0.0.1]: https://github.com/synheart-ai/synheart-core-dart/releases/tag/v0.0.1
