// codex review 1, finding 3: literal parsing precision (double rounding through x87)
double d1 = 0x1.00000000000008001p0;
double d2 = 0.1;
double d3 = 1e300;
float f1 = 0.1f;
float f2 = 16777217.0f;
long double l1(void) { return 0x1.00000000000000010000000000000001p0L; }
double g(void) { return 0x1.00000000000008001p0; }
