# Core ↔ synheart-runtime alignment

This document describes how **synheart-core-dart** aligns with the **synheart-runtime** C ABI and lists any issues that require changes in the runtime (or its dependency **synheart-session-runtime**).

---

## 1. Config (synheart_runtime_new)

| Runtime expects (c_api.rs) | Core sends (RuntimeConfig.toJson) | Status |
|----------------------------|-----------------------------------|--------|
| `window_ms` (i64, default 60000) | `window_ms`: `SynheartDefaults.runtimeWindowMs` (10000) | ✅ Aligned |
| `step_ms` (i64, default 5000) | `step_ms`: `SynheartDefaults.runtimeStepMs` (10000) | ✅ Aligned |
| `subject_id` (string) | `subject_id`: `userId` from init | ✅ Aligned |
| `session_id` (string) | `session_id`: `sess_${DateTime.now().millisecondsSinceEpoch}` | ✅ Aligned |
| `behavior_enabled` (bool, default true) | `behavior_enabled`: true | ✅ Aligned |

Core does **not** pass `window_ms`/`step_ms` explicitly at the call site; they come from `RuntimeConfig` defaults (`lib/src/core/defaults.dart`: `runtimeWindowMs = 10000`, `runtimeStepMs = 10000`). The JSON sent to `synheart_runtime_new` therefore includes all five fields.

---

## 2. Push API

| Runtime C function | Core usage | Status |
|--------------------|------------|--------|
| `synheart_runtime_push_rr(handle, ts_ms, rr_ms)` | When `WearSample` has RR intervals: one `push_rr` per interval. When only HR: one `push_rr(ts_ms, 60000/hr)` (clamped to valid RR range). | ✅ Aligned |
| `synheart_runtime_push_hr(handle, ts_ms, bpm)` | Called only when RR intervals are also present (HR + RR from source). When only HR, Core sends derived `push_rr` instead. | ✅ Aligned |
| `synheart_runtime_push_accel(handle, ts_ms, x, y, z)` | Not used by Core (no accel stream wired). | ✅ Optional |
| `synheart_runtime_push_behavior(handle, ts_ms, event_type, value)` | Called for every behavior event; `event_type` and `value` mapped below. | ✅ Aligned |

**Timestamps:** Core enforces **monotonically increasing** `ts_ms` for wear data. If the wear source reuses the same timestamp (e.g. Health returns the same latest point every poll), Core replaces it with `DateTime.now().millisecondsSinceEpoch` so that `ts_ms > last_ingest_ts_ms`. The runtime rejects out-of-order events (`accept_ts` in pipeline.rs).

**Behavior event_type mapping (Core → Runtime):**

- `tap`, `keyDown`, `keyUp` → **2** (Touch), value 1.0  
- `scroll` → **5** (Scroll), value = `metadata['delta']` or 1.0  
- `appSwitch` → **3** (AppSwitch), value 1.0  
- `notificationReceived`, `notificationOpened` → **4** (NotificationReceived), value 1.0  

Runtime documents 0=ScreenOn, 1=ScreenOff, 2=Touch, 3=AppSwitch, 4=NotificationReceived, 5=Scroll, 6=Swipe, 7=Call. Core does not send 0, 1, 6, 7; unknown types are ignored in the runtime (`_ => return`).

---

## 3. Tick and query

| Runtime | Core | Status |
|---------|------|--------|
| `synheart_runtime_tick(handle, now_ms)` | Called every 5 s with `DateTime.now().millisecondsSinceEpoch` | ✅ Aligned |
| `synheart_runtime_last_quality` | Used on stop / when frameCount==0 for logging | ✅ Aligned |
| `synheart_runtime_last_preprocessed` | Used for debug when no HSI yet | ✅ Aligned |
| `synheart_runtime_frame_count` | Used for logging | ✅ Aligned |
| `synheart_runtime_free_string` | Called on every returned string | ✅ Aligned |

---

## 4. SRM (optional symbols)

Core uses `synheart_runtime_export_srm_snapshot`, `synheart_runtime_load_srm_snapshot` if present. Lookup is optional; if the symbol is missing, Core skips save/load. No change required in the runtime for Core to work.

---

## 5. Summary: Core is aligned

- Config JSON keys and types match the runtime’s expectations.  
- Push calls use the same types (i64 `ts_ms`, f64 for values, i32 `event_type`).  
- Timestamps are monotonic for wear data.  
- Tick uses epoch ms; strings are freed after use.  

No changes are required in **synheart-core-dart** for API alignment with the current runtime contract.

---

## 6. For the Rust / session-runtime developer

**Observed issue:** The “Last preprocessed” JSON for completed windows shows:

- `quality.rr_count` = 0  
- `quality.coverage_pct` = 0  
- `derived_features.hrv` = null  
- `behavior_features` = null  
- SRM deviations all `"observed":0`, `"status":"Empty"`  

**Confirmed:** Core now sends **explicit** `push_rr(ts_ms, rr_ms)` when the wear source provides only HR (no RR intervals). Example log line:  
`[Runtime in] push_rr ts_ms=1772199304548 rr_ms=529.49 (from hr=113.31)`  
So the pipeline receives explicit RR (e.g. ~1 per second, 59 samples in a ~1 min session). Window bounds in the same run are e.g. `window_start_ms=1772199295103`, `window_end_ms=1772199305103`; pushed `ts_ms` values fall within that range. **Despite this, preprocessed output still has rr_count=0.** So the bug is in **synheart-session-runtime**: either RR are not being included in the window, or they are not counted when building the FeatureSet.

**Likely cause:** In **synheart-session-runtime**:

1. **RR/quality:** RR received via `push_rr` are not counted for the window (e.g. wrong time base, or FeatureSet built before RR are associated with the window).  
   **Ask:** Ensure all RR in the session buffer whose `ts_ms` is in `[window_start_ms, window_end_ms]` are included in `quality.rr_count`, `coverage_pct`, and HRV.

2. **Window alignment:** Window bounds may use a different time base than the epoch-ms `ts_ms` from the pipeline (e.g. relative to session start).  
   **Ask:** Confirm window bounds are in the same epoch-ms domain as `push_rr`/`tick(now_ms)`. Log per-window RR count to verify.

3. **Behavior:** If behavior features are aggregated only from events whose `ts_ms` lies in the window, confirm that Core’s behavior timestamps (also `DateTime.now()` at event time) are in the same epoch-ms range as the window. If the session runtime uses a different time base for windows (e.g. relative to session start), that could explain null behavior_features.

**Suggested checks in synheart-session-runtime:**

- When building the FeatureSet for a completed window, are all RR intervals in the session buffer whose `ts_ms` is in `[window_start_ms, window_end_ms]` counted?  
- Is the window time base the same as the `ts_ms` from the pipeline (epoch milliseconds)?  
- Log for the last completed window: number of RR with `ts_ms` in `[window_start_ms, window_end_ms]` and number of behavior events in the same range. If these are 0, fix window alignment; if they are >0 but FeatureSet still has rr_count=0, fix aggregation.

Once session-runtime includes these RR in the FeatureSet and uses the same window bounds as the preprocessed JSON, the preprocessed output and HSI should show non-zero quality and features.
