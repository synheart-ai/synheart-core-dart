/// Human State Interface (HSI) - Flutter SDK
/// 
/// HSI is Synheart's unified pipeline for understanding human internal state
/// in real time. It ingests biosignals, behavioral signals, and context signals,
/// processes them into a Human State Vector (HSV), and feeds higher-level models.
library hsi_flutter;

export 'src/hsi.dart';
export 'src/models/hsv.dart';
export 'src/models/emotion.dart';
export 'src/models/focus.dart';
export 'src/models/behavior.dart';
export 'src/models/context.dart';
export 'src/core/state_engine.dart';
export 'src/core/ingestion.dart';
export 'src/core/processors.dart';
export 'src/core/data_sources.dart';
export 'src/heads/emotion_head.dart';
export 'src/heads/focus_head.dart';

