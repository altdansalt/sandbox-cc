# sandbox-cc: a C compiler toolchain that is sandboxed by default and small enough to verify

**Question (from the brief):** can we build a compiler toolchain that is sandboxed by default and simple enough to verify (like LFI or WASM)? Which existing compiler is closest, and can that compiler itself be sandboxed through WASM (or LFI)?

**Approach:** survey the small C compilers that exist, pick the closest, compile it to wasm32-wasi and run it inside a WebAssembly runtime so that compiling untrusted source is safe. Then push further: make the sandboxed compiler produce sandboxed output (wasm, LFI-conforming x86-64), and check whether the sandboxed compiler can rebuild itself byte-for-byte.

## Where things stand

| Step | State |
|---|---|
| Environment: wasi-sdk 34 (clang 23, wasm32-wasip1 sysroot), wazero, tcc, prebuilt x86-64 LFI toolchain v0.12 | in progress |
| Survey of candidate compilers (chibicc, tcc, cproc+qbe, sandbox-stack/cc, lfi, clang-wasm) | in progress |
| Exp 1: upstream chibicc compiled to wasm32-wasi, run under wazero, output checked against native chibicc | not started |
| Exp 2: tinycc (compiler+assembler+linker in one module) compiled to wasm32-wasi | not started |
| Exp 3: sandbox-stack/cc (chibicc + wasm backend + own x86-64 assembler/ELF writer) in wasm: sandboxed compiler emitting sandboxed (wasm) or native output with no host tools | not started |
| Exp 4: LFI: run the compiler under LFI (lfi-run -v), and pass chibicc's assembly through the LFI rewriter/verifier | not started |
| Write-up on this page | continuous |

## What's happening right now
Setting up the environment and vendoring the candidates. The user's earlier project (github.com/altdansalt/sandbox-stack) turns out to contain a chibicc fork with a WebAssembly backend and its own assembler/ELF writer; that is the strongest candidate for "sandboxed by default".

## Findings so far
(none yet)
