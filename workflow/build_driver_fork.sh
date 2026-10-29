#!/bin/bash
# Build the pure-Grid HMC driver (production/hasen/) against this fork's Grid build
# (BUILD), out of source: the binary goes to BUILD/production/hasen/ and, after the
# checks, is copied to INSTALL_BIN (durable; what jobs run). Paths: workflow/paths.sh.
# Adapted from grid-lqcd-workflow/.../perlmutter/build_driver_stock.sh.
# The six action headers and the four helpers live INSIDE the tree
# (Grid/qcd/action/pseudofermion/{,hasen/}), so there is no shadowing include
# directory and no refusal check; -I production/hasen resolves "params.h",
# -I production/hasen/src resolves "grid_mg/...".
#
# Env overrides: TREE, BUILD, INSTALL_BIN, SRC, BIN.
# No -DGRID_HAVE_QUDA: the driver's #ifdef GRID_HAVE_QUDA blocks drop out.

HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
source "$MACHINE_ENV"
set -e

GRID_CONFIG=$BUILD/grid-config
HB=$TREE/production/hasen

[ -x "$GRID_CONFIG" ] || { echo "ERROR: $GRID_CONFIG missing: configure the fork first." >&2; exit 1; }
[ -f "$BUILD/Grid/libGrid.a" ] || { echo "ERROR: $BUILD/Grid/libGrid.a missing: build the library first." >&2; exit 1; }
[ -f "$HB/params.h" ] || { echo "ERROR: $HB/params.h missing." >&2; exit 1; }

# Patch 04 must be in the tree (the Grid-MG route coarsens on the Odd checkerboard).
GCM=$TREE/Grid/algorithms/multigrid/GeneralCoarsenedMatrix.h
N04=$(grep -c 'Honour the checkerboard of the subspace' "$GCM" || true)
[ "$N04" -ge 2 ] || { echo "ERROR: $GCM lacks patch 04 ($N04 of 2 hunks)." >&2; exit 1; }
echo "OK: patch 04 present ($N04 hunks)."

SRC=${SRC:-$HB/gen_qcd_hasenbusch_tune_compact_schur.cc}
BIN=${BIN:-$BUILD/production/hasen/gen_qcd_hasenbusch_tune_compact_schur_fork}
mkdir -p "$(dirname "$BIN")"

CXX=$("$GRID_CONFIG" --cxx)
# Source tree and build dir BEFORE grid-config's flags (its -I<prefix>/include could
# otherwise shadow the tree after a `make install`).
CXXFLAGS="-I$HB -I$HB/src -I$TREE -I$BUILD/Grid $("$GRID_CONFIG" --cxxflags)"
LDFLAGS="$("$GRID_CONFIG" --ldflags) -L$BUILD/Grid"
LIBS=$("$GRID_CONFIG" --libs)

SHA=$(git -C "$TREE" rev-parse --short HEAD)
DIRTY=$(git -C "$TREE" status --porcelain --untracked-files=no | wc -l)
echo "Compiler: $CXX"
echo "Tree:     $TREE (HEAD $SHA, $DIRTY modified tracked files)"
echo "Source:   $SRC"
echo "Binary:   $BIN"

DEPS=$BIN.d
echo "Building PURE-GRID driver (no -DGRID_HAVE_QUDA) ..."
$CXX $CXXFLAGS -MD -MF "$DEPS" -o "$BIN" "$SRC" $LDFLAGS $LIBS
echo "Done: $BIN"
printf 'built %s from tree %s HEAD %s (%s modified tracked files) by %s on %s\n' \
  "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$TREE" "$SHA" "$DIRTY" "$USER" "$(hostname)" > "$BIN.provenance"

# The dependency file proves which copies of two key headers were compiled.
check_used() {
  local pattern=$1 expect=$2 used
  used=$(tr ' \\' '\n\n' < "$DEPS" | grep "$pattern" | head -1)
  if [ -z "$used" ] || [ "$(readlink -f "$used")" != "$(readlink -f "$expect")" ]; then
    echo "ERROR: compiled $pattern = '${used:-none}', expected $expect" >&2
    exit 1
  fi
  echo "OK: compiled $used"
}
check_used 'multigrid/GeneralCoarsenedMatrix.h$' "$GCM"
check_used 'pseudofermion/TwoFlavourSchurCloverAction.h$' "$TREE/Grid/qcd/action/pseudofermion/TwoFlavourSchurCloverAction.h"

echo "--- ldd: no QUDA, zero 'not found' ---"
LDD_OUT=$(ldd "$BIN" 2>&1) || { echo "ERROR: ldd failed:" >&2; echo "$LDD_OUT" >&2; exit 1; }
if echo "$LDD_OUT" | grep -qi quda; then echo "ERROR: QUDA linked" >&2; exit 1; fi
echo "OK: no QUDA linked."
NOTFOUND=$(echo "$LDD_OUT" | grep -c 'not found' || true)
if [ "$NOTFOUND" -ne 0 ]; then
  echo "ERROR: $NOTFOUND unresolved shared libraries:" >&2
  echo "$LDD_OUT" | grep 'not found' >&2
  exit 1
fi
echo "OK: ldd reports 0 'not found'."

mkdir -p "$INSTALL_BIN"
cp -p "$BIN" "$BIN.provenance" "$INSTALL_BIN/"
echo "Installed: $INSTALL_BIN/$(basename "$BIN")"
