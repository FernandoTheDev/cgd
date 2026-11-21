#ifndef _C99_ERRNO_H
#define _C99_ERRNO_H

extern int *__errno_location(void);
#define errno (*__errno_location())

#define ENOENT 2
#define EINTR 4
#define ENOMEM 12
#define EACCES 13
#define EINVAL 22
#define ERANGE 34

#endif
