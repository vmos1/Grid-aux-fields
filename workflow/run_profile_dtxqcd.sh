#!/bin/bash
# Profile run of the fork's gen_dtxqcd_cfgs (campaign aux-optim) inside an EXISTING
# 1-node allocation: 4 ranks x 1 GPU, the collaborator's launcher defaults
# (production/run_dtxqcd_gencfgs.sh at v2-txqcd), started from the thermalized Chroma
# 16^3x48 configuration our 16^3 gate uses, a few trajectories, the first force-accepted.
#   SLURM_JOB_ID=<id> RUN=<name> bash run_profile_dtxqcd.sh [VAR=value ...]
# Extra VAR=value arguments are appended to (and override) the generator environment, so
# the same script re-profiles after each env-gated optimisation.
# Env: TREE (source tree, for the provenance SHA), BIN (default INSTALL_BIN/gen_dtxqcd_cfgs;
#      both from workflow/paths.sh), LATT (16.16.16.48), TRAJ (3, a target total),
#      NO_METROP (1), IMPORT_CFG (Chroma cfg 11100), DEVICE_MEM (38000, the
#      launcher's), TIMEOUT (100m).
# Output: runs/<RUN>/run.log in the workspace; runs/<RUN> is the generator's cwd, so its
# cfgs/ lands there (N_SKIP=10: no checkpoint within 3 trajectories). The log ends with
# exit=<rc>, which workflow/wait_for_exit.sh waits for. Analyse with
# workflow/profile_dtxqcd_log.py.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
: "${SLURM_JOB_ID:?set SLURM_JOB_ID to an existing allocation}"
: "${RUN:?set RUN to the run directory name under runs/}"
BIN=${BIN:-$INSTALL_BIN/gen_dtxqcd_cfgs}
LATT=${LATT:-16.16.16.48}
TRAJ=${TRAJ:-3}
NO_METROP=${NO_METROP:-1}
IMPORT_CFG=${IMPORT_CFG:-/global/cfs/cdirs/m4599/Users/vayyar/grid_qcd/data/cl3_16_48_b6p1_m0p2450_a_cfg_11100.lime}
DEVICE_MEM=${DEVICE_MEM:-38000}
TIMEOUT=${TIMEOUT:-100m}
DIR=$WS/runs/$RUN
LOG=$DIR/run.log

if [ -e "$LOG" ]; then echo "ERROR: $LOG exists; pick a new RUN" >&2; exit 2; fi
mkdir -p "$DIR"
source "$MACHINE_ENV"

sel=$DIR/select_gpu
printf '%s\n' '#!/bin/bash' 'export CUDA_VISIBLE_DEVICES=$SLURM_LOCALID' 'exec numactl -m $SLURM_LOCALID -N $SLURM_LOCALID "$@"' > "$sel"
chmod +x "$sel"
SRUN=(srun --jobid="$SLURM_JOB_ID" -N 1 -n 4 --ntasks-per-node=4 --gpus-per-task=1 --cpus-per-task=32 --cpu-bind=cores --gpu-bind=none --export=ALL --chdir="$DIR")

# run_dtxqcd_gencfgs.sh defaults (QUDA knobs gone in the fork), plus our validated
# optimisations (aux-optim: DTXQCD_LAZY_SMEAR=1, bit-identical, 2026-10-30), then the
# caller's overrides (pass DTXQCD_LAZY_SMEAR=0 for the eager path).
GEN_ENV=(LATT="$LATT" DTXQCD_LAZY_SMEAR=1 LAMBDA_DTXQCD=10.0 MASS_LIGHT_DTXQCD=-0.245 CSW=1.24930970916466
  STOUT_NSMEAR=1 STOUT_RHO=0.125 ADD_STRANGE=0 AUX_INIT_AUTO=1 RAT_AUTO_HI=1
  DTXQCD_PRECOMPUTE_GPU=1 DTXQCD_LOGDET_S_GPU=1 DTXQCD_LOGDET_GPU=1
  DTXQCD_MOOEEINV_CUBLAS=1 DTXQCD_MOOEE_CUBLAS=1 DTXQCD_MOOEE_FWDCACHE=1
  DTXQCD_MP_CG=1 DTXQCD_MP_CG_CLEANUP=0 DTXQCD_RATFORCE_GPU=1
  INTEGRATOR=MinimumNorm2 MDSTEPS=10 TRAJL=0.353553390593274 GAUGE_MULT=8 AUX_MULT=1
  TRAJ="$TRAJ" NO_METROP="$NO_METROP" N_SKIP=10 CG_TOL=1e-8 DIAG_TRMINV_INTERVAL=0
  DTXQCD_SUFFIX=_profile IMPORT_CFG="$IMPORT_CFG" "$@")
GRID_ARGS=(--grid "$LATT" --mpi 1.1.1.4 --accelerator-threads 8 --shm 1024 --shm-mpi 0 --device-mem "$DEVICE_MEM")

dirty=no
[ -n "$(git -C "$TREE" status --porcelain --untracked-files=no)" ] && dirty=yes
{
  echo "ENV PROFILE_DTXQCD RUN=$RUN JOBID=$SLURM_JOB_ID BIN=$BIN BIN_SHA256=$(sha256sum "$BIN" | cut -c1-64) GRID_SHA=$(git -C "$TREE" rev-parse HEAD) GRID_DIRTY=$dirty OMP_NUM_THREADS=8 MPICH_GPU_SUPPORT_ENABLED=1"
  echo "ENV GEN ${GEN_ENV[*]}"
  echo "ENV GRID_ARGS ${GRID_ARGS[*]}"
  echo "ENV LDD $(ldd "$BIN" | grep -c 'not found') unresolved, $(ldd "$BIN" | grep -ci quda) quda"
  echo "ENV START $(date '+%Y-%m-%d %H:%M:%S %Z')"
} > "$LOG"

if ! "${SRUN[@]}" "$sel" true >> "$LOG" 2>&1; then
  echo "exit=NUMA_GATE_FAILED" >> "$LOG"
  exit 1
fi

timeout -k 60s "$TIMEOUT" env "${GEN_ENV[@]}" OMP_NUM_THREADS=8 MPICH_GPU_SUPPORT_ENABLED=1 \
  "${SRUN[@]}" "$sel" "$BIN" "${GRID_ARGS[@]}" >> "$LOG" 2>&1
rc=$?
echo "ENV END $(date '+%Y-%m-%d %H:%M:%S %Z')" >> "$LOG"
printf 'exit=%s\n' "$rc" >> "$LOG"
