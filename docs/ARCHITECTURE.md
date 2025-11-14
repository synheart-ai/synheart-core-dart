# HSI Flutter Architecture

This document describes the architecture of the Human State Interface (HSI) Flutter implementation, based on the RFC.

## Overview

HSI Flutter implements a layered architecture where:

1. **HSI Core (State Engine)** processes raw signals and produces base HSV
2. **Emotion Head** (using `synheart_emotion`) populates emotion state
3. **Focus Head** (using `synheart_focus`) populates focus state
4. **Final HSV** is emitted to subscribers

## Architecture Layers

### 1. HSI Core (`lib/src/core/`)

#### State Engine (`state_engine.dart`)
- Orchestrates ingestion, processing, and fusion
- Produces base HSV stream
- Manages lifecycle (start/stop)

#### Ingestion Service (`ingestion.dart`)
- Collects signals from:
  - Synheart Wear SDK/Service (HR, HRV, motion, sleep)
  - Synheart Phone SDK (typing, scrolling, app switches)
  - Context Adapters (conversation timing, device state, user patterns)
- Emits raw `SignalData` stream

#### Signal Processor (`processors.dart`)
- Synchronization and windowing
- Noise reduction and artifact handling
- Vendor-agnostic normalization
- Baseline alignment
- Calculates derived metrics (RMSSD, SDNN, burstiness indices)

#### Fusion Engine (`processors.dart`)
- Computes low-level derived metrics
- Generates `hsi_embedding` (latent representation)
- Creates base HSV from processed signals

### 2. Model Heads (`lib/src/heads/`)

#### Emotion Head (`emotion_head.dart`)
- Subscribes to base HSV stream from State Engine
- Extracts features from HSV
- Calls `synheart_emotion` package to predict emotion
- Populates `hsv.emotion` with:
  - stress, calm, engagement, activation, valence
- Emits HSV with emotion populated

#### Focus Head (`focus_head.dart`)
- Subscribes to emotion stream (or base HSV stream)
- Extracts features from HSV (including emotion)
- Calls `synheart_focus` package to predict focus
- Populates `hsv.focus` with:
  - score, cognitive_load, clarity, distraction
- Emits final HSV

### 3. Data Models (`lib/src/models/`)

#### HSV (`hsv.dart`)
- `HumanStateVector`: Main data structure
- `MetaState`: Device, session, embeddings
- `DeviceInfo`: Platform information

#### Emotion (`emotion.dart`)
- `EmotionState`: Emotion metrics

#### Focus (`focus.dart`)
- `FocusState`: Focus metrics

#### Behavior (`behavior.dart`)
- `BehaviorState`: Behavioral metrics

#### Context (`context.dart`)
- `ContextState`: Context information
- `ConversationContext`: Conversation timing
- `DeviceStateContext`: Device state
- `UserPatternsContext`: User patterns

### 4. Main HSI Class (`lib/src/hsi.dart`)

- Singleton pattern (`HSI.shared`)
- Orchestrates State Engine and Heads
- Provides public API:
  - `configure(appKey)`: Initialize with app key
  - `start()`: Start the pipeline
  - `stop()`: Stop the pipeline
  - `onStateUpdate`: Stream of final HSV
  - `currentState`: Latest HSV
  - `enableCloudSync()`: Enable cloud sync (future)

## Data Flow

```
Raw Signals (Wear SDK, Phone SDK, Context)
    ↓
Ingestion Service
    ↓
Signal Processor (normalization, cleaning)
    ↓
Fusion Engine (hsi_embedding, base HSV)
    ↓
Emotion Head (synheart_emotion) → HSV with emotion
    ↓
Focus Head (synheart_focus) → Final HSV
    ↓
Subscribers (apps, Syni LLM layer)
```

## Integration Points

### synheart_emotion Package
- Expected interface: `EmotionModel.predict(features) -> Map<String, double>`
- Features extracted from HSV: hsi_embedding, HR, HRV, behavioral metrics, context
- Returns: stress, calm, engagement, activation, valence

### synheart_focus Package
- Expected interface: `FocusModel.predict(features) -> Map<String, double>`
- Features extracted from HSV: hsi_embedding, behavioral metrics, emotion state
- Returns: score, cognitive_load, clarity, distraction

## Next Steps

1. **Connect to actual SDKs**:
   - Integrate with Synheart Wear SDK/Service
   - Integrate with Synheart Phone SDK
   - Implement Context Adapters

2. **Implement fusion model**:
   - Replace placeholder embedding with actual Tiny Transformer or CNN-LSTM
   - Train model to fuse biosignals, behavior, and context

3. **Integrate model packages**:
   - Uncomment and implement `synheart_emotion` integration
   - Uncomment and implement `synheart_focus` integration
   - Adjust feature extraction based on model requirements

4. **Cloud sync**:
   - Implement `enableCloudSync()` method
   - Ensure only aggregated HSV is synced (no raw biosignals)

5. **Testing**:
   - Unit tests for processors
   - Integration tests for full pipeline
   - Mock SDKs for testing

6. **Performance optimization**:
   - Optimize sampling rates
   - Optimize model inference
   - Battery usage considerations

## Privacy & Security

- All processing is on-device by default
- No raw biosignals stored or transmitted
- Cloud sync only for aggregated HSV (with consent)
- Non-medical use only

