#!/bin/bash
# Rebuild everything from this repo into builds/ and installs/, then gate it, inside an
# EXISTING 1-node allocation; job steps one at a time. Use after a fresh clone, a scratch
# purge, or a layout change. The tree must be prepared and configured first
# (build_grid_fork.sh prepare, configure: login node).
#   SLURM_JOB_ID=<id> TAG=<new tag> bash rebuild_and_gate.sh
# Steps: library (JOBS, default 32), install, programs (build_programs_fork.sh), his
# tests (run_ref_gates.sh build); then gate16_fork.sh all (our HMC, bit-identical to the
# 2026-10-14 reference), both generator smokes (vs reference/gen/fork), his tests except
# the hanging and the three 12-24 min ones (vs tag fork, ~36 min), the comparison.
# Whole run ~95 min [perlmutter, 2026-10-29 estimate].
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
: "${SLURM_JOB_ID:?set SLURM_JOB_ID to an existing allocation}"
: "${TAG:?set TAG, a new tag for the test and generator results}"
export JOBS=${JOBS:-32}
step() { echo "=== $* $(date '+%Y-%m-%d %H:%M:%S %Z')"; }
STEP1=(srun --jobid="$SLURM_JOB_ID" -N 1 -n 1 --cpus-per-task=128 --export=ALL)
SKIP=" Test_dtxqcd_rational_aux_force Test_txqcd_vev Test_dtxqcd_freefield_qbarq_light Test_dtxqcd_freefield_qbarq_eo_light "
ALL_TESTS=$(sed -n -E 's/^(DTX|TXQ)="(.*)"$/\2/p' "$HERE/run_ref_gates.sh" | tr '\n' ' ')
GATE_TESTS=$(for t in $ALL_TESTS; do [[ $SKIP == *" $t "* ]] || printf '%s ' "$t"; done)

step "tree $TREE HEAD $(git -C "$TREE" rev-parse --short HEAD), build $BUILD, install $INSTALL_PREFIX"
step "1. library (make -j$JOBS)"
"${STEP1[@]}" bash "$HERE/build_grid_fork.sh" build || { step "library build FAILED"; exit 1; }
step "2. install"
"${STEP1[@]}" bash "$HERE/build_grid_fork.sh" install || { step "install FAILED"; exit 1; }
step "3. programs"
"${STEP1[@]}" bash "$HERE/build_programs_fork.sh" || { step "program builds FAILED"; exit 1; }
step "4. his tests"
TESTS="$ALL_TESTS" bash "$HERE/run_ref_gates.sh" build
step "5. gate16 all"
bash "$HERE/gate16_fork.sh" all
step "6. generator smokes"
bash "$HERE/run_ref_generators.sh" run
step "7. his tests (skipping:$SKIP)"
TESTS="$GATE_TESTS" bash "$HERE/run_ref_gates.sh" run
step "8. compare $TAG vs fork"
bash "$HERE/compare_ref_fork.sh" "$TAG" fork
step "done"
