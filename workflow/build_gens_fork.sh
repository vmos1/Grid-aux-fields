#!/bin/bash
# Build the aux-field generators (and any other production/ program) of this fork
# out of source with production/Makefile: make runs in BUILD/production with
# SRCDIR pointing at the tree, against the Grid build BUILD; the checked binaries
# are copied to INSTALL_BIN. Sources the machine environment first (the Makefile
# picks the compiler from grid-config).
#   bash build_gens_fork.sh [targets...]      default: gen_dtxqcd_cfgs gen_txqcd_cfgs_2plus1
# Env: TREE, BUILD, INSTALL_BIN, JOBS (default 2). The Makefile does not track Grid
# headers: after a header change pass MAKEFLAGS=-B. Login-node use: one or two
# targets at a time, niced.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
source "$MACHINE_ENV"
set -e
JOBS=${JOBS:-2}
HDF5_PREFIX=${HDF5_PREFIX:-/opt/cray/pe/hdf5/1.14.3.9/gnu/12.3}
export LD_LIBRARY_PATH="$HDF5_PREFIX/lib:${LD_LIBRARY_PATH:-}"
TARGETS=${*:-gen_dtxqcd_cfgs gen_txqcd_cfgs_2plus1}
OUTDIR=$BUILD/production
mkdir -p "$OUTDIR" "$INSTALL_BIN"
echo "=== make -C $OUTDIR -f $TREE/production/Makefile SRCDIR=$TREE/production GRID_BUILD_DIR=$BUILD -j$JOBS $TARGETS  ($(date '+%H:%M:%S'))"
nice -n 10 make -C "$OUTDIR" -f "$TREE/production/Makefile" SRCDIR="$TREE/production" GRID_BUILD_DIR="$BUILD" -j"$JOBS" $TARGETS
for t in $TARGETS; do
  if ldd "$OUTDIR/$t" 2>/dev/null | grep -qi quda; then echo "ERROR: $t links QUDA"; exit 1; fi
  if ldd "$OUTDIR/$t" 2>/dev/null | grep -q 'not found'; then echo "ERROR: $t has unresolved libraries"; exit 1; fi
  cp -p "$OUTDIR/$t" "$INSTALL_BIN/"
  echo "OK: $t, installed to $INSTALL_BIN"
done
