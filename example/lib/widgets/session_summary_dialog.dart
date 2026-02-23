import 'package:flutter/material.dart';
import 'package:synheart_core/synheart_core.dart';

/// Dialog that shows a summary of the last captured HSI, Emotion, and Focus
/// state after a session is stopped.
class SessionSummaryDialog extends StatelessWidget {
  final HSI10Payload? hsi;
  final EmotionState? emotion;
  final FocusState? focus;

  const SessionSummaryDialog({
    super.key,
    this.hsi,
    this.emotion,
    this.focus,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = hsi != null || emotion != null || focus != null;

    return AlertDialog(
      title: const Text('Session Summary'),
      content: hasData
          ? SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hsi != null) ...[
                    _buildDomainSection(
                      context,
                      title: 'Affect',
                      icon: Icons.mood,
                      color: Colors.red.shade700,
                      readings: hsi!.axes?.affect?.readings ?? [],
                    ),
                    _buildDomainSection(
                      context,
                      title: 'Engagement',
                      icon: Icons.people,
                      color: Colors.green.shade700,
                      readings: hsi!.axes?.engagement?.readings ?? [],
                    ),
                    _buildDomainSection(
                      context,
                      title: 'Behavior',
                      icon: Icons.touch_app,
                      color: Colors.orange.shade700,
                      readings: hsi!.axes?.behavior?.readings ?? [],
                    ),
                  ],
                  if (emotion != null) ...[
                    const SizedBox(height: 12),
                    _buildSectionHeader(
                      context,
                      title: 'Emotion',
                      icon: Icons.psychology,
                      color: Colors.purple,
                    ),
                    const SizedBox(height: 8),
                    _buildAxisRow('Stress', emotion!.stress, Colors.purple),
                    _buildAxisRow('Calm', emotion!.calm, Colors.purple),
                    _buildAxisRow(
                        'Engagement', emotion!.engagement, Colors.purple),
                    _buildAxisRow(
                        'Activation', emotion!.activation, Colors.purple),
                    _buildAxisRow('Valence', emotion!.valence, Colors.purple),
                  ],
                  if (focus != null) ...[
                    const SizedBox(height: 12),
                    _buildSectionHeader(
                      context,
                      title: 'Focus',
                      icon: Icons.center_focus_strong,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    _buildAxisRow('Score', focus!.score, Colors.blue),
                    _buildAxisRow(
                        'Cognitive Load', focus!.cognitiveLoad, Colors.blue),
                    _buildAxisRow('Clarity', focus!.clarity, Colors.blue),
                    _buildAxisRow(
                        'Distraction', focus!.distraction, Colors.blue),
                  ],
                ],
              ),
            )
          : const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No data captured during this session',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildDomainSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<HSI10Reading> readings,
  }) {
    if (readings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _buildSectionHeader(context, title: title, icon: icon, color: color),
        const SizedBox(height: 8),
        ...readings.map(
          (r) => _buildAxisRow(r.axis, r.score, color),
        ),
      ],
    );
  }

  Widget _buildAxisRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: color.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
