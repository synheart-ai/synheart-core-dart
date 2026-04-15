# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Offline-first consent FFI surface:** `Synheart.consentConfigureCloud`,
  `consentGetEditableForm`, `consentSubmitForm`, `consentEffectiveState`,
  `consentStatus`, `consentNeedsTokenRefresh`, `consentClearStored` — wraps the
  new offline-first consent module from synheart-core-runtime 0.4.0. Local
  choice is persisted immediately; cloud sync is best-effort.
- **Typed consent form accessors:** `consentGetEditableFormTyped()` returning
  `ConsentForm?` and `consentSubmitFormTyped({ required ConsentForm form, … })`
  for type-safe call sites. Legacy `Map<String, dynamic>` variants remain.
- **Consent coverage:** `vendorSync` and `research` are now surfaced through
  `hasConsent()` / `getConsentStatusMap()` and round-tripped through the
  granular grant API.

### Changed
- **`ConsentForm` shape is flat** (`profile_id`, `biosignals`, `phone_context`,
  `behavior`, `consent_tier`, `allow_cloud`, `allow_research`,
  `allow_vendor_sync`) to mirror `synheart-core-runtime` 0.4.0. Hosts that
  previously built `categories[] → channels[]` structures must migrate to the
  flat form — the runtime no longer accepts the nested shape.
- **Consent type strings now snake_case** at the runtime boundary. Flutter
  continues to accept camelCase on its public API, but internal `grantConsent`
  calls, `_getConsentStatusMap`, and any direct FFI passthrough now send
  `phone_context` / `cloud_upload` / `vendor_sync` to match the runtime
  canonical names (runtime still accepts camelCase aliases).
- Core business logic (storage, crypto, sync, consent, artifact pipeline, cloud connector, SRM)
  migrated to synheart-core-runtime (Rust). SDK is now a thin FFI shell.
- RuntimeBridge/RuntimeModule replaced by CoreRuntimeBridge (FFI to libsynheart_core_runtime)
- HSI state updates delivered via native callback mechanism instead of platform-specific streams

### Removed
- **`ConsentCategory` and `ConsentChannel` types:** removed alongside the flat
  form rewrite. Runtime no longer exposes per-channel UI data to hosts;
  channel-level truth is owned by the runtime and intersected against the
  cloud default profile on submit.
- StorageManager, ArtifactCrypto, SMK, URK, SyncEngine, SyncModule, ArtifactPipeline
- RuntimeBridge, RuntimeModule (replaced by CoreRuntimeBridge)
- CloudConnector, UploadQueue, UploadClient, HsiSchemaTransformer
- SRM computation modules (SRMModule, SRMBuffer, SRMSnapshotStorage)

## [1.3.0] - 2026-03-08

### Added

- Artifacts pipeline, storage manager, sync engine, auth module, crypto helpers (URK/SMK, envelopes).
- `env/synheart.endpoints.example.json` for ingest/consent base URLs.

### Changed

- `Synheart` / `SynheartConfig` session and platform-ingest wiring; `runtime_module` and cloud upload client.
- Example app (provider, settings, runtime diagnostics, home); README.

## [1.2.1] - 2026-03-07

### Removed

- **`configure()` method** — Merged into `initialize()`. Single entry point: `static Future<void> initialize({SynheartConfig? config, String? userId, bool autoStart = false})`.
- **Feature provider interfaces** — Removed `WearFeatureProvider`, `PhoneFeatureProvider`, `BehaviorFeatureProvider`. Modules no longer implement these interfaces.
- **On-demand feature query methods** — Removed `getWearFeatures()`, `getBehaviorFeatures()`, `getPhoneFeatures()` static methods. Feature computation lives in synheart-engine.
- **Legacy config fields** — Removed `enableCloudSync`, `enableSyniHooks`, `updateInterval`, `logLevel`, and `LogLevel` enum from `SynheartConfig`.
- **Code generation dependencies** — Removed `json_annotation`, `json_serializable`, and `build_runner`. All models use manual `fromJson()`/`toJson()` now.
- **Empty directories** — Removed unused `heads/` and `integrations/` directories.

