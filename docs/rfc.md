## **1. Summary**

The **Human State Interface (HSI)** is Synheart’s unified, on-device pipeline for understanding human internal state in real time.

HSI:

- Ingests **biosignals**, **behavioral signals**, and **context signals**
- Cleans, normalizes, and fuses them into a **base state representation**
- Exposes this as a **Human State Vector (HSV)** stream
- Feeds higher-level models:
    - **Synheart Emotion (Emotion Engine)**
    - **Synheart Focus (Focus Engine)**
    - **Syni (LLM layer)**

**Key principle:**

> HSI = how we *measure and represent*
> 

> Emotion & Focus = models that sit *on top*
> 

---

## **2. Motivation**

Modern AI understands language, not humans.

We already have:

- **Wear SDK / Wear Service** for HR, HRV, motion, sleep
- **Behavior SDK** for typing cadence, scroll velocity, idle gaps
- **LLMs (Syni)** for conversation
- **Synheart Emotion & Focus** models

Without HSI, each subsystem pulls raw signals directly and re-implements:

- ingestion
- preprocessing
- normalization
- feature extraction
- fusion

This leads to:

- tight coupling between models and data sources
- duplicated logic
- fragmented interpretations of “state”
- poor scalability when adding new models or devices

**HSI exists to:**

- centralize all signal processing and fusion
- create a **single canonical Human State Vector (HSV)**
- turn Emotion & Focus into **“heads”** on top of a shared state engine
- give Syni and other apps one **clean human-state API** instead of raw signals

---

## **3. Goals & Non-Goals**

### **3.1 Goals**

- Define a **standard multimodal pipeline** for human state
- Produce a **real-time HSV** stream consumable by all Synheart components
- Make **Synheart Emotion & Focus** thin heads on top of HSI
- Keep processing **on-device-first**, with optional cloud export of aggregated HSV only
- Provide a **simple SDK** for apps to subscribe to human state
- Support **future heads** (fatigue, burnout, clarity, etc.) without changing ingestion

### **3.2 Non-Goals**

- HSI is **not** an LLM
- HSI is **not** a wearable connector (that’s Wear Service/SDK)
- HSI does **not** perform diagnoses or medical classification
- HSI does **not** store raw biosignals by default

---

## **4. Layered Architecture**

The stack is explicitly structured in **three model layers** plus the LLM layer:

1. **HSI Core (State Engine)**
2. **Emotion Engine (Synheart Emotion)**
3. **Focus Engine (Gamma Focus)**
4. **Syni LLM Layer**

### **4.1 HSI Core**

HSI Core is responsible for:

### **4.1.1 Ingestion**

- From **Synheart Wear SDK / Service**
    - HR, HRV, R-R intervals
    - accelerometer / motion
    - sleep stage metadata
    - respiration rate (where available)
- From **Synheart Phone SDK**
    - keystroke / tap cadence
    - typing bursts
    - scroll velocity
    - idle gaps between interactions
    - app switch events
- From **Context Adapters**
    - conversation timing (reply delays, bursts, interrupts)
    - device state (foreground/background, DND/focus mode, screen on/off)
    - user patterns (average session length, time-of-day bias, baseline cadence)

### **4.1.2 Processing & Normalization**

- Synchronization and windowing
- Noise reduction and artifact handling
- Vendor-agnostic normalization (different wearables, devices)
- Baseline alignment (per-user resting metrics, when available)

### **4.1.3 Fusion & Embedding**

HSI computes:

- Low-level derived metrics (e.g., RMSSD, SDNN, motion energy, burstiness indices)
- A deep **latent embedding: hsi_embedding**
    
    – produced by a **Tiny Transformer** or **CNN-LSTM** that fuses biosignals, behavior, and context
    

The output of HSI Core is an **initial HSV**:

```
{
  "version": "1.0.0",
  "timestamp": 1731459200123,
  "emotion": {},          // not yet filled
  "focus": {},            // not yet filled
  "behavior": {
    "typing_cadence": 0.43,
    "typing_burstiness": 0.62,
    "scroll_velocity": 0.31,
    "idle_gaps": 1.4,
    "app_switch_rate": 0.18
  },
  "context": {
    "overload": 0.0,
    "frustration": 0.0,
    "engagement": 0.0,
    "conversation": {
      "avg_reply_delay_sec": 4.8,
      "burstiness": 0.67,
      "interrupt_rate": 0.12
    },
    "device_state": {
      "foreground": true,
      "screen_on": true,
      "focus_mode": "work"
    },
    "user_patterns": {
      "morning_focus_bias": 0.71,
      "avg_session_minutes": 18.4,
      "baseline_typing_cadence": 0.39
    }
  },
  "meta": {
    "session_id": "sess-123",
    "device": { "platform": "ios" },
    "sampling_rate_hz": 2,
    "hsi_embedding": [0.12, -0.03, ...] // internal latent
  }
}
```

> This is the shared “state bus”.
> 

> Emotion and Focus never touch raw sensors directly; they consume this HSI output.
> 

---

### **4.2 Emotion Engine (Synheart Emotion Head)**

The **Emotion Engine** is a model head that subscribes to the **HSI Core stream**.

### **Inputs**

- hsi_embedding
- HR/HRV over short time windows
- Short history buffer of recent HSVs

### **Outputs →**

### **hsv.emotion**

```
"emotion": {
  "stress": 0.21,
  "calm": 0.74,
  "engagement": 0.68,
  "activation": 0.45,
  "valence": 0.31
}
```

### **Data Flow**

Conceptually:

