# Synheart Core SDK - Architecture Guide

**Last Updated**: March 2026
**Version**: 2.0.0

---

## Overview

The Synheart Core SDK (Dart) is a thin FFI shell that delegates all core business logic to `synheart-core-runtime` (Rust) via `CoreRuntimeBridge`. The SDK coordinates platform-specific data collection (wear, phone, behavior) and routes it through the shared Rust core.

**Key Principle**:
> All core operations (storage, crypto, sync, consent, artifact pipeline, SRM, signal processing) live in `synheart-core-runtime`. The Dart SDK is a platform integration layer.

---

## Architecture Layers

```
┌─────────────────────────────────────────┐
│         Application (Your App)          │
│  onHSIUpdate, lastQuality, consent UI   │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│      Synheart Core SDK (Dart)           │
│      Thin FFI shell                     │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  Platform Collection Modules    │   │
│  │  • Wear (wearables)             │   │
│  │  • Phone (motion, context)      │   │
│  │  • Behavior (interactions)      │   │
│  └──────────────┬──────────────────┘   │
│                 │                       │
│  ┌──────────────▼──────────────────┐   │
│  │  CoreRuntimeBridge (dart:ffi)   │   │
│  │  synheart_core_runtime_*()      │   │
│  └──────────────┬──────────────────┘   │
└──────────────────┬──────────────────────┘
                   │ (C ABI)
┌──────────────────▼──────────────────────┐
│    synheart-core-runtime (Rust)         │
│  • Storage (SQLite), Crypto (E2EE)      │
│  • Sync engine, Consent management      │
│  • Artifact pipeline, Cloud connector   │
│  • SRM (baselines), Capability gating   │
│  • Signal processing (synheart-engine) │
│  • HSV computation, HSI serialization   │
└─────────────────────────────────────────┘
```

---

## Core Modules

### 1. CoreRuntimeBridge
**Purpose**: FFI bridge to synheart-core-runtime (Rust)

All core business logic is delegated to the Rust runtime via this bridge:
- Capability gating, consent management, storage, crypto, sync
- Artifact pipeline, cloud connector, SRM baselines
- Signal processing and HSI computation (via embedded synheart-engine)

**Key Class**: `CoreRuntimeBridge`

---

### 2. Wear Module
**Purpose**: Biosignal collection from wearables

**Data Sources**:
- Apple Health (iOS), Google Fit (Android)
- WHOOP API, Garmin Health
- Mock source (for testing)

**Output**: `WearSample` objects with:
- `timestamp`, `hr`, `hrvRmssd`, `respirationRate`
- `rrIntervals` (RR interval list for runtime)

**Key Classes**: `WearModule`, `WearSample`, `WearCache`

---

### 4. Phone Module
**Purpose**: Device context signals

**Collectors**:
- MotionCollector (accelerometer)
- ScreenStateTracker (on/off)
- AppFocusTracker (foreground app)
- NotificationTracker (notification events)

**Storage**: Time-windowed aggregation via PhoneCache

**Key Classes**: `PhoneModule`, `PhoneContextData`

---

### 4. Behavior Module
**Purpose**: User interaction tracking

**Event Types**:
- `TAP`, `SCROLL`, `KEY_DOWN`, `KEY_UP`
- `APP_SWITCH`, `NOTIFICATION_*`

**Pipeline**:
```
BehaviorEventStream
  → WindowAggregator (30s, 5m, 1h, 24h windows)
  → CoreRuntimeBridge
```

**Key Classes**: `BehaviorModule`, `BehaviorEvent`, `WindowAggregator`

---

### Modules now in synheart-core-runtime (Rust)

The following modules previously lived in the Dart SDK but have been migrated to `synheart-core-runtime` and are accessed via `CoreRuntimeBridge`:

- **Capability Module** -- Feature gating via signed tokens (HMAC-SHA256)
- **Consent Module** -- User permission management, default-deny, persistent
- **SRM Module** -- Self-Reference Model baselines (per-stratum buffers, median/MAD)
- **Cloud Connector** -- HMAC-signed uploads, rate limiting, offline queue, exponential backoff
- **Storage Manager** -- SQLite CRUD, WAL mode, corrupt DB recovery
- **Artifact Pipeline** -- HSI window, baseline snapshot, session summary artifacts
- **Crypto** -- SMK, URK, E2EE encryption/decryption
- **Sync Engine** -- Push/pull with URK provisioning, exponential backoff

---

## Data Flow

### Initialization

```
1. Synheart.initialize(userId, config)
   ├─ CoreRuntimeBridge.initialize(config JSON)
   │   ├─ Validate capability token
   │   ├─ Load consent from storage
   │   ├─ Initialize storage, crypto, sync
   │   └─ Create signal processing runtime
   └─ Start platform collection modules (wear, phone, behavior)

2. NO DATA COLLECTION YET
```

### Session Lifecycle

