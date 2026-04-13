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
export 'src/config/synheart_mode.dart';
export 'src/config/synheart_errors.dart';

// Artifacts (RFC-CORE-0006 Tier A)
export 'src/artifacts/artifact_header.dart';
export 'src/artifacts/hsi_window.dart';
export 'src/artifacts/baseline_snapshot.dart';
export 'src/artifacts/session_summary.dart';
export 'src/artifacts/tombstone.dart';

// Session model
export 'src/models/session_handle.dart';

// Phase 2: Typed state and metrics
export 'src/models/hsi_state.dart';
export 'src/models/metric_event.dart';

// Wearable Events
export 'src/models/canonical_wearable_event.dart';

// Vendor Providers (cloud OAuth + data fetch)
export 'src/modules/vendor/whoop_provider.dart';
export 'src/modules/vendor/garmin_provider.dart';

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
export 'src/modules/wear/wear_module_status.dart';
export 'src/modules/wear/wear_source_handler.dart' show WearSample;
export 'src/modules/phone/phone_module.dart';
export 'src/modules/behavior/behavior_module.dart';
export 'src/modules/behavior/behavior_events.dart';
export 'src/modules/cloud/upload_models.dart';
export 'src/modules/cloud/cloud_exceptions.dart';

// Core Runtime Bridge (FFI to synheart-core-runtime for HSI, baselines, lab, sync)
export 'src/core_runtime/core_runtime_bridge.dart';
export 'src/core_runtime/sdk_crypto_callbacks.dart';

// Watch Session (adapter around synheart_session for watch relay)
export 'src/modules/session/watch_session_module.dart';

// Device Auth
export 'src/modules/cloud/device_auth_provider.dart';
export 'src/modules/capabilities/capability_token_fetcher.dart';

// Device Auth (re-exported from synheart_auth, hiding name collisions)
export 'package:synheart_auth/synheart_auth.dart' hide NetworkError;

// Session lifecycle (re-exported from synheart_session)
export 'package:synheart_session/synheart_session.dart';

// BLE Heart Rate Monitor (re-exported from synheart_wear)
export 'package:synheart_wear/src/adapters/ble_hrm_models.dart';
export 'package:synheart_wear/src/adapters/ble_hrm_bridge.dart';
