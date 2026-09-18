#!/bin/bash
# Exp 3: sandbox-stack's cc (chibicc + wasm backend + own x86-64 assembler/ELF writer)
# running as a wasm module. For every test source, compile with native cc and with
# cc.wasm under wazero; the outputs (wasm modules / static ELF executables) must be
# byte-identical, and they must run: wasm guests through build/control (env.read/write/exit
# host), ELF executables natively.
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD; OUT=build/exp3; mkdir -p $OUT/tu
WZ="wazero run -cachedir build/wzcache -mount=$ROOT:/:ro -mount=$ROOT/$OUT:/$OUT"
same=0; differ=0; pass=0; fail=0; rejected=0
# --- wasm backend: tests/cc ---
for src in tests/cc/*.c; do
  n=$(basename $src .c); tu=$OUT/tu/$n.c
  printf '#include "%s"\n#include "libc/libc.c"\n' $src > $tu
  if grep -qx "$n" tests/cc/must-fail; then
    if $WZ build/cc/cc.wasm -I. -Ilibc -Ilibc/include -o /$OUT/$n.wasm.wasm /$tu >/dev/null 2>&1; then echo "FAIL cc/$n compiled (expected rejection)"; fail=$((fail+1)); else rejected=$((rejected+1)); fi
    continue
  fi
  ./build/cc/cc-native -I. -Ilibc -Ilibc/include -o $OUT/$n.native.wasm $tu 2>$OUT/$n.native.err
  $WZ build/cc/cc.wasm -I. -Ilibc -Ilibc/include -o /$OUT/$n.wasm.wasm /$tu 2>$OUT/$n.wasm.err
  if cmp -s $OUT/$n.native.wasm $OUT/$n.wasm.wasm; then same=$((same+1)); else differ=$((differ+1)); echo "DIFF cc/$n"; fi
  if ./build/control $OUT/$n.wasm.wasm </dev/null >$OUT/$n.run 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL cc/$n (exit $?)"; fi
done
# --- x86-64 backend + assembler + ELF writer: tests/x86c ---
for src in tests/x86c/*.c; do
  n=$(basename $src .c)
  if grep -qx "$n" tests/x86c/must-fail; then
    if $WZ build/cc/cc.wasm -mx86 -Itests/x86c -Ilibc/include -o /$OUT/$n.wasm.elf /$src >/dev/null 2>&1; then echo "FAIL x86c/$n compiled (expected rejection)"; fail=$((fail+1)); else rejected=$((rejected+1)); fi
    continue
  fi
  ./build/cc/cc-native -mx86 -Itests/x86c -Ilibc/include -o $OUT/$n.native.elf $src 2>$OUT/$n.native.err
  $WZ build/cc/cc.wasm -mx86 -Itests/x86c -Ilibc/include -o /$OUT/$n.wasm.elf /$src 2>$OUT/$n.wasm.err
  if cmp -s $OUT/$n.native.elf $OUT/$n.wasm.elf; then same=$((same+1)); else differ=$((differ+1)); echo "DIFF x86c/$n"; fi
  chmod +x $OUT/$n.wasm.elf 2>/dev/null
  if $OUT/$n.wasm.elf >$OUT/$n.run 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL x86c/$n (exit $?)"; fi
done
echo "outputs identical: $same, differ: $differ; run pass: $pass, fail: $fail; correctly rejected: $rejected"
