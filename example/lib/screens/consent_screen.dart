import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:synheart_core/synheart_core.dart';
import '../providers/synheart_provider.dart';
import 'home_screen.dart';

/// Consent screen for managing consent
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  // User's consent choices
  bool _biosignals = false;
  bool _behavior = false;
  bool _motion = false;
  bool _cloudUpload = false;
  String? _selectedProfileId;
  bool _isGranting = false;

  @override
  void initState() {
    super.initState();
    // Load profiles if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<SynheartProvider>(context, listen: false);
      if (provider.needsConsent && provider.availableProfiles.isEmpty) {
        provider.fetchConsentProfiles();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consent Management'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: Consumer<SynheartProvider>(
        builder: (context, provider, child) {
          // If consent is needed, show consent form
          if (provider.needsConsent) {
            return _buildConsentForm(context, provider);
          }

          // Otherwise, show consent status and management
          return _buildConsentStatus(context, provider);
        },
      ),
    );
  }

  /// Build consent form for first-time consent
  Widget _buildConsentForm(BuildContext context, SynheartProvider provider) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with icon
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.verified_user,
                      size: 48,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Data Collection Consent',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Please review and grant consent for the data collection features you want to enable. You can change these settings later.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withOpacity(
                        0.8,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Consent Options
            if (provider.consentInfo.containsKey('biosignals')) ...[
              _buildConsentOption(
                context,
                title: 'Biosignals',
                description: provider.consentInfo['biosignals']!,
                icon: Icons.favorite,
                color: const Color(0xFFE91E63),
                value: _biosignals,
                onChanged: (value) => setState(() => _biosignals = value),
              ),
              const SizedBox(height: 16),
            ],

            if (provider.consentInfo.containsKey('behavior')) ...[
              _buildConsentOption(
                context,
                title: 'Behavior',
                description: provider.consentInfo['behavior']!,
                icon: Icons.touch_app,
                color: const Color(0xFFFF9800),
                value: _behavior,
                onChanged: (value) => setState(() => _behavior = value),
              ),
              const SizedBox(height: 16),
            ],

            if (provider.consentInfo.containsKey('motion')) ...[
              _buildConsentOption(
                context,
                title: 'Motion & Phone Context',
                description: provider.consentInfo['motion']!,
                icon: Icons.phone_android,
                color: const Color(0xFF4CAF50),
                value: _motion,
                onChanged: (value) => setState(() => _motion = value),
              ),
              const SizedBox(height: 16),
            ],

            // Cloud Upload (only if CloudConfig is provided)
            if (provider.consentInfo.containsKey('cloudUpload')) ...[
              _buildConsentOption(
                context,
                title: 'Cloud Upload',
                description: provider.consentInfo['cloudUpload']!,
                icon: Icons.cloud,
                color: const Color(0xFF2196F3),
                value: _cloudUpload,
                onChanged: (value) => setState(() => _cloudUpload = value),
              ),
              const SizedBox(height: 32),

              // Profile Selection (if profiles are available)
              if (provider.availableProfiles.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.list_alt,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Select Consent Profile',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...provider.availableProfiles.map((profile) {
                        final isSelected = _selectedProfileId == profile.id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline.withOpacity(0.2),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _cloudUpload
                                  ? () => setState(
                                      () => _selectedProfileId = profile.id,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    if (profile.isDefault)
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.star,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    if (profile.isDefault)
                                      const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            profile.name,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          if (profile
                                              .description
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              profile.description,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.7),
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (profile.cloudEnabled)
                                      Icon(
                                        Icons.cloud,
                                        color: Colors.blue.shade400,
                                        size: 24,
                                      )
                                    else
                                      Icon(
                                        Icons.cloud_off,
                                        color: Colors.grey.shade400,
                                        size: 24,
                                      ),
                                    const SizedBox(width: 8),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: theme.colorScheme.primary,
                                        size: 24,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ] else if (_cloudUpload) ...[
                // Show loading or fetch button if profiles not loaded
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Loading consent profiles...',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await provider.fetchConsentProfiles();
                          if (provider.availableProfiles.isNotEmpty) {
                            setState(() {});
                          }
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],

            // Error Message
            if (provider.hasError) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        provider.errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => provider.clearError(),
                      color: Colors.red.shade700,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Grant Consent Button
            FilledButton.icon(
              onPressed: _isGranting
                  ? null
                  : () => _grantConsent(context, provider),
              icon: _isGranting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(
                _isGranting ? 'Granting Consent...' : 'Grant Consent',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 12),

            // Cancel Button
            OutlinedButton(
              onPressed: _isGranting ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build consent status view (after consent is granted)
  Widget _buildConsentStatus(BuildContext context, SynheartProvider provider) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: provider.hasConsentToken
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: provider.hasConsentToken
                      ? Colors.green.shade200
                      : Colors.orange.shade200,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: provider.hasConsentToken
                          ? Colors.green
                          : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      provider.hasConsentToken
                          ? Icons.check_circle
                          : Icons.pending,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.hasConsentToken
                              ? 'Consent Granted'
                              : 'Consent Pending',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: provider.hasConsentToken
                                ? Colors.green.shade900
                                : Colors.orange.shade900,
                          ),
                        ),
                        if (provider.currentToken != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Token expires: ${provider.currentToken!.expiresAt}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: provider.hasConsentToken
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Error Message
            if (provider.hasError) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        provider.errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => provider.clearError(),
                      color: Colors.red.shade700,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Token Display
            if (provider.currentToken != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExpansionTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.vpn_key,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: const Text(
                    'Consent Token',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Profile: ${provider.currentToken!.profileId}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(
                            'Profile ID',
                            provider.currentToken!.profileId,
                            theme,
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            'Expires At',
                            provider.currentToken!.expiresAt.toString(),
                            theme,
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            'Is Valid',
                            provider.currentToken!.isValid.toString(),
                            theme,
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            'Scopes',
                            provider.currentToken!.scopes.join(', '),
                            theme,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Actions
            if (!provider.hasConsentToken) ...[
              FilledButton.icon(
                onPressed: () => _fetchAndShowProfiles(context, provider),
                icon: const Icon(Icons.refresh),
                label: const Text('Fetch Consent Profiles'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: () => _showRevokeDialog(context, provider),
                icon: const Icon(Icons.cancel),
                label: const Text('Revoke Consent'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConsentOption(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value
              ? color.withOpacity(0.5)
              : theme.colorScheme.outline.withOpacity(0.2),
          width: value ? 2 : 1,
        ),
        boxShadow: value
            ? [
                BoxShadow(
                  color: color.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: 1.2,
                            child: Switch(
                              value: value,
                              onChanged: onChanged,
                              activeColor: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _grantConsent(
    BuildContext context,
    SynheartProvider provider,
  ) async {
    // Validate: if cloudUpload is selected, profile must be selected
    if (_cloudUpload && _selectedProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('Please select a consent profile for cloud upload'),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      );
      return;
    }

    setState(() => _isGranting = true);

    try {
      await provider.grantConsent(
        biosignals: _biosignals,
        behavior: _behavior,
        motion: _motion,
        cloudUpload: _cloudUpload,
        profileId: _cloudUpload ? _selectedProfileId : null,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Consent granted successfully!')),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        );

        // Wait a bit for the snackbar to show, then navigate back
        await Future.delayed(const Duration(milliseconds: 500));

        if (context.mounted) {
          // Navigate back if consent was granted
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            // If we can't pop, replace with home screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to grant consent: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGranting = false);
      }
    }
  }

  Future<void> _fetchAndShowProfiles(
    BuildContext context,
    SynheartProvider provider,
  ) async {
    try {
      await provider.fetchConsentProfiles();
      if (provider.availableProfiles.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No consent profiles available'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        final selected = await showDialog<ConsentProfile>(
          context: context,
          builder: (context) =>
              _ProfileSelectionDialog(profiles: provider.availableProfiles),
        );

        if (selected != null) {
          await provider.requestConsent(selected);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Consent granted successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            // Enable cloud sync after consent
            await provider.enableCloudSync();
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showRevokeDialog(BuildContext context, SynheartProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 12),
            Text('Revoke Consent'),
          ],
        ),
        content: const Text(
          'Are you sure you want to revoke consent? This will clear your token and stop cloud uploads.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await provider.revokeConsent();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Consent revoked'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }
}

class _ProfileSelectionDialog extends StatelessWidget {
  final List<ConsentProfile> profiles;

  const _ProfileSelectionDialog({required this.profiles});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Select Consent Profile'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final profile = profiles[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: profile.isDefault
                    ? Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.star,
                          color: Colors.white,
                          size: 20,
                        ),
                      )
                    : const Icon(Icons.radio_button_unchecked),
                title: Text(profile.name),
                subtitle: Text(profile.description),
                trailing: profile.cloudEnabled
                    ? const Icon(Icons.cloud, color: Colors.blue)
                    : const Icon(Icons.cloud_off, color: Colors.grey),
                onTap: () => Navigator.of(context).pop(profile),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
