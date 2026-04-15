import '../interfaces/consent_provider.dart';

/// Editable consent form returned by core-runtime cloud consent APIs.

class ConsentForm {
  const ConsentForm({
    required this.profileId,
    required this.categories,
    required this.consentTier,
    required this.allowCloud,
    required this.allowResearch,
    required this.allowVendorSync,
  });

  final String profileId;
  final List<ConsentCategory> categories;
  final ConsentTier consentTier;
  final bool allowCloud;
  final bool allowResearch;
  final bool allowVendorSync;

  factory ConsentForm.fromJson(Map<String, dynamic> json) {
    final categoriesRaw = json['categories'];
    return ConsentForm(
      profileId: (json['profile_id'] ?? '').toString(),
      categories: categoriesRaw is List
          ? categoriesRaw
                .whereType<Map<String, dynamic>>()
                .map(ConsentCategory.fromJson)
                .toList(growable: false)
          : const <ConsentCategory>[],
      consentTier: parseConsentTier(json['consent_tier']?.toString()),
      allowCloud: json['allow_cloud'] == true,
      allowResearch: json['allow_research'] == true,
      allowVendorSync: json['allow_vendor_sync'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile_id': profileId,
      'categories': categories.map((c) => c.toJson()).toList(growable: false),
      'consent_tier': consentTier.name,
      'allow_cloud': allowCloud,
      'allow_research': allowResearch,
      'allow_vendor_sync': allowVendorSync,
    };
  }

  ConsentForm copyWith({
    String? profileId,
    List<ConsentCategory>? categories,
    ConsentTier? consentTier,
    bool? allowCloud,
    bool? allowResearch,
    bool? allowVendorSync,
  }) {
    return ConsentForm(
      profileId: profileId ?? this.profileId,
      categories: categories ?? this.categories,
      consentTier: consentTier ?? this.consentTier,
      allowCloud: allowCloud ?? this.allowCloud,
      allowResearch: allowResearch ?? this.allowResearch,
      allowVendorSync: allowVendorSync ?? this.allowVendorSync,
    );
  }
}

/// Consent category section in the editable form.
class ConsentCategory {
  const ConsentCategory({
    required this.categoryKey,
    required this.categoryName,
    required this.channels,
  });

  final String categoryKey;
  final String categoryName;
  final List<ConsentChannel> channels;

  factory ConsentCategory.fromJson(Map<String, dynamic> json) {
    final channelsRaw = json['channels'];
    return ConsentCategory(
      categoryKey: (json['category_key'] ?? '').toString(),
      categoryName: (json['category_name'] ?? '').toString(),
      channels: channelsRaw is List
          ? channelsRaw
                .whereType<Map<String, dynamic>>()
                .map(ConsentChannel.fromJson)
                .toList(growable: false)
          : const <ConsentChannel>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category_key': categoryKey,
      'category_name': categoryName,
      'channels': channels.map((c) => c.toJson()).toList(growable: false),
    };
  }
}

/// Consent channel toggle in the editable form.
class ConsentChannel {
  const ConsentChannel({
    required this.key,
    required this.displayName,
    required this.isGranted,
  });

  final String key;
  final String displayName;
  final bool isGranted;

  factory ConsentChannel.fromJson(Map<String, dynamic> json) {
    return ConsentChannel(
      key: (json['key'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      isGranted: json['is_granted'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'display_name': displayName,
      'is_granted': isGranted,
    };
  }

  ConsentChannel copyWith({String? key, String? displayName, bool? isGranted}) {
    return ConsentChannel(
      key: key ?? this.key,
      displayName: displayName ?? this.displayName,
      isGranted: isGranted ?? this.isGranted,
    );
  }
}

ConsentTier parseConsentTier(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'cloud':
      return ConsentTier.cloud;
    case 'research':
      return ConsentTier.research;
    case 'local':
    default:
      return ConsentTier.local;
  }
}
