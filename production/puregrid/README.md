# DTXQCD generator in pure Grid

`gen_dtxqcd_cfgs` from the `dtxqcd-v2` branch of Grid-TXQCD, in this fork of Grid with QUDA
removed, and faster. Same physics: the same action, integrator, step sizes, tolerances and
rational approximation as `dtxqcd-v2`'s launcher defaults. The light hopping force that
`dtxqcd-v2` gives to QUDA (`DTXQCD_QUDA_HYBRID=1`) is computed in Grid.

- **Speed:** one 16³×48 trajectory on one Perlmutter node (4 × A100 80 GB) takes
  **195 s**, against 679 s for `dtxqcd-v2`'s code without QUDA (Grid's
  `Total time for trajectory`, started from the same configuration).
- **Checked:** every speed-up gave bit-identical results (an 8³×16 smoke against
  `dtxqcd-v2` built without QUDA, and all physics lines of a 16³×48 trajectory against the
  previous step). The one exception is `--comms-overlap`, which changes summation order:
  ΔH 0.0189107 → 0.0189127.

## How to get the speed

Most speed-ups are in the code and on by default. Three things are set at run time, and the
batch script here sets all of them:

| setting | value | effect |
|---|---|---|
| `GRID_ALLOC_NCACHE_LARGE` | 64 (Grid default 8) | Grid's device-allocation cache; −36% per trajectory |
| `DTXQCD_LAZY_SMEAR` | 1 (code default 0) | smear only after the links change; −40 s per trajectory |
| Grid flags | `--shm 2048 --shm-mpi 0 --comms-overlap --accelerator-threads 8` | grid_qcd's production comms set (with the Cray MPICH variables in the script) |

`dtxqcd-v2`'s own launcher, `production/run_dtxqcd_gencfgs.sh`, sets none of these: it uses
`--shm-mpi 1` and Grid's default cache. Run with `gen_dtxqcd_perlmutter.sbatch` instead, or
copy these settings into your launcher.

## Perlmutter

### Build

The workflow scripts put `builds/`, `installs/` and `runs/` next to the clone, so clone into an
empty directory:

```bash
mkdir dtxqcd && cd dtxqcd
git clone https://github.com/vmos1/Grid-aux-fields.git
cd Grid-aux-fields
git checkout v3-txqcd
export CLIME_ROOT=<your c-lime install>   # needed to read .lime configurations
bash workflow/build_grid_fork.sh prepare  # login node: Eigen, bootstrap
bash workflow/build_grid_fork.sh configure
# library build and install on a compute node:
salloc --nodes=1 --constraint=gpu --gpus-per-node=4 --qos=interactive --time=02:00:00 --account=<project>_g
srun -N 1 -n 1 --cpus-per-task=128 bash workflow/build_grid_fork.sh build
srun -N 1 -n 1 --cpus-per-task=128 bash workflow/build_grid_fork.sh install
exit
bash workflow/build_gens_fork.sh gen_dtxqcd_cfgs   # login node is fine; installs to ../installs/grid-aux-fields-gpu/bin
```

The environment (modules, CUDA 12.9, cray-mpich 9.0.1, HDF5, MPFR) comes from
`machines/perlmutter.sh`, which every script sources. The configure flags are in
`workflow/build_grid_fork.sh` (`configure_grid`).

### Check that you get the speed

From the repository root, start one trajectory from Chroma configuration 11100 of
`cl3_16_48_b6p1_m0p2450` (the 16³×48 b6.1 point `dtxqcd-v2`'s launcher is matched to):

```bash
IMPORT_CFG=<path>/cl3_16_48_b6p1_m0p2450_a_cfg_11100.lime \
  sbatch --account=<project>_g production/puregrid/gen_dtxqcd_perlmutter.sbatch
```

`gen_dtxqcd_<jobid>.out` should contain:

```
Total H after trajectory  = 38595020.0151707  dH = 0.0189127326011658
Total time for trajectory (s): 194.8   (about 195; ours)
```

The same ΔH to all digits means the same code and physics. The time varies by about 10%
from node to node.

### Production

Set `NO_METROP=0`, a fixed `RUN_DIR` and a target `TRAJ`, and raise `--time` (~195 s per
trajectory at 16³×48). Checkpoints are written every `N_SKIP` trajectories (default 10)
under `RUN_DIR/cfgs/`. Resubmitting with the same `RUN_DIR` and a larger `TRAJ` continues
from the latest checkpoint. Every physics variable of `dtxqcd-v2`'s launcher can be
overridden the same way; the script lists them all.

## Other machines

Not tested off Perlmutter. The batch script is the full recipe:

- **Keep:** every exported physics, GPU-path and speed variable, and the Grid flags.
- **Replace:**
  - `machines/perlmutter.sh` (modules and library paths);
  - the `MPICH_*` variables, which are Cray MPICH, with the GPU-aware settings of your MPI;
  - the `#SBATCH` lines, the `srun` options and the NUMA binding in `select_gpu`.
- **Build:** Grid as for `dtxqcd-v2`, but without `--with-quda`, and with `--with-lime`,
  `--with-hdf5` and `--enable-shm=nvlink`. Then build the generator with
  `production/Makefile`: `make GRID_BUILD_DIR=<grid build> gen_dtxqcd_cfgs`.
- **Check:** run this binary and `dtxqcd-v2`'s on the same configuration in one allocation.
  ΔH agrees to rounding (bit for bit only against `dtxqcd-v2` run without QUDA and with the
  same comms flags), and the time should drop.

## Switches

Every speed-up is an environment variable, on by default, `=0` restores the old path:
`DTXQCD_REUSE_SITE_MATRICES`, `DTXQCD_PACK_ON_DEVICE`, `DTXQCD_SITE_APPLY_ROWS`,
`DTXQCD_RATFORCE_CB_ACCUM`, `DTXQCD_INVN_DEVICE_PACK`, `DTXQCD_HOPFORCE_CB_ACCUM`.
Timers, print only: `DTXQCD_CG_TIMING=1`, `DTXQCD_FORCE_TIMING=1`, `DTXQCD_EO_TIMING=1`.

## Known limits

- Timed only at 16³×48 on one node. Nothing larger has been run yet.
- Only `gen_dtxqcd_cfgs` is optimised. The TXQCD generators and the measurement programs
  build and run in pure Grid, but have not been timed.
- Out-of-source builds print "Current Grid git commit hash is undefined"; note the commit
  yourself.
- Work continues on branch `pure-txqcd`. Every new speed-up follows the same rule
  (a switch, on by default, bit-identical), so `git pull` does not change results.
