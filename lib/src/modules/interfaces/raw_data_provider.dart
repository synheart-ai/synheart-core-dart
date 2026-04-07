import '../behavior/behavior_events.dart';
import '../phone/phone_cache.dart';
import '../wear/wear_source_handler.dart';
import 'feature_providers.dart';

/// Protocols for modules to expose raw buffered data to the runtime pipeline.
///
/// fusion, embedding, and HSV construction are delegated to synheart-engine.

/// Provides raw wear samples for a given window.
abstract class RawWearDataProvider {
  List<WearSample> rawSamples(WindowType window);
}

/// Provides raw phone data points for a given window.
abstract class RawPhoneDataProvider {
  List<PhoneDataPoint> rawDataPoints(WindowType window);
}

/// Provides raw behavior events for a given window.
abstract class RawBehaviorDataProvider {
  List<BehaviorEvent> rawEvents(WindowType window);
}
