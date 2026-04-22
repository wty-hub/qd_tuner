import 'dart:async';

import 'package:flutter/material.dart'; // ignore: unnecessary_import
import 'dart:math' as math;
import 'package:permission_handler/permission_handler.dart';
import 'audio_engine.dart';

void main() {
  runApp(const QdTunerApp());
}

class QdTunerApp extends StatelessWidget {
  const QdTunerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QD Tuner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF2979FF),
          surface: Color(0xFF2C2C2C),
        ),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

/// 主界面：调音
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final AudioEngine _audioEngine = AudioEngine();
  bool? _hasPermission;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndStart();
  }

  Future<void> _checkPermissionAndStart() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!mounted) return;
    setState(() {
      _hasPermission = status.isGranted;
    });
    if (status.isGranted) {
      await _audioEngine.init();
      await _audioEngine.start();
    }
  }

  @override
  void dispose() {
    _audioEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPermission == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
        ),
      );
    }

    if (_hasPermission == false) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mic_off, size: 64, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                '该应用需要麦克风权限',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: openAppSettings,
                child: const Text('设置权限'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _checkPermissionAndStart,
                child: const Text('刷新'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(body: TunerTab(audioEngine: _audioEngine));
  }
}

class TunerTab extends StatefulWidget {
  const TunerTab({super.key, required this.audioEngine});

  final AudioEngine audioEngine;

  @override
  State<TunerTab> createState() => _TunerTabState();
}

enum TunerInstrument { guitar }

enum TuningMode { targetString, freeListening }

class _NearestNote {
  const _NearestNote({required this.label, required this.frequency});

  final String label;
  final double frequency;
}

