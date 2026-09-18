#!/bin/sh
# Build tinycc (x86-64 target) as a wasm32-wasip1 module. Needs ~/src/tinycc configured
# natively (for config.h, tccdefs_.h, libtcc1.a and include/).
set -e
cd "$(dirname "$0")/.."
TCC=${TINYCC_SRC:-$HOME/src/tinycc}
WCC=${WASI_SDK:-$HOME/opt/wasi-sdk-34.0-x86_64-linux}/bin/clang
mkdir -p build/tcc/lib
cp tcc/sjlj.h build/tcc/
(cd $TCC && make -s tccdefs_.h libtcc1.a >/dev/null)
cp -r $TCC/include $TCC/libtcc1.a build/tcc/lib/
$WCC --target=wasm32-wasip1 -O2 -DONE_SOURCE=1 -DTCC_TARGET_X86_64 \
  -DCONFIG_TCCDIR='"/tcc"' \
  -DCONFIG_TCC_CRTPREFIX='"/usr/lib/x86_64-linux-gnu"' \
  -DCONFIG_TCC_LIBPATHS='"{B}:/usr/lib/x86_64-linux-gnu:/usr/lib:/lib/x86_64-linux-gnu"' \
  -DCONFIG_TCC_SYSINCLUDEPATHS='"{B}/include:/usr/local/include:/usr/include/x86_64-linux-gnu:/usr/include"' \
  -DCONFIG_TCC_SEMLOCK=0 -DCONFIG_TCC_BACKTRACE=0 -DCONFIG_TCC_BCHECK=0 -DCONFIG_TCC_STATIC \
  -D_SETJMP_H -D'execvp(a,b)=(-1)' \
  -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_MMAN \
  -include tcc/sjlj.h -lwasi-emulated-process-clocks -lwasi-emulated-signal -lwasi-emulated-mman \
  -Wno-everything -I$TCC $TCC/tcc.c -o build/tcc/tcc.wasm
(cd $TCC && git rev-parse HEAD) > tcc/UPSTREAM
ls -l build/tcc/tcc.wasm
