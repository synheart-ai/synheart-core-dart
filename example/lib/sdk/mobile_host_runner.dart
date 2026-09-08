import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:synheart_core/synheart_core.dart';

import 'host_snapshot_store.dart';
import 'rest_window_detector.dart';
import 'synthetic_cardiac_source.dart';
import 'typing_micro_windows.dart';

/// The host-side half of the mobile integration: everything the guide says a
/// mobile SDK team has to *drive*, as opposed to configure.
///
/// [SynheartController] owns configuration, consent and the session. This owns
/// what has to keep happening once a session is live, in the order §6 requires:
///
/// * **§6.1 — tick for the whole session.** There is no internal ticker.
///   `ingest_batch` advances the clock, but `push_behavior` does not, so a
///   session with interaction and no cardiac input emits *zero* HSI windows
///   unless the host ticks. This runs a 1 Hz loop for the life of the session,
///   not only while a keyboard is up.
/// * **§6.4 — drain before the tick that closes the window.** Retroactive
///   buffers (here, the typing micro-window aggregator) are flushed *first*,
///   then the tick runs. Reverse that order and the window closes without the
///   events that belong to it, and the window cursor loses them for good.
/// * **§6.5 — declare rest.** Evaluated once per window against the composite
///   definition, one-shot per window.
/// * **§7 — three snapshots.** Session state once per emitted window and on
///   background; SRM at session end; longitudinal after every wearable
///   recompute. Session state is loaded *before the first tick*, because
///   window 1 writes each head's state slot and a later restore is overwritten
///   by a cold window.
/// * **§8 — the daily loop.** `roll_day` at session start and at local
///   midnight, wearable dailies into the SRM, recompute, persist.
///
/// It also owns the simulated cardiac stream, which is the only signal source
/// available on a bare phone with no strap and no health permissions.
///
/// ## Degradation is the normal case, not the error case
///
/// The vendored runtime is a pinned artifact that lags this SDK, so several of
/// these calls are no-ops on any given device — `Synheart.mobileHostAbiSupport`
/// says which. Every call site here handles the absent case by name rather
/// than assuming, and [abiSupport] is surfaced so the UI can show a developer
/// which parts of this file are actually running.
class MobileHostRunner {
  MobileHostRunner({required this.onChanged});

  /// Called whenever anything a UI renders changes. Wired to the controller's
  /// `notifyListeners`, so this class stays free of ChangeNotifier plumbing.
  final VoidCallback onChanged;

  // ── Declarations this host makes (§2) ─────────────────────────────────

  /// Whether to declare a sensing profile, device class, mask profile and CFI
  /// denominator at all.
  ///
  /// Off by default, and that default is not timidity: declaring
  /// `device_class` folds into the SRM `config_hash` and **invalidates every
  /// persisted baseline**, costing the person a 30-observation re-warm across
  /// 3 distinct days. Undeclared reproduces pre-0.16.0 behaviour exactly. This
  /// is a first-launch decision to be made once and kept stable, which is why
  /// it is a toggle on the Setup screen rather than something this runner
  /// flips at will.
  bool declareHostProfile = false;

  /// Claim continuous sensing on iOS.
  ///
  /// `"auto"` resolves iOS to `IOS_EPISODIC`, which **withholds Capacity and
  /// Mental Fatigue from every frame** with reason `episodic_sensing`. That is
  /// the honest default: without a BLE peripheral holding the process alive,
  /// an iOS app gets whatever foreground slices the user grants, and
  /// publishing a torn session clock as a trajectory is worse than withholding
  /// two heads.
  ///
  /// Continuous is a claim only the host can make, and only truthfully — it
  /// requires an actual live peripheral connection. This example has none, so
  /// turning this on is a way to *see* the two heads come back, not a way to
  /// earn them.
  bool claimContinuousSensing = false;

