import 'dart:async';
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../interfaces/consent_provider.dart';
import '../interfaces/feature_providers.dart';
import '../interfaces/raw_data_provider.dart';
import 'phone_collectors.dart';
import 'phone_cache.dart';

/// Phone Module
///
/// Captures device-level motion and context signals.
/// RFC-CORE-0007 compliant: no feature computation in Core.
class PhoneModule extends BaseSynheartModule
    implements PhoneFeatureProvider, RawPhoneDataProvider {
  @override
  String get moduleId => 'phone';

  final MotionCollector _motionCollector = MotionCollector();
  final ScreenStateTracker _screenTracker = ScreenStateTracker();
  final AppFocusTracker _appTracker = AppFocusTracker();
  final NotificationTracker _notificationTracker = NotificationTracker();
  final PhoneCache _cache = PhoneCache();

  final CapabilityProvider _capabilities;
  final ConsentProvider _consent;

  final List<StreamSubscription> _subscriptions = [];

  PhoneModule({
    required CapabilityProvider capabilities,
    required ConsentProvider consent,
  }) : _capabilities = capabilities,
       _consent = consent;

  @override
  PhoneWindowFeatures? features(WindowType window) {
    // Feature computation removed per RFC-CORE-0007.
    // Features will be computed by synheart-runtime when wired.
    return null;
  }

  // MARK: - RawPhoneDataProvider

  @override
  List<PhoneDataPoint> rawDataPoints(WindowType window) {
    if (!_consent.current().phoneContext) return [];
    return _cache.getDataPoints(window);
  }

  @override
  Future<void> onInitialize() async {
    SynheartLogger.log('[PhoneModule] Initializing phone collectors...');
    // Nothing to initialize for mock collectors
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[PhoneModule] Starting phone data collection...');

    // Start motion collection
    await _motionCollector.start();
    _subscriptions.add(
      _motionCollector.motionStream.listen(
        (motion) => _cache.addMotionData(motion),
        onError: (e, st) => SynheartLogger.log(
          '[PhoneModule] Motion error: $e',
          error: e,
          stackTrace: st,
        ),
      ),
    );

    // Start screen state tracking
    await _screenTracker.start();
    _subscriptions.add(
      _screenTracker.screenStream.listen(
        (state) => _cache.addScreenState(state, DateTime.now()),
        onError: (e, st) => SynheartLogger.log(
          '[PhoneModule] Screen state error: $e',
          error: e,
          stackTrace: st,
        ),
      ),
    );

    // Start app tracking (if capability allows)
    if (_capabilities.capability(Module.phone).index >=
        CapabilityLevel.extended.index) {
      await _appTracker.start();
      _subscriptions.add(
        _appTracker.appSwitchStream.listen(
          (_) => _cache.addAppSwitch(DateTime.now()),
          onError: (e, st) => SynheartLogger.log(
            '[PhoneModule] App tracking error: $e',
            error: e,
            stackTrace: st,
          ),
        ),
      );
    }

    // Start notification tracking (if capability allows)
    if (_capabilities.capability(Module.phone).index >=
        CapabilityLevel.extended.index) {
      await _notificationTracker.start();
      _subscriptions.add(
        _notificationTracker.notificationStream.listen(
          (event) => _cache.addNotification(event),
          onError: (e, st) => SynheartLogger.log(
            '[PhoneModule] Notification error: $e',
            error: e,
            stackTrace: st,
          ),
        ),
      );
    }

    SynheartLogger.log(
      '[PhoneModule] Started ${_subscriptions.length} collectors',
    );
  }

  @override
  Future<void> onStop() async {
    SynheartLogger.log('[PhoneModule] Stopping phone data collection...');

    // Cancel all subscriptions
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    // Stop all collectors
    await _motionCollector.stop();
    await _screenTracker.stop();
    await _appTracker.stop();
    await _notificationTracker.stop();
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    _cache.clear();
    SynheartLogger.log('[PhoneModule] Cache cleared');
  }

  @override
  Future<void> onDispose() async {
    SynheartLogger.log('[PhoneModule] Disposing phone module...');

    await _motionCollector.dispose();
    await _screenTracker.dispose();
    await _appTracker.dispose();
    await _notificationTracker.dispose();
  }
}
