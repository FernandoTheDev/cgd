#ifndef _C99_MATH_H
#define _C99_MATH_H

#define HUGE_VAL (1.0 / 0.0)
#define M_PI 3.14159265358979323846
#define M_E 2.71828182845904523536

extern double fabs(double x);
extern double floor(double x);
extern double ceil(double x);
extern double trunc(double x);
extern double round(double x);
extern double fmod(double x, double y);
extern double sqrt(double x);
extern double cbrt(double x);
extern double pow(double x, double y);
extern double hypot(double x, double y);
extern double exp(double x);
extern double exp2(double x);
extern double log(double x);
extern double log2(double x);
extern double log10(double x);
extern double sin(double x);
extern double cos(double x);
extern double tan(double x);
extern double asin(double x);
extern double acos(double x);
extern double atan(double x);
extern double atan2(double y, double x);
extern double sinh(double x);
extern double cosh(double x);
extern double tanh(double x);

#endif
