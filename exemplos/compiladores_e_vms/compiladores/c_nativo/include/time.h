#ifndef _C99_TIME_H
#define _C99_TIME_H

#include <stddef.h>

typedef long time_t;
typedef long clock_t;

#define CLOCKS_PER_SEC 1000000L

struct tm {
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
    long tm_gmtoff;
    const char *tm_zone;
};

extern clock_t clock(void);
extern double difftime(time_t time1, time_t time0);
extern time_t time(time_t *timer);
extern time_t mktime(struct tm *timeptr);
extern struct tm *gmtime(const time_t *timer);
extern struct tm *localtime(const time_t *timer);

#endif
