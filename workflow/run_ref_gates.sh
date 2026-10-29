#!/bin/bash
# Build and run the collaborator's 42 gate tests (reference/GATE_TESTS.md) inside an
# EXISTING allocation, one rank on one GPU each, and record every log under
# reference/tests/<tag>/ of the workspace. Works on any Grid tree that carries
# tests/dtxqcd and tests/txqcd: by default this fork (TREE, BUILD from
# workflow/paths.sh); the reference clone with TREE=$REF_TREE BUILD=$REF_TREE/build-gpu.
#   SLURM_JOB_ID=<id> TAG=<tag> bash run_ref_gates.sh build     # make the 42 programs (-j16)
#   SLURM_JOB_ID=<id> TAG=<tag> bash run_ref_gates.sh run       # run them, write summary
#   SLURM_JOB_ID=<id> TAG=<tag> bash run_ref_gates.sh all
# Env: TAG (required: a new tag per run, never reuse), TREE, BUILD, GRID_LATT
# (default 4.4.4.8, their laptop scout size), TESTS (subset), JOBS (default 16).
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
: "${SLURM_JOB_ID:?set SLURM_JOB_ID to an existing allocation}"
: "${TAG:?set TAG (e.g. ref for the reference clone, fork_<what> for this tree)}"
PHASE=${1:-all}
GRID_LATT=${GRID_LATT:-4.4.4.8}
JOBS=${JOBS:-16}
HDF5_PREFIX=${HDF5_PREFIX:-/opt/cray/pe/hdf5/1.14.3.9/gnu/12.3}
OUT=$WS/reference/tests/$TAG
mkdir -p "$OUT"
SUMMARY=$OUT/SUMMARY.txt
say() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }

source "$MACHINE_ENV"
export LD_LIBRARY_PATH="$HDF5_PREFIX/lib:${LD_LIBRARY_PATH:-}"

DTX="Test_dtxqcd_aux_gaussian Test_dtxqcd_aux_io Test_dtxqcd_clover_herm Test_dtxqcd_delta_diag_lower Test_dtxqcd_delta_herm Test_dtxqcd_gamma5_herm_full Test_dtxqcd_logdet_aux_force Test_dtxqcd_meooe_free_field Test_dtxqcd_mooee_clover_consistency Test_dtxqcd_mooee_consistency Test_dtxqcd_mooee_herm Test_dtxqcd_mooeeinv_n Test_dtxqcd_pfaff_logdet_blockdiag Test_dtxqcd_pfaffian_antisymmetry Test_dtxqcd_rational_aux_force Test_dtxqcd_rational_full_force Test_dtxqcd_site_lu Test_dtxqcd_trminv_zeroaux Test_dtxqcd_wilson_clover_fermion_eo Test_dtxqcd_zero_aux_doubled_qcd Test_dtxqcd_freefield_qbarq_heavy Test_dtxqcd_freefield_qbarq_light Test_dtxqcd_freefield_qbarq_eo_heavy Test_dtxqcd_freefield_qbarq_eo_light"
TXQ="Test_aux_gaussian Test_aux_kinetic Test_qcd_eo_clover Test_qcd_logdet_clover_force Test_txqcd_clover_vs_grid Test_txqcd_delta_color Test_txqcd_clover_mooee Test_txqcd_hasenbusch_force Test_txqcd_logdet_clover_eo_force Test_txqcd_logdet_eo_force Test_txqcd_pf_force Test_txqcd_rational_eo_force Test_txqcd_rational_force Test_txqcd_vev Test_txqcd_freefield_qbarq_heavy Test_txqcd_freefield_qbarq_light Test_txqcd_freefield_qbarq_eo_heavy Test_txqcd_freefield_qbarq_eo_light"

dir_of() { case "$1" in Test_dtxqcd_*) echo dtxqcd ;; *) echo txqcd ;; esac; }

build_tests() {
  local d list
  for d in dtxqcd txqcd; do
    if [ "$d" = dtxqcd ]; then list=$DTX; else list=$TXQ; fi
    [ -z "${TESTS:-}" ] || list=$(for t in $TESTS; do [ "$(dir_of "$t")" = "$d" ] && echo "$t"; done)
    [ -n "$list" ] || continue
    say "--- make -C $BUILD/tests/$d -j$JOBS ($(date '+%H:%M:%S')): $list"
    srun --jobid="$SLURM_JOB_ID" -N 1 -n 1 --cpus-per-task=128 --export=ALL \
      make -C "$BUILD/tests/$d" -j"$JOBS" $list > "$OUT/make_$d.log" 2>&1
    say "    make $d exit=$?  ($(grep -c -i ' error' "$OUT/make_$d.log") error lines)"
  done
}

run_tests() {
  local t d bin log rc verdict
  SELECT_GPU=$OUT/select_gpu
  # One rank, one GPU: no numactl pinning (a single task is placed on an arbitrary NUMA
  # domain by Slurm, so "numactl -N 0" fails; the binding only matters for 4-rank runs).
  printf '%s\n' '#!/bin/bash' 'export CUDA_VISIBLE_DEVICES=0' 'exec "$@"' > "$SELECT_GPU"
  chmod +x "$SELECT_GPU"
  SRUN=(srun --jobid="$SLURM_JOB_ID" -N 1 -n 1 --ntasks-per-node=1 --gpus-per-task=1 --cpus-per-task=32 --cpu-bind=cores --gpu-bind=none --export=ALL --chdir="$OUT")
  "${SRUN[@]}" "$SELECT_GPU" true || { say "ERROR: launch gate failed"; exit 1; }
  export OMP_NUM_THREADS=8 MPICH_GPU_SUPPORT_ENABLED=1
  say "==== run tag=$TAG tree=$TREE HEAD=$(git -C "$TREE" rev-parse --short HEAD) latt=$GRID_LATT $(date '+%Y-%m-%d %H:%M:%S %Z')"
  for t in ${TESTS:-$DTX $TXQ}; do
    d=$(dir_of "$t"); bin=$BUILD/tests/$d/$t; log=$OUT/$t.log
    if [ ! -x "$bin" ]; then say "$t: NOT BUILT"; continue; fi
    timeout -k 30s "${TEST_TIMEOUT:-30m}" "${SRUN[@]}" "$SELECT_GPU" "$bin" --grid "$GRID_LATT" --mpi 1.1.1.1 --accelerator-threads 8 --shm 1024 --shm-mpi 0 > "$log" 2>&1
    rc=$?
    verdict=$(grep -a -o -E 'ALL CHECKS PASSED|SOME CHECKS FAILED|TEST RESULT: [A-Z]+|RESULT: [A-Z]+|\bPASS\b|\bFAIL(ED)?\b' "$log" | sort | uniq -c | tr '\n' ' ')
    say "$(printf '%-44s exit=%-3s %s' "$t" "$rc" "${verdict:-no verdict line}")"
  done
  say "==== done $(date '+%H:%M:%S'); logs in $OUT"
}

case $PHASE in
  build) build_tests ;;
  run) run_tests ;;
  all) build_tests; run_tests ;;
  *) echo "usage: SLURM_JOB_ID=<id> [TAG=ref] bash $0 {build|run|all}" >&2; exit 2 ;;
esac
