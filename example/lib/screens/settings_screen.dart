import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/synheart_provider.dart';
import '../widgets/feature_toggle_card.dart';
import '../widgets/hsi_export_viewer.dart';

/// Settings screen with feature toggles and configuration
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _consentUrlController;
  late final TextEditingController _appIdController;
  late final TextEditingController _appApiKeyController;
  bool _consentSaving = false;

  @override
  void initState() {
    super.initState();
    _consentUrlController = TextEditingController();
    _appIdController = TextEditingController();
    _appApiKeyController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<SynheartProvider>();
      await provider.loadConsentCredentialsFromStorage();
      if (mounted) {
        setState(() {
          _consentUrlController.text = provider.savedConsentServiceUrl;
          _appIdController.text = provider.savedConsentAppId;
          _appApiKeyController.text = provider.savedConsentAppApiKey;
        });
      }
    });
  }

  @override
  void dispose() {
    _consentUrlController.dispose();
    _appIdController.dispose();
    _appApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveConsentCredentials(
    BuildContext context,
    SynheartProvider provider,
  ) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _consentSaving = true);
    try {
      await provider.saveConsentCredentials(
        consentServiceUrl: _consentUrlController.text,
        appId: _appIdController.text,
        appApiKey: _appApiKeyController.text,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Consent API saved. Re-initialize SDK to use new values.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _consentSaving = false);
    }
  }

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
              // Consent API credentials
              Text(
                'Consent API',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Stored locally. Used when initializing the SDK and for consent profile / token calls. Re-initialize SDK after saving.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _consentUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Consent service URL',
                            hintText: 'https://your-platform.example.com',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final u = Uri.tryParse(v.trim());
                            if (u == null || !u.hasScheme) {
                              return 'Enter a valid URL';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _appIdController,
                          decoration: const InputDecoration(
                            labelText: 'App ID',
                            hintText: 'app_synheart_xxx',
                            border: OutlineInputBorder(),
                          ),
                          autocorrect: false,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _appApiKeyController,
                          decoration: const InputDecoration(
                            labelText: 'App API key',
                            hintText: 'synheart_sk_live_...',
                            border: OutlineInputBorder(),
                          ),
                          obscureText: true,
                          autocorrect: false,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _consentSaving
                              ? null
                              : () =>
                                    _saveConsentCredentials(context, provider),
                          icon: _consentSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _consentSaving ? 'Saving...' : 'Save consent API',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

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
                    child: HSIExportViewer(hsiJson: provider.latestHSI),
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
}
