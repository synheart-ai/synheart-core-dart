import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:synheart_core/synheart_core.dart' show HSIState, HSIAxisValue;

import '../sdk/synheart_controller.dart';
import '../widgets/ui.dart';

/// Step 3 — run a session and watch HSI arrive.
///
/// `initialize()` configures the SDK; it does not collect. Collection starts
/// here and stops at [SynheartController.stopSession].
///
/// The runtime closes an HSI window about every 60 seconds. It does so on that
/// cadence whether or not a biosignal arrived, emitting each axis at zero
/// confidence when it has no basis for one — so a steadily climbing window
/// count is not evidence that anything is being measured.
///
/// What grounds those axes is physiological signal. Behavior and motion are
/// collected and do reach the runtime, but they feed the digital and kinematic
/// modalities, which the Live HSI card renders separately. On a bare phone with
/// nothing attached the screen says all of this plainly rather than fabricating
/// beats: synthetic samples would flow into the same longitudinal baselines as
/// real ones and corrupt the reference ranges the runtime builds on device.
class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SynheartController>();
    final running = c.isSessionRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: StatusPill(
                running ? 'collecting' : 'stopped',
                tone: running ? PillTone.good : PillTone.neutral,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // One banner, not two: the SDK's own StateError says the same thing
          // as the consent precondition, so showing both stacked was noise.
          if (c.sessionError != null)
            ErrorBanner(c.sessionError!)
          else if (!c.hasCollectionConsent)
            const ErrorBanner(
              'No enabled feature has matching consent. A session needs both '
              'halves of a pair — the feature enabled in SynheartConfig and its '
              'consent granted. Grant biosignals, behavior, or phone context on '
              'the Consent tab; cloud upload, vendor sync, and research do not '
              'make any sensor readable on their own.',
            ),

          SectionCard(
            title: running ? 'Session running' : 'No active session',
            subtitle: running
                ? 'The runtime closes a window about every 60 seconds.'
                : 'Start a session to begin collection.',
            children: [
              SizedBox(
                width: double.infinity,
                child: running
                    ? OutlinedButton.icon(
                        onPressed: c.stopSession,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop session'),
                      )
                    : FilledButton.icon(
                        // Disabled without collection consent: the SDK now
                        // rejects that case anyway, and offering a button that
                        // throws is worse than one that is visibly unavailable.
                        onPressed: c.hasCollectionConsent
                            ? c.startSession
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start session'),
                      ),
              ),
              if (c.session != null) ...[
                const SizedBox(height: 12),
                KeyValueRow(
                  'session_id',
                  c.session!.sessionId,
                  selectable: true,
                ),
                KeyValueRow('mode', c.session!.mode.name),
              ],
            ],
          ),

          SectionCard(
            title: 'Live HSI',
            subtitle:
                'Typed HSIState from Synheart.onStateUpdate. Each window is '
                'parsed once and shared across listeners.',
            trailing: StatusPill('${c.hsiWindowCount} windows'),
            children: [
              if (c.latestState == null)
                Text(
                  running
                      ? 'Waiting for the first window…\n\n'
                            'The runtime closes one about every 60 seconds, so '
                            'the first can take a minute to appear.'
                      : 'Start a session to receive HSI.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                _AxisTable(state: c.latestState!),
            ],
          ),

          // Uploading needs no host code: the runtime subscribes to the engine's
          // HSI broadcast, enqueues each window itself, and POSTs on
          // CloudConfig.uploadInterval. This card exists to make that visible
          // and to force a flush — not to drive it.
          if (SynheartController.uploadConfigured)
            SectionCard(
              title: 'Cloud ingest',
              subtitle:
                  'The runtime uploads on its own: it enqueues every window as '
                  'it closes and POSTs on CloudConfig.uploadInterval. No host '
                  'code required. When nothing arrives, the cause is almost '
                  'always the consent gate below, not a missing call.',
              trailing: StatusPill(
                c.uploadError != null
                    ? 'error'
                    : c.uploadedCount > 0
                    ? 'uploaded ${c.uploadedCount}'
                    : 'nothing sent',
                tone: c.uploadError != null
                    ? PillTone.warn
                    : c.uploadedCount > 0
                    ? PillTone.good
                    : PillTone.neutral,
              ),
              children: [
                KeyValueRow('queued, not yet sent', '${c.uploadQueueLength}'),
                KeyValueRow('uploaded by Flush now', '${c.uploadedCount}'),
                KeyValueRow(
                  'last flush',
                  c.lastFlushAt?.toIso8601String().substring(11, 19) ?? '—',
                ),
                if (c.uploadError != null) ...[
                  const SizedBox(height: 8),
                  ErrorBanner(c.uploadError!),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: c.isFlushing ? null : c.flushUploads,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(c.isFlushing ? 'Flushing…' : 'Flush now'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The runtime flushes on its own schedule; this only forces '
                  'one early. The counter above tracks what these manual '
                  'flushes sent, so it can read 0 while automatic uploads are '
                  'succeeding — watch the queue depth for the real signal.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

          SectionCard(
            title: 'Signal sources',
            subtitle:
                'What is actually feeding the runtime. This example never '
                'fabricates biosignals — synthetic beats would corrupt the '
                'longitudinal baselines the runtime builds on this device.',
            trailing: StatusPill(
              c.hasBiosignalSource
                  ? 'receiving'
                  : c.wearEmittingButEmpty
                  ? 'empty samples'
                  : 'no signal',
              tone: c.hasBiosignalSource ? PillTone.good : PillTone.warn,
            ),
            children: [
              _SourceRow(
                label: 'Wear',
                detail: 'Heart rate, RR intervals, vendor HRV → runtime',
                active: c.isWearCollecting,
                reachesRuntime: true,
              ),
              _SourceRow(
                label: 'Behavior',
                detail:
                    'Taps, scrolls, swipes, app switches → digital modality',
                active: c.isBehaviorCollecting,
                reachesRuntime: true,
              ),
              _SourceRow(
                label: 'Phone',
                // Collected into an in-memory PhoneCache that nothing reads.
                // Unlike wear and behavior, PhoneModule has no runtime wiring,
                // so this data does not influence HSI.
                detail: 'Motion and device context — cached locally only',
                active: c.isPhoneCollecting,
                reachesRuntime: false,
              ),
              const Divider(height: 24),

              // Behavior needs no sensor, so on a phone with no wearable this
              // counter is the only live proof that collection is running.
              Text(
                'behavior events',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              KeyValueRow('captured', '${c.behaviorEventCount}'),
              if (c.behaviorBreakdown.isNotEmpty)
                KeyValueRow(
                  'by type',
                  c.behaviorBreakdown
                      .map((e) => '${e.key.name} ${e.value}')
                      .join(', '),
                ),
              if (c.behaviorEventCount == 0 && running)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Scroll or tap anywhere in this app to generate some. '
                    'Events are captured by the gesture detector that wraps '
                    'the screen content.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              const Divider(height: 24),
              if (!c.hasBiosignalSource) ...[
                KeyValueRow('samples emitted', '${c.wearSampleCount}'),
                KeyValueRow('carrying data', '${c.wearDataSampleCount}'),
                const SizedBox(height: 8),
                Text(
                  c.wearEmittingButEmpty
                      ? 'The wear source is emitting once per second, but every '
                            'sample so far is empty — no heart rate, no HRV, no '
                            'RR intervals.\n\n'
                            'This is the normal state on a phone with no '
                            'wearable paired, or with Health Connect / Apple '
                            'Health permission not yet granted. Watch the '
                            '"carrying data" count, not "samples emitted": the '
                            'latter climbs steadily either way.\n\n'
                            'All five axes stay at zero confidence until a real '
                            'reading arrives — including focus and capacity. '
                            'Behavior and motion are collected and do reach the '
                            'runtime, but they feed the kinematic and digital '
                            'modalities rather than these axes. Pair a BLE '
                            'chest strap or grant health-data access to ground '
                            'them.'
                      : 'No samples yet. HSI physiology is built from heart '
                            'rate and HRV, so pair a BLE chest strap, grant '
                            'health-data access, or connect a watch companion.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                KeyValueRow('samples emitted', '${c.wearSampleCount}'),
                KeyValueRow('carrying data', '${c.wearDataSampleCount}'),
                KeyValueRow(
                  'latest hr',
                  c.lastWearSample!.hr?.toStringAsFixed(1) ?? '—',
                ),
                KeyValueRow(
                  'latest rmssd',
                  c.lastWearSample!.hrvRmssd?.toStringAsFixed(1) ?? '—',
                ),
                KeyValueRow(
                  'rr intervals',
                  '${c.lastWearSample!.rrIntervals?.length ?? 0}',
                ),
                KeyValueRow(
                  'received',
                  c.lastWearSample!.timestamp.toIso8601String(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The five HSI 1.3 axes, with confidence.
///
/// A null axis means the engine has not produced a value yet — usually not
/// enough signal. That is distinct from a parse failure, which
/// [HSIState.hasParseError] reports separately.
/// One modality's presence in the current window, with its fidelity tier when
/// the runtime reported one. Lower tier number = higher fidelity.
class _ModalityChip extends StatelessWidget {
  const _ModalityChip({required this.label, required this.present, this.tier});

  final String label;
  final bool present;
  final int? tier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = present ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: present
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            present ? Icons.check_circle : Icons.remove_circle_outline,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            // Pair the tier with the label only when the modality is actually
            // present. The runtime reports a tier for modalities it did not
            // observe in the window, and "digital · tier 2" beside an absent
            // marker reads as a contradiction rather than as two separate
            // facts.
            present && tier != null ? '$label · tier $tier' : label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _AxisTable extends StatelessWidget {
  const _AxisTable({required this.state});

  final HSIState state;

  @override
  Widget build(BuildContext context) {
    // Needed to distinguish "nothing was collected" from "collection ran but
    // the runtime credited no modality" in the empty-modality copy below.
    final c = context.watch<SynheartController>();
    final axes = <String, HSIAxisValue?>{
      'focus': state.hsi.focus,
      'capacity': state.hsi.capacity,
      'arousal': state.hsi.arousal,
      'stress': state.hsi.stress,
      'sleep': state.hsi.sleep,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.hasParseError) ...[
          ErrorBanner('HSI parse failed: ${state.parseError}'),
        ],
        for (final entry in axes.entries)
          _AxisRow(name: entry.key, value: entry.value),

        // The digital domain — derived from interaction alone, so these are
        // the axes that resolve on a phone with no wearable attached. Shown
        // separately because they are scored differently: interruption
        // pressure is lower_is_more and interaction mode is bidirectional,
        // so neither reads like the five above.
        if (state.hsi.hasDigital) ...[
          const Divider(height: 20),
          Text(
            'digital axes — from interaction, no wearable needed',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          _AxisRow(name: 'focus quality', value: state.hsi.focusQuality),
          _AxisRow(
            name: 'interruption ↓',
            value: state.hsi.interruptionPressure,
          ),
          _AxisRow(name: 'interaction mode', value: state.hsi.interactionMode),
          const SizedBox(height: 6),
          Text(
            'interruption ↓ is lower_is_more: a low score means MORE '
            'interruption. interaction mode is bidirectional — neither end '
            'is better.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],

        const Divider(height: 20),

        // Which modalities the runtime saw in this window, derived from
        // `meta.provenance.sources[*].signals`.
        //
        // This is the answer to "the SDK is collecting but every axis says no
        // basis". The five axes above are physiology-derived; behavior and
        // motion land here instead. Without this row a developer on a phone
        // with no wearable sees five empty axes and reasonably concludes
        // nothing is working, when digital signal is in fact arriving.
        Text(
          'modalities in this window',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ModalityChip(
              label: 'physiological',
              present: state.modalities.physiological,
              tier: state.tiers.physiological,
            ),
            _ModalityChip(
              label: 'kinematic',
              present: state.modalities.kinematic,
              tier: state.tiers.kinematic,
            ),
            _ModalityChip(
              label: 'digital',
              present: state.modalities.digital,
              tier: state.tiers.digital,
            ),
          ],
        ),
        if (state.modalities.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            // Deliberately does not claim nothing was collected. Modality is
            // derived from `meta.provenance.sources[*].signals`, so a window
            // can carry behavior events the runtime never lists as a source —
            // watch the behavior counter below to tell the two apart.
            c.behaviorEventCount > 0
                ? 'The runtime listed no source in this window\'s provenance, '
                      'though ${c.behaviorEventCount} behavior events were '
                      'captured and pushed.\n\n'
                      'Digital readings lag by one window: the runtime flushes '
                      'interaction events for the window that just closed and '
                      'attaches them to the NEXT emission. Keep the session '
                      'running and watch the digital axes above.'
                : 'No modality is present. The runtime closed this window '
                      'without a source it recognised, so every axis is '
                      'reported at zero confidence.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ] else if (!state.modalities.physiological) ...[
          const SizedBox(height: 8),
          Text(
            'Signal is arriving, but none of it is physiological. The five '
            'axes above are derived from heart rate and HRV, so they stay at '
            'zero confidence until a wearable or BLE strap is connected.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],

        const Divider(height: 20),
        KeyValueRow(
          'timestamp',
          DateTime.fromMillisecondsSinceEpoch(
            state.timestampMs,
          ).toIso8601String(),
        ),
        KeyValueRow('subject', state.subjectId.isEmpty ? '—' : state.subjectId),
      ],
    );
  }
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({required this.name, required this.value});

  final String name;
  final HSIAxisValue? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    // Confidence 0.0 means the engine produced a number with nothing behind it.
    final grounded = v != null && v.confidence > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(name, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                // Draw nothing at zero confidence. The engine emits a value
                // alongside a confidence of 0.0 to say it has no basis for it;
                // rendering that as a half-filled bar reads as a real
                // measurement, which it is not.
                value: grounded ? v.value.clamp(0.0, 1.0) : 0,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 116,
            child: Text(
              v == null
                  ? 'no data'
                  : grounded
                  ? '${v.value.toStringAsFixed(2)}  conf ${v.confidence.toStringAsFixed(2)}'
                  : 'no basis',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: grounded
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One collection module and whether it is currently running.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.label,
    required this.detail,
    required this.active,
    required this.reachesRuntime,
  });

  final String label;
  final String detail;
  final bool active;

  /// Whether this module actually pushes into the native runtime.
  ///
  /// Not every collecting module does. Wear and behavior are wired through
  /// `setBridge` / `pushBehaviorToRuntime`; phone context is collected into a
  /// Dart-side cache with no consumer, so it never influences HSI. Showing all
  /// three as "collecting" under a heading that says "feeding the runtime"
  /// implied otherwise.
  final bool reachesRuntime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(
            !active
                ? 'idle'
                : reachesRuntime
                ? 'feeding'
                : 'local only',
            tone: !active
                ? PillTone.neutral
                : reachesRuntime
                ? PillTone.good
                : PillTone.neutral,
          ),
        ],
      ),
    );
  }
}
