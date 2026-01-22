import 'package:flutter/material.dart';
import 'package:synheart_core/src/modules/wear/wear_source_handler.dart';
import 'package:synheart_core/src/modules/behavior/behavior_events.dart';

/// Widget for displaying raw data streams
class RawDataViewer extends StatelessWidget {
  final String title;
  final List<WearSample>? wearSamples;
  final List<BehaviorEvent>? behaviorEvents;
  final VoidCallback onClear;

  const RawDataViewer({
    super.key,
    required this.title,
    this.wearSamples,
    this.behaviorEvents,
    required this.onClear,
  }) : assert(
          (wearSamples != null) != (behaviorEvents != null),
          'Must provide either wearSamples or behaviorEvents',
        );

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: _buildDataList(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataList(BuildContext context) {
    if (wearSamples != null) {
      if (wearSamples!.isEmpty) {
        return Center(
          child: Text(
            'No wear samples yet. Start wear collection to see data.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        );
      }
      return ListView.builder(
        reverse: true, // Show latest first
        itemCount: wearSamples!.length,
        itemBuilder: (context, index) {
          final sample = wearSamples![index];
          return ListTile(
            dense: true,
            title: Text(
              'HR: ${sample.hr?.toStringAsFixed(1) ?? "N/A"} BPM',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            subtitle: Text(
              'HRV: ${sample.hrvRmssd?.toStringAsFixed(1) ?? "N/A"} ms | '
              'RR: ${sample.rrIntervals?.length ?? 0} intervals | '
              '${_formatTime(sample.timestamp)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      );
    } else if (behaviorEvents != null) {
      if (behaviorEvents!.isEmpty) {
        return Center(
          child: Text(
            'No behavior events yet. Start behavior collection to see data.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        );
      }
      return ListView.builder(
        reverse: true, // Show latest first
        itemCount: behaviorEvents!.length,
        itemBuilder: (context, index) {
          final event = behaviorEvents![index];
          return ListTile(
            dense: true,
            leading: Icon(_getEventIcon(event.type), size: 20),
            title: Text(
              event.type.name.toUpperCase(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            subtitle: Text(
              _formatTime(event.timestamp),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      );
    }
    return const SizedBox.shrink();
  }

  IconData _getEventIcon(BehaviorEventType type) {
    switch (type) {
      case BehaviorEventType.tap:
        return Icons.touch_app;
      case BehaviorEventType.scroll:
        return Icons.swipe;
      case BehaviorEventType.keyDown:
      case BehaviorEventType.keyUp:
        return Icons.keyboard;
      case BehaviorEventType.appSwitch:
        return Icons.swap_horiz;
      case BehaviorEventType.notificationReceived:
      case BehaviorEventType.notificationOpened:
        return Icons.notifications;
    }
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }
}

