# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.3] - 2026-06-07

### Added
- `Synheart.requestStudyDataDeletion({bool dryRun})`: request erasure of the data
  the participant contributed to their study for this app — the deletion the
  consent copy promises alongside withdrawal. No identifiers are passed; the
  participant and app come from the device's signed cloud credential. `dryRun`
  returns an inventory preview without deleting; a real request is accepted
  asynchronously and carries a `request_id`. Idempotent.

## [0.6.2] - 2026-06-07

### Added
- Research-study enrolment API: `Synheart.enrolResearchStudy(...)`,
  `Synheart.validateResearchStudyCodes(...)`, and `Synheart.withdrawResearchStudy()`.
  Enrolment rides the device's signed cloud credential — no tokens are handled by
  the app. Withdrawal is idempotent.
- `DeviceAuthConfig.packageName`: the app's package / bundle id, passed through so
  device registration can be bound to the app. Optional (defaults to empty).

## [0.6.1] - 2026-05-24

### Added
- **Consent surface for Syni.** `ConsentForm.syni`, the parameter
  `Synheart.grantConsent(..., syni: bool)`, and `ConsentSnapshot.syni`
  are now exposed end-to-end so hosts can track and persist the user's
  consent for on-device or cloud LLM processing alongside the other
  channels. Backward compatible — `syni` defaults to `false` everywhere
  so existing callers compile unchanged.
- **Canonical channel iteration.** New `ConsentTypeMeta` extension on
  `ConsentType` exposes `wireKey`, `displayName`, `valueOn` (typed
  accessor for `ConsentEffectiveState`), and `valueOnForm` (typed
  accessor for `ConsentForm`). Plus `ConsentEffectiveState.toChannelMap()`
  / `ConsentForm.toChannelMap()` and `ConsentForm.fromChannelMap(...)`.
  Hosts can now iterate `ConsentType.values` rather than hardcoding each
  channel — adding a new channel becomes a single change in the SDK
  enum plus its metadata; consumers pick it up automatically.
- **`Synheart.consentChanges`** — public broadcast stream of
  `ConsentSnapshot`s. Emits on any grant or revoke so hosts that render
  consent in multiple places (e.g. a profile counter alongside a
  consent screen) can stay in sync without polling
  `consentEffectiveStateTyped` or re-dispatching reads.
