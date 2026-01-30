#pragma once

#include <complex.h>
#include <math.h>

typedef complex float yin_complex;

void fft(yin_complex x[], int n);
void ifft(yin_complex x[], int n);