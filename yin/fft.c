#include "fft.h"

#include <assert.h>
#define PI 3.14159265358979323846

/* 根据索引的二进制反转来排序 */
static void sort_by_binrev(yin_complex x[], int n) {
  // n 只能是 2 的指数
  assert((n & (n - 1)) == 0);
  // 通过模拟反向二进制加法，获取 i 对应的二进制反转 j
  for (int i = 1, j = 0; i < n; i++) {
    // i 加上 1，反转情况下，就是在最高位加了 1
    int add_bit = n >> 1;
    // 模拟反向加法，如果 j 在 add_bit 位置为 1, 则需要进位
    for (; j & add_bit; add_bit >>= 1) {
      // 异或清零
      j ^= add_bit;
    }
    // 异或将该位设为1
    j ^= add_bit;

    // 交换 i 和 j 的位置，因为在反转排序中，x[i] 应该在 x[j] 的位置
    // 防止重复交换
    if (i < j) {
      yin_complex t = x[i];
      x[i] = x[j];
      x[j] = t;
    }
  }
}

/* fft 迭代版 */
void fft(yin_complex x[], int n) {
  sort_by_binrev(x, n);

  // 自底向上计算
  // 问题规模 size 从 2 开始，因为 1 就是终点情况
  for (int size = 2; size <= n; size *= 2) {
    // 计算当前规模的单位旋转因子（就是当前单位圆上的旋转角度）
    const float theta = (float)(-2.0 * PI / size);
    yin_complex w_unit = yin_cexp_imag(theta);
    // 当前规模下每个问题的起点
    for (int i = 0; i < n; i += size) {
      // 当前旋转因子
      // 同样是合并的过程
      yin_complex w = yin_make_complex(1.0f, 0.0f);
      for (int j = 0; j < size / 2; j++) {
        yin_complex u = x[i + j];
        // 计算之前，前半段都是偶序列的，后半段都是奇序列的
        yin_complex t = w * x[i + j + size / 2];

        x[i + j] = u + t;
        x[i + j + size / 2] = u - t;
        // 现在已经重新排序好了

        w *= w_unit;
      }
    }
  }
}

/* 反向 fft 迭代版 */
void ifft(yin_complex x[], int n) {
  for (int i = 0; i < n; i++) {
    x[i] = yin_conj(x[i]);
  }
  fft(x, n);
  for (int i = 0; i < n; i++) {
    x[i] = yin_conj(x[i]) / (float)n;
  }
}