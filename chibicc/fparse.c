// Host-independent parsing of C floating literals into the x87 80-bit format.
//
// chibicc's native build used the host strtold(), whose result depends on the
// host's long double (x87 on x86-64, IEEE binary128 on wasm32). A compiler that
// must produce identical code wherever it runs has to own this conversion, so
// this file parses decimal and hexadecimal literals exactly with a small
// big-integer and rounds once, to nearest-even, to a 64-bit significand.
//
// Algorithm: value = D * 10^e10 * 2^e2 with D an integer of the literal's
// digits. For e10 >= 0 the product is an integer; for e10 < 0 the quotient
// D*2^k / 10^-e10 is computed by bit-serial division with a sticky remainder.
// The result is then normalized to 64 significand bits (+ round bit + sticky),
// denormalized if below the minimum exponent, and rounded once.
#include "chibicc.h"

#define BN_LIMBS 1200  // > (800 decimal digits + 10^6000) in 32-bit limbs
typedef struct { uint32_t d[BN_LIMBS]; int n; } Bn;

static void bn_set_u64(Bn *a, uint64_t v) {
  a->n = 0;
  while (v) { a->d[a->n++] = (uint32_t)v; v >>= 32; }
}

static int bn_bits(Bn *a) {
  if (a->n == 0) return 0;
  uint32_t top = a->d[a->n - 1];
  int b = 0;
  while (top) { b++; top >>= 1; }
  return (a->n - 1) * 32 + b;
}

// a = a * m + add
static void bn_mul_small(Bn *a, uint32_t m, uint32_t add) {
  uint64_t carry = add;
  for (int i = 0; i < a->n; i++) {
    uint64_t t = (uint64_t)a->d[i] * m + carry;
    a->d[i] = (uint32_t)t;
    carry = t >> 32;
  }
  if (carry) {
    if (a->n >= BN_LIMBS) error("floating literal too large to represent");
    a->d[a->n++] = (uint32_t)carry;
  }
}

static void bn_shl(Bn *a, int bits) {
  if (a->n == 0 || bits == 0) return;
  int limbs = bits / 32, sh = bits % 32;
  if (a->n + limbs + 1 > BN_LIMBS) error("floating literal too large to represent");
  if (sh) {
    uint32_t carry = 0;
    for (int i = 0; i < a->n; i++) {
      uint32_t v = a->d[i];
      a->d[i] = (v << sh) | carry;
      carry = v >> (32 - sh);
    }
    if (carry) a->d[a->n++] = carry;
  }
  if (limbs) {
    for (int i = a->n - 1; i >= 0; i--) a->d[i + limbs] = a->d[i];
    for (int i = 0; i < limbs; i++) a->d[i] = 0;
    a->n += limbs;
  }
}

static void bn_shr1(Bn *a) {
  uint32_t carry = 0;
  for (int i = a->n - 1; i >= 0; i--) {
    uint32_t v = a->d[i];
    a->d[i] = (v >> 1) | (carry << 31);
    carry = v & 1;
  }
  while (a->n > 0 && a->d[a->n - 1] == 0) a->n--;
}

static int bn_cmp(Bn *a, Bn *b) {
  if (a->n != b->n) return a->n < b->n ? -1 : 1;
  for (int i = a->n - 1; i >= 0; i--)
    if (a->d[i] != b->d[i]) return a->d[i] < b->d[i] ? -1 : 1;
  return 0;
}

// a -= b, requires a >= b
static void bn_sub(Bn *a, Bn *b) {
  int64_t borrow = 0;
  for (int i = 0; i < a->n; i++) {
    int64_t t = (int64_t)a->d[i] - (i < b->n ? b->d[i] : 0) - borrow;
    borrow = t < 0;
    a->d[i] = (uint32_t)(t + (borrow ? ((int64_t)1 << 32) : 0));
  }
  while (a->n > 0 && a->d[a->n - 1] == 0) a->n--;
}

static void bn_pow10(Bn *a, int e) {
  bn_set_u64(a, 1);
  while (e >= 9) { bn_mul_small(a, 1000000000u, 0); e -= 9; }
  static const uint32_t p[] = {1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000};
  bn_mul_small(a, p[e], 0);
}

