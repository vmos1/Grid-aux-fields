#!/bin/bash
#SBATCH --job-name=gen_dtxqcd
#SBATCH --nodes=1
#SBATCH --constraint=gpu&hbm80g
#SBATCH --gpus-per-node=4
#SBATCH --qos=regular
#SBATCH --time=01:00:00
#SBATCH --output=gen_dtxqcd_%j.out
#
# gen_dtxqcd_cfgs (DTXQCD aux-field HMC, pure Grid) on one Perlmutter GPU node, with every
# setting the v3-txqcd timings were measured with. Self-contained: every environment
# variable, Grid flag and srun option of the run is in this file. Instructions: README.md
# in this directory.
#
# Submit from the repository root (the directory holding machines/ and production/):
#   IMPORT_CFG=/path/to/cfg.lime sbatch --account=<project>_g production/puregrid/gen_dtxqcd_perlmutter.sbatch
#
# Every variable below is a default: set it in the environment before sbatch to change it
# (sbatch exports the submitting environment). The ones you normally set:
#   IMPORT_CFG  starting gauge configuration, Chroma .lime or NERSC; ignored once RUN_DIR
#               holds a checkpoint; unset and no checkpoint = weak-field start
#   RUN_DIR     the generator's working directory (cfgs/ and checkpoints go here);
#               default runs/gen_dtxqcd_<jobid> under the submit directory
#   TRAJ        TARGET total of trajectories (default 1). Resubmitting with the same
#               RUN_DIR and a larger TRAJ resumes from the latest checkpoint (every N_SKIP)
#   NO_METROP   1 = accept the first trajectory without the Metropolis test (default 1, as
#               in the check run); 0 for production
#   BIN         the binary (default ../installs/grid-aux-fields-gpu/bin/gen_dtxqcd_cfgs,
#               where workflow/build_gens_fork.sh installs it)
# Raise --time for more trajectories: ~195 s each at 16^3x48 plus ~1 min of start-up.
set -u
REPO=${REPO:-$SLURM_SUBMIT_DIR}
# Modules and runtime library paths (cray-mpich 9.0.1, CUDA 12.9, MPFR, HDF5).
source "$REPO/machines/perlmutter.sh"
BIN=${BIN:-$REPO/../installs/grid-aux-fields-gpu/bin/gen_dtxqcd_cfgs}
RUN_DIR=${RUN_DIR:-$SLURM_SUBMIT_DIR/runs/gen_dtxqcd_$SLURM_JOB_ID}
mkdir -p "$RUN_DIR"

# ---- Physics and algorithm: the defaults of dtxqcd-v2's production/run_dtxqcd_gencfgs.sh
#      (the chroma-matched 16^3x48 b6.1 point), its QUDA switches removed.
export LATT=${LATT:-16.16.16.48}
export LAMBDA_DTXQCD=${LAMBDA_DTXQCD:-10.0}
export MASS_LIGHT_DTXQCD=${MASS_LIGHT_DTXQCD:--0.245}
export CSW=${CSW:-1.24930970916466}
export STOUT_NSMEAR=${STOUT_NSMEAR:-1}
export STOUT_RHO=${STOUT_RHO:-0.125}
export ADD_STRANGE=${ADD_STRANGE:-0}
export AUX_INIT_AUTO=${AUX_INIT_AUTO:-1}
export RAT_AUTO_HI=${RAT_AUTO_HI:-1}
export INTEGRATOR=${INTEGRATOR:-MinimumNorm2}
export MDSTEPS=${MDSTEPS:-10}
export TRAJL=${TRAJL:-0.353553390593274}
export GAUGE_MULT=${GAUGE_MULT:-8}
export AUX_MULT=${AUX_MULT:-1}
export CG_TOL=${CG_TOL:-1e-8}
export TRAJ=${TRAJ:-1}
export NO_METROP=${NO_METROP:-1}
export N_SKIP=${N_SKIP:-10}
export DIAG_TRMINV_INTERVAL=${DIAG_TRMINV_INTERVAL:-0}
export DTXQCD_SUFFIX=${DTXQCD_SUFFIX:-_puregrid}
export IMPORT_CFG=${IMPORT_CFG:-}
# Its GPU-path switches (same defaults as its launcher).
export DTXQCD_PRECOMPUTE_GPU=${DTXQCD_PRECOMPUTE_GPU:-1}
export DTXQCD_LOGDET_S_GPU=${DTXQCD_LOGDET_S_GPU:-1}
export DTXQCD_LOGDET_GPU=${DTXQCD_LOGDET_GPU:-1}
export DTXQCD_MOOEEINV_CUBLAS=${DTXQCD_MOOEEINV_CUBLAS:-1}
export DTXQCD_MOOEE_CUBLAS=${DTXQCD_MOOEE_CUBLAS:-1}
export DTXQCD_MOOEE_FWDCACHE=${DTXQCD_MOOEE_FWDCACHE:-1}
export DTXQCD_MP_CG=${DTXQCD_MP_CG:-1}
export DTXQCD_MP_CG_CLEANUP=${DTXQCD_MP_CG_CLEANUP:-0}
export DTXQCD_RATFORCE_GPU=${DTXQCD_RATFORCE_GPU:-1}

# ---- Speed: the settings that live outside the code. The code's own speed-ups are on by
#      default; these two must be set here (both bit-identical).
export DTXQCD_LAZY_SMEAR=${DTXQCD_LAZY_SMEAR:-1}            # smear only after the links change: 640 -> 20 per trajectory
export GRID_ALLOC_NCACHE_LARGE=${GRID_ALLOC_NCACHE_LARGE:-64} # Grid's device-allocation cache (Grid default 8): -36% per trajectory

# ---- Communication: grid_qcd's production flag set. Cray MPICH, GPU-aware.
export MPICH_GPU_SUPPORT_ENABLED=1 MPICH_GPU_IPC_ENABLED=1 MPICH_RDMA_ENABLED_CUDA=1
export MPICH_GPU_EAGER_REGISTER_HOST_MEM=0 MPICH_GPU_NO_ASYNC_MEMCPY=0 MPICH_OFI_NIC_POLICY=GPU
export OMP_NUM_THREADS=8
GRID_ARGS=(--grid "$LATT" --mpi 1.1.1.4 --accelerator-threads 8
           --shm 2048 --shm-mpi 0 --comms-overlap --device-mem 38000)

# ---- One rank per GPU, memory and cores on that rank's NUMA domain.
sel=$RUN_DIR/select_gpu
printf '%s\n' '#!/bin/bash' 'export CUDA_VISIBLE_DEVICES=$SLURM_LOCALID' \
  'exec numactl -m $SLURM_LOCALID -N $SLURM_LOCALID "$@"' > "$sel"
chmod +x "$sel"

echo "BIN=$BIN"
echo "RUN_DIR=$RUN_DIR  IMPORT_CFG=${IMPORT_CFG:-<resume or weak field>}  TRAJ=$TRAJ  NO_METROP=$NO_METROP"
echo "GRID_ARGS=${GRID_ARGS[*]}"
srun -N 1 -n 4 --ntasks-per-node=4 --gpus-per-task=1 --cpus-per-task=32 \
     --cpu-bind=cores --gpu-bind=none --export=ALL --chdir="$RUN_DIR" \
     "$sel" "$BIN" "${GRID_ARGS[@]}"
echo "exit=$?"