  /// Where the accelerometer currently sits (§4.3).
  ///
  /// [AccelPlacement.unknown] withholds all four kinematic heads, and only
  /// `pocket` and `waist` are inside the validated envelope. There is no
  /// hand-held placement, and during exactly the interaction the digital axes
  /// measure the phone is in the hand — so this is genuinely dynamic, and a
  /// fixed compile-time `pocket` is wrong the moment the person picks the
  /// device up. Re-declared through [setAccelPlacement] as it changes.
  AccelPlacement placement = AccelPlacement.unknown;

  /// The host declarations to merge into the config, or an empty set.
  HostDeclarations buildHostDeclarations() {
    if (!declareHostProfile) return const HostDeclarations();
    return HostDeclarations(
      // A lateness budget matters even for a phone with no retroactive
      // source: the typing aggregator is one, and so is any HealthKit read.
      // The engine holds each completed window this long and emits it once,
      // complete, just later — the frame's content is unchanged.
      sensing: claimContinuousSensing
          ? const SensingProfile(
              mode: SensingMode.continuous,
              latenessBudgetMs: 30_000,
            )
          : 'auto',
      deviceClass: 'auto',
      maskProfile: 'auto',
      // 4 is the documented mobile value. It **lowers** conf_CFI for identical
      // evidence by widening the coverage denominator — that direction
      // surprises people, and it is correct.
      cfiStructuralComponents: 4,
    );
  }

  // ── Runtime capability audit (§1) ─────────────────────────────────────

  /// Which mobile-host ABI calls the loaded native runtime exports.
  Map<String, bool> get abiSupport => Synheart.mobileHostAbiSupport;

  /// Calls this SDK binds that the vendored runtime does not export, sorted.
  List<String> get unsupportedCalls =>
      (abiSupport.entries.where((e) => !e.value).map((e) => e.key).toList())
        ..sort();

  // ── Session-scoped state ──────────────────────────────────────────────

  Timer? _tickTimer;
  Timer? _cardiacTimer;
  Timer? _midnightTimer;
  StreamSubscription<BehaviorEvent>? _behaviorSub;

  HostSnapshotStore? _store;
  String _deviceClassKey = 'phone';

  final RestWindowDetector rest = RestWindowDetector();
  final TypingMicroWindowAggregator typing = TypingMicroWindowAggregator();

  SyntheticCardiacSource? _cardiac;
  int _lastCardiacTickMs = 0;

  bool get isRunning => _tickTimer != null;
  bool get isStreamingCardiac => _cardiacTimer != null;

  // ── Counters the UI renders ───────────────────────────────────────────

  int ticks = 0;
  int windowsDrained = 0;
  int restDeclarations = 0;
  int typingWindowsPushed = 0;
  int typingTapsPushed = 0;
  int rrPacketsPushed = 0;
  int beatsPushed = 0;
  int speedSamplesPushed = 0;
  int sessionStateSaves = 0;
  int dailyPushes = 0;
  int contextEventsAccepted = 0;
  int contextEventsRejected = 0;
  String? lastError;

  /// Latest simulated reading, for the live display.
  double? latestSimBpm;
  double? latestSimRmssd;
  String simActivity = '—';

  /// The comparability key this session is running under (§9.5).
  String? configId;

  /// True when the persisted `config_id` differs from the live one, meaning
  /// anything cached under the old key is no longer comparable.
  bool configIdChanged = false;

