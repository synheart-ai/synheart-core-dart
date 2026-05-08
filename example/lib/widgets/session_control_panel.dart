import 'package:flutter/material.dart';
import 'package:synheart_core/src/models/behavior_session_results.dart';

/// Widget for behavior session management
class SessionControlPanel extends StatelessWidget {
  final String? activeSessionId;
  final BehaviorSessionResults? lastSessionResults;
  final Future<String> Function() onStartSession;
  final Future<BehaviorSessionResults> Function() onStopSession;

  const SessionControlPanel({
    super.key,
    this.activeSessionId,
    this.lastSessionResults,
    required this.onStartSession,
    required this.onStopSession,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Start/Stop buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: activeSessionId == null
                  ? () async {
                      try {
                        await onStartSession();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Session started'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to start session: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: activeSessionId != null
                  ? () async {
                      try {
                        final results = await onStopSession();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Session ended. Focus: ${results.focusHint.toStringAsFixed(2)}',
                              ),
                              backgroundColor: Colors.blue,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to stop session: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),

        // Active session info
        if (activeSessionId != null) ...[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Session',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Session ID: $activeSessionId'),
                ],
              ),
            ),
          ),
        ],

        // Last session results
        if (lastSessionResults != null) ...[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last Session Results',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildResultRow(
                    'Duration',
                    '${(lastSessionResults!.durationMs / 1000).toStringAsFixed(1)}s',
                  ),
                  _buildResultRow(
                    'Tap Rate',
                    lastSessionResults!.tapRate.toStringAsFixed(2),
                  ),
                  _buildResultRow(
                    'Keystroke Rate',
                    lastSessionResults!.keystrokeRate.toStringAsFixed(2),
                  ),
                  _buildResultRow(
                    'Focus Hint',
                    lastSessionResults!.focusHint.toStringAsFixed(2),
                  ),
                  _buildResultRow(
                    'Interaction Intensity',
                    lastSessionResults!.interactionIntensity.toStringAsFixed(2),
                  ),
                  _buildResultRow(
                    'Burstiness',
                    lastSessionResults!.burstiness.toStringAsFixed(2),
                  ),
                  _buildResultRow(
                    'Total Events',
                    lastSessionResults!.totalEvents.toString(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
