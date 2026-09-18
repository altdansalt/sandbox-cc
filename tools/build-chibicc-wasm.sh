#!/bin/sh
# Build chibicc as a wasm32-wasip1 module (and natively, for comparison).
set -e
cd "$(dirname "$0")/.."
WCC=${WASI_SDK:-$HOME/opt/wasi-sdk-34.0-x86_64-linux}/bin/clang
mkdir -p build/chibicc
$WCC --target=wasm32-wasip1 -O2 -std=c11 -fno-common -Wall -Wno-switch -Wno-unused-but-set-variable \
  -D_WASI_EMULATED_PROCESS_CLOCKS -lwasi-emulated-process-clocks \
  -o build/chibicc/chibicc.wasm chibicc/*.c
(cd chibicc && make -s chibicc CC=gcc 2>/dev/null)
ls -l build/chibicc/chibicc.wasm chibicc/chibicc
