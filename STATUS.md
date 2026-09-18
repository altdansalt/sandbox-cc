# sandbox-cc: a C compiler toolchain that is sandboxed by default and small enough to verify

**Question (from the brief):** can we build a compiler toolchain that is sandboxed by default and simple enough to verify (like LFI or WASM)? Which existing compiler is closest, and can that compiler itself be sandboxed through WASM (or LFI)?

**Approach:** survey the small C compilers that exist, pick the closest, compile it to wasm32-wasi and run it inside a WebAssembly runtime so that compiling untrusted source is safe. Then push further: make the sandboxed compiler produce sandboxed output (wasm, LFI-conforming x86-64), and check whether the sandboxed compiler can rebuild itself byte-for-byte.

## Where things stand

| Step | State |
|---|---|
| Environment: wasi-sdk 34 (clang 23, wasm32-wasip1 sysroot), wazero, tcc, LFI x86-64 toolchain v0.12 + lfi-run/lfi-verify/lfi-rewrite built from source | done |
| Survey of candidate compilers (chibicc, tcc, cproc+qbe, sandbox-stack/cc, lfi, clang-wasm) | done, see NOTES |
| Exp 1: upstream chibicc compiled to wasm32-wasi, run under wazero, output checked against native chibicc | **done, verified**: 41/41 chibicc tests pass through the sandboxed compiler; 40/41 assembly outputs byte-identical to native (the 41st differs only in `__TIME__`); compiling chibicc's own 27 sources gives 27/27 identical outputs |
| Exp 2: tinycc (compiler+assembler+linker in one module) compiled to wasm32-wasi | **done, verified**: tcc.wasm (922 KB) compiles, assembles and links hello.c to an ELF executable inside wazero; the ELF is byte-identical to native tcc's |
| Exp 3: sandbox-stack/cc (chibicc + wasm backend + own x86-64 assembler/ELF writer) in wasm: sandboxed compiler emitting sandboxed (wasm) or native output with no host tools | not started |
| Exp 4: LFI: run the compiler under LFI (lfi-run -v), and pass chibicc's assembly through the LFI rewriter/verifier | **done, verified** both ways: chibicc built with the LFI clang passes lfi-verify and runs under lfi-run -v (restricted dirs) producing identical output; chibicc-emitted assembly goes through the LFI rewriter, verifies, and runs (needs `movsxd`→`movslq`) |
| Write-up on this page | continuous |

## What's happening right now
Exp 1, 2 and 4 are done. Starting Exp 3: the sandbox-stack `cc` (chibicc + wasm backend + own assembler/ELF writer) compiled to wasm so that a sandboxed compiler emits sandboxed programs with no host tools at all, and a check whether it can rebuild itself byte-for-byte.

## Findings so far
- **Closest existing compiler: chibicc** (9.4k lines, C11, self-hosting, compiles git/sqlite). It ports to wasm32-wasi with ~60 changed lines: the driver forks `as`/`ld` and re-execs itself for cc1 (replaced by an in-process call), and it assumes the host `long` is 64-bit (strtoul, `1L <<`, `%ld`), which silently miscompiles when the compiler runs as wasm32. Also `long double` is x87 on the host but IEEE binary128 on wasm32, so the compiler must convert constant bits itself (done: `x87_bits()` in codegen.c) and wasi-libc needs `-lc-printscan-long-double` for `strtold`.
- **tinycc is the most complete single-module toolchain**: one 922 KB wasm file is compiler + assembler + linker; the ELF it links inside the sandbox is byte-identical to native tcc's. It needed setjmp/longjmp (used only for error recovery) and `execvp` stubbed out, plus paths to crt/libc. It is ~3x the source of chibicc (27k lines for the x86-64 subset), and it has no wasm backend, so its *output* is not sandboxed.
- **Cost of sandboxing the compiler** (chibicc compiling its own 27 sources, 9.4k lines): native 0.52 s, wazero compiled 1.49 s, LFI verified 2.34 s, wazero interpreter 30.7 s. Per-invocation startup: native 2.5 ms, lfi-run 2.2 ms (23.6 ms with verification of the 400 KB binary), wazero 93 ms (it JITs the 529 KB module on every run; the interpreter starts in 20 ms). All outputs identical.
- **LFI works in both directions on x86-64 today**: the compiler can be sandboxed by LFI (build with the LFI clang; verifier accepts it), and a tiny compiler's assembly output can be sandboxed by LFI (rewriter + verifier) as long as it avoids the two reserved registers, which chibicc does. The LFI verifier for x86-64 is 2.8k lines of C; the prebuilt LFI bundle ships only clang, so lfi-run/lfi-verify/lfi-rewrite were built from source (meson).
