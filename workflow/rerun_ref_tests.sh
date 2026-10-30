#!/bin/bash
# Rebuild the collaborator's tests and the two generators from this repo, then re-run
# them, inside an EXISTING 1-node allocation; steps one at a time. Use after a change to
# the aux-field code or tests (the library itself is not rebuilt).
#   SLURM_JOB_ID=<id> TAG=<new tag> bash rerun_ref_tests.sh
# Order: the tests that failed on 2026-10-29 first (FIRST), then both 8^3x16 generator
# smokes (vs reference/gen/fork), then the remaining gate tests; the hanging
# Test_dtxqcd_rational_aux_force and the three 12-24 min tests are skipped (SKIP).
# Finally compare_ref_fork.sh <TAG> fork_tpl (the pre-fix run of the same tree layout).
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
: "${SLURM_JOB_ID:?set SLURM_JOB_ID to an existing allocation}"
: "${TAG:?set TAG, a new tag for the results}"
export JOBS=${JOBS:-32}
step() { echo "=== $* $(date '+%Y-%m-%d %H:%M:%S %Z')"; }
FIRST="Test_aux_kinetic Test_dtxqcd_logdet_aux_force Test_txqcd_clover_vs_grid Test_txqcd_hasenbusch_force Test_txqcd_freefield_qbarq_heavy Test_txqcd_freefield_qbarq_eo_heavy Test_txqcd_freefield_qbarq_light Test_txqcd_freefield_qbarq_eo_light"
SKIP=" Test_dtxqcd_rational_aux_force Test_txqcd_vev Test_dtxqcd_freefield_qbarq_light Test_dtxqcd_freefield_qbarq_eo_light "
ALL_TESTS=$(sed -n -E 's/^(DTX|TXQ)="(.*)"$/\2/p' "$HERE/run_ref_gates.sh" | tr '\n' ' ')
REST=$(for t in $ALL_TESTS; do [[ $SKIP == *" $t "* || " $FIRST " == *" $t "* ]] || printf '%s ' "$t"; done)

step "tree $TREE HEAD $(git -C "$TREE" rev-parse --short HEAD) $(git -C "$TREE" status --porcelain --untracked-files=no | wc -l) modified"
step "1. build his tests"
TESTS="$ALL_TESTS" bash "$HERE/run_ref_gates.sh" build
step "2. rebuild the generators"
srun --jobid="$SLURM_JOB_ID" -N 1 -n 1 --cpus-per-task=128 --export=ALL env MAKEFLAGS=-B bash "$HERE/build_gens_fork.sh" gen_dtxqcd_cfgs gen_txqcd_cfgs_2plus1
step "3. previously failing tests"
TESTS="$FIRST" bash "$HERE/run_ref_gates.sh" run
step "4. generator smokes"
bash "$HERE/run_ref_generators.sh" run
step "5. remaining gate tests"
TESTS="$REST" bash "$HERE/run_ref_gates.sh" run
step "6. compare $TAG vs fork_tpl"
bash "$HERE/compare_ref_fork.sh" "$TAG" fork_tpl
step "7. compare generator smokes $TAG vs fork"
bash "$HERE/compare_ref_fork.sh" "$TAG" fork | sed -n '/==== generator/,$p'
step "done"
