import 'package:flutter/material.dart';

/// Widget for controlling individual module start/stop
class ModuleControlCard extends StatelessWidget {
  final String moduleName;
  final bool isCollecting;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final void Function(Duration)? onStartWithInterval;

  const ModuleControlCard({
    super.key,
    required this.moduleName,
    required this.isCollecting,
    required this.onStart,
    required this.onStop,
    this.onStartWithInterval,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCollecting ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 12),
            // Module name
            Expanded(
              child: Text(
                moduleName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // Interval selector (for wear module)
            if (moduleName == 'Wear' && onStartWithInterval != null) ...[
              DropdownButton<Duration>(
                value: const Duration(seconds: 5),
                items: const [
                  DropdownMenuItem(
                    value: Duration(seconds: 1),
                    child: Text('1s'),
                  ),
                  DropdownMenuItem(
                    value: Duration(seconds: 5),
                    child: Text('5s'),
                  ),
                  DropdownMenuItem(
                    value: Duration(seconds: 10),
                    child: Text('10s'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null && !isCollecting) {
                    onStartWithInterval!(value);
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
            // Start/Stop button
            ElevatedButton(
              onPressed: isCollecting ? onStop : onStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: isCollecting ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text(isCollecting ? 'Stop' : 'Start'),
            ),
          ],
        ),
      ),
    );
  }
}
