import 'package:flutter/material.dart';

/// Card widget for feature toggles
class FeatureToggleCard extends StatelessWidget {
  final String title;
  final String description;
  final bool enabled;
  final bool isLoading;
  final IconData icon;
  final Color enabledColor;
  final Color disabledColor;
  final VoidCallback? onToggle;

  const FeatureToggleCard({
    super.key,
    required this.title,
    required this.description,
    required this.enabled,
    required this.icon,
    this.isLoading = false,
    this.enabledColor = Colors.green,
    this.disabledColor = Colors.grey,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: enabled ? 2 : 1,
      color: enabled
          ? enabledColor.withOpacity(0.1)
          : Colors.grey.shade50,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: enabled
                      ? enabledColor.withOpacity(0.2)
                      : disabledColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: enabled ? enabledColor : disabledColor,
                  size: 24,
                ),
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
                            color: enabled ? enabledColor : Colors.grey.shade700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch(
                  value: enabled,
                  onChanged: onToggle != null ? (_) => onToggle!() : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

