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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SynheartProvider>().checkWatchStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On-Demand Collection'), elevation: 0),
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

              // Watch Session Section
              _buildSection(
                title: 'Watch Session',
                child: _buildWatchSession(provider),
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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

  Widget _buildWatchSession(SynheartProvider provider) {
    // Countdown overlay
    if (provider.isCountingDown) {
      return _buildCountdownView(provider);
    }

    // Active session
    if (provider.isWatchSessionActive) {
      return _buildActiveSessionView(provider);
    }

    // Summary card
    if (provider.lastWatchSummary != null) {
      return _buildSummaryView(provider);
    }

    // Configuration / start view
    return _buildSessionConfigView(provider);
  }

  Widget _buildSessionConfigView(SynheartProvider provider) {
    final status = provider.watchStatus;
    final reachable = status?.reachable ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Watch status
        Row(
          children: [
            Icon(
              reachable ? Icons.watch : Icons.watch_off,
              color: reachable ? Colors.green : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              reachable ? 'Watch connected' : 'Watch not connected',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: reachable ? Colors.green : Colors.grey,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => provider.checkWatchStatus(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Mode selector
        Text('Mode', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<SessionMode>(
          segments: const [
            ButtonSegment(
              value: SessionMode.focus,
              label: Text('Focus'),
              icon: Icon(Icons.center_focus_strong, size: 16),
            ),
            ButtonSegment(
              value: SessionMode.breathing,
              label: Text('Breathing'),
              icon: Icon(Icons.air, size: 16),
            ),
          ],
          selected: {provider.selectedSessionMode},
          onSelectionChanged: (modes) {
            provider.setSessionMode(modes.first);
          },
        ),
        const SizedBox(height: 16),

        // Duration selector
        Text('Duration', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _durationChip(provider, 30, '30 sec'),
            _durationChip(provider, 60, '1 min'),
            _durationChip(provider, 180, '3 min'),
            _durationChip(provider, 300, '5 min'),
            _durationChip(provider, 600, '10 min'),
          ],
        ),
        const SizedBox(height: 20),

        // Start button
        FilledButton.icon(
          onPressed: () => provider.startWatchSessionWithCountdown(),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Session'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _durationChip(SynheartProvider provider, int seconds, String label) {
    final selected = provider.sessionDurationSec == seconds;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => provider.setSessionDuration(seconds),
    );
  }

  Widget _buildCountdownView(SynheartProvider provider) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Text(
          '${provider.countdownSeconds}',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Starting session...',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => provider.cancelCountdown(),
          child: const Text('Cancel'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildActiveSessionView(SynheartProvider provider) {
    final remaining = provider.sessionDurationSec - provider.watchElapsedSec;
    final remainingMin = (remaining ~/ 60).toString().padLeft(2, '0');
    final remainingSec = (remaining % 60).toString().padLeft(2, '0');
    final stopping = provider.isWatchStopRequested;

    return Column(
      children: [
        // Live HR display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                Icons.favorite,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                provider.liveWatchHR != null
                    ? '${provider.liveWatchHR!.toStringAsFixed(0)} BPM'
                    : 'Waiting...',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stopping
                    ? 'Stopping... waiting for watch'
                    : '$remainingMin:$remainingSec remaining',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // HRV metrics row
        Row(
          children: [
            Expanded(
              child: _metricTile(
                'RMSSD',
                provider.liveWatchRMSSD != null
                    ? '${provider.liveWatchRMSSD!.toStringAsFixed(1)} ms'
                    : '--',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricTile(
                'SDNN',
                provider.liveWatchSDNN != null
                    ? '${provider.liveWatchSDNN!.toStringAsFixed(1)} ms'
                    : '--',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricTile(
                'Frames',
                '${provider.watchFrameCount}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Stop button (disabled while stopping)
        FilledButton.icon(
          onPressed: stopping ? null : () => provider.stopWatchSession(),
          icon: stopping ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.stop),
          label: Text(stopping ? 'Stopping...' : 'Stop Session'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: const Size(double.infinity, 0),
          ),
        ),
      ],
    );
  }

  Widget _metricTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryView(SynheartProvider provider) {
    final summary = provider.lastWatchSummary!;
    final metrics = summary.metrics;
    final durationMin = summary.durationActualSec ~/ 60;
    final durationSec = summary.durationActualSec % 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.tertiary,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                'Session Complete',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Duration: ${durationMin}m ${durationSec}s',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              if (metrics.isNotEmpty) ...[
                ...metrics.entries
                    .where((e) => e.value is num)
                    .take(6)
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                e.key,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onTertiaryContainer,
                                    ),
                              ),
                              Text(
                                (e.value as num).toStringAsFixed(1),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onTertiaryContainer,
                                    ),
                              ),
                            ],
                          ),
                        )),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => provider.clearWatchSummary(),
          child: const Text('Dismiss'),
        ),
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
