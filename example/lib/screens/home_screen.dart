import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/synheart_provider.dart';
import '../widgets/feature_toggle_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/status_indicator.dart';
import 'hsv_screen.dart';
import 'emotion_screen.dart';
import 'focus_screen.dart';
import 'behavior_screen.dart';
import 'consent_screen.dart';
import 'settings_screen.dart';

/// Home screen with feature overview and toggles
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Synheart SDK',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: Consumer<SynheartProvider>(
        builder: (context, provider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // SDK Status Card
                _buildSDKStatusCard(context, provider),
                const SizedBox(height: 16),

                // Error Message
                if (provider.hasError) ...[
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              provider.errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => provider.clearError(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Feature Toggles - Show only features with enabled configs
                Text(
                  'Features',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Wear Module (Biosignals) - only show if wearConfig is provided
                if (provider.sdkConfig?.wearConfig != null) ...[
                  FeatureToggleCard(
                    title: 'Biosignals',
                    description:
                        provider.consentInfo['biosignals'] ??
                        'Collect heart rate, HRV, and other biosignals from wearables',
                    enabled: provider.consentStatusMap['biosignals'] ?? false,
                    icon: Icons.favorite,
                    enabledColor: Colors.red,
                    onToggle: () => _handleBiosignalsToggle(context, provider),
                  ),
                  const SizedBox(height: 12),
                ],

                // Phone Module (Motion) - only show if phoneConfig is provided
                if (provider.sdkConfig?.phoneConfig != null) ...[
                  FeatureToggleCard(
                    title: 'Motion & Phone Context',
                    description:
                        provider.consentInfo['motion'] ??
                        'Collect motion and phone context data',
                    enabled: provider.consentStatusMap['motion'] ?? false,
                    icon: Icons.phone_android,
                    enabledColor: Colors.green,
                    onToggle: () => _handleMotionToggle(context, provider),
                  ),
                  const SizedBox(height: 12),
                ],

                // Behavior Module - only show if behaviorConfig is provided
                if (provider.sdkConfig?.behaviorConfig != null) ...[
                  FeatureToggleCard(
                    title: 'Behavior',
                    description:
                        provider.consentInfo['behavior'] ??
                        'Collect behavioral data and interaction patterns',
                    enabled: provider.consentStatusMap['behavior'] ?? false,
                    icon: Icons.touch_app,
                    enabledColor: Colors.orange,
                    onToggle: () => _handleBehaviorToggle(context, provider),
                  ),
                  const SizedBox(height: 12),
                ],

                // Interpretation Modules (Emotion and Focus)
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

                // Quick Metrics Preview
                if (provider.isInitialized && provider.latestHSV != null) ...[
                  Text(
                    'Current State',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          label: 'Arousal',
                          value:
                              provider.latestAxes?.affect.arousalIndex ?? 0.0,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetricCard(
                          label: 'Engagement',
                          value:
                              provider
                                  .latestAxes
                                  ?.engagement
                                  .engagementStability ??
                              0.0,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (provider.emotionEnabled &&
                      provider.latestEmotion != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: MetricCard(
                            label: 'Stress',
                            value: provider.latestEmotion!.stress,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MetricCard(
                            label: 'Calm',
                            value: provider.latestEmotion!.calm,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (provider.focusEnabled &&
                      provider.latestFocus != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: MetricCard(
                            label: 'Focus',
                            value: provider.latestFocus!.score,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MetricCard(
                            label: 'Cognitive Load',
                            value: provider.latestFocus!.cognitiveLoad,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ],

                // Navigation Cards
                Text(
                  'Explore',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildNavigationCard(
                  context,
                  'HSV State',
                  'View all state axes',
                  Icons.analytics,
                  Colors.indigo,
                  () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const HSVScreen())),
                ),
                const SizedBox(height: 12),
                _buildNavigationCard(
                  context,
                  'Behavior',
                  'Interaction patterns',
                  Icons.touch_app,
                  Colors.amber,
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BehaviorScreen()),
                  ),
                ),
                if (provider.emotionEnabled) ...[
                  const SizedBox(height: 12),
                  _buildNavigationCard(
                    context,
                    'Emotion',
                    'Emotion metrics',
                    Icons.psychology,
                    Colors.purple,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EmotionScreen()),
                    ),
                  ),
                ],
                if (provider.focusEnabled) ...[
                  const SizedBox(height: 12),
                  _buildNavigationCard(
                    context,
                    'Focus',
                    'Focus metrics',
                    Icons.center_focus_strong,
                    Colors.blue,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FocusScreen()),
                    ),
                  ),
                ],
                // Consent navigation - show if cloud config is provided
                if (provider.sdkConfig?.cloudConfig != null) ...[
                  const SizedBox(height: 12),
                  _buildNavigationCard(
                    context,
                    'Consent',
                    'Manage consent and tokens',
                    Icons.verified_user,
                    Colors.green,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ConsentScreen()),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: Consumer<SynheartProvider>(
        builder: (context, provider, child) {
          // Don't show FAB if SDK is not initialized (button is in status card)
          if (!provider.isInitialized) {
            return const SizedBox.shrink();
          }

          // Show consent button if consent is needed
          if (provider.needsConsent) {
            return FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConsentScreen()),
                );
              },
              backgroundColor: Colors.orange,
              icon: const Icon(Icons.verified_user),
              label: const Text('Grant Consent'),
            );
          }

          return FloatingActionButton(
            onPressed: () => provider.stop(),
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.stop),
          );
        },
      ),
    );
  }

  Widget _buildSDKStatusCard(BuildContext context, SynheartProvider provider) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: provider.isInitialized
            ? Colors.green.shade50
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: provider.isInitialized
              ? Colors.green.shade200
              : theme.colorScheme.outline.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: provider.isInitialized
                      ? Colors.green.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  provider.isInitialized
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: provider.isInitialized ? Colors.green : Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.isInitialized ? 'SDK Active' : 'SDK Inactive',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      provider.isInitialized
                          ? 'Collecting and processing data'
                          : 'Initialize SDK to start',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!provider.isInitialized) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: provider.isInitializing
                    ? null
                    : () => _showInitializeDialog(context, provider),
                icon: provider.isInitializing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  provider.isInitializing
                      ? 'Initializing...'
                      : 'Initialize SDK',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
          if (provider.isInitialized) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusIndicator(
                  label: 'HSV',
                  isActive: provider.latestHSV != null,
                  icon: Icons.analytics,
                ),
                if (provider.emotionEnabled)
                  StatusIndicator(
                    label: 'Emotion',
                    isActive: provider.latestEmotion != null,
                    icon: Icons.psychology,
                  ),
                if (provider.focusEnabled)
                  StatusIndicator(
                    label: 'Focus',
                    isActive: provider.latestFocus != null,
                    icon: Icons.center_focus_strong,
                  ),
                if (provider.sdkConfig?.cloudConfig != null &&
                    provider.cloudSyncEnabled)
                  StatusIndicator(
                    label: 'Cloud',
                    isActive: provider.hasConsentToken,
                    icon: Icons.cloud,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavigationCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBiosignalsToggle(
    BuildContext context,
    SynheartProvider provider,
  ) {
    final hasConsent = provider.consentStatusMap['biosignals'] ?? false;
    if (hasConsent) {
      // Revoke consent (disable feature)
      _showRevokeConsentDialog(
        context,
        provider,
        'biosignals',
        'Biosignals',
        'This will stop collecting heart rate and HRV data from your wearable device.',
      );
    } else {
      // Grant consent (enable feature) - show grant dialog
      _showGrantConsentDialog(
        context,
        provider,
        'biosignals',
        'Biosignals',
        provider.consentInfo['biosignals'] ??
            'Collect heart rate, HRV, and other biosignals from wearables',
      );
    }
  }

  void _handleMotionToggle(BuildContext context, SynheartProvider provider) {
    final hasConsent = provider.consentStatusMap['motion'] ?? false;
    if (hasConsent) {
      // Revoke consent (disable feature)
      _showRevokeConsentDialog(
        context,
        provider,
        'motion',
        'Motion & Phone Context',
        'This will stop collecting motion and phone context data.',
      );
    } else {
      // Grant consent (enable feature) - show grant dialog
      _showGrantConsentDialog(
        context,
        provider,
        'motion',
        'Motion & Phone Context',
        provider.consentInfo['motion'] ??
            'Collect motion and phone context data',
      );
    }
  }

  void _handleBehaviorToggle(BuildContext context, SynheartProvider provider) {
    final hasConsent = provider.consentStatusMap['behavior'] ?? false;
    if (hasConsent) {
      // Revoke consent (disable feature)
      _showRevokeConsentDialog(
        context,
        provider,
        'behavior',
        'Behavior',
        'This will stop collecting behavioral data and interaction patterns.',
      );
    } else {
      // Grant consent (enable feature) - show grant dialog
      _showGrantConsentDialog(
        context,
        provider,
        'behavior',
        'Behavior',
        provider.consentInfo['behavior'] ??
            'Collect behavioral data and interaction patterns',
      );
    }
  }

  void _handleEmotionToggle(BuildContext context, SynheartProvider provider) {
    if (provider.emotionEnabled) {
      provider.disableEmotion();
    } else {
      provider.enableEmotion();
    }
  }

  void _handleFocusToggle(BuildContext context, SynheartProvider provider) {
    if (provider.focusEnabled) {
      provider.disableFocus();
    } else {
      provider.enableFocus();
    }
  }

  void _showGrantConsentDialog(
    BuildContext context,
    SynheartProvider provider,
    String consentType,
    String featureName,
    String description,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enable $featureName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            const SizedBox(height: 16),
            const Text(
              'This will start collecting data for this feature. You can disable it at any time.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                // Get current consent status
                final currentConsent = provider.currentConsentSnapshot;

                // Grant consent for this specific feature
                await provider.grantConsent(
                  biosignals: consentType == 'biosignals'
                      ? true
                      : currentConsent.biosignals,
                  behavior: consentType == 'behavior'
                      ? true
                      : currentConsent.behavior,
                  motion: consentType == 'motion'
                      ? true
                      : currentConsent.motion,
                  cloudUpload: currentConsent
                      .cloudUpload, // Keep existing cloud upload consent
                  profileId:
                      null, // No profile needed for individual feature consent
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$featureName enabled'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to enable $featureName: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  void _showRevokeConsentDialog(
    BuildContext context,
    SynheartProvider provider,
    String consentType,
    String featureName,
    String description,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Revoke $featureName Consent'),
        content: Text(
          '$description\n\nData collection for this feature will stop immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await provider.revokeConsentType(consentType);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$featureName consent revoked'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to revoke consent: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }

  void _showInitializeDialog(BuildContext context, SynheartProvider provider) {
    showDialog(
      context: context,
      builder: (context) => _InitializeDialog(provider: provider),
    );
  }
}

class _InitializeDialog extends StatefulWidget {
  final SynheartProvider provider;

  const _InitializeDialog({required this.provider});

  @override
  State<_InitializeDialog> createState() => _InitializeDialogState();
}

class _InitializeDialogState extends State<_InitializeDialog> {
  final _userIdController = TextEditingController();
  bool _isInitializing = false;

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Initialize SDK'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _userIdController,
            decoration: const InputDecoration(
              labelText: 'User ID',
              hintText: 'Enter user ID or leave empty for auto',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isInitializing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isInitializing ? null : _initialize,
          child: _isInitializing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Initialize'),
        ),
      ],
    );
  }

  Future<void> _initialize() async {
    setState(() => _isInitializing = true);

    try {
      final userId = _userIdController.text.trim().isEmpty
          ? 'user_${DateTime.now().millisecondsSinceEpoch}'
          : _userIdController.text.trim();

      await widget.provider.initialize(userId: userId);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SDK initialized successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Initialization failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }
}
