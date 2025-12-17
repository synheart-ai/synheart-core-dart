import 'dart:async';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../interfaces/consent_provider.dart';
import '../interfaces/feature_providers.dart';
import 'phone_collectors.dart';
import 'phone_cache.dart';

/// Phone Module
///
/// Captures device-level motion and context signals.
/// Provides window-based features to HSI Runtime.
class PhoneModule extends BaseSynheartModule implements PhoneFeatureProvider {
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
  })  : _capabilities = capabilities,
        _consent = consent;

  @override
  PhoneWindowFeatures? features(WindowType window) {
    // Check consent
    if (!_consent.current().motion) {
      return null; // Return null if consent denied
    }

    final features = _cache.getFeatures(window);
    if (features == null) {
      return null;
    }

    // Filter based on capability level
    return _filterByCapability(features);
  }

  /// Filter features based on capability level
  PhoneWindowFeatures? _filterByCapability(PhoneWindowFeatures features) {
    final level = _capabilities.capability(Module.phone);

    switch (level) {
      case CapabilityLevel.none:
        return null;

      case CapabilityLevel.core:
        // Core: Motion, screen, and hashed app switching
        // Notification metadata: limited (rate only, no metadata)
        return PhoneWindowFeatures(
          motionLevel: features.motionLevel,
          motionVector: features.motionVector,
          gyroscopeVector: features.gyroscopeVector,
          activityCode: features.activityCode,
          screenState: features.screenState,
          screenOnRatio: features.screenOnRatio,
          appSwitchRate:
              features.appSwitchRate, // Enable at core level (hashed)
          notificationRate: features.notificationRate, // Limited: rate only
          idleRatio: features.idleRatio,
        );

      case CapabilityLevel.extended:
        // Extended: Add detailed app context and notification metadata
        return PhoneWindowFeatures(
          motionLevel: features.motionLevel,
          motionVector: features.motionVector,
          gyroscopeVector: features.gyroscopeVector,
          activityCode: features.activityCode,
          screenState: features.screenState,
          screenOnRatio: features.screenOnRatio,
          appSwitchRate: features.appSwitchRate,
          notificationRate: features.notificationRate,
          idleRatio: features.idleRatio,
          appContext: _appTracker.getAppContext(),
        );

      case CapabilityLevel.research:
        // Research: Full access including raw notification structure
        return PhoneWindowFeatures(
          motionLevel: features.motionLevel,
          motionVector: features.motionVector,
          gyroscopeVector: features.gyroscopeVector,
          activityCode: features.activityCode,
          screenState: features.screenState,
          screenOnRatio: features.screenOnRatio,
          appSwitchRate: features.appSwitchRate,
          notificationRate: features.notificationRate,
          idleRatio: features.idleRatio,
          appContext: _appTracker.getAppContext(),
          rawNotifications: _notificationTracker.getRawNotifications(),
        );
    }
  }

  @override
  Future<void> onInitialize() async {
    print('[PhoneModule] Initializing phone collectors...');
    // Nothing to initialize for mock collectors
  }

  @override
  Future<void> onStart() async {
    print('[PhoneModule] Starting phone data collection...');

    // Start motion collection
    await _motionCollector.start();
    _subscriptions.add(
      _motionCollector.motionStream.listen(
        (motion) => _cache.addMotionData(motion),
        onError: (e) {
          print('[PhoneModule] Motion error: $e');
          // Don't cancel - sensors might recover
        },
        cancelOnError: false, // Keep stream open even on errors
      ),
    );

    // Start screen state tracking
    await _screenTracker.start();
    _subscriptions.add(
      _screenTracker.screenStream.listen(
        (state) => _cache.addScreenState(state, DateTime.now()),
        onError: (e) {
          print('[PhoneModule] Screen state error: $e');
          // Don't cancel - platform channel might recover
        },
        cancelOnError: false, // Keep stream open even on errors
      ),
    );

    // Start app tracking (available at core level and above)
    final phoneCapability = _capabilities.capability(Module.phone);
    if (phoneCapability.index >= CapabilityLevel.core.index) {
      try {
        await _appTracker.start();
        _subscriptions.add(
          _appTracker.appSwitchStream.listen(
            (appId) {
              print('[PhoneModule] ✅ App switch detected: $appId');
              _cache.addAppSwitch(DateTime.now());
              print('[PhoneModule] App switch added to cache');
            },
            onError: (e) {
              print('[PhoneModule] App tracking error: $e');
              // Don't rethrow - stream might recover if permission is granted later
            },
            cancelOnError: false,
          ),
        );
      } catch (e) {
        print('[PhoneModule] Failed to start app tracking: $e');
        // Continue - might work after permission is granted
      }
    }

    // Start notification tracking (Core: limited/rate only, Extended/Research: full metadata)
    // According to docs: Core = "limited" (rate only), Extended/Research = full metadata
    if (phoneCapability.index >= CapabilityLevel.core.index) {
      try {
        await _notificationTracker.start();

        _subscriptions.add(
          _notificationTracker.notificationStream.listen(
            (event) {
              _cache.addNotification(event);
            },
            onError: (e) {
              // Don't rethrow - stream might recover if permission is granted later
            },
            cancelOnError: false,
          ),
        );
      } catch (e) {
        // Continue - might work after permission is granted
      }
    }

    print('[PhoneModule] Started ${_subscriptions.length} collectors');
  }

  @override
  Future<void> onStop() async {
    print('[PhoneModule] Stopping phone data collection...');

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

  @override
  Future<void> onDispose() async {
    print('[PhoneModule] Disposing phone module...');

    await _motionCollector.dispose();
    await _screenTracker.dispose();
    await _appTracker.dispose();
    await _notificationTracker.dispose();
  }
}