### Changed

- **Documentation** — Updated README.md, ARCHITECTURE.md, CONTRIBUTING.md to reflect all removals. Removed stale code examples and references.

## [1.2.0] - 2026-02-23

### Removed

- **FeatureExtractor** — Deleted empty `BehaviorFeatureExtractor` placeholder class (`lib/src/modules/behavior/feature_extractor.dart`). All feature computation lives in synheart-engine per RFC-CORE-0007.

### Changed

- Removed all TODO/FIXME comments across the SDK (synheart.dart, auth_service.dart, synheart_wear_adapter.dart, capability_module.dart).
- Replaced stale TODO comments in FocusHead and EmotionHead reevaluation branches with concise `// FocusHead: HSI JSON parser pending.` / `// EmotionHead: HSI JSON parser pending.` notes.
- **README.md** — Updated version badge, fixed HSV→HSI terminology, updated code examples to use `activate()` API and `Stream<String>` types, removed Syni Hooks from module list, removed stale `startDataCollection`/`stopDataCollection` references.

### Added

- **SRM snapshot persistence** — SRM baseline model is now persisted to encrypted storage (`FlutterSecureStorage`) and automatically restored on SDK initialization. Prevents baseline loss on app restart. New `SRMSnapshotStorage` class mirrors the `ConsentStorage` pattern.
- **HSI stream consent gating** — Local `onHSIUpdate` stream now checks `biosignals` consent before forwarding HSI frames to consumers. Previously only cloud upload was gated; now local streams respect consent too.
- **SRM persistence tests** — New `srm_snapshot_storage_test.dart` with 4 tests: save/load round-trip, null on empty, clear, and full SRMModule restore-from-storage integration test.
- **HSI consent gate tests** — New `consent_gate_test.dart` with 3 tests verifying HSI frames are blocked when biosignal consent is denied.
- **synheart-engine installed** — macOS dylib, Android `.so` (4 ABIs), and iOS XCFramework now bundled in the SDK via `make install-dart`.

## [1.1.0] - 2026-02-22

### Changed

- **RuntimeBridge** (renamed from `FluxFFIProvider`) — now wraps synheart-engine C ABI instead of calling synheart-flux directly. synheart-engine composes the full session → state → flux pipeline internally.
  - `synheart_engine_new(config_json)` replaces `flux_processor_create()`
  - `synheart_engine_push_rr()`, `push_hr()`, `push_accel()`, `push_behavior()` for signal ingestion
  - `synheart_engine_tick(now_ms)` returns HSI JSON when a window completes
  - `synheart_engine_free_string()` for memory management
  - Backward-compatible: `createIfAvailable()` still returns null when native library is absent
- **RuntimeModule** (renamed from `HSVRuntimeModule`) — orchestrates signal collection and pipeline execution via RuntimeBridge.
- Updated stale comments across 10 source files to reference current module names.

## [1.0.0] - 2026-02-21

First stable release supporting HSI 1.x.

### Added
- **Flux FFI Integration** — Live pipeline from Core SDK to synheart-flux (Rust) via dart:ffi
  - `FluxFFIProvider` — concrete `FluxProvider` calling `flux_processor_process_window()` via dart:ffi
  - Platform-specific library loading (Android `.so`, iOS `DynamicLibrary.process()`, macOS `.dylib`, Windows `.dll`)
  - Serializes raw `WearSample`, `PhoneDataPoint`, `BehaviorEvent` into WindowInput JSON
  - Maps returned Flux HSV JSON into Core `HumanStateVector` (physiology, quality, provenance, embedding)
  - Stores raw Flux HSV JSON in `MetaState.rawFluxHsv` for downstream access
  - Baseline persistence: `saveBaselines()` / `loadBaselines()` for session continuity
  - Graceful degradation: `createIfAvailable()` returns null when native library is absent
  - Memory-safe: all `flux_free_string()` / `malloc.free()` calls paired with allocations
  - Dependencies: `ffi: ^2.1.0`, `package:ffi` for UTF-8 string conversion

