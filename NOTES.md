# Lab notebook

## Environment (2026-09-18)
- exe.dev VM, x86-64, Ubuntu 24.04, 8 cores. VM was reset since the sandbox-stack work; tools re-fetched.
- wasi-sdk 34 at `~/opt/wasi-sdk-34.0-x86_64-linux` (clang 23.1.0, sysroots for wasm32-wasip1/p2/p3).
- wazero CLI at `~/.local/bin/wazero` (v0.0.0-20260903), tcc 0.9.27, clang 18 host, tokei.
- Clones under `~/src`: chibicc (rui314, 90d1f7f 2020-12-07), tinycc mob (0fb5430 2026-09-04), cproc (d1c53dd), qbe (e786f06), lfi (top-level docs), sandbox-stack (own prior work).
- LFI prebuilt x86-64 toolchain v0.12 downloading to `~/opt/lfi`.

## Candidate sizes (tokei, code lines)
| compiler | C code lines | notes |
|---|---:|---|
| chibicc (upstream) | 9,379 | x86-64 only, emits GNU asm text, needs external as/ld; C11; self-hosting |
| sandbox-stack/cc (chibicc fork) | 7,917 | x86-64 backend + wasm32 backend + own assembler and static ELF writer; no external tools |
| cproc | 9,179 | frontend only; needs QBE (15,929) plus external as/ld |
| qbe | 15,929 | backend for amd64/arm64/rv64; no wasm |
| tinycc | 108,369 (all targets; x86-64 Linux subset ~27k) | compiler+assembler+linker, no external tools; no wasm backend |
| w2c2 (vendored, pruned) | 12,336 | wasm → C translator (used for the seccomp host in sandbox-stack) |

## Exp 1: chibicc → wasm32-wasi (done)
Build: `tools/build-chibicc-wasm.sh`. Test: `tools/exp1-chibicc-wasm.sh` (runs all of `chibicc/test/*.c` through `chibicc.wasm` under wazero with the source tree mounted read-only at `/`, `/usr/include` read-only, and one writable output directory; then assembles/links the emitted `.s` with gcc and runs it). Bench: `tools/bench.sh`.

