#!/bin/bash
# Second round of the collaborator-test diagnosis (see diag_ref_failures.sh), inside an
# EXISTING 1-node allocation, one step at a time, 1 rank on 1 GPU.
#   SLURM_JOB_ID=<id> RUN=<run dir name> PHASE={buildgpu0|variants} bash diag_ref_failures2.sh
#   buildgpu0  the three crashing TXQCD tests with TXQCD_PRECOMPUTE_BUILD_GPU=0 (CPU build
#              of the per-site inverses instead of the GPU kernel the crashes are in).
#   variants   the diagnostic copies built by build_diag_variants.sh (DIAG_BIN): the
#              rational force test with solver tol 1e-10, the log-det test with larger FD
#              steps at 4.4.4.8, the aux-kinetic test with its reduction made serial.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
: "${SLURM_JOB_ID:?set SLURM_JOB_ID to an existing allocation}"
: "${RUN:?set RUN}"
: "${PHASE:?set PHASE}"
DIAG_BIN=${DIAG_BIN:-$WS/builds/diag}
HDF5_PREFIX=${HDF5_PREFIX:-/opt/cray/pe/hdf5/1.14.3.9/gnu/12.3}
source "$MACHINE_ENV"
export LD_LIBRARY_PATH="$HDF5_PREFIX/lib:${LD_LIBRARY_PATH:-}"
export MPICH_GPU_SUPPORT_ENABLED=1
OUT=$WS/runs/$RUN
mkdir -p "$OUT"
T=$BUILD/tests
SEL=$OUT/select_gpu
printf '%s\n' '#!/bin/bash' 'export CUDA_VISIBLE_DEVICES=0' 'exec "$@"' > "$SEL"
chmod +x "$SEL"
SRUN=(srun --jobid="$SLURM_JOB_ID" -N 1 -n 1 --ntasks-per-node=1 --gpus-per-task=1 --cpus-per-task=32 --cpu-bind=cores --gpu-bind=none --export=ALL --chdir="$OUT")
GARGS=(--mpi 1.1.1.1 --accelerator-threads 8 --shm 1024 --shm-mpi 0)

run() { # <step name> <cmd...>   (env set by the caller)
  local name=$1; shift
  echo "=== $name  $(date '+%H:%M:%S')"
  timeout -k 30s "${STEP_TIMEOUT:-10m}" "${SRUN[@]}" "$SEL" "$@" > "$OUT/$name.log" 2>&1
  echo "exit=$?" >> "$OUT/$name.log"
  grep -a -E '\[check\]|\[ok\]|\[FAIL\]|PASS|FAIL|PASSED|FAILED|did not converge|converged iter|Segmentation|^exit=' "$OUT/$name.log" \
    | sed 's/^Grid : [A-Za-z]* : *[0-9.]* s : //' | sort | uniq -c | sort -rn | head -20
}

case $PHASE in
  buildgpu0)
    export OMP_NUM_THREADS=8 TXQCD_PRECOMPUTE_BUILD_GPU=0
    run hasenbusch_force_buildgpu0 "$T/txqcd/Test_txqcd_hasenbusch_force" --grid 4.4.4.8 "${GARGS[@]}"
    run clover_vs_grid_buildgpu0   "$T/txqcd/Test_txqcd_clover_vs_grid"   --grid 4.4.4.8 "${GARGS[@]}"
    run freefield_heavy_buildgpu0  "$T/txqcd/Test_txqcd_freefield_qbarq_heavy" --grid 4.4.4.8 "${GARGS[@]}"
    ;;
  variants)
    export OMP_NUM_THREADS=8
    run aux_kinetic_serialsum_omp8 "$DIAG_BIN/Test_aux_kinetic_diag" --grid 4.4.4.4 "${GARGS[@]}"
    for h in 5e-8 5e-7 5e-6; do
      FD_H=$h run "logdet_4448_h$h" "$DIAG_BIN/Test_dtxqcd_logdet_aux_force_diag" --grid 4.4.4.8 "${GARGS[@]}"
    done
    SOLVER_TOL=1e-10 STEP_TIMEOUT=20m run rational_aux_force_tol1e-10 "$DIAG_BIN/Test_dtxqcd_rational_aux_force_diag" "${GARGS[@]}"
    ;;
esac
echo "=== done $(date '+%H:%M:%S')"
