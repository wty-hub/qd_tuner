import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'yin_bindings.dart';

/// 输入场景：手机麦克风（木吉他等）与电琴/夹子拾音等线路信号特性不同，门限分开调。
enum TunerInputMode {
  /// 环境/琴箱声，略偏抗环境噪声
  microphone,

  /// 电吉他、压电夹子等：波形更尖、底噪相对小，可略放宽检出
  pickup,
}

class AudioEngine {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final YinBindings _yinBindings = YinBindings();

  // FFI 指针
  Pointer<Yin>? _yinPointer;
  Pointer<Float>? _inputBuffer;

  StreamSubscription<Uint8List>? _audioStreamSubscription;
  final StreamController<double> _pitchController =
      StreamController<double>.broadcast();

  // 缓冲：PCM 16 位每采样 2 字节；2048 采样 = 4096 字节
  final List<int> _audioBuffer = [];
  static const int _requiredSamples = 2048;
  static const int _bytesPerSample = 2; // 16 位
  static const int _requiredBytes = _requiredSamples * _bytesPerSample;

  // 音高结果平滑
  final List<double> _pitchHistory = [];
  static const int _medianWindowSize = 5;

  /// 至少累计这么多帧有效音高就开始输出（略小于窗口，小声时更快有读数）
  static const int _minHistoryForOutput = 3;

  /// 连续多少个「门关闭」的处理窗之后才视为静音
  /// （44100 Hz、每块 2048 采样时约 93 ms）。
  static const int _quietChunksForSilence = 2;

  TunerInputMode _inputMode = TunerInputMode.microphone;
  double _rmsSmooth = 0.72;
  double _rmsOpen = 0.014;
  double _rmsClose = 0.009;
  double _peakGateWeight = 0.42;
  double _yinThreshold = 0.14;

  TunerInputMode get inputMode => _inputMode;

  double _rmsEnvelope = 0.0;
  bool _voiceGateOpen = false;
  int _quietChunkCount = 0;

  Stream<double> get pitchStream => _pitchController.stream;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<void> init() async {
    // 分配 FFI 内存
    _yinPointer = calloc<Yin>();
    _inputBuffer = calloc<Float>(_requiredSamples);

    _applyInputModePresets();
    _yinBindings.init(_yinPointer!, _yinThreshold);
  }

  /// 切换麦克风 / 拾音器预设（可随时调用，会重置 YIN 内部阈值状态）
  void setInputMode(TunerInputMode mode) {
    if (mode == _inputMode) return;
    _inputMode = mode;
    _applyInputModePresets();
    if (_yinPointer != null) {
      _yinBindings.init(_yinPointer!, _yinThreshold);
    }
  }

  void _applyInputModePresets() {
    switch (_inputMode) {
      case TunerInputMode.microphone:
        _rmsSmooth = 0.72;
        _rmsOpen = 0.014;
        _rmsClose = 0.009;
        _peakGateWeight = 0.42;
        _yinThreshold = 0.14;
        break;
      case TunerInputMode.pickup:
        _rmsSmooth = 0.68;
        _rmsOpen = 0.010;
        _rmsClose = 0.006;
        _peakGateWeight = 0.50;
        _yinThreshold = 0.12;
        break;
    }
  }

  Future<void> start() async {
    if (_isRecording) return;

    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Microphone permission not granted');
    }

