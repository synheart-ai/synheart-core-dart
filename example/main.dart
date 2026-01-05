import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synheart Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SynheartExamplePage(),
    );
  }
}

class SynheartExamplePage extends StatefulWidget {
  const SynheartExamplePage({super.key});

  @override
  State<SynheartExamplePage> createState() => _SynheartExamplePageState();
}

class _SynheartExamplePageState extends State<SynheartExamplePage> {
  HumanStateVector? _currentState;
  bool _isInitialized = false;
  StreamSubscription<HumanStateVector>? _subscription;
  Timer? _sessionTimer;
  Duration _sessionDuration = Duration.zero;
  DateTime? _sessionStartTime;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initializeSynheart() async {
    try {
      if (_isInitialized) return;

      // Initialize Core SDK
      await Synheart.initialize(
        appKey: 'YOUR_APP_KEY_HERE',
        userId: 'example_user_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Grant all consents to enable data collection
      // In production, you should request user consent via UI
      await Synheart.updateConsent(ConsentSnapshot.all());

      // Enable optional interpretation modules (so Emotion/Focus fields update)
      await Synheart.enableEmotion();
      await Synheart.enableFocus();

      _subscription = Synheart.onHSVUpdate.listen((hsv) {
        setState(() {
          _currentState = hsv;
        });
      });

      // Start a session through the behavior module if available
      final behaviorModule = Synheart.shared.behaviorModule;
      if (behaviorModule?.synheartBehavior != null) {
        try {
          await behaviorModule!.synheartBehavior!.startSession();
        } catch (e) {
          // Session start is optional, continue if it fails
          print('Note: Could not start behavior session: $e');
        }
      }

      // Start session timer
      _startSessionTimer();

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing Synheart: $e')),
        );
      }
    }
  }

  void _startSessionTimer() {
    _sessionStartTime = DateTime.now();
    _sessionDuration = Duration.zero;
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _sessionStartTime != null) {
        setState(() {
          _sessionDuration = DateTime.now().difference(_sessionStartTime!);
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _stopSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _sessionStartTime = null;
    _sessionDuration = Duration.zero;
  }

  Future<void> _stopSynheart() async {
    // Stop session timer
    _stopSessionTimer();

    // End session through behavior module if available
    final behaviorModule = Synheart.shared.behaviorModule;
    if (behaviorModule?.synheartBehavior != null) {
      try {
        // Note: synheart_behavior sessions are typically ended automatically
        // when the app is closed or when explicitly ended
      } catch (e) {
        print('Note: Could not end behavior session: $e');
      }
    }

    await Synheart.stop();
    setState(() {
      _currentState = null;
      _isInitialized = false;
    });
  }

  @override
  void dispose() {
    _stopSessionTimer();
    _subscription?.cancel();
    _subscription = null;
    Synheart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use automatic behavior capture if synheart_behavior is initialized
    final synheartBehavior = Synheart.shared.behaviorModule?.synheartBehavior;
    final isRunning = _isInitialized;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Synheart Core Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_currentState != null) {
            setState(() {});
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status Card
              _buildStatusCard(isRunning),
              const SizedBox(height: 16),

              // Control Button
              FilledButton.icon(
                onPressed: isRunning ? _stopSynheart : _initializeSynheart,
                icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
                label: Text(
                  isRunning ? 'Stop Synheart' : 'Initialize Synheart',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 24),

              if (_currentState != null) ...[
                // Emotion Section with Visual Indicators
                _buildEmotionSection(),
                const SizedBox(height: 16),

                // Focus Section
                _buildFocusSection(),
                const SizedBox(height: 16),

                // HSV Axes Section
                _buildHSVAxesSection(),
                const SizedBox(height: 16),

                // Behavior Section
                _buildBehaviorSection(),
                const SizedBox(height: 16),

                // Metadata Section
                _buildMetadataSection(),
              ] else
                _buildEmptyState(),
            ],
          ),
        ),
      ),
    );

    // Wrap with synheart_behavior's gesture detector for automatic capture
    if (synheartBehavior != null && isRunning) {
      return synheartBehavior.wrapWithGestureDetector(scaffold);
    }
    return scaffold;
  }

  Widget _buildStatusCard(bool isRunning) {
    final consent = Synheart.shared.currentConsent;
    final hasConsent =
        consent != null &&
        (consent.biosignals || consent.behavior || consent.motion);

    return Card(
      color: isRunning
          ? (hasConsent ? Colors.green.shade50 : Colors.orange.shade50)
          : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRunning
                      ? (hasConsent ? Icons.check_circle : Icons.warning)
                      : Icons.circle_outlined,
                  color: isRunning
                      ? (hasConsent ? Colors.green : Colors.orange)
                      : Colors.grey,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRunning ? 'Synheart Active' : 'Synheart Inactive',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isRunning
                            ? (hasConsent
                                  ? 'Collecting and processing data'
                                  : 'Waiting for consent to collect data')
                            : 'Tap Initialize to start',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isRunning && consent != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildConsentChip('Biosignals', consent.biosignals),
                  _buildConsentChip('Behavior', consent.behavior),
                  _buildConsentChip('Motion', consent.motion),
                ],
              ),
            ],
            if (isRunning) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timer,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Session Time: ${_formatDuration(_sessionDuration)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConsentChip(String label, bool granted) {
    return Chip(
      label: Text(label),
      avatar: Icon(granted ? Icons.check : Icons.close, size: 16),
      backgroundColor: granted ? Colors.green.shade100 : Colors.red.shade100,
      labelStyle: TextStyle(
        color: granted ? Colors.green.shade900 : Colors.red.shade900,
        fontSize: 12,
      ),
    );
  }

  Widget _buildEmotionSection() {
    final emotion = _currentState!.emotion;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, color: Colors.purple.shade700),
                const SizedBox(width: 8),
                Text(
                  'Emotion State',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Primary emotions with visual bars
            _buildEmotionBar('Stress', emotion.stress, Colors.red),
            const SizedBox(height: 12),
            _buildEmotionBar('Calm', emotion.calm, Colors.blue),
            const SizedBox(height: 12),
            _buildEmotionBar('Engagement', emotion.engagement, Colors.green),
            const SizedBox(height: 16),
            // Derived metrics
            Row(
              children: [
                Expanded(
                  child: _buildEmotionMetric(
                    'Activation',
                    emotion.activation,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildEmotionMetric(
                    'Valence',
                    emotion.valence,
                    emotion.valence >= 0 ? Colors.purple : Colors.pink,
                  ),
                ),
              ],
            ),
          ],
        ),
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
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
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

  Widget _buildEmotionMetric(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusSection() {
    final focus = _currentState!.focus;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.center_focus_strong, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Focus State',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Focus Score with circular indicator
            Center(
              child: _buildCircularProgress(
                'Focus Score',
                focus.score,
                Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            // Other focus metrics
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'Cognitive Load',
                    focus.cognitiveLoad,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    'Clarity',
                    focus.clarity,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildEmotionBar('Distraction', focus.distraction, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularProgress(String label, double value, Color color) {
    return Column(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 12,
                  backgroundColor: color.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(value * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHSVAxesSection() {
    final axes = _currentState!.meta.axes;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Text(
                  'HSI Axes',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildAxisRow(
              'Affect Arousal',
              axes.affect.arousalIndex ?? 0.0,
              Colors.red,
            ),
            _buildAxisRow(
              'Valence Stability',
              axes.affect.valenceStability ?? 0.0,
              Colors.purple,
            ),
            const Divider(height: 24),
            _buildAxisRow(
              'Engagement Stability',
              axes.engagement.engagementStability ?? 0.0,
              Colors.green,
            ),
            _buildAxisRow(
              'Interaction Cadence',
              axes.engagement.interactionCadence ?? 0.0,
              Colors.blue,
            ),
            const Divider(height: 24),
            _buildAxisRow(
              'Motion Index',
              axes.activity.motionIndex ?? 0.0,
              Colors.orange,
            ),
            _buildAxisRow(
              'Posture Stability',
              axes.activity.postureStability ?? 0.0,
              Colors.teal,
            ),
            const Divider(height: 24),
            _buildAxisRow(
              'Screen Active Ratio',
              axes.context.screenActiveRatio ?? 0.0,
              Colors.cyan,
            ),
            _buildAxisRow(
              'Session Fragmentation',
              axes.context.sessionFragmentation ?? 0.0,
              Colors.pink,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAxisRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 12,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviorSection() {
    final behavior = _currentState!.behavior;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.touch_app, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Text(
                  'Behavior Metrics',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMetric('Typing Cadence', behavior.typingCadence),
            _buildMetric('Typing Burstiness', behavior.typingBurstiness),
            _buildMetric('Scroll Velocity', behavior.scrollVelocity),
            _buildMetric('Idle Gaps', behavior.idleGaps),
            _buildMetric('App Switch Rate', behavior.appSwitchRate),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataSection() {
    final meta = _currentState!.meta;
    return Card(
      elevation: 1,
      child: ExpansionTile(
        leading: Icon(Icons.info_outline, color: Colors.grey.shade700),
        title: Text('Metadata', style: Theme.of(context).textTheme.titleMedium),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Session ID', meta.sessionId),
                _buildInfoRow('Platform', meta.device.platform),
                _buildInfoRow('Device', meta.device.model ?? 'Unknown'),
                _buildInfoRow('OS Version', meta.device.osVersion ?? 'Unknown'),
                _buildInfoRow(
                  'Sampling Rate',
                  '${meta.samplingRateHz.toStringAsFixed(1)} Hz',
                ),
                _buildInfoRow(
                  'Embedding Size',
                  '${meta.embedding.vector.length}D',
                ),
                _buildInfoRow(
                  'Timestamp',
                  DateTime.fromMillisecondsSinceEpoch(
                    _currentState!.timestamp,
                  ).toString().substring(0, 19),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          children: [
            Icon(
              Icons.psychology_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No State Data Yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Initialize Synheart to begin receiving real-time updates',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }
}
