import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synheart_core/synheart_core.dart';

/// The one place in this example that talks to the Synheart SDK.
///
/// Every screen reads state from here and calls methods here — no screen
/// imports `package:synheart_core` directly. That keeps the SDK integration
/// readable as a single file you can skim top-to-bottom, and makes it obvious
/// what a host app actually has to implement.
///
/// The lifecycle it models is the one the SDK documents:
///
///   1. [initialize]      — validate config, load the native runtime
///   2. [submitConsent]   — write the user's choices through the runtime form
///   3. [startSession]    — begin collection; HSI starts arriving
///   4. [stopSession]     — end collection
///   5. [dispose]         — tear down
///
/// Consent uses the runtime's editable-form flow
/// (`consentGetEditableFormTyped` → `consentSubmitFormTyped` →
/// `consentEffectiveStateTyped`). That is the canonical path: the runtime
/// persists the choice offline-first, then reconciles with the cloud profile
/// when cloud is enabled. The older Dart-side helpers (`requestConsent`,
/// `getAvailableConsentProfiles`, `setConsentUIProvider`) are legacy and are
/// deliberately not used here.
class SynheartController extends ChangeNotifier {
  // ── Build-time configuration ───────────────────────────────────────────
  //
  // This example is LOCAL-ONLY by default: no CloudConfig, no
  // DeviceAuthConfig. Everything it demonstrates runs offline on any device
  // with no credentials. See SETUP.md to opt into cloud upload.

  /// Application identifier, reported on session records and ingest rows.
  /// Override with `--dart-define=SYNHEART_APP_ID=...`.
  static const String appId = String.fromEnvironment(
    'SYNHEART_APP_ID',
    defaultValue: 'ai.synheart.core.example',
  );

  static const _kSubjectId = 'example.subject_id';
  static const _kDeviceId = 'example.device_id';

  // ── State the UI renders ───────────────────────────────────────────────

  String? _subjectId;
  String? _deviceId;
  bool _isInitializing = false;
  bool _isInitialized = false;
  String? _initError;

  ConsentForm? _consentForm;
  ConsentEffectiveState? _consentState;
  bool _isSubmittingConsent = false;
  String? _consentError;

  bool _isSessionRunning = false;
  SessionHandle? _session;
  String? _sessionError;

  HSIState? _latestState;
  int _hsiWindowCount = 0;
  StreamSubscription<HSIState>? _hsiSub;

  String? get subjectId => _subjectId;
  String? get deviceId => _deviceId;
  bool get isInitializing => _isInitializing;
  bool get isInitialized => _isInitialized;
  String? get initError => _initError;

  ConsentForm? get consentForm => _consentForm;
  ConsentEffectiveState? get consentState => _consentState;
  bool get isSubmittingConsent => _isSubmittingConsent;
  String? get consentError => _consentError;

  bool get isSessionRunning => _isSessionRunning;
  SessionHandle? get session => _session;
  String? get sessionError => _sessionError;

  HSIState? get latestState => _latestState;
  int get hsiWindowCount => _hsiWindowCount;

  /// True once the user has granted at least one collection channel.
  /// [startSession] is pointless before this — nothing would be collected.
  bool get hasAnyConsent => _consentState?.hasAnyGrant ?? false;

  // ── 1. Identity + initialization ───────────────────────────────────────