- **`Synheart.syni.bindPersona(SyniPersona)`** (passthrough to
  `package:syni`'s new `SyniAgent.bindPersona`). Cloud chat needs only
  a persona plus a configured cloud client; hosts that pick
  `SyniExecutionMode.cloudOnly` can call this once instead of running
  `install()` purely to attach a persona. Requires `syni: ^0.3.2`.

### Changed
- `syni` dependency bumped to `^0.3.2` (carries `bindPersona` + the
  fix that lets `cloudOnly` chat run without a local install).
- `ConsentEffectiveState.hasAnyGrant` now includes `syni` — previously
  the flag was tracked through the rest of the state but missing from
  this convenience getter.

### Fixed
- `consentSubmitFormTyped` now propagates the form's `syni` value to
  the runtime via the per-type grant/revoke FFI when the runtime's
  form parser doesn't carry the key directly. Without this a host
  setting `syni` on the typed form would see the other channels update
  but `syni` stay at its previous value.

## [0.6.0] - 2026-05-23

### Added
- `Synheart.configure()` now wires Syni's hybrid router to the cloud — it
  builds the `SyniCloudConfig` and authenticates Syni cloud-chat requests
  with an `X-Synheart-Proof` device-attestation header (produced by
  core-runtime). `Synheart.syni` cloud chat needs no extra host-app setup.
- `DeviceAuthProvider.signUrl` — builds an `X-Synheart-Proof` for an
  absolute URL (no base-URL prefixing); `signRequest` now delegates to it.

### Changed
- Bumped the `syni` dependency to `^0.3.0`, whose `SyniCloudConfig`
  replaced the static `authToken` with the request-aware `authHeaders`.
  Consumers building a `SyniCloudConfig` directly need to update to the
  new shape; consumers using `Synheart.configure()` are unaffected.
- The SDK-side default `SyniCloudConfig.authHeaders` closure lazily
  attaches `X-Synheart-Proof` via `Synheart.buildProofHeader` — works
  whether device auth resolves through the Dart `DeviceAuthProvider`
  or the core-runtime ABI registration path (`sdkDeviceAuthAbi=true`).

## [0.5.3] - 2026-05-21

### Fixed
- **iOS: the native runtime can now start on the ONNX-backed tiers.**
  The podspec force-loads ONNX Runtime into the host app binary. The
  runtime framework resolves `OrtGetApiBase` at load time, and
  `onnxruntime-c` ships ONNX as a static archive — nothing in the host
  app references it directly, so the linker dead-stripped the whole
  archive and the runtime crashed on first use. Consumers no longer
  need any per-app linker configuration; depending on `synheart_core`
  is enough. iOS build configuration only — no Dart API change.

## [0.5.2] - 2026-05-20

### Changed
- Bumped the `synheart_behavior` dependency to `^0.4.0`. The behavior
  SDK is now an event producer — a session summary may arrive with no
  `behavioralMetrics`. `BehaviorSessionResults.fromSummary` already
  treats those metrics as optional and defaults each to 0 when absent.

## [0.5.1] - 2026-05-19

### Changed
- Scrubbed internal references from the public package surface — dartdoc
  comments, section header dividers, and barrel-file comments no longer
  cite internal identifiers or internal documentation paths. Comments
  and doc strings only; no code or API changes.

## [0.5.0] - 2026-05-19

### Added
- **Cross-device baseline sync.** `Synheart.syncCreateSpace`,
  `syncJoinSpace`, `syncGeneratePairing`, `syncStatus` — pair two devices
  and replicate baselines in either direction with end-to-end encryption.
- **Offline export / import.** `Synheart.baselineExportOffline(passphrase)`
  produces an encrypted `.srm.synheart` bundle (6-word passphrase, never
  sent to any server). `baselineImportOffline(passphrase, bytes)` returns
  `{imported, skipped, errors}`. Lets users move baselines across
  devices without the cloud.
- **`BaselineLocalHydrator` facade** — `wireLocalHydrator(...)` is the
  new entry point for hydrating baselines into the SDK from
  device-local sources.

### Fixed
- **iOS native runtime loading.** Replaced the relative-path framework
  open with `DynamicLibrary.process()`, which resolves symbols from the
  auto-loaded embedded framework. The previous form silently failed and
  surfaced only as a generic "Native runtime not loaded" warning.
- **Runtime initialization failures are now visible.** When the native
  runtime rejects a configuration on iOS, the host now sees the actual
  reason instead of a silent fallback.

### Changed (breaking)
- **`wireCloud(...)` removed.** Migrate to `wireLocalHydrator(...)`. The
  separate baseline cloud uploader is retired; baselines now ride the
  cross-device sync path.
- **iOS install model.** Podspec moves to a vendored dynamic framework
  installed via the synheart CLI (`synheart install runtime`), rather
  than a static library bundled with the package. Consumer Podfile gets
  a `prepare_command` symlink pointing at the CLI-managed vendor dir.

### Other
- Logging hygiene: consent change events emit one structured line
  instead of an 8-line block; native bridge startup is silent on the
  happy path and warns only on real failures; baseline scoring no
  longer dumps the full engine input JSON.

### Requires
- The matching native runtime release (`synheart-core-runtime` v0.10.0).

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

[Unreleased]: https://github.com/synheart-ai/synheart-core-flutter/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.6.1
[0.5.3]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.5.3
[0.5.2]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.5.2
[0.2.0]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.2.0
[0.1.1]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.1.1
[0.1.0]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.1.0
