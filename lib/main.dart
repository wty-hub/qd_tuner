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
      home: const TunerScreen(),
    );
  }
}

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen>
    with SingleTickerProviderStateMixin {
  bool? _hasPermission;
  String _targetNote = 'E';
  double _currentDiff = 0.0; // -1.0 to 1.0 (flat to sharp)
  double _currentPitch = 0.0;
  bool _isListening = false;
  late AnimationController _needleController;
  final AudioEngine _audioEngine = AudioEngine();

  final List<String> _strings = ['E', 'A', 'D', 'G', 'B', 'e'];
  // E2, A2, D3, G3, B3, E4
  final Map<String, double> _frequencies = {
    'E': 82.41,
    'A': 110.00,
    'D': 146.83,
    'G': 196.00,
    'B': 246.94,
    'e': 329.63,
  };

  @override
  void initState() {
    super.initState();
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: -1.0,
      upperBound: 1.0,
    );
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (mounted) {
      setState(() {
        _hasPermission = status.isGranted;
      });
      if (_hasPermission == true) {
        _initAudio();
      }
    }
  }

  Future<void> _initAudio() async {
    await _audioEngine.init();
    _audioEngine.pitchStream.listen((pitch) {
      if (!mounted) return;
      _processPitch(pitch);
    });
    // Auto start listening
    if (!_isListening) {
      _toggleListening();
    }
  }

  void _processPitch(double pitch) {
    if (pitch == -1.0) {
      // if (mounted) {
      //   setState(() {
      //     _currentPitch = 0.0;
      //     _currentDiff = 0.0;
      //   });
      //   _needleController.animateTo(0.0);
      // }
      return;
    }

    // If pitch is unreasonable, ignore (e.g., < 40Hz)
    if (pitch < 40) return;

    // Smoothing (simple exponential moving average)
    // double smoothedPitch = 0.7 * _lastPitch + 0.3 * pitch;
    // if (_lastPitch == 0.0) smoothedPitch = pitch;
    // _lastPitch = smoothedPitch;
    // Actually YIN gives good snapshots, but they might fluctuate.
    // Let's use raw pitch for responsiveness for now.

    double targetFreq = _frequencies[_targetNote]!;

    // Calculate cents difference
    // cents = 1200 * log2(f1 / f2)
    double cents = 1200 * math.log(pitch / targetFreq) / math.ln2;

    // We assume the range of the meter is +/- 100 cents
    double maxCents = 100.0;

    // Normalize to -1.0 to 1.0
    double val = (cents / maxCents).clamp(-1.0, 1.0);

    setState(() {
      _currentPitch = pitch;
      _currentDiff = val;
    });
    _needleController.animateTo(val, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _needleController.dispose();
    _audioEngine.dispose();
    super.dispose();
  }

  void _toggleListening() async {
    try {
      if (_isListening) {
        await _audioEngine.stop();
        if (!mounted) return;
        setState(() {
          _isListening = false;
          _currentDiff = 0.0;
          _needleController.animateTo(0.0);
        });
      } else {
        await _audioEngine.start();
        if (!mounted) return;
        setState(() {
          _isListening = true;
        });
      }
    } catch (e) {
      print('Error parsing audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
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
                onPressed: _checkPermission,
                child: const Text('刷新'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // const Icon(Icons.settings, color: Colors.white54),
                  const Text(
                    'QD 调音器',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Colors.white70,
                    ),
                  ),
                  // IconButton(
                  //   icon: Icon(
                  //     _isListening ? Icons.mic : Icons.mic_off,
                  //     color: _isListening
                  //         ? const Color(0xFF00E5FF)
                  //         : Colors.white54,
                  //   ),
                  //   onPressed: _toggleListening,
                  // ),
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
                              _targetNote,
                              style: TextStyle(
                                fontSize: 96,
                                fontWeight: FontWeight.w200,
                                color: _currentDiff.abs() < 0.1
                                    ? const Color(0xFF00E676)
                                    : Colors.white,
                              ),
                            ),
                            Text(
                              '${_frequencies[_targetNote]} Hz',
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
                            if (_isListening)
                              if (_currentPitch <= 0)
                                // Text(
                                //   _currentDiff.abs() < 0.1
                                //       ? "合适"
                                //       : (_currentDiff < 0
                                //           ? "低了"
                                //           : "高了"),
                                //   style: TextStyle(
                                //     color: _currentDiff.abs() < 0.1
                                //         ? const Color(0xFF00E676)
                                //         : Colors.white54,
                                //     fontSize: 14,
                                //     fontWeight: FontWeight.bold,
                                //     letterSpacing: 1.5,
                                //   ),
                                // )
                              // else
                                const Text(
                                  "请拨动琴弦",
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