  /// Load (or mint) the identifiers this install is bound to.
  ///
  /// `subjectId` MUST be stable across restarts — the runtime scopes storage,
  /// baselines, and device identity to it, so a value that changes per launch
  /// makes every session look like a new person and baselines never mature.
  /// A real app uses its own account id; this example generates one once and
  /// persists it.
  Future<void> loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    _subjectId = prefs.getString(_kSubjectId);
    if (_subjectId == null || _subjectId!.isEmpty) {
      _subjectId = 'demo_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_kSubjectId, _subjectId!);
    }
    _deviceId = prefs.getString(_kDeviceId);
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = 'dev_${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_kDeviceId, _deviceId!);
    }
    notifyListeners();
  }

  /// Replace the subject id and persist it. Clears SDK state, because the
  /// runtime binds storage to the subject — carrying state across a change
  /// would attribute one person's data to another.
  Future<void> setSubjectId(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _subjectId) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSubjectId, trimmed);
    _subjectId = trimmed;
    if (_isInitialized) await shutdown();
    notifyListeners();
  }

  /// The config this example initializes with. Kept as a getter so the setup
  /// screen can show developers exactly what is being passed.
  SynheartConfig buildConfig() {
    return SynheartConfig(
      // Both are REQUIRED — validate() rejects an empty value.
      appId: appId,
      subjectId: _subjectId ?? '',
      appVersion: '1.0.0',
      appName: 'Synheart Core Example',
      deviceId: _deviceId ?? '',
      mode: SynheartMode.personal,

      // Development only. In production the capability lattice is driven by a
      // verified consent token; running unsigned means "allow everything".
      allowUnsignedCapabilities: true,

      // Declaring a module config both activates the feature and tells the SDK
      // which collectors to wire. Omit one and that module never starts.
      wearConfig: const WearConfig(),
      phoneConfig: const PhoneConfig(),
      behaviorConfig: const BehaviorConfig(),

      // Required for the runtime consent-form flow: consentSubmitFormTyped
      // needs a non-empty deviceId + platform to stamp on the submission.
      // Without a ConsentConfig the submit call returns null and consent can
      // never be written.
      consentConfig: ConsentConfig(
        deviceId: _deviceId,
        platform: 'flutter',
        userId: _subjectId,
      ),

      // No CloudConfig / DeviceAuthConfig: this example is local-only.
      // Adding them enables device attestation and HSI upload — see SETUP.md.
    );
  }

  /// Validate the config and load the native runtime.
  ///
  /// `autoStart: false` is deliberate — initializing must not begin collecting.
  /// Collection starts at [startSession], after consent.
  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    _initError = null;
    notifyListeners();

    try {
      if (_subjectId == null) await loadIdentity();
      await Synheart.initialize(config: buildConfig(), autoStart: false);
      _isInitialized = true;
      await refreshConsent();
    } on SynheartError catch (e) {
      // Configuration was rejected. The message names the field and the fix.
      _initError = '${e.code}\n\n${e.message}';
    } catch (e) {
      _initError = '$e';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  // ── 2. Consent (runtime editable-form flow) ────────────────────────────

  /// Read the runtime's current form and effective state.
  ///
  /// The form is what the user edits; the effective state is what the runtime
  /// actually enforces after intersecting the choice with the cloud profile.
  /// They can differ — always gate features on the effective state.
  Future<void> refreshConsent() async {
    if (!_isInitialized) return;
    _consentForm = Synheart.consentGetEditableFormTyped();
    _consentState = Synheart.consentEffectiveStateTyped();
    notifyListeners();
  }

  /// Apply a local edit to the pending form without submitting it, so toggles
  /// feel immediate. Nothing is enforced until [submitConsent].
  void editConsent({
    bool? biosignals,
    bool? phoneContext,
    bool? behavior,
    bool? allowCloud,
    bool? allowResearch,
    bool? allowVendorSync,
  }) {
    final form = _consentForm;
    if (form == null) return;
    _consentForm = form.copyWith(
      biosignals: biosignals,
      phoneContext: phoneContext,
      behavior: behavior,
      allowCloud: allowCloud,
      allowResearch: allowResearch,
      allowVendorSync: allowVendorSync,
    );
    notifyListeners();
  }

  /// Submit the edited form to the runtime.
  ///
  /// Offline-first: the runtime persists the choice immediately and succeeds
  /// even with no network. When `allowCloud` is set it additionally fetches the
  /// cloud default profile, intersects it with the choice, and issues a consent
  /// token — a step that legitimately fails offline without invalidating the
  /// local save.
  Future<void> submitConsent() async {
    final form = _consentForm;
    if (form == null || !_isInitialized) return;
    _isSubmittingConsent = true;
    _consentError = null;
    notifyListeners();

    try {
      final result = await Synheart.consentSubmitFormTyped(form: form);
      if (result == null) {
        _consentError =
            'Submit returned null — the runtime bridge or ConsentConfig is '
            'missing. Check that SynheartConfig.consentConfig is set with a '
            'non-empty deviceId and platform.';
      } else if (result['error'] != null) {
        _consentError = '${result['error']}';
      }
      await refreshConsent();
    } catch (e) {
      _consentError = '$e';
    } finally {
      _isSubmittingConsent = false;
      notifyListeners();
    }
  }

  // ── 3. Session + HSI ───────────────────────────────────────────────────

  /// Start collecting. HSI windows begin arriving on [latestState] once the
  /// runtime has enough signal to close a window (~10s of samples).
  Future<void> startSession() async {
    if (!_isInitialized || _isSessionRunning) return;
    _sessionError = null;
    try {
      _hsiWindowCount = 0;
      _latestState = null;
      _wearSampleCount = 0;
      _wearDataSampleCount = 0;
      _lastWearSample = null;

      // Subscribe BEFORE starting so the first completed window is not missed.
      // onStateUpdate parses each window once and shares it across listeners.
      _hsiSub ??= Synheart.onStateUpdate.listen((state) {
        _latestState = state;
        _hsiWindowCount++;
        notifyListeners();
      });

      // Raw samples as the wear module produces them. Consent-gated by the SDK:
      // nothing is emitted unless biosignals are granted.
      _wearSub ??= Synheart.wearSampleStream.listen((sample) {
        _wearSampleCount++;
        if (_carriesBiosignal(sample)) {
          // Keep the last sample that actually held a reading, so the UI shows
          // the most recent real value rather than the most recent empty tick.
          _lastWearSample = sample;
          _wearDataSampleCount++;
        }
        notifyListeners();
      });

      _session = await Synheart.startSession();
      _isSessionRunning = Synheart.isSessionRunning;
    } catch (e) {
      _sessionError = '$e';
    }
    notifyListeners();
  }

  Future<void> stopSession() async {
    if (!_isSessionRunning) return;
    try {
      await Synheart.stopSession();
    } catch (e) {
      _sessionError = '$e';
    }
    await _hsiSub?.cancel();
    _hsiSub = null;
    await _wearSub?.cancel();
    _wearSub = null;
    _session = null;
    _isSessionRunning = Synheart.isSessionRunning;
    notifyListeners();
  }

  // ── Real signal sources ────────────────────────────────────────────────
  //
  // This example never fabricates biosignals. Synthetic heart rates would
  // teach the wrong integration AND pollute real state: pushed samples feed the
  // runtime's longitudinal baselines (SRM), so fake beats would corrupt the
  // user's actual reference ranges on the device they ran the demo on.
  //
  // Signal arrives from the modules the config activated:
  //   wear      — HealthKit / Health Connect / BLE strap / watch companion
  //   phone     — device motion and context
  //   behavior  — taps and typing rhythm, via the gesture detector wrapper
  //
  // The SDK pushes those into the runtime itself. `Synheart.pushWearHr`,
  // `pushRr`, and `pushRrBatch` exist for hosts that own a source the SDK does
  // not adapt — a proprietary strap, say — and should carry that source's real
  // readings, never placeholders.

  /// Live raw samples from the wear module, so the UI can show what is actually
  /// arriving rather than asserting that something is.
  WearSample? _lastWearSample;
  int _wearSampleCount = 0;
  int _wearDataSampleCount = 0;
  StreamSubscription<WearSample>? _wearSub;

  WearSample? get lastWearSample => _lastWearSample;

  /// Every sample the wear module emitted, including empty ones.
  int get wearSampleCount => _wearSampleCount;

  /// Samples that actually carried a biosignal.
  ///
  /// Tracked separately because the wear source emits a [WearSample] on every
  /// poll tick whether or not a metric resolved. With no wearable paired and no
  /// health data available, that is one all-null envelope per second — so a
  /// raw sample count climbing steadily says nothing about whether biosignals
  /// are arriving, and reporting it as "receiving" would be false.
  int get wearDataSampleCount => _wearDataSampleCount;

  static bool _carriesBiosignal(WearSample s) =>
      s.hr != null ||
      s.hrvRmssd != null ||
      (s.rrIntervals?.isNotEmpty ?? false);

  bool get isWearCollecting => Synheart.isWearCollecting;
  bool get isPhoneCollecting => Synheart.isPhoneCollecting;
  bool get isBehaviorCollecting => Synheart.isBehaviorCollecting;

  /// True once a sample carrying an actual biosignal has arrived — not merely
  /// once the stream is ticking. Until then the runtime has no heart-rate or
  /// HRV input, so the physiological axes stay empty no matter how long the
  /// session runs.
  bool get hasBiosignalSource => _wearDataSampleCount > 0;

  /// The wear source is emitting, but every sample so far has been empty. This
  /// is the normal state on a phone with no wearable paired or with health
  /// permissions not yet granted, and it is worth naming: it looks identical
  /// to "working" if you only watch the sample counter.
  bool get wearEmittingButEmpty =>
      _wearSampleCount > 0 && _wearDataSampleCount == 0;

  // ── Behavior capture ───────────────────────────────────────────────────

  /// Wrap the app in the SDK's gesture detector so taps and typing rhythm feed
  /// the behavior module.
  ///
  /// Required for behavior collection — declaring `behaviorConfig` and granting
  /// behavior consent is not enough on its own, because the SDK has no way to
  /// observe your widget tree otherwise. Safe to call unconditionally: it
  /// returns [child] unchanged when the SDK is not initialized or behavior
  /// consent is not granted.
  Widget wrapWithBehaviorDetector(Widget child) =>
      Synheart.wrapWithBehaviorDetector(child);

  // ── 4. Diagnostics ─────────────────────────────────────────────────────

  /// Native runtime health, with a FULL symbol audit.
  ///
  /// `probeAll: true` matters here. Optional bindings resolve lazily, so a
  /// diagnostics screen that just reads `missingSymbols` reports an empty list
  /// — and looks healthy — while having checked nothing. This example never
  /// calls the lab, resilience, priority, or backfill APIs, so without the
  /// probe every one of those symbols would go unexamined.
  Map<String, dynamic> get diagnostics =>
      Synheart.runtimeDiagnostics(probeAll: true);

  /// SDK version constant, kept in sync with pubspec.
  String get sdkVersion => synheartCoreVersion;

  /// Whether the loaded runtime exposes the lab session ABI.
  ///
  /// Worth surfacing next to `missingSymbols`, because that list does NOT cover
  /// it. Most lab operations (`lab_start`, `lab_open_window`, `lab_finalize`, …)
  /// are bound eagerly rather than through the guarded optional path, so an
  /// absent one throws on first access instead of being recorded as missing.
  /// `is_lab_available` is the SDK's documented gate — check it before calling
  /// any lab API.
  bool get isLabAvailable => Synheart.isLabAvailable;

  /// HSI windows buffered during the session, capped by the SDK.
  List<String> get sessionWindows => Synheart.getSessionHsiWindows();

  // ── 5. Teardown ────────────────────────────────────────────────────────

  /// Stop and release everything, returning to the pre-initialize state.
  Future<void> shutdown() async {
    await stopSession();
    try {
      await Synheart.dispose();
    } catch (_) {
      // Dispose is best-effort; nothing useful to do if teardown throws.
    }
    _isInitialized = false;
    _consentForm = null;
    _consentState = null;
    _latestState = null;
    _hsiWindowCount = 0;
    _session = null;
    notifyListeners();
  }

  /// Erase every byte the SDK holds on this device.
  Future<void> wipeLocalData() async {
    await Synheart.wipeLocalData();
    _latestState = null;
    _hsiWindowCount = 0;
    await refreshConsent();
  }

  @override
  void dispose() {
    _hsiSub?.cancel();
    _wearSub?.cancel();
    super.dispose();
  }
}
