// errno_fix.h — override picolibc's thread-local errno for NeoRV32 newlib compat
// Force-included before all compilation units
#ifdef errno
#undef errno
#endif
#define errno (*__errno_location())
int *__errno_location(void);