```
Synheart.startSession()
├─ CoreRuntimeBridge.startSession()
└─ Platform modules begin streaming

Data flows:
Wear → WearModule ──┐
Phone → PhoneModule ──┼──→ CoreRuntimeBridge (FFI) → synheart-core-runtime
Behavior → BehaviorModule ──┘

synheart-core-runtime → HSI JSON → native callback → onHSIUpdate stream

Synheart.stopSession()
├─ CoreRuntimeBridge.stopSession()
└─ Session artifacts + SRM snapshots persisted in Rust
```

### Signal Fusion

```
INPUT SIGNALS (Parallel)
├─ RR intervals (ms)
├─ Heart rate (bpm)
├─ Accelerometer (x, y, z)
└─ Behavior events (type, value)
     ↓ (consent & capability gated in Rust)
     ↓
CoreRuntimeBridge (dart:ffi → Rust C ABI)
synheart_core_runtime_push_rr(ts, rr_ms)
synheart_core_runtime_push_hr(ts, bpm)
synheart_core_runtime_push_accel(ts, x, y, z)
synheart_core_runtime_push_behavior(ts, event_type, value)
synheart_core_runtime_tick(ts) ← every 5 seconds
     ↓
synheart-core-runtime (Rust)
├─ Signal processing (embedded synheart-engine)
├─ Feature extraction
├─ HSV computation (6 heads)
├─ SRM baseline application
├─ Quality assessment
├─ HSI JSON serialization
├─ Artifact pipeline + storage
└─ Cloud upload (rate-limited, HMAC-signed)
     ↓
HSI JSON Output
├─ onHSIUpdate (native callback → Stream<String>)
├─ lastQuality() (quality metrics)
└─ lastHsv() (internal diagnostics)
```

---

## HSV vs HSI

### HSV (Human State Vector) - INTERNAL

**Computed by**: synheart-core-runtime (embedded synheart-engine)
**Access**: `CoreRuntimeBridge.lastHsv()` → JSON string
**Use**: Internal SDK diagnostics and quality assessment
**NOT**: Part of public SDK API

**Structure** (per head):
```json
{
  "emotion": {
    "valence": 0.65,
    "arousal": 0.42,
    "confidence": 0.85,
    "meta": {
      "inference_mode": "DETERMINISTIC",
      "model_id": "emotion-v1",
      "engine": "synheart-state-runtime",
      "engine_version": "0.1.0"
    }
  },
  "focus": {"value": 0.72, "confidence": 0.90, "meta": {...}},
  "capacity": {"value": 0.55, "confidence": 0.80, "meta": {...}},
  "recovery": {"value": 0.60, "confidence": 0.75, "meta": {...}},
  "strain": {"value": 0.30, "confidence": 0.88, "meta": {...}},
  "sleep": {"value": 0.45, "confidence": 0.70, "meta": {...}}
}
```

### HSI (Human State Interface) - PUBLIC

**Computed by**: synheart-core-runtime (Flux layer)
**Access**: `onHSIUpdate` stream (primary) or `lastQuality()` query
**Use**: Main output format for consumers
**Format**: RFC HSI 1.1 JSON with domain axes

**Structure** (abbreviated):
```json
{
  "affect": {
    "stress": {"score": 0.65, "confidence": 0.85},
    "energy": {"score": 0.42, "confidence": 0.80}
  },
  "engagement": {
    "capacity": {"score": 0.55, "confidence": 0.80},
    "focus": {"score": 0.72, "confidence": 0.90}
  },
  "physiological": {...},
  "behavioral": {...},
  "contextual": {...}
}
```

**Relationship**:
```
HSV (runtime-internal)
  ↓ (Flux reorganization)
  ↓
HSI 1.1 (public domain axes)
```

### Pre-processed Data (Internal)

**Computed by**: synheart-core-runtime (internal signal pipeline)
**Access**: `CoreRuntimeBridge.lastPreprocessed()` → JSON string
**Use**: On-device model training, R&D, feature engineering, anomaly detection
**Scope**: Internal-only; NOT part of public API

**Structure** (simplified):
```json
{
  "schema_version": "1.0.0",
  "window_start_ms": 1000,
  "window_end_ms": 11000,
  "quality": {
    "score": 0.85,
    "coverage_pct": 0.9,
    "dropout_count": 0,
    "rr_count": 10
  },
  "derived_features": {
    "hrv": {
      "rmssd_ms": 42.5,
      "sdnn_ms": 38.0,
      "pnn50": 0.25,
      "mean_rr_ms": 800.0,
      "hr_mean_bpm": 72.0
    },
    "motion": null,
    "artifact": null
  },
  "behavior_features": null,
  "srm_context": {
    "ready_count": 5,
    "total_count": 14,
    "deviations": {}
  },
  "embeddings": {
    "signal_embedding": {
      "vector": [0.1, 0.2, 0.3, ...],
      "dimension": 64,
      "space": "latent"
    }
  }
}
```

