# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-05-19

### Added
- **Cross-device sync surface.** `syncCreateSpace`, `syncJoinSpace`,
  `syncGeneratePairing`, `syncStatus` drive the SyncEngine landed in
  core-runtime v0.10.0.
- **Offline export / import.** `baselineExportOffline(passphrase)` and
  `baselineImportOffline(passphrase, bytes)` — encrypted `.srm.synheart`
  bundle with 6-word BIP39 passphrase, never sent to the server.
- **`BaselineLocalHydrator` facade** — `wireLocalHydrator(...)` replaces
  the deleted `wireCloud(...)` path.

### Fixed
- **iOS framework load** — switched to `DynamicLibrary.process()` so
  symbols resolve from the auto-loaded embedded framework. Previous
  `dlopen` of the literal relative path silently failed; symptom was
  "Native runtime not loaded" with no actionable error.
- **`CoreRuntimeBridge.create` surfaces Rust's last-error message** via
  the new `synheart_core_last_error()` FFI symbol when `coreNew` returns
  nullptr. Replaces silent failure.

### Changed (breaking)
- **`wireCloud(...)` removed.** Migrate to `wireLocalHydrator(...)`. The
  parallel baseline-cloud uploader is retired; baselines now ride the
  SyncEngine.
- **iOS podspec** moves from static `.a` + `force_load` to a vendored
  dynamic framework + `prepare_command` symlink. Consumer apps install
  the xcframework via the synheart CLI.

### Other
- Logging hygiene: consent-changed multi-line block collapsed; native
  callback bootstrap silent on success; baselines `scoreInput` log no
  longer dumps full engine JSON.

### Requires
- `synheart-core-runtime` v0.10.0 (FFI surface + sync handshake).

## [0.4.0] - 2026-05-16

### Added
- `Synheart.syni` — gated Syni client surface with install lifecycle +
  chat + chatStream, delegating to `package:syni`'s `SyniAgent`.
- `SyniContextBuilder` — projects this SDK's HSI (live state + stored
  session history) into the runtime's conditioning contract.
  HSI-version-agnostic; iterates whatever axes the runtime emitted.
- Trivial-message context skip — for greetings / acks, ship only the
  persona prefix instead of full HSI + history (~30–50% prefill
  reduction on short messages).
- `SyniSpecPersona` re-exported from `package:syni` so consumers can
  `SyniSpecPersona.load('focus.coach.v1')` for canonical prompts.
- `Synheart.{closeOrphanSession, sweepOrphanSessions}` — host-side
  orphan cleanup. Sweep on app start closes `state='active'` sessions
  older than 6h that the runtime never finalized (force-kill, OS
  reclaim, sudden reboot).
- `Synheart.configureSyniCloud(...)` — injects cloud client config;
  `Synheart.syni.hasCloud` + per-call `SyniExecutionMode` routes
  between local and cloud.
- Cold-start restore — `SyniAgent.restoreInstallIfReady` checks disk
  before download flow; consumers don't re-prompt for an install when
  the model is already cached.

### Changed
- `syni` dependency switched from `path: ../syni-flutter` to
  `^0.1.0` (now published on pub.dev).
- `SessionSummaryArtifact` parser rewritten to match the runtime's
  actual wire format (nested `header` block, `started_at_ms` /
  `ended_at_ms` keys, nullable per-axis aggregates, structured
  `SessionAggregates` keyed by axis name).
- `SessionRecord` now reads `started_at_ms` from the FFI (was missing —
  surfaced as 1970-01-01 timestamps in downstream digests). `state`
  and `endedAtUtc` exposed for the sweep's filter.

## [0.3.0] - 2026-05-14

### Added
- `Synheart.labReenqueueSession(String sessionJson)` — replay a
  previously-finalized lab session payload through the cloud
  connector. Useful when the initial upload was dropped on a 4xx
  (typically a cloud schema mismatch — the runtime removes those
  rows from the in-memory upload queue per
  `ingest/hsi/connector.rs::deliver_lab_chunk`). Host reads the
  persisted JSON from app-side storage and passes it back.
- `Synheart.isLabReenqueueAvailable` — feature-detect whether the
  linked runtime binary exports the symbol (engine v0.8.1+).
- `LabReenqueueResult` enum — mirrors the FFI return codes
  (`queued`, `researchNotAllowed`, `cloudNotConfigured`,
  `parseError`, `invalidArgument`, `unsupported`).
- `CoreRuntimeBridge.labReenqueueSession` instance method + companion
  `isLabReenqueueAvailable` getter; new `_LabReenqueueC` / `_LabReenqueueDart`
  typedefs in `ffi_bindings.dart`. Lookup is optional so older
  runtime binaries (pre-v0.8.1) keep loading without errors.
