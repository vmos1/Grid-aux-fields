#!/bin/bash
# Compile the diagnostic copies of the collaborator's tests in builds/diag/src/*_diag.cc
# against this fork's Grid build, in parallel (run inside one job step:
# srun --jobid=<id> -N 1 -n 1 --cpus-per-task=128 bash build_diag_variants.sh).
# The copies live outside the repo; they are throw-away instruments, not fixes.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
source "$MACHINE_ENV"
DIAG=${DIAG:-$WS/builds/diag}
GRID_CONFIG=$BUILD/grid-config
CXX=$("$GRID_CONFIG" --cxx)
CXXFLAGS="-I$TREE -I$BUILD/Grid $("$GRID_CONFIG" --cxxflags)"
LDFLAGS="$("$GRID_CONFIG" --ldflags) -L$BUILD/Grid"
LIBS=$("$GRID_CONFIG" --libs)
pids=()
for src in "$DIAG"/src/*_diag.cc; do
  bin=$DIAG/$(basename "$src" .cc)
  echo "=== $(basename "$bin")  $(date '+%H:%M:%S')"
  $CXX $CXXFLAGS -o "$bin" "$src" $LDFLAGS $LIBS > "$bin.build.log" 2>&1 &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=$((fail + 1)); done
for src in "$DIAG"/src/*_diag.cc; do
  bin=$DIAG/$(basename "$src" .cc)
  if [ -x "$bin" ]; then echo "OK: $bin"; else echo "FAILED: $bin (see $bin.build.log)"; fi
done
exit "$fail"
