// Ignore dynamic calls because types from deferred libraries are unavailable
// for early type-hinting.
// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
// 1. Deferred Loading: Download the ML pipeline only when needed.
import 'package:pipecat_smart_turn/pipecat_smart_turn.dart'
    deferred as smart_turn;
import 'package:record/record.dart';

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
  StreamSubscription<Uint8List>? _micSub;
  final _audioRecorder = AudioRecorder();
  // Using dynamic for deferred library types
  dynamic _audioBuffer;
  bool _isRecording = false;

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
      _audioBuffer = smart_turn.AudioBuffer(
        maxSeconds: config.maxAudioSeconds,
      );

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

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_detector == null) return;

    if (await _audioRecorder.hasPermission()) {
      _audioBuffer?.clear();

      setState(() {
        _isRecording = true;
        _lastResult = null;
        _status = 'Listening to microphone...';
      });

      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _micSub = stream.listen((data) async {
        // Yield to the event loop before heavy tasks
        await Future<void>.delayed(Duration.zero);

        try {
          // Convert 16-bit PCM (little endian) to Float32List (-1.0 to 1.0)
          final float32List = Float32List(data.length ~/ 2);
          final byteData = ByteData.sublistView(data);
          for (var i = 0; i < float32List.length; i++) {
            final pcm16 = byteData.getInt16(i * 2, Endian.little);
            float32List[i] = pcm16 / 32768.0;
          }

          _audioBuffer?.append(float32List);
          final fullContextList = _audioBuffer?.toFloat32List() as Float32List?;
          if (fullContextList == null || fullContextList.isEmpty) return;

          final result = await _detector.predict(fullContextList);
          if (result != null && mounted) {
            setState(() {
              _lastResult = result;
              if (result.isComplete as bool) {
                _status = 'User finished turn!';
                _audioBuffer?.clear();
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
      _micSub?.onError((Object error) {
        if (mounted) {
          setState(() => _status = 'Recording error: $error');
        }
      });
    } else {
      if (mounted) {
        setState(() => _status = 'Microphone permission denied.');
      }
    }
  }

  Future<void> _stopRecording() async {
    await _micSub?.cancel();
    _micSub = null;
    _audioBuffer?.clear();
    await _audioRecorder.stop();
    if (mounted) {
      setState(() {
        _isRecording = false;
        if (_status == 'Listening to microphone...' ||
            _status == 'User is speaking...') {
          _status = 'Recording stopped.';
        }
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
    unawaited(_micSub?.cancel());
    unawaited(_audioRecorder.dispose());
    final d = _detector;
    if (d != null) {
      unawaited(d.dispose() as Future<void>);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Turn Demo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'On-Device Semantic VAD',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
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
                _ResultRow(
                  'Latency (Per chunk):',
                  '${_lastResult!.latencyMs}ms',
                ),
              ] else
                const Center(child: Text('No stream data yet.')),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        (_status.contains('Ready') ||
                                _status.contains('finished') ||
                                _status.contains('User') ||
                                _status.contains('stopped') ||
                                _status == 'Stream naturally finished.') &&
                            !_isRecording
                        ? () => unawaited(_simulateStreamInference())
                        : null,
                    icon: const Icon(Icons.science),
                    label: const Text('Test'),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                        _status.contains('Ready') ||
                            _status.contains('finished') ||
                            _status.contains('User') ||
                            _status.contains('stopped') ||
                            _status == 'Stream naturally finished.' ||
                            _isRecording
                        ? () => unawaited(_toggleRecording())
                        : null,
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                    label: Text(_isRecording ? 'Stop' : 'Record'),
                  ),
                ],
              ),
            ],
          ),
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
