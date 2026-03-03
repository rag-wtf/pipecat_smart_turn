// Ignore dynamic calls because types from deferred libraries are unavailable
// for early type-hinting.
// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

// 1. Deferred Loading: Download the ML pipeline only when needed.
import 'package:pipecat_smart_turn/pipecat_smart_turn.dart'
    deferred as smart_turn;

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
  // Using dynamic since types from deferred libraries cannot be used
  // as annotations
  dynamic _detector;
  dynamic _lastResult;
  String _status = 'Initializing...';

  StreamSubscription<Float32List>? _audioSub;

  @override
  void initState() {
    super.initState();
    unawaited(_initDetector());
  }

  Future<void> _initDetector() async {
    setState(() => _status = 'Downloading inference engine...');

    try {
      // Execute deferred loading here before instantiating ONNX components
      await smart_turn.loadLibrary();

      final config = smart_turn.SmartTurnConfig();
      _detector = smart_turn.SmartTurnDetector(config: config);
      await _detector.initialize();

      if (!mounted) return;
      setState(() {
        _status = 'Bundled model loaded successfully. Ready for stream.';
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Initialization error: $e';
      });
    }
  }

  Future<void> _simulateStreamInference() async {
    if (_detector == null) return;

    // Setup for Stream Optimization
    setState(() {
      _lastResult = null;
      _status = 'Streaming simulated audio...';
    });

    await _audioSub?.cancel();

    // 3. Stream Optimization: emit audio chunks periodically
    // instead of one massive block
    final chunkStream = Stream.periodic(const Duration(milliseconds: 500), (
      count,
    ) {
      // Simulate roughly 500ms of audio (8000 samples at 16kHz)
      return Float32List(8000);
    }).take(16); // Run for 8 seconds total (16 * 500ms)

    _audioSub = chunkStream.listen((chunk) async {
      // 2. Chunked Execution: Yield to the event loop before heavy tasks
      // to prevent UI jank
      await Future<void>.delayed(Duration.zero);

      try {
        final result = await _detector.predict(chunk);
        if (result != null && mounted) {
          setState(() {
            _lastResult = result;
            if (result.isComplete as bool) {
              _status = 'User finished turn!';
            } else {
              _status = 'User is speaking...';
            }
          });
        }
      } on Exception catch (e) {
        if (mounted) {
          setState(() => _status = 'Error: $e');
        }
      }
    });

    _audioSub?.onDone(() {
      if (mounted && _status == 'Streaming simulated audio...') {
        setState(() => _status = 'Stream naturally finished.');
      }
    });
  }

  @override
  void dispose() {
    unawaited(_audioSub?.cancel());
    final d = _detector;
    if (d != null) {
      unawaited(d.dispose() as Future<void>);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Turn Web Demo')),
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
                'Incremental Stream Result:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _ResultRow(
                'Is Complete:',
                (_lastResult!.isComplete as bool) ? 'YES' : 'NO',
                color: (_lastResult!.isComplete as bool)
                    ? Colors.green
                    : Colors.orange,
              ),
              _ResultRow(
                'Confidence:',
                '${(_lastResult!.confidence * 100).toStringAsFixed(1)}%',
              ),
              _ResultRow('Latency (Per chunk):', '${_lastResult!.latencyMs}ms'),
            ] else
              const Center(child: Text('No stream data yet.')),
            const Spacer(),
            Center(
              child: ElevatedButton.icon(
                onPressed:
                    _status.contains('Ready') ||
                        _status.contains('finished') ||
                        _status.contains('User')
                    ? _simulateStreamInference
                    : null,
                icon: const Icon(Icons.stream),
                label: const Text('Start Audio Stream'),
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
