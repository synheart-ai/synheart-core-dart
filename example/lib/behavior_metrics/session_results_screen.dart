import 'package:flutter/material.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;

/// Screen to display session results with events timeline and behavior metrics
class SessionResultsScreen extends StatefulWidget {
  final sb.BehaviorSessionSummary summary;
  final List<sb.BehaviorEvent> events;
  final sb.SynheartBehavior? behavior;

  const SessionResultsScreen({
    super.key,
    required this.summary,
    required this.events,
    this.behavior,
  });

  @override
  State<SessionResultsScreen> createState() => _SessionResultsScreenState();
}

class _SessionResultsScreenState extends State<SessionResultsScreen> {
  DateTime? _selectedStartTime;
  DateTime? _selectedEndTime;

  @override
  void initState() {
    super.initState();
    // Initialize time range to session start/end
    final sessionStartUtc = DateTime.parse(widget.summary.startAt);
    final sessionEndUtc = DateTime.parse(widget.summary.endAt);
    _selectedStartTime = sessionStartUtc;
    _selectedEndTime = sessionEndUtc;
  }

  @override
  Widget build(BuildContext context) {
    // Sort events by timestamp (oldest first)
    final sortedEvents = List<sb.BehaviorEvent>.from(widget.events)
      ..sort((a, b) {
        try {
          final timeA = DateTime.parse(a.timestamp);
          final timeB = DateTime.parse(b.timestamp);
          return timeA.compareTo(timeB);
        } catch (e) {
          return 0;
        }
      });

    // Calculate relative time from session start
    final sessionStart = DateTime.parse(widget.summary.startAt);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Results'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Information',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Session ID', widget.summary.sessionId),
                    _buildInfoRow(
                      'Start Time',
                      _formatDateTime(widget.summary.startAt),
                    ),
                    _buildInfoRow(
                      'End Time',
                      _formatDateTime(widget.summary.endAt),
                    ),
                    _buildInfoRow(
                      'Duration',
                      _formatMs(widget.summary.durationMs),
                    ),
                    _buildInfoRow(
                      'Micro Session',
                      widget.summary.microSession ? 'Yes' : 'No',
                    ),
                    _buildInfoRow('OS', widget.summary.os),
                    if (widget.summary.appId != null)
                      _buildInfoRow('App ID', widget.summary.appId!),
                    if (widget.summary.appName != null)
                      _buildInfoRow('App Name', widget.summary.appName!),
                    _buildInfoRow(
                      'Session Spacing',
                      _formatMs(widget.summary.sessionSpacing),
                    ),
                    _buildInfoRow(
                      'Total Events',
                      '${widget.summary.activitySummary.totalEvents}',
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    // Time Range Picker Section
                    Text(
                      'Time Range Selection',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    // Start Time Picker
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickStartTime(context),
                            icon: const Icon(Icons.access_time),
                            label: Text(
                              _selectedStartTime != null
                                  ? 'Start: ${_formatDateTimeWithSeconds(_selectedStartTime!.toLocal())}'
                                  : 'Pick Start Time',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // End Time Picker
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickEndTime(context),
                            icon: const Icon(Icons.access_time),
                            label: Text(
                              _selectedEndTime != null
                                  ? 'End: ${_formatDateTimeWithSeconds(_selectedEndTime!.toLocal())}'
                                  : 'Pick End Time',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Calculate Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_selectedStartTime != null &&
                                _selectedEndTime != null)
                            ? () => _calculateAndLog()
                            : null,
                        icon: const Icon(Icons.calculate),
                        label: const Text('Calculate Metrics'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Motion Data Debug Card (temporary for debugging)
            Card(
              color: Colors.orange.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motion Data Debug',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.orange[900],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      'Motion Data Available',
                      widget.summary.motionData != null ? 'Yes' : 'No',
                    ),
                    _buildInfoRow(
                      'Motion Data Count',
                      '${widget.summary.motionData?.length ?? 0} windows',
                    ),
                    _buildInfoRow(
                      'Motion State Available',
                      widget.summary.motionState != null ? 'Yes' : 'No',
                    ),
                    if (widget.summary.motionData != null &&
                        widget.summary.motionData!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'First window sample (first 5 features):',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.summary.motionData!.first.features.entries
                            .take(5)
                            .map(
                              (e) => '${e.key}: ${e.value.toStringAsFixed(4)}',
                            )
                            .join('\n'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Motion State Card
            if (widget.summary.motionState != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Motion State',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        'Major State',
                        widget.summary.motionState!.majorState,
                      ),
                      _buildInfoRow(
                        'Major State %',
                        '${(widget.summary.motionState!.majorStatePct * 100).toStringAsFixed(1)}%',
                      ),
                      _buildInfoRow(
                        'ML Model',
                        widget.summary.motionState!.mlModel,
                      ),
                      _buildInfoRow(
                        'Confidence',
                        widget.summary.motionState!.confidence.toStringAsFixed(
                          2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'State Array (${widget.summary.motionState!.state.length} windows):',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      // Display as JSON-like array format
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          '[${widget.summary.motionState!.state.map((s) => '"$s"').join(', ')}]',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Also show as readable list
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: widget.summary.motionState!.state
                            .asMap()
                            .entries
                            .map((entry) {
                              return Chip(
                                label: Text(
                                  '${entry.key + 1}: ${entry.value}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              );
                            })
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Motion Data Card (ML Features)
            if (widget.summary.motionData != null &&
                widget.summary.motionData!.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Motion Data (ML Features)',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        'Data Points',
                        '${widget.summary.motionData!.length} time windows',
                      ),
                      _buildInfoRow('Time Window', '5 seconds per window'),
                      _buildInfoRow('Features per Window', '561 ML features'),
                      const SizedBox(height: 8),
                      Text(
                        'Sample Features (First window):',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...widget.summary.motionData!.take(1).map((dataPoint) {
                        return ExpansionTile(
                          title: Text(
                            'Window: ${dataPoint.timestamp}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Features: ${dataPoint.features.length}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Show first 20 features as examples
                                  ...dataPoint.features.entries.take(20).map((
                                    entry,
                                  ) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 4.0,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              entry.key,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text(
                                              entry.value.toStringAsFixed(4),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontFamily: 'monospace',
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  if (dataPoint.features.length > 20)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        '... and ${dataPoint.features.length - 20} more features',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                      if (widget.summary.motionData!.length > 1)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            '... and ${widget.summary.motionData!.length - 1} more windows',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Device Context Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device Context',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      'Avg Screen Brightness',
                      widget.summary.deviceContext.avgScreenBrightness
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Start Orientation',
                      widget.summary.deviceContext.startOrientation,
                    ),
                    _buildInfoRow(
                      'Orientation Changes',
                      '${widget.summary.deviceContext.orientationChanges}',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Activity Summary Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activity Summary',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      'Total Events',
                      '${widget.summary.activitySummary.totalEvents}',
                    ),
                    _buildInfoRow(
                      'App Switch Count',
                      '${widget.summary.activitySummary.appSwitchCount}',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Behavior Metrics Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Behavior Metrics',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      'Interaction Intensity',
                      widget.summary.behavioralMetrics.interactionIntensity
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Task Switch Rate',
                      widget.summary.behavioralMetrics.taskSwitchRate
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Task Switch Cost',
                      _formatMs(
                        widget.summary.behavioralMetrics.taskSwitchCost,
                      ),
                    ),
                    _buildInfoRow(
                      'Idle Time Ratio',
                      widget.summary.behavioralMetrics.idleTimeRatio
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Active Time Ratio',
                      widget.summary.behavioralMetrics.activeTimeRatio
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Notification Load',
                      widget.summary.behavioralMetrics.notificationLoad
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Burstiness',
                      widget.summary.behavioralMetrics.burstiness
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Distraction Score',
                      widget
                          .summary
                          .behavioralMetrics
                          .behavioralDistractionScore
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Focus Hint',
                      widget.summary.behavioralMetrics.focusHint
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Fragmented Idle Ratio',
                      widget.summary.behavioralMetrics.fragmentedIdleRatio
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Scroll Jitter Rate',
                      widget.summary.behavioralMetrics.scrollJitterRate
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Deep Focus Blocks',
                      '${widget.summary.behavioralMetrics.deepFocusBlocks.length}',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Notification Summary Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notification Summary',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      'Notification Count',
                      '${widget.summary.notificationSummary.notificationCount}',
                    ),
                    _buildInfoRow(
                      'Notifications Ignored',
                      '${widget.summary.notificationSummary.notificationIgnored}',
                    ),
                    _buildInfoRow(
                      'Ignore Rate',
                      widget.summary.notificationSummary.notificationIgnoreRate
                          .toStringAsFixed(3),
                    ),
                    _buildInfoRow(
                      'Call Count',
                      '${widget.summary.notificationSummary.callCount}',
                    ),
                    _buildInfoRow(
                      'Calls Ignored',
                      '${widget.summary.notificationSummary.callIgnored}',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // System State Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System State',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      'Internet',
                      widget.summary.systemState.internetState
                          ? 'Connected'
                          : 'Disconnected',
                    ),
                    _buildInfoRow(
                      'Do Not Disturb',
                      widget.summary.systemState.doNotDisturb ? 'On' : 'Off',
                    ),
                    _buildInfoRow(
                      'Charging',
                      widget.summary.systemState.charging ? 'Yes' : 'No',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Events Timeline
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Events Timeline (${widget.summary.activitySummary.totalEvents} events)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (sortedEvents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            'No events collected during this session.',
                          ),
                        ),
                      )
                    else
                      ...sortedEvents.asMap().entries.map((entry) {
                        final index = entry.key;
                        final event = entry.value;
                        final eventTime = DateTime.parse(event.timestamp);
                        final relativeTime = eventTime.difference(sessionStart);
                        final relativeTimeMs = relativeTime.inMilliseconds;

                        return _buildEventTimelineItem(
                          context,
                          event,
                          index + 1,
                          relativeTimeMs,
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStartTime(BuildContext context) async {
    final sessionStartUtc = DateTime.parse(widget.summary.startAt);
    final sessionEndUtc = DateTime.parse(widget.summary.endAt);
    final sessionStartLocal = sessionStartUtc.toLocal();
    final sessionEndLocal = sessionEndUtc.toLocal();

    final selected = await _showDateTimePicker(
      context: context,
      title: 'Select Start Time',
      initialDateTime: _selectedStartTime?.toLocal() ?? sessionStartLocal,
      firstDate: sessionStartLocal.subtract(const Duration(days: 1)),
      lastDate: sessionEndLocal.add(const Duration(days: 1)),
    );

    if (selected != null) {
      setState(() {
        _selectedStartTime = selected.toUtc();
      });
    }
  }

  Future<void> _pickEndTime(BuildContext context) async {
    final sessionStartUtc = DateTime.parse(widget.summary.startAt);
    final sessionEndUtc = DateTime.parse(widget.summary.endAt);
    final sessionStartLocal = sessionStartUtc.toLocal();
    final sessionEndLocal = sessionEndUtc.toLocal();

    final selected = await _showDateTimePicker(
      context: context,
      title: 'Select End Time',
      initialDateTime:
          _selectedEndTime?.toLocal() ??
          (_selectedStartTime?.toLocal() ?? sessionStartLocal),
      firstDate: _selectedStartTime?.toLocal() ?? sessionStartLocal,
      lastDate: sessionEndLocal.add(const Duration(days: 1)),
    );

    if (selected != null) {
      setState(() {
        _selectedEndTime = selected.toUtc();
      });
    }
  }

  Future<void> _calculateAndLog() async {
    if (_selectedStartTime == null || _selectedEndTime == null) {
      print('ERROR: Start time or end time is null');
      return;
    }

    if (widget.behavior == null) {
      print('ERROR: Behavior SDK is not available');
      return;
    }

    // Validate that start time is before end time
    if (_selectedStartTime!.isAfter(_selectedEndTime!)) {
      print('ERROR: Start time must be before end time!');
      return;
    }

    final startTimestampSeconds =
        _selectedStartTime!.millisecondsSinceEpoch ~/ 1000;
    final endTimestampSeconds =
        _selectedEndTime!.millisecondsSinceEpoch ~/ 1000;

    print('Calculating metrics for time range...');
    print('Start: ${_selectedStartTime!.toIso8601String()}');
    print('End: ${_selectedEndTime!.toIso8601String()}');

    try {
      final result = await widget.behavior!.calculateMetricsForTimeRange(
        startTimestampSeconds: startTimestampSeconds,
        endTimestampSeconds: endTimestampSeconds,
        sessionId: widget.summary.sessionId,
      );

      final metrics = Map<String, dynamic>.from(result);
      print('Metrics calculated: $metrics');
    } catch (e, stackTrace) {
      print('ERROR calculating metrics: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<DateTime?> _showDateTimePicker({
    required BuildContext context,
    required String title,
    required DateTime initialDateTime,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    DateTime selectedDate = initialDateTime;
    int hour = initialDateTime.hour;
    int minute = initialDateTime.minute;
    int second = initialDateTime.second;

    return showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Date',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: firstDate,
                          lastDate: lastDate,
                        );
                        if (pickedDate != null) {
                          setState(() {
                            selectedDate = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              hour,
                              minute,
                              second,
                            );
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const Icon(Icons.calendar_today),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Time (HH:MM:SS)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Hour
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_up),
                              onPressed: () {
                                setState(() {
                                  hour = (hour + 1) % 24;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                            Container(
                              width: 60,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                hour.toString().padLeft(2, '0'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_down),
                              onPressed: () {
                                setState(() {
                                  hour = (hour - 1 + 24) % 24;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                        const Text(':', style: TextStyle(fontSize: 24)),
                        // Minute
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_up),
                              onPressed: () {
                                setState(() {
                                  minute = (minute + 1) % 60;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                            Container(
                              width: 60,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                minute.toString().padLeft(2, '0'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_down),
                              onPressed: () {
                                setState(() {
                                  minute = (minute - 1 + 60) % 60;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                        const Text(':', style: TextStyle(fontSize: 24)),
                        // Second
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_up),
                              onPressed: () {
                                setState(() {
                                  second = (second + 1) % 60;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                            Container(
                              width: 60,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                second.toString().padLeft(2, '0'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_drop_down),
                              onPressed: () {
                                setState(() {
                                  second = (second - 1 + 60) % 60;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    hour,
                                    minute,
                                    second,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(selectedDate);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDateTimeWithSeconds(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEventTimelineItem(
    BuildContext context,
    sb.BehaviorEvent event,
    int eventNumber,
    int relativeTimeMs,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getEventTypeColor(event.eventType),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  event.eventType.name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '+${_formatMs(relativeTimeMs)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Time: ${_formatDateTime(event.timestamp)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Metrics:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          ...event.metrics.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      '${entry.key}: ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Flexible(
                    flex: 2,
                    child: Text(
                      entry.value.toString(),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getEventTypeColor(sb.BehaviorEventType eventType) {
    switch (eventType) {
      case sb.BehaviorEventType.scroll:
        return Colors.blue;
      case sb.BehaviorEventType.tap:
        return Colors.green;
      case sb.BehaviorEventType.swipe:
        return Colors.orange;
      case sb.BehaviorEventType.call:
        return Colors.red;
      case sb.BehaviorEventType.notification:
        return Colors.purple;
      case sb.BehaviorEventType.typing:
        return Colors.teal;
    }
  }

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      return '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}:'
          '${dateTime.second.toString().padLeft(2, '0')}.'
          '${(dateTime.millisecond ~/ 100).toString()}';
    } catch (e) {
      return isoString;
    }
  }

  String _formatMs(int milliseconds) {
    if (milliseconds < 1000) {
      return '${milliseconds}ms';
    } else if (milliseconds < 60000) {
      return '${(milliseconds / 1000).toStringAsFixed(1)}s';
    } else {
      return '${(milliseconds / 60000).toStringAsFixed(1)}m';
    }
  }
}
