import '../../core/logger.dart';
import 'consent_profile.dart';

/// Callback type for presenting consent UI
///
/// Apps can provide their own UI implementation. The callback receives
/// available consent profiles and should return the selected profile,
/// or null if user declined.
typedef ConsentUIProvider = Future<ConsentProfile?> Function(
  List<ConsentProfile> availableProfiles,
);

/// Manager for consent UI hooks
///
/// Provides a flexible way for apps to implement their own consent UI
/// while the SDK handles the backend integration.
class ConsentUIManager {
  /// Custom UI provider (set by app)
  ConsentUIProvider? customUIProvider;

  ConsentUIManager({this.customUIProvider});

  /// Present consent flow to user
  ///
  /// If customUIProvider is set, it will be called. Otherwise,
  /// returns null (app must handle UI separately).
  Future<ConsentProfile?> presentConsentFlow(
    List<ConsentProfile> profiles,
  ) async {
    if (profiles.isEmpty) {
      SynheartLogger.log(
        '[ConsentUI] No consent profiles available',
      );
      return null;
    }

    if (customUIProvider != null) {
      try {
        final selected = await customUIProvider!(profiles);
        if (selected != null) {
          SynheartLogger.log(
            '[ConsentUI] User selected profile: ${selected.id}',
          );
        } else {
          SynheartLogger.log('[ConsentUI] User declined consent');
        }
        return selected;
      } catch (e) {
        SynheartLogger.log(
          '[ConsentUI] Error in custom UI provider: $e',
          error: e,
        );
        return null;
      }
    }

    // No custom UI provider - app must handle UI separately
    SynheartLogger.log(
      '[ConsentUI] No custom UI provider set. App must implement consent UI.',
    );
    return null;
  }

  /// Get default profile from list (if available)
  ConsentProfile? getDefaultProfile(List<ConsentProfile> profiles) {
    try {
      return profiles.firstWhere((p) => p.isDefault);
    } catch (e) {
      // No default profile found
      return null;
    }
  }
}

