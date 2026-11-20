/* Parser puro: regressões e corpus aleatório limitado; executável sem runtime/GC. */
#include "http_interno.h"
#include <assert.h>
static uint32_t seed = 0x434744;
static uint32_t random_value(void) {
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return seed;
}
int main(void) {
    rt_http_request request;
    const char *good = "GET / HTTP/1.1\r\nHost: x\r\n\r\n";
    for (size_t size = 0; size < strlen(good); ++size)
        assert(rt_http_parse(good, size, 1024, &request) != 0);
    assert(rt_http_parse(good, strlen(good), 1024, &request) == 0);
    char buffer[4096];
    for (unsigned iteration = 0; iteration < 50000; ++iteration) {
        size_t size = random_value() % sizeof(buffer);
        for (size_t i = 0; i < size; ++i)
            buffer[i] = (char)(random_value() & 255);
        if (iteration % 2 == 0) {
            size_t length = strlen(good);
            memcpy(buffer, good, length);
            size = length;
            buffer[random_value() % size] = (char)(random_value() & 255);
        }
        int result = rt_http_parse(buffer, size, iteration % 4097, &request);
        assert(result == 0 || result == 400 || result == 413 || result == 417 || result == 431 ||
               result == 501);
        if (!result) {
            assert(request.body_size <= iteration % 4097);
            assert(request.count <= RT_HTTP_FIELDS);
        }
    }
    return 0;
}
