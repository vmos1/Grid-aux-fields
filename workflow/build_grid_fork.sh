#!/usr/bin/env bash
# Prepare, configure, build and install the Grid library of this fork (branch
# pure-txqcd of vmos1/Grid-aux-fields) on Perlmutter. Out of source: the tree is
# this repo (CFS), the build tree is builds/grid/build-gpu (scratch through the
# workspace's builds/ symlink), the install prefix is installs/grid-aux-fields-gpu
# (CFS). Paths: workflow/paths.sh.
# Adapted from grid-lqcd-workflow/1_build_grid/build_grid_stock_hmc.sh: the
# tree IS the source (no staging clone, no patch step: the patches are commits).
#
# Actions:
#   prepare    vendor Eigen 3.4.0 (symlinks into builds/), Grid/Eigen.inc, scripts/filelist, autoreconf
#   configure  configure for Perlmutter A100, identical flags to the stock build, no QUDA
#   build      make libGrid     -- ALLOCATION ONLY (compute node), JOBS default 16
#   install    make install     -- ALLOCATION ONLY
#   all        prepare + configure   (never builds)
#   info       print paths only
#
# Env overrides: TREE, BUILD_DIR (default BUILD), INSTALL_PREFIX, JOBS, EIGEN_ARCHIVE,
# EIGEN_DIR, PROVENANCE. Provenance (tree SHA, dirty flag, configure command) is
# appended to ${PROVENANCE} in the workspace root.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${HERE}/paths.sh"
source "${MACHINE_ENV}"

ACTION=${1:-all}
BUILD_DIR=${BUILD_DIR:-${BUILD}}
JOBS=${JOBS:-16}
EIGEN_ARCHIVE=${EIGEN_ARCHIVE:-${WS}/builds/downloads/eigen-3.4.0.tar.bz2}
EIGEN_URL=https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.bz2
EIGEN_SHA256=b4c198460eba6f28d34894e3a5710998818515104d6e74e5cc331ce31e46e626
EIGEN_DIR=${EIGEN_DIR:-${WS}/builds/eigen-3.4.0}
PREPARED_MARKER=${TREE}/.grid-fork-prepared
PROVENANCE=${PROVENANCE:-${WS}/PROVENANCE_grid_build.txt}
# Extra configure options, space-separated. Default: HDF5 (the aux-field generators
# and measurement programs write hmc_diagnostics.*.h5 through Grid's Hdf5IO, which
# needs the C++ API of the serial cray-hdf5), when the prefix is present.
HDF5_PREFIX=${HDF5_PREFIX:-/opt/cray/pe/hdf5/1.14.3.9/gnu/12.3}
if [[ -z ${EXTRA_CONFIGURE+x} ]]; then
  if [[ -f ${HDF5_PREFIX}/include/H5Cpp.h ]]; then EXTRA_CONFIGURE="--with-hdf5=${HDF5_PREFIX}"; else EXTRA_CONFIGURE=""; fi
fi

now() { date '+%Y-%m-%d %H:%M:%S %Z'; }
tree_sha() { git -C "${TREE}" rev-parse HEAD; }
tree_dirty() {
  if [[ -n "$(git -C "${TREE}" status --porcelain --untracked-files=no)" ]]; then echo dirty; else echo clean; fi
}

print_paths() {
  printf 'TREE=%s (HEAD %s, %s)\n' "${TREE}" "$(tree_sha)" "$(tree_dirty)"
  printf 'BUILD_DIR=%s\n' "${BUILD_DIR}"
  printf 'INSTALL_PREFIX=%s\n' "${INSTALL_PREFIX}"
  printf 'JOBS=%s\n' "${JOBS}"
}

provenance_line() {
  mkdir -p "$(dirname "${PROVENANCE}")"
  printf '%s  %s  tree=%s HEAD=%s %s  %s\n' "$(now)" "$(hostname)" "${TREE}" "$(tree_sha)" "$(tree_dirty)" "$*" >> "${PROVENANCE}"
}

