#ifndef _C99_STRING_H
#define _C99_STRING_H

#include <stddef.h>

extern void *memcpy(void *dst, const void *src, size_t n);
extern void *memmove(void *dst, const void *src, size_t n);
extern void *memset(void *dst, int c, size_t n);
extern int memcmp(const void *a, const void *b, size_t n);
extern char *strcpy(char *dst, const char *src);
extern char *strncpy(char *dst, const char *src, size_t n);
extern char *strcat(char *dst, const char *src);
extern char *strncat(char *dst, const char *src, size_t n);
extern int strcmp(const char *a, const char *b);
extern int strncmp(const char *a, const char *b, size_t n);
extern size_t strlen(const char *s);
extern char *strchr(const char *s, int c);
extern char *strstr(const char *haystack, const char *needle);

#endif
