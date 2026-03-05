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

// Configuration
export 'src/config/api_endpoints.dart';
export 'src/config/synheart_config.dart';
export 'src/config/synheart_feature.dart';
export 'src/config/platform_ingest_config.dart';

// Data Models
export 'src/models/behavior.dart';
export 'src/models/context.dart';
export 'src/models/hsi_axes.dart';
export 'src/models/hsi_export.dart';
export 'src/models/behavior_session_results.dart';
export 'src/models/preprocessed_window.dart';

// Module Base
export 'src/modules/base/synheart_module.dart';
export 'src/modules/base/module_manager.dart';

// Module Interfaces
export 'src/modules/interfaces/capability_provider.dart';
export 'src/modules/interfaces/auth_provider.dart';
export 'src/modules/interfaces/consent_provider.dart';
export 'src/modules/interfaces/feature_providers.dart';

// Modules
export 'src/modules/capabilities/capability_module.dart';
export 'src/modules/capabilities/capability_token.dart';
export 'src/modules/consent/consent_module.dart';
export 'src/modules/consent/consent_profile.dart';
export 'src/modules/consent/consent_token.dart';
export 'src/modules/consent/consent_ui.dart';
export 'src/modules/wear/wear_module.dart';
export 'src/modules/wear/wear_source_handler.dart' show WearSample;
export 'src/modules/phone/phone_module.dart';
export 'src/modules/behavior/behavior_module.dart';
export 'src/modules/behavior/behavior_events.dart';
export 'src/modules/runtime/runtime_module.dart';
export 'src/modules/cloud/cloud_connector_module.dart';
export 'src/modules/cloud/upload_models.dart';
export 'src/modules/cloud/cloud_exceptions.dart';
export 'src/modules/cloud/hmac_signer.dart';

// Platform Ingest
export 'src/modules/platform_ingest/platform_ingest_module.dart';
export 'src/modules/platform_ingest/platform_ingest_client.dart';

// Runtime Bridge (FFI to synheart-runtime, includes SRM baseline access)
export 'src/modules/runtime/runtime_bridge.dart';

// Watch Session (adapter around synheart_session for watch relay)
export 'src/modules/session/watch_session_module.dart';

// Services
export 'src/services/auth_service.dart';

// Session lifecycle (re-exported from synheart_session)
export 'package:synheart_session/synheart_session.dart';

// BLE Heart Rate Monitor (re-exported from synheart_wear)
export 'package:synheart_wear/src/adapters/ble_hrm_models.dart';
export 'package:synheart_wear/src/adapters/ble_hrm_bridge.dart';