- Customer-facing data deletion API (`requestDataDeletion`,
  `getDataDeletion`, `listDataDeletions`) and `DataDeletion*` models
  for GDPR Article 17 (landed via PR #40).

### Runtime compatibility
- Requires `synheart-core-runtime` v0.8.1+ for `labReenqueueSession`
  to actually invoke the FFI. Older binaries return
  `LabReenqueueResult.unsupported`.

## [0.2.0] - 2026-05-09

### Added
- HSI 1.3 envelope parsing in `HSIState` and `HSIPayload`. Producers
  emit the closed 5-axis domain set (`physiological`, `kinematic`,
  `digital`, `cognitive`, `affective`) with deterministic UUIDv5
  `hsi_id`. The SDK now parses the new shape and exposes the digital
  readings (`focus_quality`, `interruption_pressure`,
  `interaction_mode`) alongside the existing physiological / cognitive
  / affective fields. The 1.2 wire shape is still accepted as a
  fallback; consumers should not rely on that path long-term.

### Fixed
- `BehaviorModule._convertSynheartEvent` now forwards
  `BehaviorEventType.app_switch` to the runtime instead of dropping it
  via the default-arm. The runtime needs `app_switch` to detect
  notification responses (an app switch shortly after a notification)
  and to anchor session boundaries between foreground events of
  different apps. Without this forward, the digital readings on the
  HSI 1.3 envelope (`axes.digital[]` — `focus_quality`,
  `interruption_pressure`, `interaction_mode`) were silent on iOS and
  Android.

## [0.1.1] - 2026-05-08

### Changed
- Bumped `synheart_auth` dep to `^0.1.2`. Picks up the Maven Central
  `ai.synheart:synheart-auth:0.1.1` upgrade (clock-skew auto-apply,
  register/rotate race fix, HTTP timeouts, §13 audit-log PII redaction).

## [0.1.0] - 2026-05-08

First public open-source release on pub.dev. The SDK is now a thin
FFI shell over the native Synheart Runtime — storage, crypto, sync,
consent, the artifact pipeline, the cloud connector, and SRM live in
the runtime, and this package exposes them through a Dart surface.

The native runtime is license-gated and installed via the
[Synheart CLI](https://docs.synheart.ai/synheart-cli)
(`synheart install runtime`); see the README.

This release consolidates the OSS-launch refactors that were tagged
internally as 0.0.3 and 0.0.4 but never reached pub.dev, plus the
post-tag breaking change to `processVendorEvent`.

### Breaking
- `Synheart.processVendorEvent(...)` and
  `WearModule.processVendorEvent(...)` now return
  `Future<CanonicalWearableEvent?>` instead of `Future<void>`. The
  previous void return discarded the canonical event the vendor payload
  was mapped to. Mirrors the Swift and Kotlin counterparts.
- Removed `CloudConfig.tenantId`. Drop the argument — `app_id` is the
  only identifier the SDK sends.
- Removed `CloudConfig.hmacSecret`. Request signing uses the device key;
  `authProvider` is now optional.
- Removed `InvalidTenantError`.
- `ConsentForm` shape is flat (`profile_id`, `biosignals`,
  `phone_context`, `behavior`, `consent_tier`, `allow_cloud`,
  `allow_research`, `allow_vendor_sync`) to mirror the runtime. Hosts
  that previously built `categories[] → channels[]` structures must
  migrate to the flat form.
- Consent type strings are snake_case at the runtime boundary
  (`phone_context` / `cloud_upload` / `vendor_sync`). Flutter still
  accepts camelCase on its public API.
- Removed `ConsentCategory` and `ConsentChannel` types — channel-level
  truth is owned by the runtime.

### Added
- `Synheart.rawRamenEvents` — broadcast `Stream<RamenEvent>` re-exported
  from `synheart_wear`, surfacing every RAMEN event with its
  capability-flavored `deliveryHint`. `app_id` / `user_id` from the
  active `startVendorSync` config are stamped onto each event so
  `RamenEventDispatcher` can drive REST pulls without extra plumbing.
- Offline-first consent FFI surface: `consentConfigureCloud`,
  `consentGetEditableForm`, `consentSubmitForm`, `consentEffectiveState`,
  `consentStatus`, `consentNeedsTokenRefresh`, `consentClearStored`.
  Local choice is persisted immediately; cloud sync is best-effort.
- Typed consent form accessors: `consentGetEditableFormTyped()` and
  `consentSubmitFormTyped({ required ConsentForm form, … })`.
- Consent coverage for `vendorSync` and `research` through
  `hasConsent()` / `getConsentStatusMap()` and the granular grant API.
- Durable `data_dir` for the native runtime via `path_provider`. Fixes
  SRM snapshots and the artifact SQLite landing in
  `std::env::temp_dir()` (cleaned up by the OS), which broke baseline
  persistence across app restarts.

### Changed
- `setStreamCallback` auto-route now skips `delivery_hint == "ping"`
  events. Their inline `payload_json` is empty by design (Garmin / Oura
  / Fitbit only send a notification), so apps must subscribe to
  `rawRamenEvents` and use `RamenEventDispatcher` to fetch the full
  record before re-feeding the canonical pipeline.
- README rewritten to match the actual public API.
- Dependencies on sibling Synheart SDKs are now hosted on pub.dev
  (`synheart_wear ^0.4.0`, `synheart_session ^0.2.0`,
  `synheart_behavior ^0.3.0`, `synheart_auth ^0.1.1`) instead of git
  refs.

[Unreleased]: https://github.com/synheart-ai/synheart-core-flutter/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.2.0
[0.1.1]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.1.1
[0.1.0]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.1.0