- **synheart-flux 0.4.0 Alignment** — HSV types updated to match Flux HSV specification
  - `HsvAxisValue` — score + confidence pair for per-axis readings (replaces hardcoded 0.8 confidence)
  - `PhysiologyState` — wearable-derived physiology domain with 11 axes (sleep efficiency, recovery, HRV deviation, RHR deviation, respiratory rate, SpO2, strain, sleep duration, deep sleep ratio, REM sleep ratio, sleep fragmentation)
  - `StateQuality` — aggregated quality assessment (overall confidence, modality count, degraded flag, quality flags)
  - `ProvenanceInfo` — data provenance tracking (source IDs, vendors, device ID, timezone, baseline days)
  - `ExportPolicy` — controls which domains, axes, and confidence thresholds appear in exported HSI
  - `HumanStateVector` gains `physiology`, `stateQuality`, and `provenance` fields
  - `FluxBridge.export()` now accepts optional `ExportPolicy` for domain filtering and confidence gating
  - FluxBridge uses per-axis `HsvAxisValue.confidence` for physiology readings instead of hardcoded values
  - FluxBridge meta block includes `modality_count`, `overall_confidence`, and `vendors` from provenance

- **Capability Token Validation** — SDK now validates server-signed capability tokens during initialization
  - New `SynheartConfig` fields: `capabilityToken`, `capabilitySecret`, `allowUnsignedCapabilities`
  - When token and secret are provided, `CapabilityModule.loadFromToken()` validates HMAC signature and expiry
  - `allowUnsignedCapabilities: true` serves as a debug escape hatch (logs a warning)
  - Without a valid token or explicit opt-in, initialization throws `StateError`
  - Removed hardcoded `mock_secret` and `_authService.authenticate()` from production initialization path

- **Consent Revocation Deactivates Modules** — Revoking consent mid-session now stops affected modules immediately
  - `biosignals` revoked → stops `WearModule`, cancels Emotion/Focus head subscriptions
  - `behavior` revoked → stops `BehaviorModule`
  - `motion` revoked → stops `PhoneModule`
  - `cloudUpload` revoked → stops `CloudConnectorModule`
  - Granting consent re-starts the corresponding module
  - Each stop/start is isolated — one module failure does not cascade
  - Rewrote `_onConsentChanged` from logging-only to active module management

- **On-Demand Data Collection API**: Granular control over when data collection starts and stops
  - `autoStart` parameter in `initialize()` to control automatic collection start (defaults to `true` for backward compatibility)
  - `startDataCollection()` / `stopDataCollection()` for global collection control
  - Module-specific start/stop methods: `startWearCollection()`, `stopWearCollection()`, `startBehaviorCollection()`, `stopBehaviorCollection()`, `startPhoneCollection()`, `stopPhoneCollection()`
  - Status getters: `isWearCollecting`, `isBehaviorCollecting`, `isPhoneCollecting`
  - Custom collection intervals for wear module via `startWearCollection(interval: Duration)` (e.g., 1s for games, 5s for normal use)
  - `updateCollectionInterval()` method on `WearModule` to change collection frequency at runtime
  
- **Raw Data Stream Access**: Direct access to raw samples and events
  - `Synheart.wearSampleStream` - Stream of raw `WearSample` data (HR, HRV, RR intervals, motion, timestamp)
  - `Synheart.behaviorEventStream` - Stream of raw `BehaviorEvent` data (taps, keystrokes, scrolls, app switches, notifications)
  - `WearModule.rawSampleStream` - Direct access to wear samples from the module
  - Streams respect consent - no data emitted without consent
  - Broadcast streams support multiple subscribers
  
- **Behavior Session Management**: Track and analyze behavior sessions
  - `startBehaviorSession()` - Start a behavior tracking session and get session ID
  - `stopBehaviorSession(sessionId)` - End session and get aggregated results
  - `BehaviorSessionResults` class with simplified access to key metrics:
    - `tapRate`, `keystrokeRate`, `focusHint`, `interactionIntensity`, `burstiness`
    - `totalEvents`, `durationMs`, `sessionId`
    - Full `BehaviorSessionSummary` available via `summary` property
  
