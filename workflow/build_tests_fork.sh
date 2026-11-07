#!/bin/bash
# Build the four standalone helper tests of production/hasen against this fork's
# Grid build (BUILD, pure Grid, no QUDA), out of source: binaries in
# BUILD/production/hasen/, then copied to INSTALL_BIN. Same flags and checks as
# build_driver_fork.sh; one niced nvcc compile per test (login-node safe).
#   test_grid_mg_odd         production/hasen/src/grid_mg/test_grid_mg_odd.cc
#   test_fused_clover_force  production/hasen/tests/test_fused_clover_force.cc
#   test_cmunu_stencil       production/hasen/tests/test_cmunu_stencil.cc
#   test_fast_import         production/hasen/tests/test_fast_import.cc
# Env overrides: TREE, BUILD, INSTALL_BIN, TESTS (space-separated subset), NICE.

HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
source "$MACHINE_ENV"
set -e

GRID_CONFIG=$BUILD/grid-config
HB=$TREE/production/hasen
OUTDIR=$BUILD/production/hasen
NICE=${NICE:-10}
TESTS=${TESTS:-"test_grid_mg_odd test_fused_clover_force test_cmunu_stencil test_fast_import"}

[ -x "$GRID_CONFIG" ] || { echo "ERROR: $GRID_CONFIG missing." >&2; exit 1; }
[ -f "$BUILD/Grid/libGrid.a" ] || { echo "ERROR: libGrid.a missing." >&2; exit 1; }

CXX=$("$GRID_CONFIG" --cxx)
CXXFLAGS="-I$HB -I$HB/src -I$TREE -I$BUILD/Grid $("$GRID_CONFIG" --cxxflags)"
LDFLAGS="$("$GRID_CONFIG" --ldflags) -L$BUILD/Grid"
LIBS=$("$GRID_CONFIG" --libs)
mkdir -p "$OUTDIR" "$INSTALL_BIN"

src_of() {
  case "$1" in
    test_grid_mg_odd) echo "$HB/src/grid_mg/test_grid_mg_odd.cc" ;;
    test_fused_clover_force|test_cmunu_stencil|test_fast_import) echo "$HB/tests/$1.cc" ;;
    *) echo "ERROR: unknown test $1" >&2; exit 2 ;;
  esac
}

for t in $TESTS; do
  SRC=$(src_of "$t")
  BIN=$OUTDIR/$t
  echo "=== $t  ($(date '+%H:%M:%S'))"
  nice -n "$NICE" $CXX $CXXFLAGS -MD -MF "$BIN.d" -o "$BIN" "$SRC" $LDFLAGS $LIBS
  LDD_OUT=$(ldd "$BIN" 2>&1)
  if echo "$LDD_OUT" | grep -qi quda; then echo "ERROR: QUDA linked in $t" >&2; exit 1; fi
  if echo "$LDD_OUT" | grep -q 'not found'; then echo "ERROR: unresolved libraries in $t" >&2; echo "$LDD_OUT" | grep 'not found' >&2; exit 1; fi
  cp -p "$BIN" "$INSTALL_BIN/"
  echo "OK: $BIN (no QUDA, 0 not found), installed to $INSTALL_BIN"
done