**Use Cases**:
1. **On-Device Training**: Access raw features and embeddings for per-user model fine-tuning
2. **Anomaly Detection**: Use Z-score deviations and quality scores for real-time early warning
3. **Feature Engineering**: Intermediate HRV, motion, behavior metrics for rapid validation
4. **R&D Analysis**: Export pre-processed data for offline analysis, pattern discovery

---

## RFC-0005: Four-Authority Access Control

A feature is **operational** when ALL four conditions hold:

```
FeatureOperational = Activation AND Consent AND Capability AND SessionActive

Example: WEAR feature
  Activation:  Synheart.activate(WEAR) called?        ✓
  Consent:     User granted biosignals permission?    ✓
  Capability:  Server token allows WEAR level?        ✓
  SessionActive: startSession() called?               ✓

  Result: WEAR data collection ACTIVE

  (If user revokes consent → stops immediately)
```

**Features**:
- `WEAR` → `biosignals` consent
- `BEHAVIOR` → `behavior` consent
- `PHONE_CONTEXT` → `phoneContext` consent
- `CLOUD` → `cloudUpload` consent
- `SYNI` → `syni` consent

---

## Key Design Patterns

### 1. Consent-First
- Default-deny for all consent types
- No data collection without explicit user grant
- Immediate revocation stops streams
- Persisted across app restarts

### 2. Module Dependency Injection
- Each module receives dependencies
- Enables testing and isolation
- Clear separation of concerns

### 3. Graceful Degradation
- Missing native library doesn't crash
- Pipeline operates inert (no errors)
- Standard pattern for all runtime consumers

### 4. Reactive Streams
- RxDart for async data flow
- Cold observables (late subscribers see no data)
- Hot subjects for shared streams

### 5. Persistent State
- Consent stored in SharedPreferences
- SRM baselines persisted to disk
- Survive app restart

---

## Testing Strategy

### Unit Tests (38+ passing)
- Consent gating logic
- Cloud upload pipeline (rate limiting, retry)
- Capability token validation
- Module lifecycle management

### Integration Tests
- Full signal fusion (with native library)
- SRM baseline computation
- Cloud upload round-trip

### Expected Test Failures
- CoreRuntimeBridge tests skip (native library not available in test env)
- This is expected behavior

---

## Usage Examples

### Initialize SDK

```dart
// All core logic (storage, crypto, sync, consent, pipeline) runs in synheart-core-runtime
await Synheart.initialize(
  userId: 'user_123',
  config: SynheartConfig(
    allowUnsignedCapabilities: true,  // Use capabilityToken + capabilitySecret in production
    wearConfig: WearConfig(),
    phoneConfig: PhoneConfig(),
    behaviorConfig: BehaviorConfig(),
  ),
);
```

### Start Session

```dart
await Synheart.startSession();

// Listen for HSI updates (primary output)
Synheart.onHSIUpdate.listen((hsiJson) {
  print('New HSI: $hsiJson');
});
```

### Query Diagnostics

```dart
// Get last quality metrics
final quality = Synheart.lastQuality();
print('Overall confidence: ${quality.overallConfidence}');

// Get raw HSV (internal diagnostics only)
final hsvJson = Synheart.lastHsv();
// Parse and use for internal diagnostics
```

### Stop Session

```dart
await Synheart.stopSession();
// SRM baselines persisted automatically
```

---

## Troubleshooting

### CoreRuntimeBridge Tests Skip/Fail
**Cause**: `libsynheart_core_runtime` native library not available
**Expected**: Yes, this is normal in test environment
**Resolution**: None needed for SDK; native library is bundled in production

### Consent Changes Don't Take Effect Immediately
**Expected**: Changes take effect at next `reevaluateAllFeatures()` cycle
**Workaround**: Call explicitly if needed

---

## Performance Considerations

- **Memory**: ~5-10 MB for core SDK
- **Battery**: Depends on wear data source (typically 2-5% per hour)
- **CPU**: Tick every 5 seconds is lightweight
- **Storage**: SRM snapshots ~50KB, persisted

---

## Security & Privacy

- ✅ Consent-first: All data requires explicit user grant
- ✅ Encryption: SRM snapshots encrypted in storage
- ✅ Signed uploads: HMAC-SHA256 request authentication
- ✅ Secure deletion: Consent revocation immediately stops data collection
- ✅ No third-party data sharing: All data owned by user/tenant

---

## Next Steps

1. **Review Architecture**: Understand module boundaries
2. **Review Four-Authority Model**: Understand access control
3. **Implement Consent UI**: Let users manage permissions
4. **Test Integration**: Verify with your app
5. **Monitor Production**: Use `lastQuality()` to track data quality

---

**For questions or issues, refer to the main [synheart-core](https://github.com/synheart-ai/synheart-core) documentation.**
