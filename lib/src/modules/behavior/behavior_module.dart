import 'dart:async';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../interfaces/consent_provider.dart';
import '../interfaces/feature_providers.dart';
import 'behavior_events.dart';
import 'behavior_event_stream.dart';
import 'window_aggregator.dart';
import 'feature_extractor.dart';

/// Behavior Module
///
/// Captures user-device interaction patterns.
/// Provides window-based behavioral features to HSI Runtime.
class BehaviorModule extends BaseSynheartModule implements BehaviorFeatureProvider {
  @override
  String get moduleId => 'behavior';

  final BehaviorEventStream _eventStream = BehaviorEventStream();
  final WindowAggregator _aggregator = WindowAggregator();
  final BehaviorFeatureExtractor _extractor = BehaviorFeatureExtractor();

  final CapabilityProvider _capabilities;
  final ConsentProvider _consent;

  StreamSubscription<BehaviorEvent>? _eventSubscription;
  Timer? _cleanupTimer;

  BehaviorModule({
    required CapabilityProvider capabilities,
    required ConsentProvider consent,
  })  : _capabilities = capabilities,
        _consent = consent;

  /// Get the event stream for recording events
  BehaviorEventStream get eventStream => _eventStream;

  @override
  BehaviorWindowFeatures? features(WindowType window) {
    // Check consent
    if (!_consent.current().behavior) {
      return null; // Return null if consent denied
    }

    final events = _aggregator.getEvents(window);
    final features = _extractor.extract(events);

    // Filter based on capability level
    return _filterByCapability(features);
  }

  /// Filter features based on capability level
  BehaviorWindowFeatures? _filterByCapability(BehaviorWindowFeatures features) {
    final level = _capabilities.capability(Module.behavior);

    switch (level) {
      case CapabilityLevel.none:
        return null;

      case CapabilityLevel.core:
        // Core: Only basic metrics
        return BehaviorWindowFeatures(
          tapRateNorm: features.tapRateNorm,
          keystrokeRateNorm: features.keystrokeRateNorm,
          scrollVelocityNorm: features.scrollVelocityNorm,
          idleRatio: features.idleRatio,
          switchRateNorm: features.switchRateNorm,
          burstiness: 0.0, // Not available at core
          sessionFragmentation: 0.0, // Not available at core
          notificationLoad: 0.0, // Not available at core
          distractionScore: features.distractionScore,
          focusHint: features.focusHint,
        );

      case CapabilityLevel.extended:
      case CapabilityLevel.research:
        // Extended/Research: Full access
        return features;
    }
  }

  @override
  Future<void> onInitialize() async {
    print('[BehaviorModule] Initializing behavior tracking...');
    // Nothing to initialize
  }

  @override
  Future<void> onStart() async {
    print('[BehaviorModule] Starting behavior tracking...');

    // Subscribe to event stream
    _eventSubscription = _eventStream.events.listen(
      (event) {
        // Check consent before adding event
        if (_consent.current().behavior) {
          _aggregator.addEvent(event);
        }
      },
      onError: (e) => print('[BehaviorModule] Event stream error: $e'),
    );

    // Start cleanup timer (every minute)
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _aggregator.cleanOldWindows();
    });

    print('[BehaviorModule] Behavior tracking started');
  }

  @override
  Future<void> onStop() async {
    print('[BehaviorModule] Stopping behavior tracking...');

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  @override
  Future<void> onDispose() async {
    print('[BehaviorModule] Disposing behavior module...');
    await _eventStream.dispose();
  }
}