Changes to upstream chibicc (commit in `chibicc/UPSTREAM`):
- `main.c`: `NO_SUBPROCESS` (auto-defined for `__wasm__`) makes `run_cc1` call `cc1()` in-process instead of fork+exec of itself; `assemble`, `run_linker`, `create_tmpfile` become errors ("use -S"). One C input per invocation (parser/preprocessor state is global).
- `chibicc.h`: `<glob.h>`, `<sys/wait.h>` guarded; `<inttypes.h>` added.
- Host-`long` assumptions fixed: `strtoul` → `strtoull` (integer literals above 2^32 were truncated), `1L << bit_width` → `1LL`, `long` locals in the preprocessor's `#if` evaluator and `new_ulong`, `Node.begin/end` (case ranges) → `int64_t`, `%ld/%lu` → `PRId64/PRIu64`.
- `codegen.c`: `long double` constants: `x87_bits()` converts the compiler's own `long double` (binary128 on wasm32) to the x87 80-bit bit pattern (same exponent bias, significand narrowed 112→63 bits, round-to-nearest-even). Comments in the emitted asm print `(double)` values so both builds print the same text.
- Link with `-lc-printscan-long-double` (wasi-libc's `strtold` otherwise aborts).

Results: 41/41 tests pass, 40/41 `.s` byte-identical to native; `macro.c` differs in two bytes (`__TIME__`). Self-compile: 27/27 identical.
Sharp edges: wazero's guest `cwd` is `/`, so `#include "relative/path"` needs the source tree mounted at `/`. wazero's argv[0] is the module path, so chibicc's `dirname(argv0)/include` default does not resolve; pass `-I<dir>/include` explicitly.

## Exp 2: tinycc → wasm32-wasi (done)
Build: `tools/build-tcc-wasm.sh` (one-source build of `tcc.c` for target x86-64; `config.h`, `tccdefs_.h`, `libtcc1.a` and `include/` come from a native `make` in `~/src/tinycc`).
- wasi-sdk's `setjmp.h` `#error`s (needs the exception-handling proposal); tcc uses setjmp only for `tcc_error` recovery, so `tcc/sjlj.h` stubs `setjmp` to 0 and `longjmp` to trap. `execvp` (used by `tcc -run`-style re-exec in tcctools.c) defined to -1.
- Search paths baked in: `/tcc` (include + libtcc1.a), `/usr/lib/x86_64-linux-gnu` for crt*.o, `/lib64/ld-linux-x86-64.so.2` must be visible for the dynamic link.
- Run: `wazero run -mount=/usr:/usr:ro -mount=/lib:/lib:ro -mount=/lib64:/lib64:ro -mount=build/tcc/lib:/tcc:ro -mount=out:/out tcc.wasm -B/tcc -o /out/hello /in/hello.c`. Output ELF byte-identical to native tcc (same source). wazero does not set the executable bit (WASI has no chmod), so `chmod +x` afterwards.
- `-static` against glibc fails (unresolved `_Unwind_*`, `__letf2`): known tcc limitation, not a sandbox issue.
- Startup under wazero: 324 ms (JIT of 922 KB); tcc has no wasm backend, so tcc.wasm is "sandboxed compiler, unsandboxed output".

## Exp 4: LFI (done)
Tools: prebuilt `x86_64-lfi-clang` v0.12 (clang 23 + musl sysroot); `lfi-runtime`, `lfi-verifier` (x86-64 verifier: `src/x64/*`), `lfi-rewriter` cloned and built with meson.
- Compiler under LFI: `x86_64_lfi-linux-musl-clang -O2 -DNO_SUBPROCESS -static-pie chibicc/*.c` → 402 KB static-pie; `lfi-verify` passes; `lfi-run -v -r --dir=... --wd=/ -- chibicc-lfi -S ...` produces output identical to native.
- Output under LFI: chibicc's `.s` → `x86_64_lfi-linux-musl-clang -static-pie` (the driver runs lfi-rewrite + lfi-postlink itself; feeding an already-rewritten file gives "nested .bundle_lock") → `lfi-verify` passes → `lfi-run -v` prints the expected line. One mnemonic fix: LLVM's assembler rejects `movsxd` (GNU as accepts it); `movslq` works in both.
- The rewritten `main` shows the LFI scheme: `sub $16,%esp; lea (%rsp,%r14,1),%rsp` (stack pointer masked into the sandbox region via reserved `%r14`), `mov %rsp,%gs:-8(%ebp)` (32-bit addressing through the `%gs` segment base).

## Timings (chibicc compiling its own 27 sources; `tools/bench.sh`)
| configuration | total | per-run startup (empty input) |
|---|---:|---:|
| native (gcc-built chibicc) | 0.52 s | 2.5 ms |
| LFI, verified on each run | 2.34 s | 23.6 ms (2.2 ms without `-v`) |
| wazero, compiler (JIT per run, no cache) | 1.49 s | 93 ms |
| wazero, interpreter | 30.7 s | 20 ms |

## Codex review 1 (chibicc port): findings and fixes
`reviews/codex-review-1.md`. Codex compared the port against upstream and tested the native and WASI binaries; it found four reproducible code-generation differences I had missed, all host-`long`/host-float leaks of the same family as the ones fixed earlier.

| # | sev | finding | fix |
|---|---|---|---|
| 1 | high | `Relocation.addend` is host `long`: `char *p = a + 0x100000000L;` emitted `.quad a+0` from wasm | `int64_t`, `PRId64` (`chibicc.h`, `codegen.c`); test `tests/port/reloc_addend.c` |
| 2 | high | `x87_bits()` flushed binary128 subnormals to zero (x87 has the same minimum exponent, so they are representable) | rewritten: subnormals keep the fraction, rounding may carry into the exponent (subnormal→min normal, max→inf); test `tests/port/x87_subnormal.c` |
| 3 | high | literals are parsed with the host `strtold`: native rounds once to x87 (64-bit significand), wasm rounds to binary128 and then to x87, a double rounding. `double d = 0x1.00000000000008001p0;` differs by one ulp | **open**, see below: the compiler must parse floating literals itself |
| 4 | high | `unsigned long a = 0x1p63;` folded through `(int64_t)double`, UB: x86 gives 0x8000000000000000, wasm saturates to 0x7fff… | `eval2` ND_CAST and global initializers convert with the destination's signedness and explicit range checks (`parse.c`); test `tests/port/fold_unsigned.c`. For values ≥ 2^63 native upstream produced the x86 "integer indefinite", i.e. it was wrong; both builds now agree on the correct value |
| 5 | high (claim) | `tools/bench.sh` ran `lfi-run` without `-r`, i.e. with the whole filesystem mapped, and mounted the repo writable into wazero | restricted LFI dirs (`-r --dir … --wd /`), read-only mounts + one output dir everywhere |
| 6 | medium | default include dir is `dirname(argv[0])/include`; wazero's argv[0] is the module path | documented; pass `-I` |
| 7 | medium | `__DATE__`/`__TIME__`/`__TIMESTAMP__` from the clock and file mtimes | `SOURCE_DATE_EPOCH` honoured (gmtime) in both compilers |
| 8 | low | NaN with all-discarded payload became infinity in `x87_bits()` | fixed with #2 |

Upstream limitations (not port regressions), kept as-is: `eval_double` folds in binary64 even for `long double`; static `long double x = 1.0L;` is unsupported ("internal error").

After the fixes: exp1 41/41 identical, exp3 11/11 identical, `tests/port/`: 3/4 identical, `literals.c` still differs (finding 3).