// Low 64 bits of a >> sh; sets *sticky if any shifted-out bit is nonzero.
static uint64_t bn_extract(Bn *a, int sh, bool *sticky) {
  for (int i = 0; i < sh / 32 && i < a->n; i++) if (a->d[i]) *sticky = true;
  if (sh % 32) {
    int i = sh / 32;
    if (i < a->n && (a->d[i] & ((1u << (sh % 32)) - 1))) *sticky = true;
  }
  uint64_t v = 0;
  for (int i = 0; i < 3; i++) {
    int idx = sh / 32 + i;
    if (idx < a->n) v |= (uint64_t)a->d[idx] << (32 * i) >> 0, v = v; // placeholder, replaced below
  }
  // Recompute cleanly as a 96-bit window shifted right by sh%32.
  uint64_t lo = 0, hi = 0;
  int base = sh / 32;
  uint64_t w0 = base < a->n ? a->d[base] : 0;
  uint64_t w1 = base + 1 < a->n ? a->d[base + 1] : 0;
  uint64_t w2 = base + 2 < a->n ? a->d[base + 2] : 0;
  int s = sh % 32;
  lo = (w0 | (w1 << 32));
  hi = w2;
  if (s) lo = (lo >> s) | (hi << (64 - s));
  (void)v;
  return lo;
}

static Bn D, P, T, Q;

