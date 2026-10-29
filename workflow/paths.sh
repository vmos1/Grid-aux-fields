# Paths of the grid_txqcd workspace (project template, folder layout), sourced by
# every script in workflow/. Everything derives from where this repo sits, so the
# scripts work from any clone; each variable can be overridden from the environment.
#
#   <WS>/                         workspace root (CFS), not a repo
#     Grid-aux-fields/            REPO: this fork (source, production code, workflow/, machines/)
#     builds/ -> scratch          regenerable: builds/grid/build-gpu (BUILD), eigen-3.4.0, downloads
#     installs/                   durable: grid-aux-fields-gpu (INSTALL_PREFIX), bin/ = what jobs run
#     runs/  reference/  logs/  slurm_logs/  snapshots/  __docs/
#
# REF_TREE is the collaborator's branch as committed (frozen reference, in-tree build
# build-gpu/): the one recorded exception to the layout, on scratch.
_paths_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=${REPO:-$(cd "$_paths_here/.." && pwd)}
WS=${WS:-$(cd "$REPO/.." && pwd)}
TREE=${TREE:-$REPO}
BUILD=${BUILD:-$WS/builds/grid/build-gpu}
INSTALL_PREFIX=${INSTALL_PREFIX:-$WS/installs/grid-aux-fields-gpu}
INSTALL_BIN=${INSTALL_BIN:-$INSTALL_PREFIX/bin}
MACHINE_ENV=${MACHINE_ENV:-$REPO/machines/perlmutter.sh}
REF_TREE=${REF_TREE:-${PSCRATCH:-}/grid_txqcd/ref-dtxqcd-v2}
unset _paths_here
