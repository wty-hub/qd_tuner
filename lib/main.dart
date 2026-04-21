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

/// 底部导航：调音 / 拾音器输入预设
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final AudioEngine _audioEngine = AudioEngine();
  bool? _hasPermission;
  int _navIndex = 0;
  TunerInputMode _inputMode = TunerInputMode.microphone;

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

    return Scaffold(
      body: IndexedStack(
        index: _navIndex,
        children: [
          TunerTab(audioEngine: _audioEngine),
          PickupTab(
            mode: _inputMode,
            onModeChanged: (mode) {
              setState(() {
                _inputMode = mode;
                _audioEngine.setInputMode(mode);
              });
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: '调音',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_input_component_outlined),
            selectedIcon: Icon(Icons.settings_input_component),
            label: '拾音器',
          ),
        ],
      ),
    );
  }
}

class TunerTab extends StatefulWidget {
  const TunerTab({super.key, required this.audioEngine});

  final AudioEngine audioEngine;

  @override
  State<TunerTab> createState() => _TunerTabState();
}

class _TunerTabState extends State<TunerTab>
    with SingleTickerProviderStateMixin {
  String _targetNote = 'E';
  double _currentDiff = 0.0; // -1.0～1.0，负为偏低、正为偏高
  double _currentPitch = 0.0;
  late AnimationController _needleController;
  StreamSubscription<double>? _pitchSub;

  final List<String> _strings = ['E', 'A', 'D', 'G', 'B', 'e'];
  // 标准吉他空弦音名与频率：E2, A2, D3, G3, B3, E4
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

    double targetFreq = _frequencies[_targetNote]!;

    double cents = 1200 * math.log(pitch / targetFreq) / math.ln2;

    double maxCents = 100.0;

    double val = (cents / maxCents).clamp(-1.0, 1.0);

    setState(() {
      _currentPitch = pitch;
      _currentDiff = val;
    });
    _needleController.animateTo(val, curve: Curves.easeOut);
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'QD 调音器',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Colors.white70,
                    ),
                  ),
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

class PickupTab extends StatelessWidget {
  const PickupTab({super.key, required this.mode, required this.onModeChanged});

  final TunerInputMode mode;
  final ValueChanged<TunerInputMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          Text(
            '拾音方式',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '按实际接线选择，算法会自动匹配更适合的门限与灵敏度。',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          SegmentedButton<TunerInputMode>(
            segments: const [
              ButtonSegment<TunerInputMode>(
                value: TunerInputMode.microphone,
                label: Text('麦克风'),
                icon: Icon(Icons.mic_outlined),
              ),
              ButtonSegment<TunerInputMode>(
                value: TunerInputMode.pickup,
                label: Text('拾音器'),
                icon: Icon(Icons.settings_input_component_outlined),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (Set<TunerInputMode> next) {
              if (next.isNotEmpty) onModeChanged(next.first);
            },
          ),
          const SizedBox(height: 32),
          _hintCard(
            icon: Icons.mic,
            title: '麦克风',
            body: '木吉他、尤克里里等直接对环境收音。环境较吵时尽量靠近音孔、减少背景声。',
          ),
          const SizedBox(height: 16),
          _hintCard(
            icon: Icons.settings_input_component,
            title: '拾音器',
            body: '电吉他接声卡/效果器后内录、或压电夹子、IR 等线路信号。波形通常更干净，可适当调低手机系统音量避免过载。',
          ),
        ],
      ),
    );
  }

  Widget _hintCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Card(
      color: const Color(0xFF2C2C2C),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF00E5FF), size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: const TextStyle(color: Colors.white60, height: 1.35),
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
