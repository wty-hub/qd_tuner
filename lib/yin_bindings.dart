// lib/yin_bindings.dart
import 'dart:ffi';
import 'dart:io';

const int YIN_BUFFER_SIZE = 2048;

final class Yin extends Struct {
  @Array(YIN_BUFFER_SIZE)
  external Array<Float> signal_buffer;

  @Array(YIN_BUFFER_SIZE ~/ 2)
  external Array<Float> yin_buffer;

  @Float()
  external double threshold;

  @Float()
  external double probability;
}

typedef YinInitC = Void Function(Pointer<Yin>, Float);
typedef YinInitDart = void Function(Pointer<Yin>, double);

typedef YinGetPitchC = Float Function(Pointer<Yin>, Pointer<Float>);
typedef YinGetPitchDart = double Function(Pointer<Yin>, Pointer<Float>);

class YinBindings {
  late final DynamicLibrary _dylib;
  late final YinInitDart _yinInit;
  late final YinGetPitchDart _yinGetPitch;

  YinBindings() {
    if (Platform.isAndroid) {
      _dylib = DynamicLibrary.open('libyin_library.so');
    } else if (Platform.isWindows) {
      // On Windows, since we added sources to the runner, symbols are in the executable globally
      // or we can try opening `runner.exe` or `DynamicLibrary.executable()`.
      _dylib = DynamicLibrary.executable();
    } else if (Platform.isIOS || Platform.isMacOS) {
      // On iOS/macOS, symbols are usually linked into the main executable or process
      _dylib = DynamicLibrary.process();
    } else {
      // For now fallback to process
       _dylib = DynamicLibrary.process();
    }

    _yinInit = _dylib
        .lookup<NativeFunction<YinInitC>>('Yin_init')
        .asFunction<YinInitDart>();

    _yinGetPitch = _dylib
        .lookup<NativeFunction<YinGetPitchC>>('Yin_get_pitch')
        .asFunction<YinGetPitchDart>();
  }

  void init(Pointer<Yin> yin, double threshold) {
    _yinInit(yin, threshold);
  }

  double getPitch(Pointer<Yin> yin, Pointer<Float> inputBuffer) {
    return _yinGetPitch(yin, inputBuffer);
  }
}
