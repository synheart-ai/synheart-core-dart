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
          else if (!c.hasAnyConsent)
            const ErrorBanner(
              'No collection channel is granted. Grant at least biosignals on '
              'the Consent tab, or the runtime will drop every HSI window.',
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
                        onPressed: c.startSession,
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
              c.hasBiosignalSource ? 'receiving' : 'no signal',
              tone: c.hasBiosignalSource ? PillTone.good : PillTone.warn,
            ),
            children: [
              _SourceRow(
                label: 'Wear',
                detail: 'Heart rate and HRV',
                active: c.isWearCollecting,
              ),
              _SourceRow(
                label: 'Phone',
                detail: 'Motion and device context',
                active: c.isPhoneCollecting,
              ),
              _SourceRow(
                label: 'Behavior',
                detail: 'Taps and typing rhythm',
                active: c.isBehaviorCollecting,
              ),
              const Divider(height: 24),
              if (c.lastWearSample == null)
                Text(
                  'No biosignal samples yet.\n\n'
                  'HSI is built from heart rate and HRV, so the runtime cannot '
                  'produce a window until a real source is attached. Connect a '
                  'BLE chest strap, grant Apple Health / Health Connect access, '
                  'or pair a watch companion.\n\n'
                  'If you own a source the SDK does not adapt, push its real '
                  'readings with Synheart.pushRrBatch — never placeholder '
                  'values, which would enter the same baselines as real data.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                KeyValueRow('samples', '${c.wearSampleCount}'),
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
                value: v?.value.clamp(0.0, 1.0) ?? 0,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(
              v == null
                  ? 'no data'
                  : '${v.value.toStringAsFixed(2)}  ±${(1 - v.confidence).toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: v == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
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
  });

  final String label;
  final String detail;
  final bool active;

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
            active ? 'collecting' : 'idle',
            tone: active ? PillTone.good : PillTone.neutral,
          ),
        ],
      ),
    );
  }
}
