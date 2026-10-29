#!/bin/bash
# Build and run the two aux-field generators of a Grid tree carrying production/
# inside an EXISTING allocation, 4 ranks x 1 GPU on one node, small lattice, fixed
# seeds (the generators seed their RNGs with fixed integers), QUDA knobs off, cuBLAS
# knobs on as in the collaborator's canonical launcher production/run_dtxqcd_gencfgs.sh.
# By default this fork (TREE, BUILD, INSTALL_BIN from workflow/paths.sh: built out of
# source by build_gens_fork.sh, run from INSTALL_BIN); the reference clone with
# TREE=$REF_TREE BUILD=$REF_TREE/build-gpu (built and run in its production/).
#   SLURM_JOB_ID=<id> TAG=<tag> bash run_ref_generators.sh build   # make the two programs
#   SLURM_JOB_ID=<id> TAG=<tag> bash run_ref_generators.sh run     # run both smokes
#   SLURM_JOB_ID=<id> TAG=<tag> bash run_ref_generators.sh all
# Env: TAG (required, a new tag per run), TREE, BUILD, GEN_BIN_DIR, GEN_LATT (default
#      8.8.8.16), GENS (default "dtxqcd txqcd2p1": which smokes the run phase runs).
# Output: reference/gen/<tag>/{dtxqcd,txqcd2p1}/ with the log and the cfgs/ the
# generator writes (its checkpoints, aux sidecars, hmc_diagnostics h5 files).
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
: "${SLURM_JOB_ID:?set SLURM_JOB_ID to an existing allocation}"
: "${TAG:?set TAG (e.g. ref for the reference clone, fork_<what> for this tree)}"
PHASE=${1:-all}
if [ "$TREE" = "$REPO" ]; then GEN_BIN_DIR=${GEN_BIN_DIR:-$INSTALL_BIN}; else GEN_BIN_DIR=${GEN_BIN_DIR:-$TREE/production}; fi
GEN_LATT=${GEN_LATT:-8.8.8.16}
HDF5_PREFIX=${HDF5_PREFIX:-/opt/cray/pe/hdf5/1.14.3.9/gnu/12.3}
OUT=$WS/reference/gen/$TAG
mkdir -p "$OUT"
SUMMARY=$OUT/SUMMARY.txt
say() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }

source "$MACHINE_ENV"
export LD_LIBRARY_PATH="$HDF5_PREFIX/lib:${LD_LIBRARY_PATH:-}"

build_gens() {
  if [ "$TREE" = "$REPO" ]; then
    say "--- build_gens_fork.sh (out of source, -> $GEN_BIN_DIR) $(date '+%H:%M:%S')"
    srun --jobid="$SLURM_JOB_ID" -N 1 -n 1 --cpus-per-task=128 --export=ALL \
      bash "$HERE/build_gens_fork.sh" gen_dtxqcd_cfgs gen_txqcd_cfgs_2plus1 > "$OUT/make_production.log" 2>&1
    say "    build exit=$?  ($(grep -c -i ' error' "$OUT/make_production.log") error lines)"
    return 0
  fi
  say "--- make production in $TREE/production (QUDA_PREFIX empty) $(date '+%H:%M:%S')"
  srun --jobid="$SLURM_JOB_ID" -N 1 -n 1 --cpus-per-task=128 --export=ALL \
    env QUDA_PREFIX= make -C "$TREE/production" GRID_BUILD_DIR="$BUILD" -j2 gen_dtxqcd_cfgs gen_txqcd_cfgs_2plus1 > "$OUT/make_production.log" 2>&1
  say "    make exit=$?  ($(grep -c -i ' error' "$OUT/make_production.log") error lines)"
  for b in gen_dtxqcd_cfgs gen_txqcd_cfgs_2plus1; do
    if ldd "$GEN_BIN_DIR/$b" 2>/dev/null | grep -qi quda; then say "ERROR: $b links QUDA"; fi
    ldd "$GEN_BIN_DIR/$b" 2>/dev/null | grep -q 'not found' && say "ERROR: $b has unresolved libraries"
  done
  return 0
}

