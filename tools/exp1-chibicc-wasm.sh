#!/bin/bash
# Exp 1: run chibicc's test suite through chibicc.wasm (under wazero) and compare
# the emitted assembly against native chibicc; then assemble+link+run the
# wasm-produced assembly natively.
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=build/exp1; mkdir -p $OUT
WZ="wazero run -mount=$ROOT/chibicc:/:ro -mount=/usr/include:/usr/include:ro -mount=$ROOT/$OUT:/out"
pass=0; fail=0; same=0; differ=0
for src in chibicc/test/*.c; do
  n=$(basename $src .c)
  (cd chibicc && ./chibicc -Iinclude -Itest -S -o ../$OUT/$n.native.s test/$n.c 2>../$OUT/$n.native.err)
  $WZ build/chibicc/chibicc.wasm -Iinclude -Itest -S -o /out/$n.wasm.s test/$n.c 2>$OUT/$n.wasm.err
  if diff <(grep -v '^  .file' $OUT/$n.native.s) <(grep -v '^  .file' $OUT/$n.wasm.s) >$OUT/$n.diff; then same=$((same+1)); else differ=$((differ+1)); echo "DIFF $n ($(wc -l <$OUT/$n.diff) lines)"; fi
  if gcc -pthread -o $OUT/$n.exe $OUT/$n.wasm.s -xc chibicc/test/common 2>/dev/null && $OUT/$n.exe >$OUT/$n.run 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $n"; fi
done
# port regression tests (from the codex reviews): assembly must be identical, no run
psame=0; pdiff=0
for src in tests/port/*.c; do
  n=$(basename $src .c)
  ./chibicc/chibicc -Ichibicc/include -S -o $OUT/port-$n.native.s $src 2>$OUT/port-$n.native.err
  wazero run -mount=$ROOT/tests/port:/port:ro -mount=$ROOT/chibicc:/chibicc:ro -mount=$ROOT/$OUT:/out build/chibicc/chibicc.wasm -I/chibicc/include -S -o /out/port-$n.wasm.s /port/$n.c 2>$OUT/port-$n.wasm.err
  if diff <(grep -v '^  .file' $OUT/port-$n.native.s) <(grep -v '^  .file' $OUT/port-$n.wasm.s) >$OUT/port-$n.diff; then psame=$((psame+1)); else pdiff=$((pdiff+1)); echo "DIFF port/$n ($(wc -l <$OUT/port-$n.diff) lines)"; fi
done
echo "asm identical: $same, differ: $differ; run pass: $pass, fail: $fail; port tests identical: $psame, differ: $pdiff"
