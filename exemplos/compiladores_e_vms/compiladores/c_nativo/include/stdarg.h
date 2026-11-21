#ifndef _C99_STDARG_H
#define _C99_STDARG_H

typedef struct __c99_va_list_tag {
    unsigned int gp_offset;
    unsigned int fp_offset;
    void *overflow_arg_area;
    void *reg_save_area;
} va_list[1];

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_arg(ap, type) __builtin_va_arg(ap, type)
#define va_end(ap) ((void)0)
#define va_copy(dest, src) (*(dest) = *(src))

#endif
