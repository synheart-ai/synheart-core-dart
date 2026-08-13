import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:synheart_core/synheart_core.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;
import '../providers/synheart_provider.dart';
import '../widgets/feature_toggle_card.dart';
import '../widgets/session_summary_dialog.dart';
import '../widgets/status_indicator.dart';
import 'hsi_state_screen.dart';
import 'consent_screen.dart';
import 'settings_screen.dart';
import 'on_demand_screen.dart';
import 'runtime_screen.dart';

/// Home screen with feature overview and toggles
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Behavior tracking state
  sb.SynheartBehavior? _behavior;
  sb.BehaviorSession? _currentSession;
  List<sb.BehaviorEvent> _sessionEvents = [];
  bool _isSessionActive = false;
  StreamSubscription<sb.BehaviorEvent>? _eventSubscription;

  /// Throttle setState for behavior events to avoid rebuild on every tap/scroll (causes freeze).
  bool _pendingEventNotify = false;
  Timer? _eventNotifyTimer;
  static const _eventNotifyThrottleMs = 600;

  /// Selected duration in seconds for main session; null = until stopped.
  int? _mainSessionDurationSec = 300;

  @override
  void initState() {
    super.initState();
    _initializeBehaviorTracking();
    // Auto-initialize SDK on app start if we have a saved userId (initialize once across restarts)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = Provider.of<SynheartProvider>(context, listen: false);
      provider.restoreAndInitializeIfNeeded();
    });
  }

  @override
  void dispose() {
    _eventNotifyTimer?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }

  /// Initialize behavior tracking when behavior consent is granted
  void _initializeBehaviorTracking() {
    final behaviorModule = Synheart.shared.behaviorModule;
    final synheartBehavior = behaviorModule?.synheartBehavior;

    if (synheartBehavior != null) {
      _behavior = synheartBehavior;

      // Listen to events from the behavior SDK
      _eventSubscription?.cancel();
      _eventSubscription = synheartBehavior.onEvent.listen((event) {
        // Update state only (no print on every event - reduces log spam and I/O).
        if (_isSessionActive &&
            _currentSession != null &&
            event.sessionId == _currentSession!.sessionId) {
          _sessionEvents.add(event);
          _throttledEventNotify();
        } else if (_isSessionActive &&
            _currentSession != null &&
            kDebugMode &&
            _sessionEvents.length % 20 == 0) {
          // debugPrint('[HomeScreen] Event sessionId mismatch: ${event.sessionId}');
        }
      });

      // Start session if behavior consent is granted
      _checkAndStartSession();
    }
  }

  /// Debounce setState for behavior events so we don't rebuild on every tap/scroll.
  void _throttledEventNotify() {
    _pendingEventNotify = true;
    _eventNotifyTimer?.cancel();
    _eventNotifyTimer = Timer(
      const Duration(milliseconds: _eventNotifyThrottleMs),
      () {
        _eventNotifyTimer = null;
        if (_pendingEventNotify && mounted) {
          _pendingEventNotify = false;
          setState(() {});
        }
      },
    );
  }

  /// Check if behavior consent is granted and start session
  Future<void> _checkAndStartSession() async {
    final consentStatusMap = Synheart.getConsentStatusMap();
    if (consentStatusMap['behavior'] == true && _behavior != null) {
      await _startBehaviorSession();
    } else {
      // print(
      //   '[HomeScreen] Behavior consent not granted or behavior is null. '
      //   'consent: ${consentStatusMap['behavior']}, behavior: $_behavior',
      // );
    }
  }

  /// Start a behavior session
  Future<void> _startBehaviorSession() async {
    if (_behavior == null) {
      // print('[HomeScreen] ⚠️ Cannot start session: behavior is null');
      return;
    }

    if (_isSessionActive) {
      // print(
      //   '[HomeScreen] ⚠️ Session already active: ${_currentSession?.sessionId}',
      // );
      return;
    }

    try {
      final session = await _behavior!.startSession();
      setState(() {
        _currentSession = session;
        _isSessionActive = true;
        _sessionEvents = []; // Clear previous session events
      });
      // print(
      //   '[HomeScreen] ✅ Behavior session started: ${session.sessionId}, '
      //   'startTime: ${DateTime.fromMillisecondsSinceEpoch(session.startTimestamp)}',
      // );
      // print(
      //   '[HomeScreen] Current session ID in SDK: ${_behavior!.currentSessionId}',
      // );
    } catch (e) {
      // print('[HomeScreen] ❌ Failed to start behavior session: $e');
    }
  }

  /// Stop the current behavior session
  Future<void> _stopBehaviorSession() async {
    if (_currentSession == null || !_isSessionActive) return;

    try {
      // End any active typing sessions
      sb.BehaviorTextField.endAllTypingSessions();

      // End the session
      await _currentSession!.end();

      setState(() {
        _currentSession = null;
        _isSessionActive = false;
        _sessionEvents = [];
      });
      // print('[HomeScreen] ✅ Behavior session stopped');
    } catch (e) {
      // print('[HomeScreen] ❌ Failed to stop behavior session: $e');
      // Clear state even if ending failed
      setState(() {
        _currentSession = null;
        _isSessionActive = false;
        _sessionEvents = [];
      });
    }
  }

  /// End the current behavior session and navigate to results
  Future<void> _endSessionAndShowResults() async {
    if (_currentSession == null || !_isSessionActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No active behavior session. Enable behavior tracking first.',
            ),
          ),
        );
      }
      return;
    }

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      // End any active typing sessions
      sb.BehaviorTextField.endAllTypingSessions();

      // End the session using the stored session object (like the example does)
      final summary = await _currentSession!.end().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Session end timed out after 15 seconds');
        },
      );

      // Use summary start/end times (ISO8601 UTC strings) for consistency
      // Both are in UTC, so parsing them will give us UTC DateTime objects
      final sessionStartTime = DateTime.parse(summary.startAt).toUtc();
      final sessionEndTime = DateTime.parse(summary.endAt).toUtc();

      // print(
      //   '[HomeScreen] Session start time (UTC): $sessionStartTime (${summary.startAt})',
      // );
      // print('[HomeScreen] Session end time (UTC): $sessionEndTime');
      // print(
      //   '[HomeScreen] Summary total_events from native SDK: ${summary.activitySummary.totalEvents}',
      // );

      // Filter events by session time range (start to end)
      // Both times are in UTC, so we can compare directly
      final sessionStartMs = sessionStartTime.millisecondsSinceEpoch;
      final sessionEndMs = sessionEndTime.millisecondsSinceEpoch;

      // Filter events by session time range (start to end)
      // All timestamps are in UTC, so we can compare directly
      final sessionEvents = _sessionEvents.where((event) {
        try {
          // Parse event timestamp as UTC (ISO8601 with Z suffix)
          final eventTime = DateTime.parse(event.timestamp).toUtc();
          final eventTimeMs = eventTime.millisecondsSinceEpoch;
          final inRange =
              eventTimeMs >= sessionStartMs && eventTimeMs <= sessionEndMs;

          if (!inRange) {
            // print(
            //   '[HomeScreen] ⚠️ Event outside session range: ${event.eventType.name}, '
            //   'eventTime: $eventTime (${event.timestamp}), '
            //   'sessionRange: $sessionStartTime to $sessionEndTime',
            // );
          }
          return inRange;
        } catch (e) {
          // print(
          //   '[HomeScreen] ⚠️ Invalid event timestamp: ${event.timestamp}, error: $e',
          // );
          return false;
        }
      }).toList();

      // print(
      //   '[HomeScreen] Session ended. '
      //   'Total events collected: ${_sessionEvents.length}, '
      //   'Events in session range: ${sessionEvents.length}, '
      //   'Native SDK events: ${summary.activitySummary.totalEvents}, '
      //   'Summary: ${summary.sessionId}',
      // );

      // Debug: Print event breakdown (commented to reduce log noise)
      if (sessionEvents.isNotEmpty) {
        final eventTypes = <String, int>{};
        for (final event in sessionEvents) {
          eventTypes[event.eventType.name] =
              (eventTypes[event.eventType.name] ?? 0) + 1;
        }
        // print('[HomeScreen] Event breakdown: $eventTypes');
      } else {
        // print(
        //   '[HomeScreen] ⚠️ WARNING: No events in session range! '
        //   'This might indicate events are not being stored in native SDK.',
        // );
      }

      // Clear session state
      setState(() {
        _currentSession = null;
        _isSessionActive = false;
      });

      // Start a new session to continue tracking
      await _startBehaviorSession();

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
      }
    } catch (e) {
      // print('[HomeScreen] ERROR ending session: $e');

      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to show behavior results: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get behavior instance for gesture detection
    final behaviorModule = Synheart.shared.behaviorModule;
    final synheartBehavior = behaviorModule?.synheartBehavior;

    // Update behavior instance if it changed
    if (_behavior != synheartBehavior) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeBehaviorTracking();
      });
    }

    // Build the scaffold
    final scaffold = Scaffold(
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

                // Data collection session (main page) — only when initialized
                if (provider.isInitialized) ...[
                  _buildMainSessionCard(context, provider),
                  const SizedBox(height: 16),
                ],

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
                        provider.consentInfo['phoneContext'] ??
                        'Collect motion and phone context data',
                    enabled: provider.consentStatusMap['phoneContext'] ?? false,
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

                const SizedBox(height: 24),

                // Quick Metrics Preview
                if (provider.isInitialized && provider.latestHSI != null) ...[
                  Text(
                    'Current State',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                  'On-Demand Collection',
                  'Control modules, view raw data, manage sessions',
                  Icons.tune,
                  Colors.orange,
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OnDemandScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                _buildNavigationCard(
                  context,
                  'Runtime',
                  'Native runtime status, version, live HSI JSON',
                  Icons.memory,
                  Colors.teal,
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RuntimeScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                _buildNavigationCard(
                  context,
                  'HSI State',
                  'View all state axes',
                  Icons.analytics,
                  Colors.indigo,
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HsiStateScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                _buildNavigationCard(
                  context,
                  'Behavior',
                  'Interaction patterns',
                  Icons.touch_app,
                  Colors.amber,
                  () => _endSessionAndShowResults(),
                ),
                // Consent: only show when SDK is initialized (consent module is ready)
                if (provider.isInitialized) ...[
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
            onPressed: () async {
              final lastHSI = provider.latestHSI;
              await provider.stop();
              if (context.mounted) {
                showDialog(
                  context: context,
                  builder: (_) => SessionSummaryDialog(hsiJson: lastHSI),
                );
              }
            },
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.stop),
          );
        },
      ),
    );

    // Wrap with BehaviorGestureDetector if behavior consent is granted
    // This matches the pattern from synheart-behavior-flutter/example
    return Consumer<SynheartProvider>(
      builder: (context, provider, child) {
        final hasBehaviorConsent =
            provider.consentStatusMap['behavior'] ?? false;

        if (hasBehaviorConsent && synheartBehavior != null) {
          return sb.BehaviorGestureDetector(
            behavior: synheartBehavior,
            child: scaffold,
          );
        }

        return scaffold;
      },
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
                  label: 'HSI',
                  isActive: provider.latestHSI != null,
                  icon: Icons.analytics,
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
            if (provider.isInitialized)
              _buildCloudIngestionStatus(context, provider),
          ],
        ],
      ),
    );
  }

  Widget _buildCloudIngestionStatus(
    BuildContext context,
    SynheartProvider provider,
  ) {
    final hasCloudConfig = provider.sdkConfig?.cloudConfig != null;
    final theme = Theme.of(context).textTheme;
    final muted = theme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
    );
    const topPadding = 12.0;

    if (!hasCloudConfig) {
      return Padding(
        padding: const EdgeInsets.only(top: topPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cloud ingestion is off. Add CloudConfig when initializing the SDK to enable.',
                style: muted,
              ),
            ),
          ],
        ),
      );
    }

    final pending = provider.uploadQueueLength;
    final lastBatchId = provider.lastUploadBatchId;
    final lastAt = provider.lastUploadAt;
    final lastError = provider.lastUploadError;
    final lastAttemptAt = provider.lastUploadAttemptAt;

    String lastIngestedText;
    if (lastError != null) {
      // Last attempt failed: show error (trim if very long)
      final errShort = lastError.length > 120
          ? '${lastError.substring(0, 117)}...'
          : lastError;
      lastIngestedText = 'Last attempt failed: $errShort';
    } else if (lastAt != null) {
      final time =
          '${lastAt.hour.toString().padLeft(2, '0')}:${lastAt.minute.toString().padLeft(2, '0')}';
      lastIngestedText = lastBatchId != null
          ? 'Last ingested: $lastBatchId at $time'
          : 'Last ingested at $time';
    } else {
      lastIngestedText = 'Last ingested: never';
    }

    final attemptTimeText = lastAttemptAt != null
        ? 'Last attempt: ${lastAttemptAt.hour.toString().padLeft(2, '0')}:${lastAttemptAt.minute.toString().padLeft(2, '0')}'
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pending uploads: $pending', style: muted),
          const SizedBox(height: 2),
          Text(
            lastIngestedText,
            style: lastError != null
                ? muted?.copyWith(color: Colors.red.shade700)
                : muted,
          ),
          if (lastError != null && attemptTimeText != null) ...[
            const SizedBox(height: 2),
            Text(
              attemptTimeText,
              style: muted?.copyWith(color: Colors.red.shade700),
            ),
          ] else if (lastAt != null && attemptTimeText != null) ...[
            const SizedBox(height: 2),
            Text(attemptTimeText, style: muted),
          ],
        ],
      ),
    );
  }

  Widget _buildMainSessionCard(
    BuildContext context,
    SynheartProvider provider,
  ) {
    final isRunning = provider.isSessionRunning;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data collection session',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildRuntimeModeRow(context, provider),
            const SizedBox(height: 12),
            if (isRunning) ...[
              Row(
                children: [
                  Icon(Icons.play_circle_filled, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Session running',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _formatElapsed(provider.sessionElapsedSec),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => provider.stopSession(),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop session'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                ),
              ),
              _buildLiveAxesSection(context, provider),
            ] else ...[
              Text(
                'Duration',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _mainSessionDurationChip(30, '30 sec'),
                  _mainSessionDurationChip(60, '1 min'),
                  _mainSessionDurationChip(300, '5 min'),
                  _mainSessionDurationChip(1800, '30 min'),
                  _mainSessionDurationChip(null, 'Until stopped'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => provider.startSession(
                    durationSec: _mainSessionDurationSec,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start session'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRuntimeModeRow(BuildContext context, SynheartProvider provider) {
    final isBatch = provider.batchIngestOnStop;
    return Row(
      children: [
        Text(
          'Runtime mode',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(width: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Batch'),
              icon: Icon(Icons.inventory_2_outlined),
            ),
            ButtonSegment(
              value: false,
              label: Text('Realtime'),
              icon: Icon(Icons.show_chart),
            ),
          ],
          selected: {isBatch},
          onSelectionChanged: (Set<bool> selected) {
            final value = selected.first;
            provider.setBatchIngestOnStop(value);
          },
          showSelectedIcon: false,
        ),
      ],
    );
  }

  Widget _buildLiveAxesSection(
    BuildContext context,
    SynheartProvider provider,
  ) {
    final axes = provider.latestLiveAxes;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live state',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _liveAxisChip(context, 'Valence', axes?['valence']),
              _liveAxisChip(context, 'Arousal', axes?['arousal']),
              _liveAxisChip(context, 'Focus', axes?['focus']),
              _liveAxisChip(context, 'Capacity', axes?['capacity']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _liveAxisChip(BuildContext context, String label, double? value) {
    final display = value != null ? value.toStringAsFixed(2) : '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          Text(
            display,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mainSessionDurationChip(int? seconds, String label) {
    final selected = _mainSessionDurationSec == seconds;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        if (v == true) setState(() => _mainSessionDurationSec = seconds);
      },
    );
  }

  /// Format elapsed seconds as MM:SS.
  static String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
    final hasConsent = provider.consentStatusMap['phoneContext'] ?? false;
    if (hasConsent) {
      // Revoke consent (disable feature)
      _showRevokeConsentDialog(
        context,
        provider,
        'phoneContext',
        'Motion & Phone Context',
        'This will stop collecting motion and phone context data.',
      );
    } else {
      // Grant consent (enable feature) - show grant dialog
      _showGrantConsentDialog(
        context,
        provider,
        'phoneContext',
        'Motion & Phone Context',
        provider.consentInfo['phoneContext'] ??
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
                  phoneContext: consentType == 'phoneContext'
                      ? true
                      : currentConsent.phoneContext,
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
                // If revoking behavior consent, stop the active session first
                if (consentType == 'behavior') {
                  await _stopBehaviorSession();
                }

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
      // Resolve a subject id that PERSISTS across restarts. Minting
      // `user_<timestamp>` here (the previous behaviour) gave the runtime a
      // new person on every launch, so baselines never matured.
      final userId = await SynheartProvider.resolveDemoSubjectId(
        _userIdController.text,
      );

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
