# Synheart Core SDK — Architecture

## Module Lifecycle

Every module follows a strict lifecycle:

```
Uninitialized → Initialized → Running → Stopped → Disposed
```

- **Uninitialized**: Module instance created but `initialize()` not yet called.
- **Initialized**: Configuration loaded, resources allocated, ready to start.
- **Running**: Actively collecting/processing data.
- **Stopped**: Data collection halted, ephemeral buffers cleared. Can be restarted.
- **Disposed**: All resources released. Terminal state.

`ModuleManager` orchestrates lifecycle transitions in dependency order using topological sort.

## Module Dependency Graph

```
capabilities ──┐
consent ────────┤
                ├── wear
                ├── phone
                ├── behavior
                └── srm
                      │
        wear ─────────┤
        behavior ─────┤
                      └── runtime
                            │
                            └── cloud (optional)
```

Modules are initialized top-down and stopped bottom-up.

## Data Flow

```
Wear (HR, HRV, RR)   ──┐
Phone (motion, screen) ──┼──→ RuntimeBridge (FFI) ──→ synheart-runtime (Rust)
Behavior (events)     ──┘         │
                                  ├──→ HSI JSON ──→ hsiStream
                                  │
                                  ├──→ FocusHead (optional) ──→ focusStream
                                  └──→ EmotionHead (optional) ──→ emotionStream
```

1. **Wear/Phone/Behavior** modules push raw samples into `RuntimeBridge`.
2. **RuntimeBridge** calls the synheart-runtime C ABI via FFI (dlsym / JNA / dart:ffi).
3. **synheart-runtime** fuses signals into an HSI frame every 5 seconds (configurable).
4. The HSI JSON string is emitted on `hsiStream` / `onHSIUpdate`.
5. Optional **FocusHead** and **EmotionHead** subscribe to the HSI stream and produce interpretation signals.

## SRM Baseline Persistence

The Self-Reference Model (SRM) maintains per-user baselines:

- **Auto-load on start**: `RuntimeModule.onStart()` restores the SRM snapshot from platform storage (UserDefaults / SharedPreferences / FlutterSecureStorage).
- **Auto-save on stop**: `RuntimeModule.onStop()` persists the current SRM snapshot.
- **Per-stratum buffers**: Bounded circular buffers partitioned by time stratum (e.g., morning, afternoon, evening).
- **Reference statistics**: Median and MAD (Median Absolute Deviation) computed per stratum for robust baselines.

## Consent System

Consent follows an explicit opt-in model:

- **ConsentSnapshot** holds boolean flags for each consent type: `biosignals`, `behavior`, `phoneContext`, `focusEstimation`, `emotionEstimation`, `cloudUpload`, `syni`.
- All consents default to `false` — collection requires explicit grant.
- Consent changes trigger `reevaluateAllFeatures()`, which starts/stops modules based on the four-authority model.

### Four-Authority Model (RFC-0005)

A feature is **operational** when all four authorities agree:

```
FeatureOperational = Activated AND HasConsent AND CapabilityAllowed AND SessionActive
```

- **Activated**: Developer called `activate(feature)`.
- **HasConsent**: User granted the required consent type.
- **CapabilityAllowed**: The capability token permits the feature.
- **SessionActive**: A session is currently running.

## Cloud Upload Pipeline

```
HSI JSON ──→ ConsentGate ──→ RateLimiter ──→ UploadQueue ──→ UploadClient
                                                │
                                                ├── FIFO queue (default 100 items)
                                                ├── HMAC-SHA256 signed requests
                                                ├── Exponential backoff (max 3 retries)
                                                └── Network monitoring with auto-flush
```

- Uploads are gated by `cloudUpload` consent.
- The queue persists to disk for offline resilience.
- Network availability changes trigger automatic queue flush.
