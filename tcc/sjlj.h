/* WASI has no setjmp/longjmp; tcc only uses them for error recovery. */
typedef int jmp_buf[1];
static inline int setjmp(jmp_buf b) { (void)b; return 0; }
static inline __attribute__((noreturn)) void longjmp(jmp_buf b, int v) { (void)b; (void)v; __builtin_trap(); }