```
hsi.onStateUpdate { baseHsv in
    let features = emotionFeaturizer.from(hsv: baseHsv)
    let scores = emotionModel.predict(features)
    var hsv = baseHsv
    hsv.emotion = scores
    emotionStream.emit(hsv)
}
```

The **emotionStream** now carries HSVs with the emotion block populated.

---

### **4.3 Focus Engine (Synheart Focus Head)**

The **Focus Engine** is another model head, building on HSI (and optionally on Emotion output).

### **Inputs**

- hsi_embedding
- Behavioral metrics (typing bursts, idle gaps, app switching)
- Short history of HSVs
- Optional task label / app metadata (e.g., “coding”, “reading”, “study mode”)

### **Outputs →**

### **hsv.focus**

```
"focus": {
  "score": 0.68,
  "cognitive_load": 0.32,
  "clarity": 0.71,
  "distraction": 0.19
}
```

### **Data Flow**

Conceptually (one simple wiring):

```
emotionStream.onUpdate { hsvWithEmotion in
    let features = focusFeaturizer.from(hsv: hsvWithEmotion)
    let scores = focusModel.predict(features)
    var hsv = hsvWithEmotion
    hsv.focus = scores
    finalStateStream.emit(hsv)
}
```

Alternatively, Focus can read directly from the HSI stream; the architecture keeps that flexible. The important part is:

- **HSI**: shared representation
- **Emotion & Focus**: heads that read that representation and populate parts of HSV

---

### **4.4 Syni LLM Layer**

Once Emotion and Focus have populated HSV, the **final HSV** is available to the Syni LLM layer and the Synheart Dashboard.

Example integration:

```
let hsv = hsi.currentState()

syni.sendMessage(
    text: userText,
    state: hsv  // emotion + focus + behavior + context
)
```

Syni uses HSV to adapt:

- **Tone**: calmer, more validating when stress / frustration are high
- **Pacing**: slower, more structured responses during high_focus states
- **Complexity**: more summaries and chunking under high cognitive_load / overload
- **Prompts**: suggest breaks, reflections, or reframing when stress + overload persist

This is where **raw HSI understanding** becomes **human-aware AI behavior**.

---

## **5. Human State Vector (HSV) Spec (Summary, but check the docs down)**

Top-level schema:

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

- emotion: populated by Emotion Engine
- focus: populated by Focus Engine
- behavior: from Phone SDK + HSI processing
- context: from Context Adapters + HSI processing
- meta: device + session metadata + hsi_embedding (internal)

(Use the detailed HSV spec we already have it as an appendix.)

---

## **6. Developer Experience**

### **Start HSI and listen to HSV updates**

```
let hsi = HSI.shared
hsi.configure(appKey: "YOUR_APP_KEY")
hsi.start()

hsi.onStateUpdate { hsv in
    print("Stress:", hsv.emotion.stress)
    print("Focus:", hsv.focus.score)
}
```

### **Optional: Cloud sync of HSV (no raw data)**

```
hsi.enableCloudSync()
```

---

## **7. Privacy & Security**

- All ingestion, fusion, and Emotion/Focus inference are **on-device** by default
- No raw biosignals leave the device without explicit consent
- Cloud sync uses **aggregated HSV**, optionally SWIP-signed for provenance
- HSI is strictly **non-medical**; no diagnoses or clinical labels

---

## **8. Open-Source vs Proprietary**

- **Wear SDK**, **Phone SDK**, and basic context adapters: open source (Apache 2.0)
- **HSI Core runtime + fusion model**: proprietary
- **Emotion & Focus heads**: proprietary
- **HSV schema**: open spec
- **Public APIs**: stable and documented for ecosystem partners

---

## **9. Future Extensions**

- Additional heads: fatigue, burnout risk, emotional volatility, recovery
- Audio prosody as another input modality
- Personalized models via on-device fine-tuning
- RLHF-style adaptation to user preferences (still on-device)

---

## **10. Risks**

- Battery usage if sampling or models are too heavy
- Vendor changes to wearable APIs
- Ethical use concerns (e.g., manipulation, surveillance)
- Regulatory environments around biosignals and mental state modeling

Mitigations:

- lightweight models, adjustable sampling modes
- strict opt-in and transparent consent flows
- policy constraints on use (no invisible state-based optimization without the user’s knowledge)

---

## **11. Decision Log**

- Architecture is now **explicitly layered**:
    - HSI Core → Emotion & Focus heads → final HSV → Syni
- Emotion and Focus no longer depend directly on Wear SDK; they depend on **HSI**
- HSV is the **single canonical representation** of human state
- Context is handled via dedicated **Context Adapters** (conversation timing, app state, user patterns)

---

## **12. Conclusion**

HSI turns fragmented biosignals, behavioral data, and app context into a **single shared language of human state**, the HSV.

This allows Synheart to:

- Treat Emotion and Focus as **modular heads**
- Feed Syni with rich, structured human context
- Add new human-state models without rewriting ingestion
- Offer developers a **simple, powerful human-layer API**

**HSI is the human-state operating layer for Synheart.**

---

---

[**TECHNICAL SPEC FOR HSV (Human State Vector)**](https://www.notion.so/TECHNICAL-SPEC-FOR-HSV-Human-State-Vector-2aa2159f38528082ac7bf17944053c8a?pvs=21)

[**Why HSI Exists**](https://www.notion.so/Why-HSI-Exists-2aa2159f385280f2a294f86d25dec552?pvs=21)

[**Human State Architecture Overview**](https://www.notion.so/Human-State-Architecture-Overview-2aa2159f385280eda8d0d12c87e8a46b?pvs=21)