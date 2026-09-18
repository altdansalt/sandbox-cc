Review request: chibicc ported to run as a wasm32-wasi module (and under LFI).

Context: `chibicc/` is rui314's chibicc (upstream commit in chibicc/UPSTREAM) with small patches so the *compiler itself* runs inside a WebAssembly sandbox (wasi-sdk 34, wazero) while still targeting x86-64 Linux. The compiler must produce exactly the same assembly as the native build. Compare against upstream at ~/src/chibicc (same commit) — `diff -ru ~/src/chibicc chibicc` shows the changes (ignore Makefile/test).

Threat model / goals:
1. Correctness of cross-hosting: the compiler now runs on an ILP32 host (wasm32: long=4 bytes, long double=binary128) while generating code for LP64 x86-64 with x87 long double. Find any remaining place where chibicc's own host types (long, size_t, pointer size, long double arithmetic, printf formats, strtol family, time/locale) could change the emitted code vs. the native build. Pay special attention to codegen.c x87_bits() (binary128 -> x87 80-bit conversion, including rounding, subnormals, inf/nan) and to parse.c eval_double / constant folding in long double.
2. The in-process cc1 path in main.c (NO_SUBPROCESS): is global state reset correctly, any path where the driver still expects a subprocess, temp file, or /tmp?
3. Anything in the port that weakens the sandbox story (e.g., reading files outside the mounted dirs, relying on argv[0]).

Please list concrete findings with file:line, severity, and a suggested fix. Don't modify files.
