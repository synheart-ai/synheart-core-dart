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
/// HSI windows close roughly every 10 seconds, and only when a real biosignal
/// source is supplying heart rate and HRV. On a bare phone with nothing
/// attached the Signal sources card says so plainly rather than fabricating
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
                ? 'Windows close about every 10 seconds, given enough signal.'
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
                            'If nothing arrives, push some beats below — the '
                            'runtime needs samples before it can close a window.'
                      : 'Start a session to receive HSI.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                _AxisTable(state: c.latestState!),
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
                detail: 'Taps, notifications, app switches → runtime',
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
                            'The physiological axes (arousal, stress, sleep) '
                            'stay empty until a real reading arrives. Focus and '
                            'capacity can still be computed from behavior and '
                            'motion, which are arriving.'
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
class _AxisTable extends StatelessWidget {
  const _AxisTable({required this.state});

  final HSIState state;

  @override
  Widget build(BuildContext context) {
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
