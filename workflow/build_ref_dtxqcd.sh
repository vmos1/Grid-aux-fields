#!/usr/bin/env bash
# Build the collaborator's dtxqcd-v2 branch AS IS (no QUDA, with HDF5) as the
# reference for step 2: its test and generator logs are what the merged tree
# must reproduce. Thin wrapper over build_grid_fork.sh with the reference
# tree (REF_TREE, the one layout exception: frozen, on scratch, in-tree build
# build-gpu, their production/Makefile default), its own install prefix and
# provenance file, plus --with-hdf5 (serial cray-hdf5, whose C++ API Grid's
# Hdf5IO needs).
# Usage: bash build_ref_dtxqcd.sh {prepare|configure|build|install|all|info}
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${HERE}/paths.sh"
: "${PSCRATCH:?}"
HDF5_PREFIX=${HDF5_PREFIX:-/opt/cray/pe/hdf5/1.14.3.9/gnu/12.3}
[[ -f ${HDF5_PREFIX}/include/H5Cpp.h ]] || { echo "ERROR: no H5Cpp.h under ${HDF5_PREFIX}" >&2; exit 1; }
export TREE=${REF_TREE}
export BUILD_DIR=${TREE}/build-gpu
export INSTALL_PREFIX=${PSCRATCH}/grid_txqcd/ref-install
export PROVENANCE=${WS}/PROVENANCE_ref_dtxqcd_build.txt
export EXTRA_CONFIGURE="--with-hdf5=${HDF5_PREFIX}"
# The HDF5 runtime library must be on the loader path for the test binaries.
export LD_LIBRARY_PATH="${HDF5_PREFIX}/lib:${LD_LIBRARY_PATH:-}"
exec bash "${HERE}/build_grid_fork.sh" "$@"
