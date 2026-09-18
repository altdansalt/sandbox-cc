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
