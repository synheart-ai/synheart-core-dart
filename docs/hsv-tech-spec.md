---

## **Overview**

The **Human State Vector (HSV)** is the unified output representation of the Human State Interface (HSI).

Every Synheart model (Emotion, Focus, Syni LLM Layer) consumes HSV as its canonical input.

HSV is:

- **Lightweight** (0.5–2 KB per update)
- **Real-time** (1–5 Hz)
- **Multimodal** (biosignal + behavioral + context)
- **Normalized** (per-age, per-device, per-session baselines)
- **Private** (no raw signals included)

---

## **Schema**

### **Top-Level Structure**

```
{
  "version": "1.0.0",
  "timestamp": 1731459200123,
  "emotion": { ... },
  "focus": { ... },
  "behavior": { ... },
  "context": { ... },
  "meta": { ... }
}
```

---

## **1. Emotion Block**

Output from Synheart Emotion Engine.

```
"emotion": {
  "stress": 0.0,          // 0–1
  "calm": 0.0,            // 0–1
  "engagement": 0.0,      // 0–1
  "activation": 0.0,      // arousal-like measure
  "valence": 0.0          // positive/negative direction
}
```

**Notes:**

- stress and calm are **not symmetric** (both can be low).
- activation and valence enable 2D emotion space modeling.

---

## **2. Focus Block**

Output from Synheart Gamma Focus Engine.

```
"focus": {
  "score": 0.0,            // 0–1
  "cognitive_load": 0.0,   // 0–1
  "clarity": 0.0,          // clarity of thinking
  "distraction": 0.0       // momentary attentional drift
}
```

**Notes:**

- score ≠ productivity; it’s a **neurocognitive attention estimate**.
- cognitive_load can be high even if score is high.

---

## **3. Behavior Block**

Derived from Synheart Phone SDK.

```
"behavior": {
  "typing_cadence": 0.0,      // normalized taps/sec
  "typing_burstiness": 0.0,   // 0–1
  "scroll_velocity": 0.0,     // normalized units
  "idle_gaps": 0.0,           // seconds between interactions
  "app_switch_rate": 0.0      // switches/min (normalized)
}
```

---

## **4. Context Block**

Derived from runtime + interaction pattern.

```
"context": {
  "overload": 0.0,      // cognitive overwhelm
  "frustration": 0.0,   // inferred from cadence + context
  "engagement": 0.0,    // real-time immersion
  "conversation_tone": "neutral",  // optional
  "device_state": {
    "battery": 0.72,
    "movement": "stationary"
  }
}
```

---

## **5. Meta Block**

```
"meta": {
  "session_id": "abc123",
  "device": {
    "platform": "ios",
    "model": "iPhone 16 Pro"
  },
  "sampling_rate_hz": 5
}
```

---

## **HSV Update Frequency**

- **High-frequency mode:** 5 Hz (Emotion + Focus)
- **Balanced mode:** 2 Hz (default)
- **Low-power mode:** 0.5 Hz

---

## **HSV Transport Modes**

- Local Callback
- Shared Memory / Streams
- WebSocket (Wear → Phone)
- Optional Cloud Upload (SWIP-signed)

---

# **2. HSI SDK API REFERENCE**

**Document ID:** HSI-SDK-API-v1

**Platforms:** iOS, Android, Flutter, Kotlin Multiplatform (2026)

---

# **Setup**

### **iOS (Swift)**

```
import SynheartHSI

let hsi = HSI.shared
hsi.configure(appKey: "YOUR_APP_KEY")
```

### **Android (Kotlin)**

```
val hsi = HSI.getInstance(context)
hsi.configure(appKey = "YOUR_APP_KEY")
```

---

# **Core APIs**

## **1. Start / Stop**

```
hsi.start()      // begins HSI processing pipeline
hsi.stop()       // stops ingestion + fusion
```

---

## **2. Listen to Human State Updates**

```
hsi.onStateUpdate { hsv in
    print(hsv.emotion.stress)
    print(hsv.focus.score)
}
```

Kotlin:

```
hsi.onStateUpdate { hsv ->
    Log.d("Stress", hsv.emotion.stress.toString())
}
```

---

## **3. Get Most Recent HSV Snapshot**

```
let current = hsi.currentState()
```

---

## **4. Enable Cloud Sync (Optional)**

```
hsi.enableCloudSync()
```

This sends **only HSV**, SWIP-signed, never raw biosignals.

---

## **5. Set Personal Baseline (Optional)**

```
hsi.setBaseline(type: .calm)
```

Use case: improving HRV-based inference based on personalized rest state.

---

## **6. Configure Modes**

```
hsi.setMode(.highFrequency)   // 5 Hz
hsi.setMode(.balanced)        // 2 Hz
hsi.setMode(.lowPower)        // 0.5 Hz
```

---

## **7. Register Custom Features (Advanced)**

Let developers fuse their own signals.

```
hsi.registerFeature(name: "custom_metric") { window in
    return computeSomething(window)
}
```

---

## **8. Session Management**

```
hsi.startSession(id: "session-001")
hsi.endSession()
```

---

## **9. Debug / Diagnostics**

```
hsi.debug.enableLogs = true
```

---

# **SDK Events**

| **Event** | **Description** |
| --- | --- |
| onStateUpdate | Fires when new HSV is generated |
| onWearConnected | Wearable stream active |
| onWearDisconnected | Lost wearable connection |
| onBaselineUpdated | Baseline changed |
| onError | Battery, permission, or signal issues |

---

# **Error Codes**

| **Code** | **Meaning** | **Example** |
| --- | --- | --- |
| HSI_ERR_NO_WEARABLE | Wearable stream missing | Watch disconnected |
| HSI_ERR_LOW_SIGNAL | Bad HRV or too much motion | Gym movement |
| HSI_ERR_NO_PERMISSION | Motion/Health permission off | User denied |
| HSI_ERR_CLOUD_DISABLED | Cloud sync unavailable | Offline |

---

# **Example: LLM Integration**

```
syni.sendMessage(
   text: "Hey",
   state: hsi.currentState()   // HSV used internally to adjust response
)
```

---