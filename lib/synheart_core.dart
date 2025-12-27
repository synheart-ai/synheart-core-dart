/// Synheart Core SDK - Flutter
///
/// The Synheart Core SDK is the single, unified integration point for developers
/// who want to collect HSI-compatible data, process human state on-device, generate
/// focus/emotion signals, and integrate with Syni.
///
/// The SDK consists of 7 core modules:
/// - Capabilities Module - Feature gating
/// - Consent Module - User permission management
/// - Wear Module - Biosignal collection
/// - Phone Module - Device motion/context
/// - Behavior Module - User interaction patterns
/// - HSI Runtime - Signal fusion and state computation
/// - Cloud Connector - Secure HSI snapshot uploads
library synheart_core;

// Core SDK Entry Point (PRD-compliant Architecture)
export 'src/synheart.dart';

// Legacy HSI class (for backward compatibility - will be deprecated)
export 'src/hsi_new.dart' show HSI;

// Configuration
export 'src/config/synheart_config.dart';

// Data Models
export 'src/models/hsv.dart';
export 'src/models/emotion.dart';
export 'src/models/focus.dart';
export 'src/models/behavior.dart';
export 'src/models/context.dart';

// Module Base
export 'src/modules/base/synheart_module.dart';
export 'src/modules/base/module_manager.dart';

// Module Interfaces
export 'src/modules/interfaces/capability_provider.dart';
export 'src/modules/interfaces/consent_provider.dart';
export 'src/modules/interfaces/feature_providers.dart';

// Modules
export 'src/modules/capabilities/capability_module.dart';
export 'src/modules/capabilities/capability_token.dart';
export 'src/modules/consent/consent_module.dart';
export 'src/modules/wear/wear_module.dart';
export 'src/modules/phone/phone_module.dart';
export 'src/modules/behavior/behavior_module.dart';
export 'src/modules/hsi_runtime/hsi_runtime_module.dart';

// Services
export 'src/services/auth_service.dart';

// Legacy exports (for backward compatibility)
// These are kept for apps still using the old monolithic architecture
export 'src/core/state_engine.dart';
export 'src/core/processors.dart';
export 'src/core/data_sources.dart';
export 'src/heads/emotion_head.dart';
export 'src/heads/focus_head.dart';
// Note: ingestion.dart exports removed to avoid SleepStage conflict

