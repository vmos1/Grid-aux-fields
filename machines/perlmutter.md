# grid_txqcd on Perlmutter: account, queues, paths, traps

Updated on 2026-10-29 10:23 CDT · perlmutter

Read by agents on every session run on Perlmutter, per rule 7 of the workspace
`AGENTS.md`. Shell environment is `perlmutter.sh` beside this file, sourced by every
script in `workflow/` (through `workflow/paths.sh`). General NERSC rules live in the
user's instruction file; this file holds only what this project needs on this
machine. Machine-independent facts belong in `__docs/`, not here. The fuller machine
file of the sibling project,
`/global/cfs/cdirs/m4599/Users/vayyar/grid_qcd/grid-lqcd-workflow/machines/perlmutter.md`,
is the source for the general facts restated briefly here (binding, loader, HPSS).

## Account and queues

Updated on 2026-10-28 11:27 CDT · perlmutter

- GPU account **`m4599_g`**; CPU account `m4599`. Every job or allocation states one.
- Default to the **interactive QOS** for anything under 4 nodes / 4 hours; check
  `sinfo -s -p gpu_ss11` first (66 idle nodes on 2026-10-26 was plenty). Ask the user
  before any allocation; state the estimate.

## Allocations and launching

Updated on 2026-10-29 10:23 CDT · perlmutter

- Only `bash ~/.claude/bin/alloc_gpu.sh <nodes 1-4> <hours 1-4> [40|80]` and
  `bash ~/.claude/bin/release_alloc.sh <jobid>`; never raw `salloc`/`scancel`. Release
  as soon as the work is done; elapsed time is charged. Timing runs pin `80` (A100-80GB)
  so numbers stay comparable.
- Workloads attach with `srun --jobid=<id> ...`; verify with
  `srun --jobid=<id> -N 1 -n 1 hostname`.
- **Steps one at a time.** A step started while another holds the node can fail at
  once with `Unable to create step for job: Invalid generic resource (gres)
  specification` (seen 2026-10-27 for `-c 128` build steps while a 32-core step ran).
  Retrying after the other step finished always worked; two `-c 32` builds side by
  side were fine.
- Long runs: the harness kills foreground commands after 10 minutes (a 48³ trajectory
  was killed that way on 2026-10-26). Run them as tracked background commands, or
  `setsid -f ... > log 2>&1` plus `workflow/wait_for_exit.sh <log>` in the background.

## Node binding

Updated on 2026-10-28 11:27 CDT · perlmutter

- 4-rank runs: the launchers' `select_gpu` (`CUDA_VISIBLE_DEVICES=$SLURM_LOCALID`,
  `numactl -m/-N $SLURM_LOCALID`, `--gpu-bind=none`, `--cpus-per-task=32`) with a hard
  gate `srun ... select_gpu true || exit 1`.
- 1-rank runs (his tests): no `numactl`; Slurm places a lone task on an arbitrary
  NUMA domain and `numactl -N 0` fails with `sched_setaffinity: Invalid argument`.

## Filesystems and paths

Updated on 2026-10-29 10:23 CDT · perlmutter

The workspace follows the project template's folder layout (2026-10-29); every path
below is computed by `workflow/paths.sh` from where this repo sits.

| what | where |
|---|---|
| workspace root (CFS, not a repo) | `/global/cfs/cdirs/m4599/Users/vayyar/grid_txqcd` |
| code repo, this fork | `Grid-aux-fields/` in the root (CFS) |
| regenerable builds | `builds/` → `$PSCRATCH/grid_txqcd/builds`: `grid/build-gpu/` (Grid configure + library + his tests, and `production/` for every program binary), `eigen-3.4.0/`, `downloads/` |
| durable installs | `installs/grid-aux-fields-gpu/` (CFS): Grid install prefix; `bin/` holds the executables jobs run |
| run output, reference results, logs | `runs/`, `reference/`, `logs/`, `slurm_logs/` in the root, never inside a git tree |
| layout exception | `$PSCRATCH/grid_txqcd/ref-dtxqcd-v2`: the collaborator's branch as committed plus 7 local fixes, in-tree build `build-gpu/`, frozen, uses `$PSCRATCH/grid_txqcd/eigen-3.4.0` and `ref-install` |
| checkpoints | `$PSCRATCH/grid_txqcd/ckpt` (48³, 7 GB each) |

