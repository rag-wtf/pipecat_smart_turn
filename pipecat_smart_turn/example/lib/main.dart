import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pipecat_smart_turn/pipecat_smart_turn.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const SmartTurnDemo(),
    );
  }
}

class SmartTurnDemo extends StatefulWidget {
  const SmartTurnDemo({super.key});

  @override
  State<SmartTurnDemo> createState() => _SmartTurnDemoState();
}

class _SmartTurnDemoState extends State<SmartTurnDemo> {
  SmartTurnDetector? _detector;
  SmartTurnResult? _lastResult;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    unawaited(_initDetector());
  }

  Future<void> _initDetector() async {
    const config = SmartTurnConfig(); // Uses bundled model by default

    _detector = SmartTurnDetector(config: config);
    await _detector!.initialize();

    setState(() {
      _status = 'Bundled model loaded successfully. Ready for inference.';
    });
  }

  Future<void> _simulateInference() async {
    if (_detector == null) return;

    setState(() {
      _lastResult = null;
      _status = 'Simulating inference...';
    });

    try {
      // Create 8 seconds of dummy audio (128,000 samples)
      final dummyAudio = Float32List(128000);

      // Perform prediction
      final result = await _detector!.predict(dummyAudio);

      setState(() {
        _lastResult = result;
        _status = result == null
            ? 'Inference skipped (backpressure)'
            : 'Inference complete';
      });
    } on Exception catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_detector?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Turn Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'On-Device Semantic VAD',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(fontStyle: FontStyle.italic)),
            const Divider(height: 48),
            if (_lastResult != null) ...[
              const Text(
                'Last Result:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _ResultRow(
                'Is Complete:',
                _lastResult!.isComplete ? 'YES' : 'NO',
                color: _lastResult!.isComplete ? Colors.green : Colors.orange,
              ),
              _ResultRow(
                'Confidence:',
                '${(_lastResult!.confidence * 100).toStringAsFixed(1)}%',
              ),
              _ResultRow('Latency:', '${_lastResult!.latencyMs}ms'),
              _ResultRow('Audio length:', '${_lastResult!.audioLengthMs}ms'),
            ] else
              const Center(child: Text('No inference results yet.')),
            const Spacer(),
            Center(
              child: ElevatedButton.icon(
                onPressed: _simulateInference,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Simulate Inference (Full Buffer)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
