#pragma once

#ifdef __cplusplus
#include <cmath>
#include <complex>
typedef std::complex<float> yin_complex;
#else
#include <complex.h>
#include <math.h>
typedef complex float yin_complex;
#endif

static inline yin_complex yin_make_complex(float re, float im) {
#ifdef __cplusplus
  return yin_complex(re, im);
#else
  return re + im * I;
#endif
}

static inline yin_complex yin_cexp_imag(float theta) {
#ifdef __cplusplus
  return std::exp(yin_make_complex(0.0f, theta));
#else
  return cexpf(theta * I);
#endif
}

static inline yin_complex yin_conj(yin_complex v) {
#ifdef __cplusplus
  return std::conj(v);
#else
  return conjf(v);
#endif
}

static inline float yin_real(yin_complex v) {
#ifdef __cplusplus
  return std::real(v);
#else
  return crealf(v);
#endif
}

void fft(yin_complex x[], int n);
void ifft(yin_complex x[], int n);