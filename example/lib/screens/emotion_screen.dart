import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/synheart_provider.dart';
import '../widgets/metric_card.dart';

/// Emotion screen showing emotion metrics
class EmotionScreen extends StatelessWidget {
  const EmotionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emotion'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<SynheartProvider>(
        builder: (context, provider, child) {
          if (!provider.emotionEnabled) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.psychology_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Emotion module not enabled',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Enable emotion module in settings',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          if (provider.latestEmotion == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.psychology_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No emotion data available',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Waiting for emotion data...',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          final emotion = provider.latestEmotion!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Primary Emotions
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.psychology,
                              color: Colors.purple.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Primary Emotions',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildEmotionBar('Stress', emotion.stress, Colors.red),
                        const SizedBox(height: 12),
                        _buildEmotionBar('Calm', emotion.calm, Colors.blue),
                        const SizedBox(height: 12),
                        _buildEmotionBar(
                          'Engagement',
                          emotion.engagement,
                          Colors.green,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Derived Metrics
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        label: 'Activation',
                        value: emotion.activation,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        label: 'Valence',
                        value: emotion.valence,
                        color: emotion.valence >= 0
                            ? Colors.purple
                            : Colors.pink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmotionBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              '${(value * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