- The m4599 CFS quota is counted in inodes as well as bytes (6.36M of 10M inodes,
  12.2 of 20 TiB on 2026-10-29; it was at 99% of inodes on 2026-08-17). Check with
  `showquota m4599`. Keep inode-heavy trees (build trees, Eigen, Python environments)
  under `builds/`; the repo itself is about 2k files plus what bootstrap generates.
- Scratch purges after ~8 weeks idle: a purge costs a rebuild of `builds/`, never a
  broken job, because jobs run from `installs/`. The repo is backed by its GitHub
  remote; commit and push before leaving work for long.
- Inputs read from the sibling workspace, read-only: `grid_qcd/data/cl3_16_48_*.lime`
  (16³), `grid_qcd/data/cl21_48_96_*_cfg_2000.lime` (48³), `grid_qcd/lime-install`.

## Build and runtime environment

Updated on 2026-10-29 10:23 CDT · perlmutter

- `machines/perlmutter.sh` before building or running (the workflow scripts source it):
  PrgEnv-gnu, cray-mpich 9.0.1, cudatoolkit 12.9, `LD_LIBRARY_PATH` from
  `CRAY_LD_LIBRARY_PATH`, MPFR, LIME, plus `cray-hdf5/1.14.3.9` and its library path
  (the aux-field generators write HDF5; Grid's `Hdf5IO` needs the C++ API, present in
  the serial module). Without it a run dies at ~10 s with `libcudart.so.13`, exit 127;
  a build on a bare login shell picks up CUDA 13.2 and fails with `cuGetProcAddress_v2`
  errors.
- Compiler: `nvcc` (`-ccbin CC`, sm_80, C++17); configure flags in
  `workflow/build_grid_fork.sh` (MPI comms, GPU SIMD width 64, nvlink shm, no fermion
  reps, no unified memory, no G-parity, LIME, HDF5, no QUDA).
- Order: `workflow/build_grid_fork.sh prepare`, `configure` (login node), `build` and
  `install` (allocation only, `make -j16`, ~20 min); then `build_driver_fork.sh`,
  `build_tests_fork.sh`, `build_gens_fork.sh` (single programs, niced on a login node
  or in the allocation; each installs its binaries into `installs/.../bin`).
- `production/Makefile` does not track Grid headers: after a header change, rebuild
  programs with `MAKEFLAGS=-B`.
- nvcc 12.9 + GCC 12.3 reject `typedef typename std::remove_cv<...>::type` inside some
  `accelerator_for` lambdas (his `TXQCDWilsonPseudoFermionAction.h`): use `std::decay_t`.
  The same form compiles in `DTXQCDFusedAuxClover.h`.

## Known failures on this machine

Updated on 2026-10-29 17:32 CDT · perlmutter

- Since `d01a54b5` all of the collaborator's gate tests pass on these A100s except
  `Test_dtxqcd_rational_aux_force`: at its tol 1e-12 every multishift solve runs into the
  20000-iteration cap (~110 s each at 4⁴), so the test needs over an hour; it logs
  "did not converge" each time. Not a hang. His branch as committed also fails
  `Test_aux_kinetic`, `Test_dtxqcd_logdet_aux_force` (at `--grid 4.4.4.8`) and crashes in six
  TXQCD tests (csw=0 GPU precompute); causes in
  `__docs/2026_10_29_collaborator_test_failures_diagnosed.md`.
- Never run `make -n -B` in the build tree to read compile commands: GNU make remakes its
  Makefiles even in dry-run mode, and `-B` makes it re-run autotools and configure (it did,
  2026-10-29, in a shell without the module environment). Re-run
  `workflow/build_grid_fork.sh configure` if it happens.

## Tools on the login node

Updated on 2026-10-29 10:23 CDT · perlmutter

- No `gh`; GitHub actions through the web UI; pushes by the user.
- The user's terminal has no bracketed paste and wraps long lines: commands handed over
  must be short and fit on one line (a two-line `rm` executed its second line as a
  command on 2026-10-27; a long `git -C <path>` lost part of its path on 2026-10-29).
- `python3` is 3.6; the checker and `workflow/strip_ifdef.py` run on it; use
  `python3 -I` for scripts that read untrusted files.

## Where the rest is

Updated on 2026-10-29 10:23 CDT · perlmutter

Campaign facts: `__docs/_TOC.md` and `_SUM.md`; build and gate details of the first
campaigns in `__docs/2026_10_28_fork_layout_build_and_gates.md` (pre-template paths);
the layout move in `__docs/2026_10_29_workspace_on_template_layout.md`.
