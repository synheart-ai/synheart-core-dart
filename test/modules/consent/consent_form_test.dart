import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  group('ConsentForm', () {
    test('parses the flat runtime shape', () {
      final form = ConsentForm.fromJson(const {
        'profile_id': 'offline-default',
        'biosignals': true,
        'phone_context': false,
        'behavior': true,
        'consent_tier': 'cloud',
        'allow_cloud': true,
        'allow_research': false,
        'allow_vendor_sync': true,
      });

      expect(form.profileId, 'offline-default');
      expect(form.biosignals, isTrue);
      expect(form.phoneContext, isFalse);
      expect(form.behavior, isTrue);
      expect(form.consentTier, ConsentTier.cloud);
      expect(form.allowCloud, isTrue);
      expect(form.allowResearch, isFalse);
      expect(form.allowVendorSync, isTrue);
    });

    test('round-trips through toJson/fromJson', () {
      const original = ConsentForm(
        profileId: 'prof_1',
        biosignals: true,
        phoneContext: true,
        behavior: false,
        consentTier: ConsentTier.research,
        allowCloud: true,
        allowResearch: true,
        allowVendorSync: false,
      );

      final round = ConsentForm.fromJson(original.toJson());

      expect(round, equals(original));
    });

    test('toJson emits runtime-canonical snake_case keys', () {
      final json = const ConsentForm(
        profileId: 'p',
        biosignals: false,
        phoneContext: false,
        behavior: false,
        consentTier: ConsentTier.local,
        allowCloud: false,
        allowResearch: false,
        allowVendorSync: false,
      ).toJson();

      expect(json.keys.toSet(), {
        'profile_id',
        'biosignals',
        'phone_context',
        'behavior',
        'consent_tier',
        'allow_cloud',
        'allow_research',
        'allow_vendor_sync',
      });
    });

    test('fromJson tolerates missing fields (all false, tier local)', () {
      final form = ConsentForm.fromJson(const {'profile_id': 'x'});

      expect(form.biosignals, isFalse);
      expect(form.phoneContext, isFalse);
      expect(form.behavior, isFalse);
      expect(form.consentTier, ConsentTier.local);
      expect(form.allowCloud, isFalse);
    });

    test('copyWith updates single field and preserves the rest', () {
      const form = ConsentForm(
        profileId: 'p',
        biosignals: true,
        phoneContext: true,
        behavior: true,
        consentTier: ConsentTier.cloud,
        allowCloud: true,
        allowResearch: false,
        allowVendorSync: true,
      );

      final updated = form.copyWith(behavior: false);

      expect(updated.behavior, isFalse);
      expect(updated.biosignals, isTrue);
      expect(updated.phoneContext, isTrue);
      expect(updated.profileId, 'p');
      expect(updated.allowCloud, isTrue);
    });

    test('parseConsentTier is case-insensitive and falls back to local', () {
      expect(parseConsentTier('CLOUD'), ConsentTier.cloud);
      expect(parseConsentTier('Research'), ConsentTier.research);
      expect(parseConsentTier('local'), ConsentTier.local);
      expect(parseConsentTier(null), ConsentTier.local);
      expect(parseConsentTier('unknown'), ConsentTier.local);
    });
  });
}
