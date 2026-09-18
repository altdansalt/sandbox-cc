#!/bin/bash
# Compile chibicc's own sources (9.4k lines) with chibicc: native, under wazero
# (compiler and interpreter), and under LFI. Reports wall time per configuration.
cd "$(dirname "$0")/.."
ROOT=$PWD; OUT=build/bench; mkdir -p $OUT
export PATH=$HOME/src/lfi-runtime/build/tools/lfi-run:$PATH
run() { # name, command prefix (compiler + flags), src prefix, out prefix
  local name=$1; shift
  local t0=$(date +%s.%N)
  for f in chibicc/*.c; do n=$(basename $f .c); if [ "$name" = lfi-verified ]; then "$@" -S -o /build/bench/$n.$name.s /chibicc/$n.c 2>/dev/null || echo "  $name: $n failed"; else "$@" -S -o $OUT/$n.$name.s $f 2>/dev/null || echo "  $name: $n failed"; fi; done
  local t1=$(date +%s.%N)
  printf "%-28s %6.2f s\n" "$name" $(echo "$t1 - $t0" | bc)
}
run native-gcc-built ./chibicc/chibicc -Ichibicc/include
run lfi-verified lfi-run -v -r --dir=/usr/include=/usr/include --dir=/chibicc=$ROOT/chibicc --dir=/build=$ROOT/build --wd=/ -- build/lfi/chibicc-lfi -I/chibicc/include
WZ="wazero run -mount=$ROOT/chibicc:/chibicc:ro -mount=/usr/include:/usr/include:ro -mount=$ROOT/$OUT:/out"
t0=$(date +%s.%N); for f in chibicc/*.c; do n=$(basename $f .c); $WZ build/chibicc/chibicc.wasm -I/chibicc/include -S -o /out/$n.wazero.s /chibicc/$n.c 2>/dev/null || echo "  wazero: $n failed"; done; t1=$(date +%s.%N)
printf "%-28s %6.2f s\n" "wazero (compiler)" $(echo "$t1 - $t0" | bc)
t0=$(date +%s.%N); for f in chibicc/*.c; do n=$(basename $f .c); $WZ -interpreter build/chibicc/chibicc.wasm -I/chibicc/include -S -o /out/$n.wazero-int.s /chibicc/$n.c 2>/dev/null || echo "  wazero-int: $n failed"; done; t1=$(date +%s.%N)
printf "%-28s %6.2f s\n" "wazero (interpreter)" $(echo "$t1 - $t0" | bc)
same=0; for f in chibicc/*.c; do n=$(basename $f .c); for v in lfi-verified wazero wazero-int; do diff -q <(grep -v '^  .file' $OUT/$n.native-gcc-built.s) <(grep -v '^  .file' $OUT/$n.$v.s) >/dev/null && same=$((same+1)) || echo "  DIFF $n $v"; done; done
echo "identical outputs: $same / $(( $(ls chibicc/*.c | wc -l) * 3 ))"
