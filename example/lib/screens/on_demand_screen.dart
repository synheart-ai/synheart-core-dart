import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:synheart_core/synheart_core.dart';
import '../providers/synheart_provider.dart';
import '../widgets/module_control_card.dart';
import '../widgets/raw_data_viewer.dart';
import '../widgets/session_control_panel.dart';

/// Screen demonstrating on-demand data collection
///
/// Shows:
/// - Module start/stop controls
/// - Raw data stream viewers
/// - Behavior session management
/// - On-demand feature queries
/// - Game scenario demo
class OnDemandScreen extends StatefulWidget {
  const OnDemandScreen({super.key});

  @override
  State<OnDemandScreen> createState() => _OnDemandScreenState();
}

class _OnDemandScreenState extends State<OnDemandScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('On-Demand Collection'),
        elevation: 0,
      ),
      body: Consumer<SynheartProvider>(
        builder: (context, provider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Module Controls Section
              _buildSection(
                title: 'Module Controls',
                child: Column(
                  children: [
                    ModuleControlCard(
                      moduleName: 'Wear',
                      isCollecting: Synheart.isWearCollecting,
                      onStart: () => provider.startWearCollection(),
                      onStop: () => provider.stopWearCollection(),
                      onStartWithInterval: (interval) =>
                          provider.startWearCollection(interval: interval),
                    ),
                    const SizedBox(height: 12),
                    ModuleControlCard(
                      moduleName: 'Behavior',
                      isCollecting: Synheart.isBehaviorCollecting,
                      onStart: () => provider.startBehaviorCollection(),
                      onStop: () => provider.stopBehaviorCollection(),
                    ),
                    const SizedBox(height: 12),
                    ModuleControlCard(
                      moduleName: 'Phone',
                      isCollecting: Synheart.isPhoneCollecting,
                      onStart: () => provider.startPhoneCollection(),
                      onStop: () => provider.stopPhoneCollection(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Raw Data Streams Section
              _buildSection(
                title: 'Raw Data Streams',
                child: Column(
                  children: [
                    RawDataViewer(
                      title: 'Wear Samples',
                      wearSamples: provider.recentWearSamples,
                      onClear: () => provider.clearWearSamples(),
                    ),
                    const SizedBox(height: 12),
                    RawDataViewer(
                      title: 'Behavior Events',
                      behaviorEvents: provider.recentBehaviorEvents,
                      onClear: () => provider.clearBehaviorEvents(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Behavior Session Section
              _buildSection(
                title: 'Behavior Session',
                child: SessionControlPanel(
                  activeSessionId: provider.activeBehaviorSessionId,
                  lastSessionResults: provider.lastSessionResults,
                  onStartSession: () => provider.startBehaviorSession(),
                  onStopSession: () => provider.stopBehaviorSession(),
                ),
              ),

              const SizedBox(height: 24),

              // On-Demand Queries Section
              _buildSection(
                title: 'On-Demand Queries',
                child: _buildQuerySection(provider),
              ),

              const SizedBox(height: 24),

              // Game Scenario Demo
              _buildSection(
                title: 'Game Scenario Demo',
                child: _buildGameScenario(provider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildQuerySection(SynheartProvider provider) {
    return Column(
      children: [
        // Window selector
        Row(
          children: [
            Expanded(
              child: Text(
                'Window: ${provider.selectedWindow?.name ?? "30s"}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            DropdownButton<WindowType>(
              value: provider.selectedWindow ?? WindowType.window30s,
              items: WindowType.values.map((window) {
                return DropdownMenuItem(
                  value: window,
                  child: Text(_getWindowName(window)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  provider.setSelectedWindow(value);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Query buttons
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: () => provider.queryWearFeatures(),
              icon: const Icon(Icons.favorite),
              label: const Text('Query Wear'),
            ),
            ElevatedButton.icon(
              onPressed: () => provider.queryBehaviorFeatures(),
              icon: const Icon(Icons.touch_app),
              label: const Text('Query Behavior'),
            ),
            ElevatedButton.icon(
              onPressed: () => provider.queryPhoneFeatures(),
              icon: const Icon(Icons.phone_android),
              label: const Text('Query Phone'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Results display
        if (provider.queriedFeatures != null)
          _buildFeatureResults(provider.queriedFeatures!),
      ],
    );
  }

  Widget _buildFeatureResults(Map<String, dynamic> features) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: features.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entry.key,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    entry.value?.toString() ?? 'N/A',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildGameScenario(SynheartProvider provider) {
    return Column(
      children: [
        Text(
          'Simulate a game session that starts/stops wear collection on demand',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: provider.isGameActive
                  ? null
                  : () => provider.startGameSession(),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Game'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: provider.isGameActive
                  ? () => provider.stopGameSession()
                  : null,
              icon: const Icon(Icons.stop),
              label: const Text('End Game'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        if (provider.isGameActive) ...[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    'Game Active',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (provider.latestGameHR != null)
                    Text(
                      'Current HR: ${provider.latestGameHR!.toStringAsFixed(1)} BPM',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _getWindowName(WindowType window) {
    switch (window) {
      case WindowType.window30s:
        return '30 seconds';
      case WindowType.window5m:
        return '5 minutes';
      case WindowType.window1h:
        return '1 hour';
      case WindowType.window24h:
        return '24 hours';
    }
  }
}

