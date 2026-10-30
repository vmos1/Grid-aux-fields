#!/bin/bash
# Diagnose the collaborator's failing gate tests inside an EXISTING 1-node allocation,
# one job step at a time, 1 rank on 1 GPU, binaries from BUILD/tests (workflow/paths.sh).
#   SLURM_JOB_ID=<id> RUN=<run dir name> bash diag_ref_failures.sh
#   1. Test_aux_kinetic with OMP_NUM_THREADS=1 and 8, twice each (data race in the
#      test's TensorInner thread_for?).
#   2. Test_dtxqcd_logdet_aux_force at --grid 4.4.4.4 (his size) and 4.4.4.8 (ours),
#      twice at 4.4.4.8, once at 4.4.4.4 with 1 thread (FD noise vs lattice size?).
#   3. Test_dtxqcd_rational_aux_force under gdb: alarm after HANG_S seconds, then a
#      backtrace of every thread (where does it hang?).
#   4. Test_txqcd_hasenbusch_force and Test_txqcd_clover_vs_grid under gdb: backtrace
#      at the segfault.
# Output: runs/<RUN>/<step>.log, a summary on stdout.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
: "${SLURM_JOB_ID:?set SLURM_JOB_ID to an existing allocation}"
: "${RUN:?set RUN}"
HANG_S=${HANG_S:-240}
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
GDB=(gdb -batch -ex "set pagination off" -ex "set print thread-events off")

run() { # <step name> <omp threads> <cmd...>
  local name=$1 omp=$2; shift 2
  echo "=== $name  OMP_NUM_THREADS=$omp  $(date '+%H:%M:%S')"
  OMP_NUM_THREADS=$omp timeout -k 30s "${STEP_TIMEOUT:-10m}" "${SRUN[@]}" "$SEL" "$@" > "$OUT/$name.log" 2>&1
  echo "exit=$?" >> "$OUT/$name.log"
  grep -a -E '\[check\]|\[ok\]|\[FAIL\]|PASSED|FAILED|^exit=' "$OUT/$name.log" | sed 's/^Grid : [A-Za-z]* : *[0-9.]* s : //' | grep -a -E 'all-5|gauge clover|PASSED|FAILED|^exit=|FAIL'
}

echo "tree $TREE HEAD $(git -C "$TREE" rev-parse --short HEAD), tests from $T"
for i in a b; do
  run "aux_kinetic_omp1_$i" 1 "$T/txqcd/Test_aux_kinetic" --grid 4.4.4.4 "${GARGS[@]}"
  run "aux_kinetic_omp8_$i" 8 "$T/txqcd/Test_aux_kinetic" --grid 4.4.4.4 "${GARGS[@]}"
done
run logdet_4444_omp8   8 "$T/dtxqcd/Test_dtxqcd_logdet_aux_force" --grid 4.4.4.4 "${GARGS[@]}"
run logdet_4444_omp1   1 "$T/dtxqcd/Test_dtxqcd_logdet_aux_force" --grid 4.4.4.4 "${GARGS[@]}"
run logdet_4448_omp8_a 8 "$T/dtxqcd/Test_dtxqcd_logdet_aux_force" --grid 4.4.4.8 "${GARGS[@]}"
run logdet_4448_omp8_b 8 "$T/dtxqcd/Test_dtxqcd_logdet_aux_force" --grid 4.4.4.8 "${GARGS[@]}"
# The hang: start, arm alarm(HANG_S) in the inferior, continue; SIGALRM stops it under gdb.
run rational_aux_force_gdb 8 "${GDB[@]}" -ex "handle SIGALRM stop print" -ex start \
  -ex "call (unsigned) alarm($HANG_S)" -ex continue -ex "info threads" -ex "thread apply all bt 40" -ex kill \
  --args "$T/dtxqcd/Test_dtxqcd_rational_aux_force" "${GARGS[@]}"
# The crashes: gdb stops at SIGSEGV before Grid's own handler runs.
run hasenbusch_force_gdb 8 "${GDB[@]}" -ex run -ex "bt 40" -ex "info threads" -ex kill \
  --args "$T/txqcd/Test_txqcd_hasenbusch_force" --grid 4.4.4.8 "${GARGS[@]}"
run clover_vs_grid_gdb 8 "${GDB[@]}" -ex run -ex "bt 40" -ex kill \
  --args "$T/txqcd/Test_txqcd_clover_vs_grid" --grid 4.4.4.8 "${GARGS[@]}"
echo "=== done $(date '+%H:%M:%S'); logs in $OUT"
