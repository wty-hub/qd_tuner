#include "yin.h"

#include <stdio.h>
#include <stdlib.h>

#include "fft.h"

// 初始化
YIN_API void Yin_init(Yin* yin, float threshold) {
  yin->threshold = threshold;
  yin->probability = 0.0f;
}

// 步骤 1: 累计均值归一化差分函数 (CMNDF)
// 这是 YIN 算法的核心，把差分值转化为“不像的概率”
// 结果存入 yin->yin_buffer
static void Yin_difference(Yin* yin, const float* input_buffer) {
  // 窗口大小
  int half_size = YIN_BUFFER_SIZE / 2;

  // 0 处取 1，硬性规定
  yin->yin_buffer[0] = 1.0f;
  float running_sum = 0.0f;

  for (int tau = 1; tau < half_size; tau++) {
    float sum = 0.0f;

    // sum 为当前差分函数的值
    for (int i = 0; i < half_size; i++) {
      float delta = input_buffer[i] - input_buffer[i + tau];
      sum += delta * delta;
    }

    running_sum += sum;
    if (running_sum < 0.00001f) {
      // 不除以很小的值，保证数值稳定
      yin->yin_buffer[tau] = 1.0f;
    } else {
      // d'(tau) = d(tau) / [ (1/tau) * sum(d(j)) ]
      yin->yin_buffer[tau] = sum * tau / running_sum;
    }
  }
}

// 辅助：获取大于等于 val 的最小 2 的幂次
int next_pow2(int val) {
  int n = 1;
  while (n < val) n <<= 1;
  return n;
}

static void Yin_difference_fft(Yin* yin, const float* input_buffer) {
  // 窗口大小
  int half_size = YIN_BUFFER_SIZE / 2;

  // A. 预计算能量项 (前缀和)
  float* S = (float*)malloc((YIN_BUFFER_SIZE + 1) * sizeof(float));
  S[0] = 0.0f;
  for (int i = 0; i < YIN_BUFFER_SIZE; i++) {
    S[i + 1] = S[i] + (input_buffer[i] * input_buffer[i]);
  }

  // 计算互相关项 (FFT)
  int fft_size = next_pow2(YIN_BUFFER_SIZE);
  // 窗口内的信号
  yin_complex* corr = (yin_complex*)malloc(fft_size * sizeof(yin_complex));
  // 延迟对比的信号
  yin_complex* corr_lag = (yin_complex*)malloc(fft_size * sizeof(yin_complex));

  for (int i = 0; i < fft_size; i++) {
    if (i < half_size) {
      corr[i] = yin_make_complex(input_buffer[i], 0.0f);
    } else {
      // 窗口之外的需要补 0
      corr[i] = yin_make_complex(0.0f, 0.0f);
    }

    if (i < YIN_BUFFER_SIZE) {
      corr_lag[i] = yin_make_complex(input_buffer[i], 0.0f);
    } else {
      // 有效数据之外的需要补 0
      corr_lag[i] = yin_make_complex(0.0f, 0.0f);
    }
  }
  fft(corr, fft_size);
  fft(corr_lag, fft_size);

  // 频域互相关: Conj(A) * B
  for (int i = 0; i < fft_size; i++) {
    corr[i] = yin_conj(corr[i]) * corr_lag[i];
  }

  ifft(corr, fft_size);

  // 硬性规定
  yin->yin_buffer[0] = 1.0f;
  float term1 = S[half_size] - S[0];  // 第一项：固定项
  float running_sum = 0.0f;

  for (int tau = 1; tau < half_size; tau++) {
    float term2 = yin_real(corr[tau]);             // 第二项：互相关项
    float term3 = S[tau + half_size] - S[tau];  // 第三项：移动能量项
    float sum = term1 - 2.0f * term2 + term3;
    if (sum < 0.0f) {
      sum = 0.0f;
    }
    running_sum += sum;
    if (running_sum < 0.00001f) {
      // 不除以很小的值，保证数值稳定
      yin->yin_buffer[tau] = 1.0f;
    } else {
      // d'(tau) = d(tau) / [ (1/tau) * sum(d(j)) ]
      yin->yin_buffer[tau] = sum * tau / running_sum;
    }
  }
  free(corr);
  free(corr_lag);
  free(S);
}

// 步骤2：寻找最佳 tau（延迟）
static int Yin_absolute_threshold(Yin* yin) {
  int half_size = YIN_BUFFER_SIZE / 2;
  int tau;

  // 寻找第一个低于阈值的点
  // tau 从 2 开始，是个小技巧，避免 "高频误差"
  for (tau = 2; tau < half_size; tau++) {
    if (yin->yin_buffer[tau] < yin->threshold) {
      // 找到了阈值之下的区域，继续找局部最小值（谷底）
      while (tau + 1 < half_size &&
             yin->yin_buffer[tau + 1] < yin->yin_buffer[tau]) {
        tau++;
      }

      yin->probability = 1.0f - yin->yin_buffer[tau];
      return tau;
    }
  }

  // 如果找不到低于阈值的，就找全局最小值（可能是噪音或很弱的信号）
  int best_tau = 2;
  float min_val = 100.0f;
  for (tau = 2; tau < half_size; tau++) {
    if (yin->yin_buffer[tau] < min_val) {
      min_val = yin->yin_buffer[tau];
      best_tau = tau;
    }
  }
  yin->probability = 1.0f - min_val;
  return best_tau;
}

static float Yin_parabolic_interpolation(Yin* yin, int tau_idx) {
  int half_size = YIN_BUFFER_SIZE / 2;

  // 边界检查
  if (tau_idx < 1 || tau_idx >= half_size - 1) {
    return (float)tau_idx;
  }

  float s0 = yin->yin_buffer[tau_idx - 1];
  float s1 = yin->yin_buffer[tau_idx];
  float s2 = yin->yin_buffer[tau_idx + 1];

  // 抛物线拟合公式找到谷底的偏移量
  float adjustment = (s2 - s0) / (2.0f * (2.0f * s1 - s2 - s0));

  return (float)tau_idx + adjustment;
}

YIN_API float Yin_get_pitch(Yin* yin, float* input_buffer) {
  // 1. 计算差分
  Yin_difference_fft(yin, input_buffer);

  // 2. 找粗略延迟
  int tau = Yin_absolute_threshold(yin);

  // 弱音时 probability 往往偏低；阈值过高会导致小声完全无读数（由上层 RMS/峰值门控挡噪声）
  if (yin->probability < 0.085f) {
    return -1.0f;
  }

  // 3. 精细插值
  float better_tau = Yin_parabolic_interpolation(yin, tau);

  // 4. 转换为频率 Hz
  // f = 采样率 / 周期
  float pitch_in_hz = (float)YIN_SAMPLING_RATE / better_tau;

  return pitch_in_hz;
}