class _TunerTabState extends State<TunerTab>
    with SingleTickerProviderStateMixin {
  TunerInstrument _instrument = TunerInstrument.guitar;
  TuningMode _tuningMode = TuningMode.targetString;
  String _targetNote = 'E';
  String _nearestNoteLabel = '--';
  double _nearestNoteFrequency = 0.0;
  double _currentDiff = 0.0; // -1.0～1.0，负为偏低、正为偏高
  double _currentPitch = 0.0;
  late AnimationController _needleController;
  StreamSubscription<double>? _pitchSub;

  static const Map<TunerInstrument, List<String>> _instrumentStrings = {
    TunerInstrument.guitar: ['E', 'A', 'D', 'G', 'B', 'e'],
  };

  // 标准吉他空弦音名与频率：E2, A2, D3, G3, B3, E4
  static const Map<TunerInstrument, Map<String, double>>
  _instrumentFrequencies = {
    TunerInstrument.guitar: {
      'E': 82.41,
      'A': 110.00,
      'D': 146.83,
      'G': 196.00,
      'B': 246.94,
      'e': 329.63,
    },
  };

  List<String> get _strings => _instrumentStrings[_instrument]!;
  Map<String, double> get _frequencies => _instrumentFrequencies[_instrument]!;

  String _instrumentLabel(TunerInstrument instrument) {
    switch (instrument) {
      case TunerInstrument.guitar:
        return '吉他，标准音';
    }
  }

  @override
  void initState() {
    super.initState();
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: -1.0,
      upperBound: 1.0,
    );
    _pitchSub = widget.audioEngine.pitchStream.listen((pitch) {
      if (!mounted) return;
      _processPitch(pitch);
    });
  }

  void _processPitch(double pitch) {
    if (pitch == -1.0) {
      return;
    }

    if (pitch < 40) return;

    late final double targetFreq;
    late final double pitchForDisplay;
    late final double cents;

    if (_tuningMode == TuningMode.freeListening) {
      final nearest = _nearestNoteFromPitch(pitch);
      targetFreq = nearest.frequency;
      pitchForDisplay = pitch;
      cents = 1200 * math.log(pitchForDisplay / targetFreq) / math.ln2;
      _nearestNoteLabel = nearest.label;
      _nearestNoteFrequency = nearest.frequency;
    } else {
      targetFreq = _frequencies[_targetNote]!;
      pitchForDisplay = _foldPitchToTargetOctave(pitch, targetFreq);
      cents = 1200 * math.log(pitchForDisplay / targetFreq) / math.ln2;
    }

    double maxCents = 100.0;

    double val = (cents / maxCents).clamp(-1.0, 1.0);

    setState(() {
      _currentPitch = pitchForDisplay;
      _currentDiff = val;
    });
    _needleController.animateTo(val, curve: Curves.easeOut);
  }

  /// 将检测到的频率折叠到离目标频率最近的八度，抑制 2x/0.5x 跳变显示。
  double _foldPitchToTargetOctave(double pitch, double targetFreq) {
    var folded = pitch;
    while (folded > targetFreq * 1.8) {
      folded /= 2.0;
    }
    while (folded < targetFreq / 1.8) {
      folded *= 2.0;
    }
    return folded;
  }

  @override
  void dispose() {
    _pitchSub?.cancel();
    _needleController.dispose();
    super.dispose();
  }

  void _selectString(String note) {
    if (_targetNote != note) {
      setState(() {
        _targetNote = note;
        _currentDiff = 0.0;
        _currentPitch = 0.0;
      });
      _needleController.animateTo(0.0);
    }
  }

  void _selectInstrument(TunerInstrument instrument) {
    if (_instrument == instrument) return;
    setState(() {
      _instrument = instrument;
      _targetNote = _instrumentStrings[instrument]!.first;
      _currentDiff = 0.0;
      _currentPitch = 0.0;
    });
    _needleController.animateTo(0.0);
  }

  void _selectTuningMode(TuningMode mode) {
    if (_tuningMode == mode) return;
    setState(() {
      _tuningMode = mode;
      _currentDiff = 0.0;
      _currentPitch = 0.0;
      _nearestNoteLabel = '--';
      _nearestNoteFrequency = 0.0;
    });
    _needleController.animateTo(0.0);
  }

  _NearestNote _nearestNoteFromPitch(double pitch) {
    const noteNames = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final midi = (69 + 12 * math.log(pitch / 440.0) / math.ln2).round();
    final noteName = noteNames[midi % 12];
    final octave = (midi ~/ 12) - 1;
    final frequency = 440.0 * math.pow(2.0, (midi - 69) / 12.0).toDouble();
    return _NearestNote(label: '$noteName$octave', frequency: frequency);
  }

  Widget _buildNoteButton(String note) {
    bool isSelected = _targetNote == note;
    return GestureDetector(
      onTap: () => _selectString(note),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF333333),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Text(
            note,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.audioEngine.isRecording;
    final displayedNote = _tuningMode == TuningMode.freeListening
        ? _nearestNoteLabel
        : _targetNote;
    final displayedTargetFrequency = _tuningMode == TuningMode.freeListening
        ? _nearestNoteFrequency
        : _frequencies[_targetNote]!;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_tuningMode == TuningMode.targetString) ...[
                    Row(
                      children: [
                        const Text(
                          '乐器',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C2C2C),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<TunerInstrument>(
                              value: _instrument,
                              dropdownColor: const Color(0xFF2C2C2C),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              items: TunerInstrument.values
                                  .map(
                                    (instrument) => DropdownMenuItem(
                                      value: instrument,
                                      child: Text(_instrumentLabel(instrument)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (next) {
                                if (next != null) _selectInstrument(next);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '目前仅支持吉他，标准音，后续会增加更多乐器。',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 250,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: TunerMeterPainter(
                        value: _currentDiff,
                        lineColor: Colors.white24,
                        activeColor: _currentDiff.abs() < 0.1
                            ? const Color(0xFF00E676)
                            : (_currentDiff < 0
                                  ? const Color(0xFFFFEA00)
                                  : const Color(0xFFFF1744)),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayedNote,
                              style: TextStyle(
                                fontSize: 96,
                                fontWeight: FontWeight.w200,
                                color: _currentDiff.abs() < 0.1
                                    ? const Color(0xFF00E676)
                                    : Colors.white,
                              ),
                            ),
                            Text(
                              displayedTargetFrequency > 0
                                  ? '${displayedTargetFrequency.toStringAsFixed(2)} Hz'
                                  : '-- Hz',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF00E5FF),
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (_currentPitch > 0)
                              Text(
                                '${_currentPitch.toStringAsFixed(1)} Hz',
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            const SizedBox(height: 10),
                            if (isRecording)
                              if (_currentPitch <= 0)
                                const Text(
                                  '请拨动琴弦',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 40),
              child: Column(
                children: [
                  if (_tuningMode == TuningMode.targetString) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _strings
                          .sublist(0, 3)
                          .map(_buildNoteButton)
                          .toList(),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _strings
                          .sublist(3, 6)
                          .map(_buildNoteButton)
                          .toList(),
                    ),
                  ] else
                    const Text(
                      '自由拾音会自动显示最接近的音名。',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                        letterSpacing: 0.4,
                      ),
                    ),
                  const SizedBox(height: 20),
                  SegmentedButton<TuningMode>(
                    segments: const [
                      ButtonSegment<TuningMode>(
                        value: TuningMode.targetString,
                        icon: Icon(Icons.music_note_outlined),
                        label: Text('定弦调音'),
                      ),
                      ButtonSegment<TuningMode>(
                        value: TuningMode.freeListening,
                        icon: Icon(Icons.graphic_eq),
                        label: Text('自由拾音'),
                      ),
                    ],
                    selected: {_tuningMode},
                    onSelectionChanged: (next) {
                      if (next.isNotEmpty) _selectTuningMode(next.first);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TunerMeterPainter extends CustomPainter {
  final double value;
  final Color lineColor;
  final Color activeColor;

  TunerMeterPainter({
    required this.value,
    required this.lineColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 60);
    final radius = size.width * 0.7;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = -10; i <= 10; i++) {
      double angle = (i * 4) * (math.pi / 180) - (math.pi / 2);
      double tickLength = (i % 5 == 0) ? 20.0 : 10.0;
      if (i == 0) tickLength = 30.0;

      final startPoint = Offset(
        center.dx + (radius - tickLength) * math.cos(angle),
        center.dy + (radius - tickLength) * math.sin(angle),
      );

      final endPoint = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      paint.color = (i == 0 && value.abs() < 0.1) ? activeColor : lineColor;

      canvas.drawLine(startPoint, endPoint, paint);
    }

    final needleAngle = (value * 40) * (math.pi / 180) - (math.pi / 2);
    final needlePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final needleStart = Offset(
      center.dx + (radius - 40) * math.cos(needleAngle),
      center.dy + (radius - 40) * math.sin(needleAngle),
    );
    final needleEnd = Offset(
      center.dx + (radius + 10) * math.cos(needleAngle),
      center.dy + (radius + 10) * math.sin(needleAngle),
    );

    canvas.drawLine(needleStart, needleEnd, needlePaint);
  }

  @override
  bool shouldRepaint(covariant TunerMeterPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.activeColor != activeColor;
  }
}
