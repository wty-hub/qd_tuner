// YIN 原生库 FFI 绑定
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
      // Windows：源码链进 runner 后符号在可执行体内，可用 DynamicLibrary.executable()
      _dylib = DynamicLibrary.executable();
    } else if (Platform.isIOS || Platform.isMacOS) {
      // iOS/macOS：符号一般在主可执行文件 / 当前进程内
      _dylib = DynamicLibrary.process();
    } else {
      // 其他平台：退回 process()
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
