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

### Planned
- Implement actual ML embedding model (currently placeholder)
- Add comprehensive test suite
- Improve documentation and examples
- Performance optimizations
- Additional wearable device support

[0.0.1]: https://github.com/synheart-ai/synheart-core-dart/releases/tag/v0.0.1