// Parses a floating literal at s. Stores the x87 bits (significand with the
// explicit integer bit; sign|exponent) and returns the end of the literal.
// Only the value is parsed; suffixes are left to the caller.
char *parse_float_literal(char *s, uint64_t out[2]) {
  char *p = s;
  bool hex = false;
  if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) { hex = true; p += 2; }

  D.n = 0;
  int ndigits = 0;      // significant digits kept in D
  int dropped = 0;      // integer-part digits dropped after the cap (scale up)
  int frac_digits = 0;  // fraction digits kept in D (scale down)
  bool extra_sticky = false, seen_point = false, any = false;
  const int cap = 800;
  for (;; p++) {
    int c = *p, v;
    if (c == '.' && !seen_point) { seen_point = true; continue; }
    if (c >= '0' && c <= '9') v = c - '0';
    else if (hex && c >= 'a' && c <= 'f') v = c - 'a' + 10;
    else if (hex && c >= 'A' && c <= 'F') v = c - 'A' + 10;
    else break;
    any = true;
    if (ndigits == 0 && v == 0) {       // leading zeros: only count fraction position
      if (seen_point) frac_digits++;
      continue;
    }
    if (ndigits < cap) {
      bn_mul_small(&D, hex ? 16 : 10, v);
      ndigits++;
      if (seen_point) frac_digits++;
    } else {
      if (v) extra_sticky = true;
      if (!seen_point) dropped++;
    }
  }
  if (!any) return s;

  int64_t exp = 0;
  if ((hex && (*p == 'p' || *p == 'P')) || (!hex && (*p == 'e' || *p == 'E'))) {
    char *q = p + 1;
    bool neg = false;
    if (*q == '+' || *q == '-') { neg = *q == '-'; q++; }
    if (*q >= '0' && *q <= '9') {
      while (*q >= '0' && *q <= '9') {
        if (exp < 100000000) exp = exp * 10 + (*q - '0');
        q++;
      }
      if (neg) exp = -exp;
      p = q;
    }
  }

  // value = D * base^(dropped - frac_digits) * (hex ? 2^exp : 10^exp)
  int64_t e10 = 0, e2 = 0;
  if (hex) { e2 = exp - 4 * (int64_t)frac_digits + 4 * (int64_t)dropped; }
  else     { e10 = exp - frac_digits + dropped; }

  uint64_t sig = 0;
  int64_t bexp;            // unbiased exponent of the significand's top bit
  bool sticky = extra_sticky, round = false;

  if (D.n == 0) {          // zero (sticky digits beyond the cap cannot matter)
    out[0] = 0; out[1] = 0;
    return p;
  }
  // Clamp absurd decimal exponents (bounded big-integer sizes); the result is
  // then certainly 0 or infinity.
  if (!hex) {
    if (e10 + ndigits > 5000) { out[0] = 1ULL << 63; out[1] = 0x7fff; return p; }
    if (e10 + ndigits < -5000) { out[0] = 0; out[1] = 0; return p; }
  }
  if (hex && e2 > 20000) { out[0] = 1ULL << 63; out[1] = 0x7fff; return p; }
  if (hex && e2 < -20000) { out[0] = 0; out[1] = 0; return p; }

  int scale;             // Q * 2^scale is the (truncated) value
  if (e10 >= 0) {
    bn_pow10(&P, (int)e10);
    // Q = D * P: multiply limb by limb into Q via repeated small multiplies of D.
    Q = D;
    // multiply Q by P using schoolbook over P's limbs
    { Bn acc; acc.n = 0;
      for (int i = P.n - 1; i >= 0; i--) {
        // acc = acc * 2^32 + D * P.d[i]
        bn_shl(&acc, 32);
        T = D; bn_mul_small(&T, P.d[i], 0);
        // acc += T
        int n = acc.n > T.n ? acc.n : T.n;
        uint64_t carry = 0;
        for (int j = 0; j < n || carry; j++) {
          if (j >= BN_LIMBS) error("floating literal too large to represent");
          uint64_t t = (uint64_t)(j < acc.n ? acc.d[j] : 0) + (j < T.n ? T.d[j] : 0) + carry;
          acc.d[j] = (uint32_t)t; carry = t >> 32;
          if (j >= acc.n) acc.n = j + 1;
        }
      }
      Q = acc; }
    scale = 0;
  } else {
    bn_pow10(&P, (int)-e10);
    // Q = floor(D * 2^k / P) with 66..67 bits, sticky if remainder != 0
    int k = bn_bits(&P) + 66 - bn_bits(&D);
    if (k < 0) k = 0;
    T = D; bn_shl(&T, k);
    Q.n = 0;
    int i0 = bn_bits(&T) - bn_bits(&P);
    Bn S = P; bn_shl(&S, i0);
    for (int i = i0; i >= 0; i--) {
      if (bn_cmp(&T, &S) >= 0) {
        bn_sub(&T, &S);
        // set bit i of Q
        int li = i / 32;
        if (li >= Q.n) { for (int j = Q.n; j <= li; j++) Q.d[j] = 0; Q.n = li + 1; }
        Q.d[li] |= 1u << (i % 32);
      }
      bn_shr1(&S);
    }
    if (T.n != 0) sticky = true;
    scale = -k;
  }
  scale += (int)e2;

  // Normalize Q to 64 bits: sig = top 64 bits, round = next bit, sticky |= rest.
  int nb = bn_bits(&Q);
  if (nb > 64) {
    int sh = nb - 64;
    bool st = false;
    uint64_t below = bn_extract(&Q, sh - 1, &st);   // 64 bits ending with the round bit
    round = below & 1;
    sticky |= st;
    sig = bn_extract(&Q, sh, &st);
    scale += sh;
  } else {
    sig = bn_extract(&Q, 0, &sticky);
    sig <<= (64 - nb);
    scale -= (64 - nb);
  }
  bexp = (int64_t)scale + 63;   // value = sig * 2^scale = 1.xxx * 2^bexp

  // Denormalize if below the minimum normal exponent -16382.
  int64_t biased = bexp + 16383;
  if (biased < 1) {
    int64_t sh = 1 - biased;    // shift right by sh, keeping round/sticky
    if (sh > 66) { sticky |= sig != 0 || round; sig = 0; round = false; }
    else {
      for (int64_t i = 0; i < sh; i++) {
        sticky |= round;
        round = sig & 1;
        sig >>= 1;
      }
    }
    biased = 0;
  }
  // Round to nearest even.
  if (round && (sticky || (sig & 1))) {
    sig++;
    if (sig == 0) { sig = 1ULL << 63; biased++; }        // carry out of normal
    else if (biased == 0 && (sig & (1ULL << 63))) biased = 1; // subnormal -> min normal
  }
  if (biased >= 0x7fff) { out[0] = 1ULL << 63; out[1] = 0x7fff; return p; }  // inf
  out[0] = sig;
  out[1] = (uint64_t)biased;
  return p;
}

// Builds the compiler's own `long double` from x87 bits: exact on x86-64
// (same format) and on wasm32 (binary128 has more precision and the same
// exponent range).
long double ldouble_from_x87(uint64_t sig, uint64_t se) {
#ifndef __wasm__
  union { long double f80; uint64_t u64[2]; } u;
  memset(&u, 0, sizeof(u));
  u.u64[0] = sig; u.u64[1] = se;
  return u.f80;
#else
  union { long double f128; uint64_t u64[2]; } u;
  uint64_t sign = (se >> 15) & 1, exp = se & 0x7fff;
  uint64_t frac;
  if (exp == 0x7fff) {
    frac = sig & 0x7fffffffffffffffULL;            // inf: 0; nan: payload
  } else if (exp == 0) {
    frac = sig;                                    // subnormal: same alignment
  } else {
    frac = sig & 0x7fffffffffffffffULL;            // drop the explicit integer bit
  }
  // 63 fraction bits -> 112: shift left by 49; hi gets the top 48 bits.
  u.u64[0] = frac << 49;
  u.u64[1] = (sign << 63) | (exp << 48) | (frac >> 15);
  return u.f128;
#endif
}