- **On-Demand Feature Queries**: Query aggregated features without subscribing to streams
  - `getWearFeatures(WindowType)` - Query wear features for specific time windows
  - `getBehaviorFeatures(WindowType)` - Query behavior features for specific time windows
  - `getPhoneFeatures(WindowType)` - Query phone features for specific time windows
  - Supports all window types: `window30s`, `window5m`, `window1h`, `window24h`
  - Returns `null` if no data available for the requested window

### Changed
- **Initialization**: `Synheart.initialize()` now accepts optional `autoStart` parameter (defaults to `true` for backward compatibility)
  - When `autoStart: false`, modules are initialized but not started
  - Call `startDataCollection()` or individual module start methods when ready
  - Existing apps continue to work without changes (backward compatible)
  
- **Consent Enforcement**: Enhanced consent checks throughout the SDK
  - **Wear Module**: Multi-layer consent enforcement
    - Consent checked before starting collection
    - Consent checked before processing samples
    - Consent checked before emitting to raw sample stream
    - Collection stops immediately if consent is revoked
  - **Behavior Module**: Consent checked before processing events
  - **Phone Module**: Consent checked before processing motion data
  - All raw data streams respect consent - no data emitted without consent
  
- **WearModule**: Added `rawSampleStream` getter for direct sample access
  - Broadcast stream supports multiple subscribers
  - Automatically forwards samples from all active sources
  - Respects consent at every level

### Documentation
- **README.md**: Comprehensive updates
  - Added "On-Demand Data Collection" section with complete API documentation
  - Updated "Consent Management" section with all available consent APIs
  - Added use case examples (game apps, focus sessions)
  - Fixed incorrect `SynheartConfig` examples (removed non-existent `enableWear`/`enablePhone`/`enableBehavior` properties)
  - Added examples for all new APIs (raw streams, sessions, feature queries)
  - Enhanced privacy & security section with consent enforcement details

### Breaking Changes
- `Synheart.initialize()` now requires either a valid capability token or `allowUnsignedCapabilities: true` in config. Existing callers that relied on implicit `loadDefaults()` via `MockAuthService` must pass `SynheartConfig(allowUnsignedCapabilities: true)`.

### Example App
- Added new `OnDemandScreen` demonstrating all on-demand collection features
  - Module start/stop controls with status indicators
  - Raw data stream viewers (wear samples and behavior events)
  - Behavior session management UI
  - On-demand feature query interface
  - Game scenario demo with real-time HR display
- Added reusable widgets:
  - `ModuleControlCard` - Toggle individual modules on/off
  - `RawDataViewer` - Display live wear samples and behavior events
  - `SessionControlPanel` - Manage behavior sessions and view results
- Updated `SynheartProvider` with comprehensive state management:
  - Collection status tracking
  - Raw data stream subscriptions
  - Behavior session management
  - On-demand query methods
  - Game session simulation
- Updated initialization to use `autoStart: false` for demonstration purposes

## [0.0.2] - 2025-12-29

### Added
- **HSI 1.0 Export Capability**: synheart-core-flutter can now export HSI 1.0 canonical payloads
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

- **Public API**: removed legacy `HSI` entrypoints; `Synheart` is now the single SDK entrypoint exported from `package:synheart_core/synheart_core.dart`.
- **Logging**: replaced `print()` usage with internal logger to satisfy `flutter_lints` (`avoid_print`).
- **Examples**: cleaned up naming and flow to match `Synheart` (including renaming the full pipeline demo).

### Planned
- Implement actual ML embedding model (currently placeholder)
- Improve documentation and examples
- Performance optimizations
- Additional wearable device support
- Phase 2: Add raw RR intervals to HSV metadata for full EmotionEngine integration



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
- Minimum SDK: Dart 3.7.0, Flutter 3.32.0
- Dependencies: synheart_wear ^0.1.2, rxdart ^0.28.0
- Architecture: Stream-based reactive module system
- Platform support: iOS, Android



[1.2.1]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v1.2.1
[1.2.0]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v1.2.0
[1.1.0]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v1.1.0
[1.0.0]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v1.0.0
[0.0.2]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.0.2
[0.0.1]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.0.1
