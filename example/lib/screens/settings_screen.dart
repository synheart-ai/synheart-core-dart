import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/synheart_provider.dart';
import '../widgets/feature_toggle_card.dart';
import '../widgets/hsi_export_viewer.dart';

/// Settings screen with feature toggles and configuration
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<SynheartProvider>(
        builder: (context, provider, child) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Feature Toggles
              Text(
                'Features',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Cloud Sync - only show if cloud config is provided
              if (provider.sdkConfig?.cloudConfig != null) ...[
                FeatureToggleCard(
                  title: 'Cloud Sync',
                  description: 'Upload data to cloud (requires consent)',
                  enabled: provider.cloudSyncEnabled,
                  icon: Icons.cloud,
                  enabledColor: Colors.blue,
                  onToggle: () => _handleCloudSyncToggle(context, provider),
                ),
                const SizedBox(height: 12),
              ],
              FeatureToggleCard(
                title: 'Emotion Module',
                description: 'Real-time emotion estimation',
                enabled: provider.emotionEnabled,
                icon: Icons.psychology,
                enabledColor: Colors.purple,
                onToggle: () => _handleEmotionToggle(context, provider),
              ),
              const SizedBox(height: 12),
              FeatureToggleCard(
                title: 'Focus Module',
                description: 'Real-time focus and engagement estimation',
                enabled: provider.focusEnabled,
                icon: Icons.center_focus_strong,
                enabledColor: Colors.blue,
                onToggle: () => _handleFocusToggle(context, provider),
              ),
              const SizedBox(height: 24),

              // SDK Status
              Text(
                'SDK Status',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            provider.isInitialized
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: provider.isInitialized
                                ? Colors.green
                                : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            provider.isInitialized
                                ? 'SDK Initialized'
                                : 'SDK Not Initialized',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (provider.userId != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'User ID: ${provider.userId}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // HSI Export
              Text(
                'HSI Export',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    height: 300,
                    child: HSIExportViewer(hsv: provider.latestHSV),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleCloudSyncToggle(BuildContext context, SynheartProvider provider) {
    if (provider.cloudSyncEnabled) {
      // Disable cloud sync
      provider.disableCloudSync();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud sync disabled'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      // Enable cloud sync - check consent first
      if (!provider.hasConsentToken) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please grant consent first'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pushNamed('/consent');
      } else {
        provider.enableCloudSync();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cloud sync enabled'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _handleEmotionToggle(BuildContext context, SynheartProvider provider) {
    if (provider.emotionEnabled) {
      provider.disableEmotion();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emotion module disabled'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      provider.enableEmotion();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emotion module enabled'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _handleFocusToggle(BuildContext context, SynheartProvider provider) {
    if (provider.focusEnabled) {
      provider.disableFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Focus module disabled'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      provider.enableFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Focus module enabled'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