run_one() { # <name> <binary> [VAR=value ...]  (the generator writes cfgs/ under its cwd)
  local name=$1 bin=$2; shift 2
  local dir=$OUT/$name
  mkdir -p "$dir"
  local sel=$dir/select_gpu
  printf '%s\n' '#!/bin/bash' 'export CUDA_VISIBLE_DEVICES=$SLURM_LOCALID' 'exec numactl -m $SLURM_LOCALID -N $SLURM_LOCALID "$@"' > "$sel"
  chmod +x "$sel"
  local SRUN=(srun --jobid="$SLURM_JOB_ID" -N 1 -n 4 --ntasks-per-node=4 --gpus-per-task=1 --cpus-per-task=32 --cpu-bind=cores --gpu-bind=none --export=ALL --chdir="$dir")
  "${SRUN[@]}" "$sel" true || { say "ERROR: NUMA gate failed for $name"; return 1; }
  say "--- $name ($(basename "$bin")) $(date '+%H:%M:%S') latt=$GEN_LATT: $*"
  printf 'ENV %s\n' "$*" > "$dir/run.log"
  timeout -k 60s 60m env "$@" OMP_NUM_THREADS=8 MPICH_GPU_SUPPORT_ENABLED=1 \
    "${SRUN[@]}" "$sel" "$bin" --grid "$GEN_LATT" --mpi 1.1.1.4 --accelerator-threads 8 --shm 1024 --shm-mpi 0 --device-mem 8000 >> "$dir/run.log" 2>&1
  local rc=$?
  printf 'exit=%s\n' "$rc" >> "$dir/run.log"
  say "    exit=$rc  $(grep -a -c 'Total H after' "$dir/run.log") trajectories; log $dir/run.log"
  grep -a -E 'Total H before|Total H after|Metropolis|Plaquette|dH' "$dir/run.log" | sed 's/^Grid : [A-Za-z]* : *[0-9.]* s : //' | head -12 | tee -a "$SUMMARY"
}

run_gens() {
  say "==== generators tag=$TAG tree=$TREE HEAD=$(git -C "$TREE" rev-parse --short HEAD) $(date '+%Y-%m-%d %H:%M:%S %Z')"
  local gens=" ${GENS:-dtxqcd txqcd2p1} "
  # DTXQCD: the canonical launcher's defaults (MN2, MDS 10, trajL sqrt2/4, gauge x8,
  # aux x1, saddle init, rational autoscale, cuBLAS paths) with QUDA off and a
  # 3-trajectory target of which the first is force-accepted.
  [[ $gens == *" dtxqcd "* ]] && run_one dtxqcd "$GEN_BIN_DIR/gen_dtxqcd_cfgs" \
    LATT="$GEN_LATT" LAMBDA_DTXQCD=10.0 MASS_LIGHT_DTXQCD=-0.245 CSW=1.24930970916466 \
    STOUT_NSMEAR=1 STOUT_RHO=0.125 ADD_STRANGE=0 AUX_INIT_AUTO=1 RAT_AUTO_HI=1 \
    DTXQCD_PRECOMPUTE_GPU=1 DTXQCD_LOGDET_S_GPU=1 DTXQCD_LOGDET_GPU=1 \
    DTXQCD_MOOEEINV_CUBLAS=1 DTXQCD_MOOEE_CUBLAS=1 DTXQCD_MOOEE_FWDCACHE=1 \
    DTXQCD_MP_CG=1 DTXQCD_MP_CG_CLEANUP=0 DTXQCD_RATFORCE_GPU=1 \
    INTEGRATOR=MinimumNorm2 MDSTEPS=10 TRAJL=0.353553390593274 GAUGE_MULT=8 AUX_MULT=1 \
    TRAJ=3 NO_METROP=1 N_SKIP=1 CG_TOL=1e-8 DIAG_TRMINV_INTERVAL=0 \
    QUDA_FORCE=0 QUDA_FORCE_KERNEL=0 DTXQCD_QUDA_HYBRID=0 DTXQCD_SUFFIX=_ref
  # TXQCD Nf=2+1: weak-field thermal start, 2 trajectories, first force-accepted.
  [[ $gens == *" txqcd2p1 "* ]] && run_one txqcd2p1 "$GEN_BIN_DIR/gen_txqcd_cfgs_2plus1" \
    LATT="$GEN_LATT" LAMBDA=10.0 STOUT_NSMEAR=1 STOUT_RHO=0.125 \
    INTEGRATOR=MinimumNorm2 MDSTEPS=10 TRAJL=0.353553390593274 GAUGE_MULT=8 AUX_MULT=1 \
    N_TRAJ=2 NO_METROP=1 N_SKIP=1 SUFFIX=_ref
  say "==== done $(date '+%H:%M:%S')"
}

case $PHASE in
  build) build_gens ;;
  run) run_gens ;;
  all) build_gens; run_gens ;;
  *) echo "usage: SLURM_JOB_ID=<id> TAG=<tag> bash $0 {build|run|all}" >&2; exit 2 ;;
esac
