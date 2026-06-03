// Minimal memcpy for bare-metal RISC-V (no standard library)
void *memcpy(void *dst, const void *src, __SIZE_TYPE__ n) {
    char *d = dst;
    const char *s = src;
    while (n--) *d++ = *s++;
    return dst;
}
