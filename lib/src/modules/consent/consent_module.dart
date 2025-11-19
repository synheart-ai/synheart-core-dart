import 'package:rxdart/rxdart.dart';
import '../base/synheart_module.dart';
import '../interfaces/consent_provider.dart';
import 'consent_storage.dart';

/// Consent Module
///
/// Single source of truth for user consent on the device.
/// Gates collection and export of biosignals, behavior, motion/context,
/// cloud upload, and Syni personalization.
class ConsentModule extends BaseSynheartModule implements ConsentProvider {
  @override
  String get moduleId => 'consent';

  final ConsentStorage _storage;
  final BehaviorSubject<ConsentSnapshot> _consentStream =
      BehaviorSubject<ConsentSnapshot>();

  ConsentSnapshot? _currentConsent;

  /// Callbacks for when consent changes
  final List<void Function(ConsentSnapshot)> _listeners = [];

  ConsentModule({ConsentStorage? storage})
      : _storage = storage ?? ConsentStorage();

  @override
  ConsentSnapshot current() {
    if (_currentConsent == null) {
      throw StateError('Consent module not initialized');
    }
    return _currentConsent!;
  }

  @override
  Stream<ConsentSnapshot> observe() => _consentStream.stream;

  @override
  Future<void> updateConsent(ConsentSnapshot newConsent) async {
    final oldConsent = _currentConsent;
    _currentConsent = newConsent;

    // Persist to storage
    await _storage.save(newConsent);

    // Emit to stream
    _consentStream.add(newConsent);

    // Notify listeners
    _notifyListeners(newConsent);

    // Check for consent revocations and log
    if (oldConsent != null) {
      _logConsentChanges(oldConsent, newConsent);
    }
  }

  /// Register a listener for consent changes
  void addListener(void Function(ConsentSnapshot) listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(void Function(ConsentSnapshot) listener) {
    _listeners.remove(listener);
  }

  /// Load consent from storage or use defaults
  Future<void> loadConsent() async {
    final stored = await _storage.load();

    if (stored != null) {
      _currentConsent = stored;
      _consentStream.add(stored);
    } else {
      // No stored consent, use defaults (all denied for safety)
      _currentConsent = ConsentSnapshot.none();
      _consentStream.add(_currentConsent!);
    }
  }

  /// Grant all consents
  Future<void> grantAll() async {
    await updateConsent(ConsentSnapshot.all());
  }

  /// Revoke all consents
  Future<void> revokeAll() async {
    await updateConsent(ConsentSnapshot.none());
  }

  /// Update a specific consent type
  Future<void> updateConsentType(ConsentType type, bool granted) async {
    if (_currentConsent == null) {
      throw StateError('Consent module not initialized');
    }

    final updated = _currentConsent!.copyWith(
      biosignals: type == ConsentType.biosignals ? granted : _currentConsent!.biosignals,
      behavior: type == ConsentType.behavior ? granted : _currentConsent!.behavior,
      motion: type == ConsentType.motion ? granted : _currentConsent!.motion,
      cloudUpload: type == ConsentType.cloudUpload ? granted : _currentConsent!.cloudUpload,
      syni: type == ConsentType.syni ? granted : _currentConsent!.syni,
      timestamp: DateTime.now(),
    );

    await updateConsent(updated);
  }

  /// Notify all registered listeners
  void _notifyListeners(ConsentSnapshot consent) {
    for (final listener in _listeners) {
      try {
        listener(consent);
      } catch (e) {
        print('Error notifying consent listener: $e');
      }
    }
  }

  /// Log consent changes for debugging
  void _logConsentChanges(ConsentSnapshot oldConsent, ConsentSnapshot newConsent) {
    if (oldConsent.biosignals != newConsent.biosignals) {
      print('Consent changed: biosignals ${newConsent.biosignals ? "granted" : "revoked"}');
    }
    if (oldConsent.behavior != newConsent.behavior) {
      print('Consent changed: behavior ${newConsent.behavior ? "granted" : "revoked"}');
    }
    if (oldConsent.motion != newConsent.motion) {
      print('Consent changed: motion ${newConsent.motion ? "granted" : "revoked"}');
    }
    if (oldConsent.cloudUpload != newConsent.cloudUpload) {
      print('Consent changed: cloudUpload ${newConsent.cloudUpload ? "granted" : "revoked"}');
    }
    if (oldConsent.syni != newConsent.syni) {
      print('Consent changed: syni ${newConsent.syni ? "granted" : "revoked"}');
    }
  }

  @override
  Future<void> onInitialize() async {
    await loadConsent();
  }

  @override
  Future<void> onStart() async {
    // Nothing to start
  }

  @override
  Future<void> onStop() async {
    // Nothing to stop
  }

  @override
  Future<void> onDispose() async {
    await _consentStream.close();
    _listeners.clear();
    _currentConsent = null;
  }
}
