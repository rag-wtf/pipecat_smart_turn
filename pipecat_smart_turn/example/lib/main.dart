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
  dynamic _config;
  String? _lastVadStateStr;
  String _platformName = '';

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

      // 3. Display active SmartTurnConfig values — create named config object
      //    so we can inspect it in the UI.
      // Note: cannot use `const` with deferred types.
      _config = smart_turn.SmartTurnConfig();
      // SmartTurnDetector uses default SmartTurnConfig internally;
      // we keep _config separately just to display its values in the UI.
      _detector = smart_turn.SmartTurnDetector();
      _vad = smart_turn.EnergyVad();
      await _detector.initialize();

      _audioBuffer = smart_turn.AudioBuffer(
        maxSeconds: _config.maxAudioSeconds as double,
      );

      // 3. Fetch platform name via PipecatSmartTurnPlatform.instance
      final name = await smart_turn.PipecatSmartTurnPlatform.instance
          .getPlatformName();

      if (!mounted) return;
      setState(() {
        _platformName = name ?? '';
        _status = 'Engine Ready';
      });
    } on Exception catch (e) {
      // 5. Typed exceptions from the package (SmartTurnModelLoadException,
      //    SmartTurnInferenceException, SmartTurnNotInitializedException) all
      //    extend SmartTurnException which implements Exception. Because the
      //    import is deferred, Dart prohibits type tests on these types here;
      //    we catch Exception and surface the message instead.
      if (!mounted) return;
      setState(() => _status = 'Initialization error: $e');
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
          // 4. Convert to normalized Float32 [-1.0, 1.0]
          //    ByteData.sublistView safely handles Android record package's
          //    unaligned buffer offsets.
          final byteData = ByteData.sublistView(data);
          final sampleCount = byteData.lengthInBytes ~/ 2;
          final float32List = Float32List(sampleCount);

          for (var i = 0; i < sampleCount; i++) {
            final sample = byteData.getInt16(i * 2, Endian.little);
            float32List[i] = sample / 32768.0;
          }

          // 1. Process VAD
          final vadState = _vad?.process(float32List);
          final vadStr = vadState?.toString().split('.').last;

          if (vadStr != _lastVadStateStr && mounted) {
            setState(() {
              // Reset Semantic Context when energy transitions
              // away from silence
              // (new speech activity makes the prior prediction stale)
              if (_lastVadStateStr == 'silence' && vadStr != 'silence') {
                _lastResult = null;
              }
              _lastVadStateStr = vadStr;
            });
          }

          // 2. Process Semantic Turn
          _audioBuffer?.append(float32List);

          // Only predict if the VAD considers the user has paused speaking
          if (vadStr == 'evaluatingSilence' || vadStr == 'silenceAfterSpeech') {
            final fullContextList =
                _audioBuffer?.toFloat32List() as Float32List?;
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
          }
        } on Exception catch (e) {
          // 5. SmartTurnInferenceException extends SmartTurnException which
          //    implements Exception. Deferred-type `is` checks are not allowed;
          //    we catch Exception and surface the message.
          if (!mounted) return;
          setState(() => _status = 'Inference error: $e');
        } on Object catch (e) {
          if (!mounted) return;
          setState(() => _status = 'Error: $e');
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
        _lastResult = null; // Reset Semantic Context on Stop
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
    // 1. Fix: also reset and clear AudioBuffer for simulation
    _audioBuffer?.clear();
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

        // 1. Fix: accumulate in AudioBuffer just like the live mic path
        _audioBuffer?.append(chunk);

        if (vadStr == 'evaluatingSilence' || vadStr == 'silenceAfterSpeech') {
          // 1. Fix: predict on full audio context, not just the raw chunk
          final fullContext = _audioBuffer?.toFloat32List() as Float32List?;
          if (fullContext == null || fullContext.isEmpty) return;
          final result = await _detector.predict(fullContext);
          if (mounted) {
            setState(() {
              _lastVadStateStr = vadStr;
              if (result != null) _lastResult = result;

              if (result != null && (result.isComplete as bool)) {
                _status = 'Turn Complete';
                _audioBuffer?.clear();
                _vad?.reset();
              } else {
                _status = 'Simulating Stream';
              }
            });
          }
        } else if (mounted) {
          setState(() {
            _lastVadStateStr = vadStr;
          });
        }
      } on Exception catch (e) {
        // 5. SmartTurnInferenceException extends SmartTurnException which
        //    implements Exception. Deferred-type `is` checks are not allowed;
        //    we catch Exception and surface the message.
        if (!mounted) return;
        setState(() => _status = 'Inference error: $e');
      } on Object catch (e) {
        if (!mounted) return;
        setState(() => _status = 'Error: $e');
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
        title: Column(
          children: [
            const Text(
              'Smart Turn AI',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
            // 3. Display platform name under the title
            if (_platformName.isNotEmpty)
              Text(
                'Platform: $_platformName',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                  letterSpacing: 0.5,
                ),
              ),
          ],
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
              const SizedBox(height: 16),

              // 4. SmartTurnConfig info row
              if (_config != null) _ConfigInfoRow(config: _config),
              const SizedBox(height: 16),

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

// 4. Config info strip — shows SmartTurnConfig field values
class _ConfigInfoRow extends StatelessWidget {
  const _ConfigInfoRow({required this.config});
  final dynamic config;

  @override
  Widget build(BuildContext context) {
    final threshold = (config.completionThreshold as double) * 100;
    final maxSecs = config.maxAudioSeconds as double;
    final useIsolate = config.useIsolate as bool;
    final threads = config.cpuThreadCount as int;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ConfigChip(label: 'Threshold', value: '${threshold.toInt()}%'),
          _ConfigDivider(),
          _ConfigChip(
            label: 'Max Audio',
            value: '${maxSecs.toStringAsFixed(0)}s',
          ),
          _ConfigDivider(),
          _ConfigChip(label: 'Isolate', value: useIsolate ? 'ON' : 'OFF'),
          _ConfigDivider(),
          _ConfigChip(
            label: 'Threads',
            value: threads.toString(),
          ),
        ],
      ),
    );
  }
}

class _ConfigDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
    color: Colors.white.withValues(alpha: 0.1),
  );
}

class _ConfigChip extends StatelessWidget {
  const _ConfigChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: Colors.tealAccent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.4),
            letterSpacing: 0.5,
          ),
        ),
      ],
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
    final incompleteConfidence = result.incompleteConfidence as double;
    final latency = result.latencyMs as int;
    final audioLengthMs = result.audioLengthMs as double;

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
                Expanded(
                  child: Text(
                    'Semantic Context',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                // 2. Show both latency and audio length in header
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _MetricBadge(
                      text: '${latency}ms inference',
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 4),
                    _MetricBadge(
                      text:
                          '${(audioLengthMs / 1000).toStringAsFixed(1)}s audio',
                      color: Colors.blueAccent.withValues(alpha: 0.8),
                    ),
                  ],
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
            // 2. Completion probability row
            _ProbabilityRow(
              label: 'Completion Probability',
              value: confidence,
              color: isComplete ? Colors.greenAccent : Colors.amberAccent,
            ),
            const SizedBox(height: 16),
            // 2. Incomplete confidence row (incompleteConfidence getter)
            _ProbabilityRow(
              label: 'Incomplete Probability',
              value: incompleteConfidence,
              color: Colors.blueGrey,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ProbabilityRow extends StatelessWidget {
  const _ProbabilityRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
            Text(
              '${(value * 100).toStringAsFixed(1)}%',
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
          child: AnimatedProgressBar(value: value, color: color),
        ),
      ],
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
