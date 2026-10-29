#!/bin/bash
# Step-1 gates for the pure-Grid fork binary, inside an EXISTING 1-node allocation
# (alloc_gpu.sh). Never allocates. Phases:
#   a1     fork binary, all production switches on, the frozen 16^3 recipe of
#          smoke16_puregrid.sh; must be bit-identical to the reference run
#          runs/2026_10_14_gate16_a1 (binary _stock_m8).
#   mg     MG on rungs 0,1 + MG heatbaths 0,1 (16^3 needs --mpi 1.1.2.2 and
#          GRID_MG_BLOCK2=2.2.1.3): fork binary and _stock_m8 back to back, same
#          environment; expected bit-identical, accepted at forces 1e-6, dH 1e-5 rel.
#   tests  the four standalone helper tests (TEST RESULT: PASS each).
#   all    a1, mg, tests
# Usage:  SLURM_JOB_ID=<id> bash gate16_fork.sh {a1|mg|tests|all}
# Binaries from INSTALL_BIN (workflow/paths.sh). Output: run dirs under the
# workspace runs/, a summary appended to logs/gate16_<date>.txt.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
: "${SLURM_JOB_ID:?set SLURM_JOB_ID to an existing allocation}"
PHASE=${1:-all}

HB=$TREE/production/hasen
FORK_BIN=${FORK_BIN:-$INSTALL_BIN/gen_qcd_hasenbusch_tune_compact_schur_fork}
GRID_QCD=/global/cfs/cdirs/m4599/Users/vayyar/grid_qcd
M8_BIN=$GRID_QCD/grid-lqcd-workflow/5_studies/hasenbusch_tune/bin/gen_qcd_hasenbusch_tune_compact_schur_stock_m8
REF_A1=$GRID_QCD/runs/2026_10_14_gate16_a1/hmc.log
WORKFLOW=$GRID_QCD/grid-lqcd-workflow
COMPARE=$WORKFLOW/5_studies/hasenbusch_tune/data_extraction_scripts/compare_smoke_logs.py
CFG=$GRID_QCD/data/cl3_16_48_b6p1_m0p2450_a_cfg_11100.lime
SMOKE=$HB/perlmutter/smoke16_puregrid.sh
MGRUN=$HB/perlmutter/run_test_grid_mg.sh
export ENV_SCRIPT=$MACHINE_ENV
export RUNS_DIR=$WS/runs
mkdir -p "$RUNS_DIR" "$WS/logs"
DATE_TAG=$(date +%Y_%-m_%-d)
SUMMARY=$WS/logs/gate16_${DATE_TAG}.txt
say() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }
die() { say "ERROR: $*"; exit 1; }
[ -x "$FORK_BIN" ] || die "fork binary missing: $FORK_BIN"
[ -x "$M8_BIN" ] || die "reference binary missing: $M8_BIN"

# Bit-identity on the physics lines, then the tolerance comparator.
KEYRE='Total H before trajectory|Total H after trajectory|Plaquette: \[|Force average|Metropolis_test'
compare_logs() { # <label> <ref log> <new log> [comparator tolerances...]
  local label=$1 ref=$2 new=$3; shift 3
  [ -f "$new" ] || die "$label: log missing: $new"
  # Strip Grid's per-line timestamps ("Grid : Integrator : 35.639035 s : ") before diffing.
  if diff <(grep -a -E "$KEYRE" "$ref" | sed 's/^Grid : [A-Za-z]* : *[0-9.]* s : //') <(grep -a -E "$KEYRE" "$new" | sed 's/^Grid : [A-Za-z]* : *[0-9.]* s : //') > "$new.keydiff"; then
    say "$label: BIT-IDENTICAL on $(grep -a -c -E "$KEYRE" "$new") physics lines (H, dH, plaquettes, forces, Metropolis)"
  else
    say "$label: physics lines DIFFER, see $new.keydiff ($(wc -l < "$new.keydiff") diff lines)"
  fi
  ( cd "$WORKFLOW" && uv run python "$COMPARE" "$ref" "$new" "$@" ) 2>&1 | tee -a "$SUMMARY"
  say "$label: comparator exit=${PIPESTATUS[0]}"
}

run_smoke() { # <bin> <run name> [VAR=value ...]
  local bin=$1 run=$2; shift 2
  say "--- smoke $run ($(basename "$bin")) $(date '+%H:%M:%S') $*"
  env "$@" SLURM_JOB_ID="$SLURM_JOB_ID" BIN="$bin" RUN="$run" bash "$SMOKE" > "$RUNS_DIR/${DATE_TAG}_${run}.out" 2>&1
  say "    exit=$? log=$RUNS_DIR/${DATE_TAG}_${run}/hmc.log"
}

phase_a1() {
  run_smoke "$FORK_BIN" fork_gate16_a1
  compare_logs a1 "$REF_A1" "$RUNS_DIR/${DATE_TAG}_fork_gate16_a1/hmc.log" --tol-force 1e-9 --tol-dh 1e-6 --tol-plaq 1e-8
}

phase_mg() {
  local mgenv="HASEN_GRID_MG_RUNGS=0,1 HASEN_GRID_MG_HEATBATH_RUNGS=0,1 GRID_MG_BLOCK2=2.2.1.3 MPI_GEOM=1.1.2.2"
  run_smoke "$FORK_BIN" fork_gate16_mg $mgenv
  run_smoke "$M8_BIN" m8_gate16_mg $mgenv
  compare_logs mg "$RUNS_DIR/${DATE_TAG}_m8_gate16_mg/hmc.log" "$RUNS_DIR/${DATE_TAG}_fork_gate16_mg/hmc.log" --tol-force 1e-6 --tol-dh 1e-5 --tol-plaq 1e-8
}

phase_tests() {
  local t args
  for t in test_grid_mg_odd test_fused_clover_force test_fast_import test_cmunu_stencil; do
    case $t in
      test_grid_mg_odd) args="--cfg $CFG --cb both" ;;
      test_cmunu_stencil) args="" ;;
      *) args="--cfg $CFG" ;;
    esac
    say "--- test $t $(date '+%H:%M:%S')"
    SLURM_JOB_ID="$SLURM_JOB_ID" BIN="$INSTALL_BIN/$t" RUN="fork_$t" bash "$MGRUN" $args > "$RUNS_DIR/${DATE_TAG}_fork_$t.out" 2>&1
    say "    exit=$?  $(grep -a -m1 'TEST RESULT' "$RUNS_DIR/${DATE_TAG}_fork_$t/test.log" || echo 'no TEST RESULT line')"
  done
}

say "==== gate16_fork $PHASE  job=$SLURM_JOB_ID  tree $TREE HEAD=$(git -C "$TREE" rev-parse --short HEAD)  bin=$FORK_BIN  $(date '+%Y-%m-%d %H:%M:%S %Z')"
case $PHASE in
  a1) phase_a1 ;;
  mg) phase_mg ;;
  tests) phase_tests ;;
  all) phase_a1; phase_mg; phase_tests ;;
  *) die "usage: SLURM_JOB_ID=<id> bash $0 {a1|mg|tests|all}" ;;
esac
say "==== done $(date '+%H:%M:%S'); summary: $SUMMARY"
