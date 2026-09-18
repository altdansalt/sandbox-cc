// codex review 1, finding 1: relocation addends above 2^32
extern char a[];
char *p = a + 0x100000000L;
char *q = a - 0x123456789L;
