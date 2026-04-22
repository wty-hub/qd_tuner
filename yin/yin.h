// yin.h
#pragma once

#include <stdint.h>
#include <stdlib.h>

/* Dart FFI on Windows uses GetProcAddress on the main module; symbols must be exported. */
#if defined(_WIN32) || defined(__CYGWIN__)
#  define YIN_API __declspec(dllexport)
#else
#  define YIN_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ----- 常数设定，这些被实践验证了，不必更改 ----- */
// 采样频率，44100 Hz
#define YIN_SAMPLING_RATE 44100

// YIN 第四步的阈值，越小越严格
#define YIN_DEFAULT_THRESHOLD 0.15f

// 缓冲区大小 (W)
// 2048 samples @ 44.1kHz = 46ms latency
#define YIN_BUFFER_SIZE 2048

// YIN 算法状态结构体
typedef struct Yin {
  float signal_buffer[YIN_BUFFER_SIZE];          // 输入的音频数据
  float yin_buffer[YIN_BUFFER_SIZE / 2];  // 计算出的差分结果
  float threshold;                        // 阈值
  float probability;                      // 当前结果可信度
} Yin;

// 函数声明
// 初始化数据结构，设定阈值
YIN_API void Yin_init(Yin* yin, float threshold);
// 根据采样的信号，获取当前基频
YIN_API float Yin_get_pitch(Yin* yin, float* input_buffer);

#ifdef __cplusplus
}
#endif
