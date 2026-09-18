// codex review 1, findings 2 and 8: subnormal and boundary long double constants
long double f1(void) { return 0x1p-16445L; }
long double f2(void) { return 0x1.fffffffffffffffep-16383L; }
long double f3(void) { return 0x1p-16382L; }
long double f4(void) { return 1.18973149535723176502e+4932L; }
long double f5(void) { return -0.0L; }
long double f6(void) { return 1.0L / 3.0L; }
long double f7(void) { return 3.14159265358979323846264338327950288L; }
