import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:synheart_core/synheart_core.dart';
import '../providers/synheart_provider.dart';

/// HSI screen showing all axis readings from the HSI payload
class HSVScreen extends StatelessWidget {
  const HSVScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HSI State'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<SynheartProvider>(
        builder: (context, provider, child) {
          if (!provider.isInitialized || provider.latestHSI == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No HSI data available',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Initialize SDK to see data',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          final hsi = provider.latestHSI!;
          final axes = hsi.axes;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Affect Domain
                _buildDomainCard(
                  context,
                  title: 'Physiological',
                  icon: Icons.mood,
                  color: Colors.red.shade700,
                  domain: axes?.physiological,
                ),
                const SizedBox(height: 16),

                // Engagement Domain
                _buildDomainCard(
                  context,
                  title: 'Engagement',
                  icon: Icons.people,
                  color: Colors.green.shade700,
                  domain: axes?.engagement,
                ),
                const SizedBox(height: 16),

                // Behavior Domain
                _buildDomainCard(
                  context,
                  title: 'Behavior',
                  icon: Icons.touch_app,
                  color: Colors.orange.shade700,
                  domain: axes?.behavior,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDomainCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    HSI11Domain? domain,
  }) {
    final readings = domain?.readings ?? [];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  '$title Axes',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (readings.isEmpty)
              const Text(
                'No readings available',
                style: TextStyle(color: Colors.grey),
              )
            else
              ...readings.map((reading) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildAxisRow(
                  reading.axis,
                  reading.score,
                  color,
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildAxisRow(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
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
    );
  }
}
