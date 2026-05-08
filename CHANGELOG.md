# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/synheart-ai/synheart-core-flutter/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.1.1
[0.1.0]: https://github.com/synheart-ai/synheart-core-flutter/releases/tag/v0.1.0
