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
      title: 'Smart Turn Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
        cardTheme: const CardThemeData(
          color: Color(0xFF1E293B), // Slate 800
          elevation: 8,
          shadowColor: Colors.black45,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
            side: BorderSide(
              color: Color(0xFF334155),
            ), // Slate 700
          ),
        ),
      ),
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
  dynamic _vad;
  dynamic _lastResult;
  String? _lastVadStateStr;

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
      _vad = smart_turn.EnergyVad(
        silenceGraceFrames: 10,
      ); // Slightly longer grace for visual stability
      await _detector.initialize();

      _audioBuffer = smart_turn.AudioBuffer(
        maxSeconds: config.maxAudioSeconds,
      );

      if (!mounted) return;
      setState(() {
        _status = 'Engine Ready';
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
      _vad?.reset();

      setState(() {
        _isRecording = true;
        _lastResult = null;
        _lastVadStateStr = null;
        _status = 'Listening';
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

          // 1. Process VAD
          final vadState = _vad?.process(float32List);
          final vadStr = vadState?.toString().split('.').last;

          if (vadStr != _lastVadStateStr && mounted) {
            setState(() {
              _lastVadStateStr = vadStr;
            });
          }

          // 2. Process Semantic Turn
          _audioBuffer?.append(float32List);
          final fullContextList = _audioBuffer?.toFloat32List() as Float32List?;
          if (fullContextList == null || fullContextList.isEmpty) return;

          final result = await _detector.predict(fullContextList);
          if (result != null && mounted) {
            setState(() {
              _lastResult = result;
              if (result.isComplete as bool) {
                _status = 'Turn Complete';
                _audioBuffer?.clear();
                _vad?.reset();
              } else {
                _status = 'Listening';
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
        setState(() => _status = 'Mic permission denied');
      }
    }
  }

  Future<void> _stopRecording() async {
    await _micSub?.cancel();
    _micSub = null;
    _audioBuffer?.clear();
    _vad?.reset();
    await _audioRecorder.stop();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _status = 'Engine Ready';
      });
    }
  }

  Future<void> _simulateStreamInference() async {
    if (_detector == null) return;

    setState(() {
      _lastResult = null;
      _lastVadStateStr = null;
      _status = 'Simulating Stream';
    });

    await _audioSub?.cancel();
    _vad?.reset();

    final chunkStream = Stream.periodic(const Duration(milliseconds: 500), (
      count,
    ) {
      // Simulate roughly 500ms of audio (8000 samples at 16kHz)
      return Float32List(8000); // 0s simulate silence
    }).take(16);

    _audioSub = chunkStream.listen((chunk) async {
      await Future<void>.delayed(Duration.zero);

      try {
        final vadState = _vad?.process(chunk);
        final vadStr = vadState?.toString().split('.').last;

        final result = await _detector.predict(chunk);
        if (mounted) {
          setState(() {
            _lastVadStateStr = vadStr;
            if (result != null) _lastResult = result;

            if (result != null && (result.isComplete as bool)) {
              _status = 'Turn Complete';
              _vad?.reset();
            } else {
              _status = 'Simulating Stream';
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
      if (mounted && _status == 'Simulating Stream') {
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
    final isReady =
        _status.contains('Ready') ||
        _status.contains('Complete') ||
        _status.contains('finished') ||
        _status == 'Listening' ||
        _status == 'Simulating Stream';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Smart Turn AI',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.5),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status Header
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                              _status == 'Listening' ||
                                  _status == 'Simulating Stream'
                              ? Colors.redAccent
                              : Colors.tealAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _status.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Dashboard Cards
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _VadStateCard(vadStateStr: _lastVadStateStr),
                    const SizedBox(height: 16),
                    _SemanticTurnCard(result: _lastResult),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              // Controls
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isReady && !_isRecording
                          ? () => unawaited(_simulateStreamInference())
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: const Color(0xFF334155),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(Icons.science_outlined),
                      label: const Text(
                        'TEST (Zero)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isReady
                          ? () => unawaited(_toggleRecording())
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: _isRecording
                            ? Colors.redAccent.withValues(alpha: 0.2)
                            : Colors.indigoAccent,
                        foregroundColor: _isRecording
                            ? Colors.redAccent
                            : Colors.white,
                        shadowColor: _isRecording
                            ? Colors.transparent
                            : Colors.indigoAccent.withValues(alpha: 0.5),
                        elevation: _isRecording ? 0 : 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: _isRecording
                              ? const BorderSide(
                                  color: Colors.redAccent,
                                  width: 2,
                                )
                              : BorderSide.none,
                        ),
                      ),
                      icon: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                      label: Text(
                        _isRecording ? 'STOP' : 'LIVE MIC',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.white12),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VadStateCard extends StatelessWidget {
  const _VadStateCard({this.vadStateStr});
  final String? vadStateStr;

  @override
  Widget build(BuildContext context) {
    if (vadStateStr == null) {
      return const _EmptyCard(
        title: 'Energy Context',
        subtitle: 'Awaiting audio frames...',
        icon: Icons.waves_rounded,
      );
    }

    Color color;
    IconData icon;
    String label;
    String desc;

    switch (vadStateStr) {
      case 'speechStart':
        color = Colors.tealAccent;
        icon = Icons.record_voice_over;
        label = 'Speech Started';
        desc = 'Audio crossed energy threshold';
      case 'speech':
        color = Colors.greenAccent;
        icon = Icons.graphic_eq_rounded;
        label = 'Speaking';
        desc = 'Ongoing active speech detected';
      case 'silenceAfterSpeech':
        color = Colors.amberAccent;
        icon = Icons.mic_none_rounded;
        label = 'Silence (Grace)';
        desc = 'Energy dropped, awaiting grace';
      case 'evaluatingSilence':
        color = Colors.deepOrangeAccent;
        icon = Icons.hourglass_empty_rounded;
        label = 'Evaluating';
        desc = 'Delaying turn check';
      case 'silence':
      default:
        color = const Color(0xFF64748B); // Slate 500
        icon = Icons.mic_off_rounded;
        label = 'Silence';
        desc = 'Low energy, background noise';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.waves_rounded,
                  color: Colors.blueAccent,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Energy Context',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 36),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          label,
                          key: ValueKey(label),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SemanticTurnCard extends StatelessWidget {
  const _SemanticTurnCard({this.result});
  final dynamic result;

  @override
  Widget build(BuildContext context) {
    if (result == null) {
      return const _EmptyCard(
        title: 'Semantic Context',
        subtitle: 'Awaiting tensor inference...',
        icon: Icons.psychology_rounded,
      );
    }

    final isComplete = result.isComplete as bool;
    final confidence = result.confidence as double;
    final latency = result.latencyMs as int;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isComplete ? Icons.check_circle_rounded : Icons.sync_rounded,
                  color: isComplete ? Colors.greenAccent : Colors.amberAccent,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Semantic Context',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${latency}ms',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              isComplete ? 'TURN COMPLETE' : 'INCOMPLETE',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: isComplete ? Colors.greenAccent : Colors.amberAccent,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Completion Probability',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${(confidence * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AnimatedProgressBar(
                value: confidence,
                color: isComplete ? Colors.greenAccent : Colors.amberAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    required this.value,
    required this.color,
    super.key,
  });
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 12,
          width: constraints.maxWidth,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: 0,
                top: 0,
                bottom: 0,
                width: constraints.maxWidth * value,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
