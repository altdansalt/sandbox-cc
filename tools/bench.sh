#!/bin/bash
# Compile chibicc's own sources (9.4k lines) with chibicc: native, under wazero
# (compiler and interpreter), and under LFI. Reports wall time per configuration.
cd "$(dirname "$0")/.."
ROOT=$PWD; OUT=build/bench; mkdir -p $OUT
export PATH=$HOME/src/lfi-runtime/build/tools/lfi-run:$PATH
run() { # name, command prefix (compiler + flags), src prefix, out prefix
  local name=$1; shift
  local t0=$(date +%s.%N)
  for f in chibicc/*.c; do n=$(basename $f .c); "$@" -S -o $OUT/$n.$name.s $f 2>/dev/null || echo "  $name: $n failed"; done
  local t1=$(date +%s.%N)
  printf "%-28s %6.2f s\n" "$name" $(echo "$t1 - $t0" | bc)
}
run native-gcc-built ./chibicc/chibicc -Ichibicc/include
run lfi-verified lfi-run -v -- build/lfi/chibicc-lfi -Ichibicc/include
WZ="wazero run -mount=$ROOT:/ -mount=/usr/include:/usr/include:ro"
t0=$(date +%s.%N); for f in chibicc/*.c; do n=$(basename $f .c); $WZ build/chibicc/chibicc.wasm -Ichibicc/include -S -o $OUT/$n.wazero.s $f 2>/dev/null || echo "  wazero: $n failed"; done; t1=$(date +%s.%N)
printf "%-28s %6.2f s\n" "wazero (compiler)" $(echo "$t1 - $t0" | bc)
t0=$(date +%s.%N); for f in chibicc/*.c; do n=$(basename $f .c); $WZ -interpreter build/chibicc/chibicc.wasm -Ichibicc/include -S -o $OUT/$n.wazero-int.s $f 2>/dev/null || echo "  wazero-int: $n failed"; done; t1=$(date +%s.%N)
printf "%-28s %6.2f s\n" "wazero (interpreter)" $(echo "$t1 - $t0" | bc)
same=0; for f in chibicc/*.c; do n=$(basename $f .c); for v in lfi-verified wazero wazero-int; do diff -q <(grep -v '^  .file' $OUT/$n.native-gcc-built.s) <(grep -v '^  .file' $OUT/$n.$v.s) >/dev/null && same=$((same+1)) || echo "  DIFF $n $v"; done; done
echo "identical outputs: $same / $(( $(ls chibicc/*.c | wc -l) * 3 ))"
