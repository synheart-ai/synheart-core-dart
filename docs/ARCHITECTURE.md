# Synheart Core SDK - Architecture Guide

**Last Updated**: February 2026
**Version**: 1.2.0

---

## Overview

The Synheart Core SDK (Dart) is a modular, consent-first framework for collecting biosignals, device context, and user behavior, fusing them through synheart-runtime (Rust) to compute human state.

**Key Principle**:
> All inference computation happens in synheart-runtime (Rust C ABI). SDKs coordinate data collection and distribution.

---

## Architecture Layers

```
┌─────────────────────────────────────────┐
│         Application (Your App)          │
│  onHSIUpdate, lastQuality, consent UI   │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│      Synheart Core SDK (Dart/FFI)       │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  Gatekeeping Modules            │   │
│  │  • Capability (feature gating)  │   │
│  │  • Consent (permissions)        │   │
│  └──────────────┬──────────────────┘   │
│                 │                       │
│  ┌──────────────▼──────────────────┐   │
│  │  Collection Modules              │   │
│  │  • Wear (wearables)             │   │
│  │  • Phone (motion, context)      │   │
│  │  • Behavior (interactions)      │   │
│  └──────────────┬──────────────────┘   │
│                 │                       │
│  ┌──────────────▼──────────────────┐   │
│  │  Runtime Bridge (dart:ffi)      │   │
│  │  synheart_runtime_push_*()      │   │
│  │  synheart_runtime_tick()        │   │
│  └──────────────┬──────────────────┘   │
│                 │                       │
│  ┌──────────────▼──────────────────┐   │
│  │  Distribution Modules            │   │
│  │  • SRM (baselines)              │   │
│  │  • Cloud (uploads)              │   │
│  └──────────────┬──────────────────┘   │
└──────────────────┬──────────────────────┘
                   │ (C ABI)
┌──────────────────▼──────────────────────┐
│    synheart-runtime (Rust)              │
│  • Signal processing                    │
│  • Feature extraction                   │
│  • HSV computation (6 heads)            │
│  • HSI 1.1 serialization                │
└─────────────────────────────────────────┘
```

---

## Core Modules

### 1. Capability Module
**Purpose**: Feature gating via signed tokens

- Validates server-signed capability tokens (HMAC-SHA256)
- Maps SDK features to capability levels: `NONE`, `CORE`, `EXTENDED`, `RESEARCH`
- Controls access to: wear, phone, behavior, cloud, HSI features
- Falls back to unsigned capabilities for development

**Key Class**: `CapabilityModule`

---

### 2. Consent Module
**Purpose**: User permission management (single source of truth)

**Consent Types**:
- `biosignals` — Heart rate, HRV collection
- `behavior` — User interaction tracking
- `phoneContext` — Device motion, screen state, app context
- `cloudUpload` — Data transmission
- `syni` — Personalization hooks

**Key Properties**:
- Default-deny (all false) for safety
- Persistent storage (SharedPreferences)
- Change notifications via listeners
- Gating enforced at multiple levels (module start, data read, upload)

**Key Class**: `ConsentModule`

---

### 3. Wear Module
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

### 5. Behavior Module
**Purpose**: User interaction tracking

**Event Types**:
- `TAP`, `SCROLL`, `KEY_DOWN`, `KEY_UP`
- `APP_SWITCH`, `NOTIFICATION_*`

**Pipeline**:
```
BehaviorEventStream
  → WindowAggregator (30s, 5m, 1h, 24h windows)
  → RuntimeModule
```

**Key Classes**: `BehaviorModule`, `BehaviorEvent`, `WindowAggregator`

---

### 6. Runtime Module
**Purpose**: FFI bridge to synheart-runtime

**Responsibilities**:
1. Subscribe to wear/behavior streams
2. Push data into native via `synheart_runtime_push_*()` functions
3. Periodic tick (every 5s): `synheart_runtime_tick()`
4. Emit HSI JSON when available

**Functions**:
- `synheart_runtime_push_rr(handle, ts_ms, rr_ms)`
- `synheart_runtime_push_hr(handle, ts_ms, bpm)`
- `synheart_runtime_push_accel(handle, ts_ms, x, y, z)`
- `synheart_runtime_push_behavior(handle, ts_ms, event_type, value)`
- `synheart_runtime_tick(handle, now_ms)` → HSI JSON string

**Graceful Degradation**: If native library not available, pipeline is inert (no errors)

**Key Classes**: `RuntimeModule`, `RuntimeBridge`

---

### 7. SRM Module
**Purpose**: Self-Reference Model (personal baselines)

**Features**:
- Per-stratum bounded buffers (quality-gated windows)
- Robust reference statistics (median/MAD per metric)
- Baseline status: `EMPTY` → `WARMING` → `READY`
- Persistent snapshot save/restore
- Distinct calendar day tracking