  /// The most recent `motion.accel_rms` the engine reported, which is what the
  /// rest detector's low-motion clause reads.
  double? latestAccelRms;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Prepare persistence and restore state. **Call before the first tick.**
  ///
  /// The ordering here is the §7 rule and it is not cosmetic:
  /// `load_session_state` must run before window 1, because window 1 writes
  /// each head's state slot — a later restore is silently overwritten by a
  /// cold window, and by then the context baseline has counted one window
  /// against the wrong history.
  Future<void> restore({
    required String subjectId,
    required String deviceClass,
  }) async {
    _deviceClassKey = deviceClass;
    final store = await HostSnapshotStore.open(subjectId: subjectId);
    _store = store;

    // Read the live comparability key first, so a mismatch is known before
    // anything cached under the old one is trusted.
    configId = Synheart.configId();
    final storedConfigId = store.readConfigId();
    configIdChanged =
        configId != null &&
        storedConfigId != null &&
        storedConfigId != configId;
    if (configId != null) await store.writeConfigId(configId!);

    // SRM and longitudinal first: both call `ensurePipeline` internally, and
    // a cold-boot host has no Pipeline until something materialises one.
    final srm = store.readSrm(deviceClass);
    if (srm != null) {
      // A rejection here is `ERR_SRM_CONFIG_MISMATCH` — the baseline
      // partition working, not a bug. Nothing to handle beyond noting it; the
      // engine starts cold.
      final ok = Synheart.loadRuntimeSRMSnapshot(srm);
      if (!ok) {
        lastError =
            'SRM snapshot rejected (config mismatch). Baselines start cold — '
            'expected after changing device_class or the sensing declaration.';
      }
    }

    final longitudinal = store.readLongitudinal();
    if (longitudinal != null) Synheart.loadLongitudinalSnapshot(longitudinal);

    final sessionState = store.readSessionState();
    if (sessionState != null) {
      final status = Synheart.loadSessionState(sessionState);
      if (status == null) {
        // Not an error — the vendored runtime simply predates the symbol. The
        // heads start cold, which is the pre-0.16.0 behaviour.
        lastError =
            'load_session_state is absent from this runtime; the stateful '
            'heads start cold each launch.';
      }
    }

    onChanged();
  }

  /// Start the loops. Call right after `Synheart.startSession()`.
  void start() {
    if (_tickTimer != null) return;
    ticks = 0;
    windowsDrained = 0;
    restDeclarations = 0;
    typingWindowsPushed = 0;
    typingTapsPushed = 0;
    rrPacketsPushed = 0;
    beatsPushed = 0;
    speedSamplesPushed = 0;
    sessionStateSaves = 0;
    dailyPushes = 0;
    lastError = null;
    rest.reset();
    typing.reset();

    // Placement is declared explicitly, including the default. Declaring
    // `unknown` is not the same as never calling it: the call is what makes
    // the withholding attributable rather than merely absent.
    setAccelPlacement(placement);

    // §8.1 — roll the day at session start, in the host's LOCAL zone. Skip it
    // and the engine adopts a provisional UTC day, which is wrong for most of
    // the world.
    _rollDayIfNeeded();
    _scheduleMidnightRoll();

    // Interaction feeds the rest detector's quiet clock.
    _behaviorSub ??= Synheart.behaviorEventStream.listen((event) {
      rest.noteInteraction(event.timestamp.millisecondsSinceEpoch);
    });

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    onChanged();
  }

  /// Stop the loops and persist everything.
  ///
  /// `flush_pending` is the call that matters most here: without it up to one
  /// lateness budget's worth of completed windows is stranded forever.
  Future<void> stop() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    _midnightTimer?.cancel();
    _midnightTimer = null;
    stopCardiacStream();
    await _behaviorSub?.cancel();
    _behaviorSub = null;

    // Drain the host's own buffer before the final flush, same §6.4 ordering
    // as every tick.
    _flushTypingWindow(force: true);

    final now = DateTime.now().millisecondsSinceEpoch;
    _countDrained(Synheart.flushPending(now));

