import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'yin_bindings.dart';

class AudioEngine {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final YinBindings _yinBindings = YinBindings();

  // FFI Pointers
  Pointer<Yin>? _yinPointer;
  Pointer<Float>? _inputBuffer;

  StreamSubscription<Uint8List>? _audioStreamSubscription;
  final StreamController<double> _pitchController = StreamController<double>.broadcast();

  // Buffer handling
  final List<int> _audioBuffer = [];
  // Since we use PCM 16bit, 2 bytes = 1 sample
  // We need 2048 samples = 4096 bytes
  static const int _requiredSamples = 2048;
  static const int _bytesPerSample = 2; // 16-bit
  static const int _requiredBytes = _requiredSamples * _bytesPerSample;

  // Smoothing
  final List<double> _pitchHistory = [];
  static const int _medianWindowSize = 7;

  Stream<double> get pitchStream => _pitchController.stream;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<void> init() async {
    // Initialize FFI memory
    _yinPointer = calloc<Yin>();
    _inputBuffer = calloc<Float>(_requiredSamples);

    // Initialize YIN algorithm
    // Increase threshold to 0.20 to prevent lower octave errors on D string
    // A higher threshold makes it easier to lock onto the fundamental frequency
    _yinBindings.init(_yinPointer!, 0.20); 
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

    _audioStreamSubscription = stream.listen((data) {
      _processAudioData(data);
    });
  }

  void _processAudioData(Uint8List data) {
    _audioBuffer.addAll(data);

    // If we have enough bytes for processing
    while (_audioBuffer.length >= _requiredBytes) {
      // Extract the chunk
      final chunkBytes = _audioBuffer.sublist(0, _requiredBytes);
      _audioBuffer.removeRange(0, _requiredBytes);

      // Convert Bytes (Int16) to Float [-1.0, 1.0]
      final byteData = ByteData.sublistView(Uint8List.fromList(chunkBytes));
      
      double sumSquare = 0.0;
      for (int i = 0; i < _requiredSamples; i++) {
        // Little Endian is standard for PCM usually
        final int16Sample = byteData.getInt16(i * 2, Endian.little);
        final double floatSample = int16Sample / 32768.0;
        _inputBuffer![i] = floatSample;
        sumSquare += floatSample * floatSample;
      }

      double rms = math.sqrt(sumSquare / _requiredSamples);

      if (rms > 0.05) {
        // Call YIN
        if (_yinPointer != null && _inputBuffer != null) {
          var pitch = _yinBindings.getPitch(_yinPointer!, _inputBuffer!);

          // Filter invalid results if necessary (e.g., -1 usually means no pitch found)
          if (pitch > 0) {
            // Anti-doubling: check against current history median
            if (_pitchHistory.isNotEmpty) {
              final sortedHistory = List<double>.from(_pitchHistory)..sort();
              final currentMedian = sortedHistory[sortedHistory.length ~/ 2];
              
              if (currentMedian > 0) {
                double adjustedPitch = pitch;
                final ratio = pitch / currentMedian;
                
                // Fix octave errors (doubling/halving)
                if (ratio > 1.9 && ratio < 2.1) {
                  // Detected an octave jump (approx 2x) -> correct to fundamental
                  adjustedPitch /= 2;
                } else if (ratio > 0.45 && ratio < 0.55) {
                  // Detected a drop to lower octave (approx 0.5x) -> correct to fundamental
                  adjustedPitch *= 2;
                }
                
                pitch = adjustedPitch;
              }
            }

            _pitchHistory.add(pitch);
            if (_pitchHistory.length > _medianWindowSize) {
              _pitchHistory.removeAt(0);
            }

            // Wait for history to fill up for stability
            if (_pitchHistory.length == _medianWindowSize) {
              // Median filter
              final sorted = List<double>.from(_pitchHistory)..sort();
              final median = sorted[sorted.length ~/ 2];
              _pitchController.add(median);
            }
          }
        }
      } else {
        _pitchHistory.clear();
        _pitchController.add(-1.0);
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