prepare() {
  [[ -d "${TREE}/.git" ]] || { printf 'ERROR: %s is not a git tree\n' "${TREE}" >&2; exit 1; }
  if [[ -f "${PREPARED_MARKER}" ]]; then
    printf 'Already prepared (%s). Re-running filelist + autoreconf only.\n' "$(<"${PREPARED_MARKER}")"
  else
    if [[ ! -f "${EIGEN_ARCHIVE}" ]]; then
      mkdir -p "$(dirname "${EIGEN_ARCHIVE}")"
      wget --no-check-certificate --output-document="${EIGEN_ARCHIVE}" "${EIGEN_URL}"
    fi
    printf '%s  %s\n' "${EIGEN_SHA256}" "${EIGEN_ARCHIVE}" | sha256sum --check
    [[ -d "${EIGEN_DIR}" ]] || tar -xjf "${EIGEN_ARCHIVE}" -C "$(dirname "${EIGEN_DIR}")"
    [[ -e "${TREE}/Grid/Eigen" ]] || ln -s "${EIGEN_DIR}/Eigen" "${TREE}/Grid/Eigen"
    [[ -e "${TREE}/Grid/Eigen/unsupported" ]] || ln -s "${EIGEN_DIR}/unsupported/Eigen" "${TREE}/Grid/Eigen/unsupported"
    # bootstrap.sh's non-destructive equivalent: Grid/Eigen.inc before autoreconf.
    (
      cd "${TREE}/Grid"
      { echo 'eigen_files =\'
        find -L Eigen -type f -print | sed 's/^/  /;$q;s/$/ \\/'
      } > Eigen.inc
    )
  fi
  (
    cd "${TREE}"
    ./scripts/filelist
    autoreconf -fvi
  )
  printf '%s\n' "$(tree_sha)" > "${PREPARED_MARKER}"
  provenance_line "prepare done (Eigen 3.4.0 sha256 ${EIGEN_SHA256}, ${EIGEN_DIR})"
}

configure_grid() {
  [[ -x "${TREE}/configure" ]] || { printf 'ERROR: run %s prepare first\n' "$0" >&2; exit 1; }
  # Flags identical to build_grid_stock_hmc.sh. No --with-quda, ever.
  local cmd=(
    "${TREE}/configure"
    --prefix="${INSTALL_PREFIX}"
    --enable-comms=mpi
    --enable-simd=GPU
    --enable-shm=nvlink
    --enable-gen-simd-width=64
    --enable-accelerator=cuda
    --enable-setdevice
    --disable-fermion-reps
    --disable-unified
    --disable-gparity
    --with-mpfr="${GRID_MPFR_PREFIX}"
    --with-lime="${CLIME_ROOT}"
    ${EXTRA_CONFIGURE}
    CXX=nvcc
    LDFLAGS="-cudart shared"
    CXXFLAGS="-ccbin CC -gencode arch=compute_80,code=sm_80 -std=c++17 -cudart shared"
  )
  provenance_line "configure in ${BUILD_DIR}: ${cmd[*]@Q}"
  printf 'configure command:\n  %s\n' "${cmd[*]@Q}"
  mkdir -p "${BUILD_DIR}" "${INSTALL_PREFIX}"
  ( cd "${BUILD_DIR}" && "${cmd[@]}" )
  "${BUILD_DIR}/grid-config" --summary
}

require_allocation() {
  if [[ -z "${SLURM_JOB_ID:-}" && "${ALLOW_NO_ALLOC:-0}" != 1 ]]; then
    printf 'ERROR: "%s" must run inside a Slurm allocation; SLURM_JOB_ID is unset.\n' "${ACTION}" >&2
    exit 1
  fi
}

build_grid() {
  require_allocation
  [[ -x "${BUILD_DIR}/grid-config" ]] || { printf 'ERROR: run %s configure first\n' "$0" >&2; exit 1; }
  provenance_line "build start JOBS=${JOBS} job=${SLURM_JOB_ID:-none}"
  make -C "${BUILD_DIR}/Grid" -j"${JOBS}"
  provenance_line "build done: $(sha256sum "${BUILD_DIR}/Grid/libGrid.a" | cut -c1-16)... libGrid.a"
}

install_grid() {
  require_allocation
  [[ -f "${BUILD_DIR}/Grid/libGrid.a" ]] || { printf 'ERROR: libGrid.a absent; run %s build first\n' "$0" >&2; exit 1; }
  make -C "${BUILD_DIR}/Grid" install
  make -C "${BUILD_DIR}" install-binSCRIPTS
  test -x "${INSTALL_PREFIX}/bin/grid-config"
  test -f "${INSTALL_PREFIX}/lib/libGrid.a"
  "${INSTALL_PREFIX}/bin/grid-config" --summary
  provenance_line "install done to ${INSTALL_PREFIX}"
}

print_paths
case "${ACTION}" in
  prepare)   prepare ;;
  configure) configure_grid ;;
  build)     build_grid ;;
  install)   install_grid ;;
  all)       prepare; configure_grid ;;
  info) ;;
  *) printf 'usage: %s {prepare|configure|build|install|all|info}\n' "$0" >&2; exit 2 ;;
esac