**Key Classes**: `SRMModule`, `SRMSnapshot`, `SRMBaseline`

---

### 8. Cloud Connector Module
**Purpose**: Secure HSI uploads to platform

**Architecture**:
```
RuntimeModule (HSI JSON)
  → RateLimiter (per window type)
  → NetworkMonitor (online/offline detection)
  → UploadQueue (FIFO, max 100, persistent)
  → UploadClient (HMAC-SHA256 signed)
  → Platform API
```

**Features**:
- HMAC-SHA256 request signing
- Consent & capability enforcement
- Rate limiting per window type
- Exponential backoff (max 3 retries)
- Offline queue with auto-flush
- Persistence (survives app restart)

**Key Classes**: `CloudConnectorModule`, `UploadClient`, `UploadQueue`, `RateLimiter`

---

## Data Flow

### Initialization

```
1. Synheart.initialize(userId, config)
   ├─ Validate capability token
   ├─ Load consent from storage
   ├─ Create all modules
   └─ Register with ModuleManager

2. ModuleManager.initializeAll()
   └─ Topologically sort dependencies
   └─ Call module.initialize() in order

3. NO DATA COLLECTION YET
```

### Session Lifecycle

```
Synheart.startSession()
├─ ModuleManager.startAll()
└─ All modules begin streaming

Data flows:
Wear → WearModule → RuntimeModule → RuntimeBridge → synheart-runtime
Phone → PhoneModule → RuntimeModule → RuntimeBridge → synheart-runtime
Behavior → BehaviorModule → RuntimeModule → RuntimeBridge → synheart-runtime

synheart-runtime → HSI JSON → onHSIUpdate stream → CloudConnector

Synheart.stopSession()
├─ ModuleManager.stopAll()
└─ Persist SRM snapshots
```

### Signal Fusion

```
INPUT SIGNALS (Parallel)
├─ RR intervals (ms)
├─ Heart rate (bpm)
├─ Accelerometer (x, y, z)
└─ Behavior events (type, value)
     ↓ (consent & capability gated)
     ↓
RuntimeBridge (dart:ffi → Rust C ABI)
synheart_runtime_push_rr(ts, rr_ms)
synheart_runtime_push_hr(ts, bpm)
synheart_runtime_push_accel(ts, x, y, z)
synheart_runtime_push_behavior(ts, event_type, value)
synheart_runtime_tick(ts) ← every 5 seconds
     ↓
synheart-runtime (Rust)
├─ Signal processing
├─ Feature extraction
├─ HSV computation (6 heads)
├─ SRM baseline application
├─ Quality assessment
└─ HSI JSON serialization
     ↓
HSI JSON Output
├─ onHSIUpdate (Stream<String>)
├─ lastQuality() (quality metrics)
├─ lastHsv() (internal diagnostics)
└─ Cloud upload (rate-limited)
```

---

## HSV vs HSI

### HSV (Human State Vector) - INTERNAL

**Computed by**: synheart-runtime
**Access**: `RuntimeBridge.lastHsv()` → JSON string
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

**Computed by**: synheart-runtime (Flux layer)
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

**Computed by**: synheart-runtime (internal signal pipeline)
**Access**: `RuntimeBridge.lastPreprocessed()` → JSON string
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
- RuntimeBridge tests skip (native library not available in test env)
- This is expected behavior

---

## Usage Examples

### Initialize SDK

```dart
final synheart = Synheart();

await synheart.initialize(
  userId: 'user_123',
  config: SynheartConfig(
    enableWear: true,
    enablePhone: true,
    enableBehavior: true,
    cloudConfig: CloudConfig(
      tenantId: 'your_tenant',
      hmacSecret: 'your_secret',
      subjectId: 'user_123',
    ),
  ),
);
```

### Start Session

```dart
await synheart.startSession();

// Listen for HSI updates (primary output)
synheart.onHSIUpdate.listen((hsiJson) {
  print('New HSI: $hsiJson');
});
```

### Query Diagnostics

```dart
// Get last quality metrics
final quality = synheart.lastQuality();
print('Overall confidence: ${quality.overallConfidence}');

// Get raw HSV (internal diagnostics only)
final hsvJson = synheart.lastHsv();
// Parse and use for internal diagnostics
```

### Stop Session

```dart
await synheart.stopSession();
// SRM baselines persisted automatically
```

---

## Troubleshooting

### RuntimeBridge Tests Skip/Fail
**Cause**: synheart-runtime native library not available
**Expected**: Yes, this is normal in test environment
**Resolution**: None needed for SDK; native library is bundled in production

### Cloud Upload Not Working
**Check**:
1. User granted `cloudUpload` consent
2. Capability token allows `CLOUD` feature
3. `CloudConfig` provided during initialization
4. Network is available (check `isOnline`)

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
