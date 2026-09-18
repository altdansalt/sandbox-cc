#!/bin/sh
# Build sandbox-stack's cc (chibicc fork: wasm32 backend + x86-64 backend + assembler + ELF writer)
# natively (clang) and as a wasm32-wasip1 module, plus the Go test host for env.* guests.
set -e
cd "$(dirname "$0")/.."
WCC=${WASI_SDK:-$HOME/opt/wasi-sdk-34.0-x86_64-linux}/bin/clang
mkdir -p build/cc
clang -O2 -Wno-unused-function -Wno-unused-variable -Wno-switch -o build/cc/cc-native cc/*.c
$WCC --target=wasm32-wasip1 -O2 -Wno-unused-function -Wno-unused-variable -Wno-switch -Wno-unused-but-set-variable \
  -D_WASI_EMULATED_PROCESS_CLOCKS -lwasi-emulated-process-clocks -lc-printscan-long-double \
  -o build/cc/cc.wasm cc/*.c
(cd control && go build -o ../build/control .)
ls -l build/cc/cc-native build/cc/cc.wasm build/control