    await _persistAll(sessionEnd: true);
    onChanged();
  }

  /// App went to background. Flush and persist — an iOS app without a live
  /// peripheral may not be scheduled again before it is suspended.
  Future<void> onBackgrounded() async {
    rest.noteScreenOff(DateTime.now().millisecondsSinceEpoch);
    if (!isRunning) return;
    _flushTypingWindow(force: true);
    _countDrained(Synheart.flushPending(DateTime.now().millisecondsSinceEpoch));
    await _persistAll(sessionEnd: false);
    onChanged();
  }

  void onForegrounded() {
    rest.noteScreenOn(DateTime.now().millisecondsSinceEpoch);
    if (!isRunning) return;
    // §6.4 on wake: drain first, then tick. A gap needs `tick_all`, not
    // `tick` — the latter polls one window and would skip the rest.
    _onTick();
  }

  void dispose() {
    _tickTimer?.cancel();
    _cardiacTimer?.cancel();
    _midnightTimer?.cancel();
    _behaviorSub?.cancel();
  }

  // ── The tick loop (§6.1, §6.4) ────────────────────────────────────────

  void _onTick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    ticks++;

    // 1. Drain retroactive buffers BEFORE the tick that may close their
    //    window. Reversed, the window closes without them and the window
    //    cursor drops them with no counter to show it.
    _flushTypingWindow(force: false, nowMs: now);

    // 2. Advance the clock. `tick_all` drains every completed window;
    //    `tick` polls one, so after any gap it silently skips the windows it
    //    spanned. Fall back only when the symbol is absent.
    final drained = Synheart.tickAll(now);
    if (drained == null) {
      _countDrained(Synheart.tick(now), single: true);
    } else {
      _countDrained(drained);
    }

    // 3. Read the engine's own motion estimate, so the rest detector's
    //    low-motion clause has a real measurement rather than an assumption.
    _refreshAccelRms();

    // 4. Rest, once per window, one-shot.
    final restTs = rest.evaluate(now);
    if (restTs != null) {
      Synheart.declareRestWindow(restTs);
      restDeclarations = rest.declaredCount;
    }

    onChanged();
  }

  /// Count windows out of a `tick_all` / `flush_pending` array, or a single
  /// `tick` document.
  ///
  /// The windows themselves need no handling here — the SDK routes them
  /// through `onStateUpdate` for us — so this is bookkeeping only.
  void _countDrained(String? json, {bool single = false}) {
    if (json == null || json.isEmpty) return;
    if (single) {
      windowsDrained++;
      return;
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) windowsDrained += decoded.length;
    } catch (_) {
      // A malformed drain is worth neither crashing nor guessing a count for.
    }
  }

  void _refreshAccelRms() {
    final featuresJson = Synheart.lastFeatures;
    if (featuresJson == null) return;
    try {
      final decoded = jsonDecode(featuresJson);
      if (decoded is! Map) return;
      final motion = decoded['motion'];
      final rms = motion is Map ? motion['accel_rms'] : null;
      if (rms is num) {
        latestAccelRms = rms.toDouble();
        rest.noteMotionRms(latestAccelRms!);
      }
    } catch (_) {
      // Features are diagnostic; a parse failure changes nothing else.
    }
  }

  // ── Typing micro-windows (§5.3) ───────────────────────────────────────

  /// Feed a text change from the typing probe.
  void onTypingChanged(String text) {
    final now = DateTime.now().millisecondsSinceEpoch;
    rest.noteInteraction(now);
    final completed = typing.onTextChanged(text, now);
    if (completed != null) _pushTypingWindow(completed);
    onChanged();
  }

  void resetTypingProbe() {
    typing.reset();
    onChanged();
  }

  void _flushTypingWindow({required bool force, int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final completed = force ? typing.flushNow() : typing.flushIfElapsed(now);
    if (completed != null) _pushTypingWindow(completed);
  }

  void _pushTypingWindow(
    ({int windowStartMs, TypingSessionData session}) completed,
  ) {
    // Stamped at the window START, matching desktop. Stamping it at emission
    // time would place a 10 s summary of past typing in a later window.
    final status = Synheart.pushBehaviorEvent(
      BehaviorEventInput.typing(completed.windowStartMs, completed.session),
    );
    if (status == null) {
      // The runtime cannot take rich events. Deliberately NOT retried through
      // the legacy int-coded path: `push_behavior` carries no payload, so the
      // typing session would arrive all-null, and the raw keystrokes behind
      // this summary already took that path inside the SDK. Sending both is
      // the §5.4 double-count.
      lastError =
          'push_behavior_event is absent from this runtime — typing windows '
          'cannot reach the engine. Re-vendor with `synheart install '
          'runtime`.';
      return;
    }
    typingWindowsPushed++;
    typingTapsPushed += completed.session.typingTapCount ?? 0;
  }

  // ── Placement (§4.3) ──────────────────────────────────────────────────

  void setAccelPlacement(AccelPlacement next) {
    placement = next;
    Synheart.setAccelPlacement(next);
    onChanged();
  }

  // ── Rest, declared by hand ────────────────────────────────────────────

  /// Declare the current window a rest window without waiting for the
  /// composite to be satisfied.
  ///
  /// Present so the effect is observable in a demo — the composite needs two
  /// minutes of screen-off, which is longer than anyone will sit through. Not
  /// something a real host does: the composite exists because screen-off alone
  /// is wrong in both directions.
  void declareRestNow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    Synheart.declareRestWindow(now);
    restDeclarations++;
    onChanged();
  }

  // ── Foreground app context (§5.5) ─────────────────────────────────────

  /// Push a foreground-app context event.
  ///
  /// This example has no `UsageStatsManager` binding, so it cannot name the
  /// app that is actually in front — it reports **itself**, which is true and
  /// useless. A real Android host wires `UsageStatsManager` (permission
  /// `PACKAGE_USAGE_STATS`) and sends the real foreground package; iOS has no
  /// API for this at all.
  ///
  /// The category, never a context label: the engine derives the 12-class
  /// `ContextLabel` itself and two-letter app codes collide with live label
  /// codes — `BR` is `BreakRecovery`, not "browsing/reading".
  void pushSelfAsContext() {
    final status = Synheart.pushContextEvent(<String, dynamic>{
      'ts_ms': DateTime.now().millisecondsSinceEpoch,
      'app_id': 'ai.synheart.core.example',
      'category': 'productivity',
    });
    if (status == null) {
      lastError =
          'push_context_event is absent from this runtime. On Android there '
          'is then no context layer at all.';
    } else if (status == 0) {
      contextEventsAccepted++;
    } else {
      // Far more likely to mean "built without the app-context cargo feature"
      // than "your JSON was wrong" — without it the symbol is an inert stub
      // that always returns 1.
      contextEventsRejected++;
      lastError =
          'push_context_event returned $status. The runtime was probably '
          'built without the `app-context` cargo feature, which compiles the '
          'symbol as an inert stub.';
    }
    onChanged();
  }

  // ── The simulated cardiac stream ──────────────────────────────────────

  /// Start streaming simulated beats into the runtime.
  ///
  /// See [SyntheticCardiacSource] for what is being modelled and why the
  /// samples are tagged `synthetic_sim` rather than `ble_hrm`. The important
  /// property for this file is the *call shape*: one
  /// `push_rr_batch(anchor, rr[], order)` per notification rather than a loop
  /// of `push_rr`, because one BLE Heart Rate Measurement carries several RR
  /// intervals under a single arrival timestamp and pushing them individually
  /// with that shared stamp collapses every beat in the packet onto one
  /// instant.
  void startCardiacStream({int? seed}) {
    if (_cardiacTimer != null) return;
    _cardiac = SyntheticCardiacSource(seed: seed);
    _lastCardiacTickMs = DateTime.now().millisecondsSinceEpoch;
    _cardiacTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _emitCardiac(),
    );
    onChanged();
  }

  void stopCardiacStream() {
    _cardiacTimer?.cancel();
    _cardiacTimer = null;
    _cardiac = null;
    onChanged();
  }

  void _emitCardiac() {
    final source = _cardiac;
    if (source == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastCardiacTickMs;
    _lastCardiacTickMs = now;

    for (final packet in source.advance(now, elapsed)) {
      // The batch path. `order: 0` is oldest-first, which is what a BLE HRM
      // reports and the order this source produces.
      Synheart.pushRrBatch(
        packet.anchorTsMs,
        packet.rrMs,
        order: 0,
        provider: _simProvider,
      );
      // HR alongside RR, as a real strap reports both. Routed through
      // `ingest_batch`, which is also what advances the pipeline clock — so a
      // cardiac session produces windows even independently of the tick loop.
      Synheart.pushWearHr(
        packet.anchorTsMs,
        packet.bpm,
        provider: _simProvider,
      );

      // §4.4 — speed is the high-confidence input for `locomotion_state`,
      // which otherwise runs permanently on its accel-only fallback. Simulated
      // here from the same activity episode that produced the beats, so the
      // two agree; a real host wires the platform's location stream.
      Synheart.pushSpeed(packet.anchorTsMs, packet.speedMps);
      speedSamplesPushed++;

      rrPacketsPushed++;
      beatsPushed += packet.rrMs.length;
      latestSimBpm = packet.bpm;
      latestSimRmssd = packet.rmssdMs;
      simActivity = packet.activityLabel;
    }
    onChanged();
  }

  /// Provider tag for every simulated push.
  ///
  /// Not `ble_hrm`. That label routes into the breathing detector's Tier-1
  /// series and stratifies research exports as a true-RR source; claiming it
  /// for invented beats would put fabricated data where the pipeline trusts it
  /// most. Tier-3 is the right floor for a source that cannot vouch for
  /// itself.
  ///
  /// `sdk_wear` rather than `default_sensor`, and the difference is not
  /// cosmetic. Both are **Tier 3** in core-runtime's `provider_tier`, so the
  /// fidelity claim is identical — but only `sdk_wear` has a row in
  /// `signals_for`, and that table is what registers the source that
  /// `meta.provenance.sources[*].signals` is built from. Tagged
  /// `default_sensor`, the push still reaches the engine and still moves the
  /// axes, but the runtime registers no source, so every modality chip reads
  /// absent while the axes sit there grounded. That is a core-runtime gap
  /// worth fixing upstream — `default_sensor` is named in `provider_tier` and
  /// omitted from `signals_for`, and it is the *default parameter value* on
  /// `Synheart.pushWearHr` — but until it is, this is the tag that reports
  /// honestly without overclaiming fidelity.
  static const String _simProvider = 'sdk_wear';

  // ── The daily loop (§8) ───────────────────────────────────────────────

  /// `roll_day` for today, if today has not been rolled yet.
  ///
  /// The index must **strictly advance** — a repeat or a negative returns
  /// `ERR_DAILY_DAY_NOT_ADVANCING` — so the last one is persisted and checked
  /// rather than rolled blindly at every launch.
  void _rollDayIfNeeded() {
    final store = _store;
    // Days since epoch in the host's LOCAL zone, which is the whole point of
    // the call: the engine's provisional fallback is UTC.
    final local = DateTime.now();
    final localMidnight = DateTime(local.year, local.month, local.day);
    final dayIndex = localMidnight.millisecondsSinceEpoch ~/ 86_400_000;

    final last = store?.readLastDayIndex();
    if (last != null && dayIndex <= last) return;

    final status = Synheart.rollDay(dayIndex);
    if (status == null) {
      lastError =
          'roll_day is absent from this runtime; the daily accumulator runs '
          'on a provisional UTC day.';
      return;
    }
    store?.writeLastDayIndex(dayIndex);
  }

  /// Re-roll at the next local midnight.
  ///
  /// A timer only covers the case where the app is alive across midnight.
  /// A real host needs a scheduled job — `workmanager` on Android,
  /// `BGTaskScheduler` on iOS — and this example deliberately does not pull
  /// those plugins in, so a phone that was asleep at midnight rolls the day at
  /// the next session start instead. That is the gap §8 names as unbuilt.
  void _scheduleMidnightRoll() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      _rollDayIfNeeded();
      _scheduleMidnightRoll();
      onChanged();
    });
  }

  /// Push one day of vendor wearable summaries into the SRM, recompute, and
  /// persist the longitudinal snapshot.
  ///
  /// This is the **only** baseline path for a phone with no live wearable
  /// session, and nothing in the stack was calling it. The values here come
  /// from the simulator rather than HealthKit / Health Connect, because this
  /// example holds no health permission — a real host reads them from the
  /// platform store and sends `fidelity: 1` for a provider summary.
  ///
  /// Note what is *not* sent: no dimension is padded to zero. A vendor that
  /// reports no deep-sleep figure means the value is absent, and a measured
  /// `0.0` there is a different claim to every head that reads it.
  Future<void> pushSimulatedDailyBaselines() async {
    final source = _cardiac;
    // Note this is the UTC epoch day, NOT the local index `roll_day` takes.
    // The two are deliberately different: `epochDayFor` is UTC so a
    // wearable's daily rollups keep a stable day boundary as the person
    // travels, whereas `roll_day` is local because the daily accumulator is
    // tracking the person's day. Using one for the other misfiles a day's
    // baselines by up to a day in either direction.
    final dayIndex = Synheart.epochDayFor(DateTime.now());

    // Resting HR from the simulator's own resting rate, and RMSSD from its
    // trailing window — so the dailies agree with the beats that were streamed
    // rather than being a second, unrelated fiction.
    final restingHr = source == null ? 58.0 : source.restingBpm;
    final rmssd = source?.rmssdMs;

    Synheart.srmPushWearableDaily(
      dimension: 'resting_hr',
      dayIndex: dayIndex,
      value: restingHr,
      confidence: 0.85,
      fidelity: 1,
    );
    dailyPushes++;

    if (rmssd != null) {
      Synheart.srmPushWearableDaily(
        dimension: 'hrv_rmssd',
        dayIndex: dayIndex,
        value: rmssd,
        confidence: 0.85,
        fidelity: 1,
      );
      dailyPushes++;
    }

    // Incremental recompute, then propagate the resulting WearableReference so
    // the next window picks up fresh baselines.
    Synheart.srmTriggerWearableRecompute(triggerType: 0, asOfDay: dayIndex);

    // §7 — persist the longitudinal snapshot after every recompute. It is what
    // carries today's partial daily accumulator, so skipping it discards the
    // morning's cardiovascular load on a mid-day relaunch.
    final longitudinal = Synheart.longitudinalSnapshotJson;
    if (longitudinal != null) await _store?.writeLongitudinal(longitudinal);

    onChanged();
  }

  // ── Persistence (§7) ──────────────────────────────────────────────────

  /// Export session state. Called once per emitted window by the controller,
  /// and on background/terminate.
  Future<void> persistSessionState() async {
    final store = _store;
    if (store == null) return;
    final json = Synheart.exportSessionState();
    if (json == null || json.isEmpty) return;
    await store.writeSessionState(json);
    sessionStateSaves++;
  }

  Future<void> _persistAll({required bool sessionEnd}) async {
    final store = _store;
    if (store == null) return;
    await persistSessionState();

    final longitudinal = Synheart.longitudinalSnapshotJson;
    if (longitudinal != null) await store.writeLongitudinal(longitudinal);

    if (sessionEnd) {
      // SRM at session end. Without it the baselines report `Warming` forever
      // across launches, however many sessions the person completes.
      final srm = Synheart.exportRuntimeSRMSnapshot();
      if (srm != null) await store.writeSrm(_deviceClassKey, srm);
    }
  }

  /// Sizes of what is on disk, for the UI.
  Map<String, int> get storedSnapshotSizes =>
      _store?.storedSizes(_deviceClassKey) ?? const <String, int>{};

  /// Forget every persisted snapshot for this subject.
  Future<void> clearSnapshots() async {
    await _store?.clear();
    onChanged();
  }
}