    final stream = await _audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      ),
    );

    _isRecording = true;
    _audioBuffer.clear();
    _pitchHistory.clear();
    _rmsEnvelope = 0.0;
    _voiceGateOpen = false;
    _quietChunkCount = 0;

    _audioStreamSubscription = stream.listen((data) {
      _processAudioData(data);
    });
  }

  void _processAudioData(Uint8List data) {
    // data 是一个 PCM（Pulse Code Modulation，脉冲编码调制）流
    _audioBuffer.addAll(data);

    while (_audioBuffer.length >= _requiredBytes) {
      // 流式读取 2048 个点（4096字节）
      final chunkBytes = _audioBuffer.sublist(0, _requiredBytes);
      _audioBuffer.removeRange(0, _requiredBytes);

      // 将裸字节转化为可以按16位整数方式读的视图
      // Int16 小端 PCM
      final byteData = ByteData.sublistView(Uint8List.fromList(chunkBytes));

      // 计算平方和与峰值
      double sumSquare = 0.0;
      double peak = 0.0;
      for (int i = 0; i < _requiredSamples; i++) {
        // PCM 通常为小端序
        final int16Sample = byteData.getInt16(i * 2, Endian.little);
        // 将原始的 int16 信号 转换到 [-1, 1] 的 浮点数
        final double floatSample = int16Sample / 32768.0;
        // 将浮点数存入 buffer
        _inputBuffer![i] = floatSample;
        sumSquare += floatSample * floatSample;
        final a = floatSample.abs();
        if (a > peak) peak = a;
      }

      double rms = math.sqrt(sumSquare / _requiredSamples);
      // 当前的“声音指标”
      // 取 平均能量 (rms) 与 峰值乘以一个权重 的最大值，
      // 平衡 短促拨弦 和 持续弱音
      final level = math.max(rms, peak * _peakGateWeight);

      // 包络平滑：上一时刻与这一时刻音量的滑动平均数
      _rmsEnvelope = _rmsSmooth * _rmsEnvelope + (1.0 - _rmsSmooth) * level;
      if (_voiceGateOpen) {
        if (_rmsEnvelope < _rmsClose) _voiceGateOpen = false;
      } else {
        if (_rmsEnvelope > _rmsOpen) _voiceGateOpen = true;
      }

      if (_voiceGateOpen) {
        _quietChunkCount = 0;
        if (_yinPointer != null && _inputBuffer != null) {
          var pitch = _yinBindings.getPitch(_yinPointer!, _inputBuffer!);

          // 无效结果（如未检出音高）已在外层用 pitch > 0 过滤
          if (pitch > 0) {
            // 结合历史中位数抑制倍频/半频跳变
            if (_pitchHistory.isNotEmpty) {
              final sortedHistory = List<double>.from(_pitchHistory)..sort();
              final currentMedian = sortedHistory[sortedHistory.length ~/ 2];

              if (currentMedian > 0) {
                double adjustedPitch = pitch;
                final ratio = pitch / currentMedian;

                // 八度修正：约 2 倍 → 折半；约 0.5 倍 → 加倍
                if (ratio > 1.9 && ratio < 2.1) {
                  adjustedPitch /= 2;
                } else if (ratio > 0.45 && ratio < 0.55) {
                  adjustedPitch *= 2;
                }

                pitch = adjustedPitch;
              }
            }

            _pitchHistory.add(pitch);
            if (_pitchHistory.length > _medianWindowSize) {
              _pitchHistory.removeAt(0);
            }

            if (_pitchHistory.length >= _minHistoryForOutput) {
              final sorted = List<double>.from(_pitchHistory)..sort();
              final median = sorted[sorted.length ~/ 2];
              _pitchController.add(median);
            }
          }
        }
      } else {
        _quietChunkCount++;
        if (_quietChunkCount >= _quietChunksForSilence) {
          _pitchHistory.clear();
          _pitchController.add(-1.0);
        }
      }
    }
  }

  Future<void> stop() async {
    if (!_isRecording) return;

    await _audioRecorder.stop();
    await _audioStreamSubscription?.cancel();
    _isRecording = false;
    _audioBuffer.clear();
    _pitchHistory.clear();
    _rmsEnvelope = 0.0;
    _voiceGateOpen = false;
    _quietChunkCount = 0;
  }

  void dispose() {
    stop();
    if (_yinPointer != null) {
      calloc.free(_yinPointer!);
      _yinPointer = null;
    }
    if (_inputBuffer != null) {
      calloc.free(_inputBuffer!);
      _inputBuffer = null;
    }
    _pitchController.close();
    _audioRecorder.dispose();
  }
}
