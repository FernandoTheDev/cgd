#ifndef _C99_STDIO_H
#define _C99_STDIO_H

#include <stdarg.h>
#include <stddef.h>

#define EOF (-1)

typedef struct _IO_FILE FILE;

extern int printf(const char *fmt, ...);
extern int sprintf(char *buf, const char *fmt, ...);
extern int snprintf(char *buf, size_t size, const char *fmt, ...);
extern int vprintf(const char *fmt, va_list ap);
extern int vsprintf(char *buf, const char *fmt, va_list ap);
extern int vsnprintf(char *buf, size_t size, const char *fmt, va_list ap);
extern int puts(const char *s);
extern int putchar(int c);
extern int fflush(FILE *stream);

#endif
