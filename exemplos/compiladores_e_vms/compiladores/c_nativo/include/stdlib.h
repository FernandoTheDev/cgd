#ifndef _C99_STDLIB_H
#define _C99_STDLIB_H

#include <stddef.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

extern void *malloc(size_t size);
extern void *calloc(size_t nmemb, size_t size);
extern void *realloc(void *ptr, size_t size);
extern void free(void *ptr);
extern void exit(int status);
extern void abort(void);
extern int abs(int j);
extern long labs(long j);
extern long long llabs(long long j);
extern int atoi(const char *nptr);
extern long atol(const char *nptr);
extern double atof(const char *nptr);
extern long strtol(const char *nptr, char **endptr, int base);
extern void qsort(void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *));
extern void *bsearch(const void *key, const void *base, size_t nmemb, size_t size,
                     int (*compar)(const void *, const void *));
extern int rand(void);
extern void srand(unsigned int seed);

#endif
