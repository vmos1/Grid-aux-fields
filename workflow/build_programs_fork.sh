#!/bin/bash
# Build every program of this fork against BUILD, in parallel, inside ONE job step
# (srun --jobid=<id> -N 1 -n 1 --cpus-per-task=128 bash build_programs_fork.sh):
# the HMC driver, the four helper tests and the two aux-field generators. Each
# build script installs its binaries into INSTALL_BIN. Logs: logs/<date>_build_<name>.log.
# Exit status: the number of builds that failed.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
D=$(date +%Y_%m_%d)
mkdir -p "$WS/logs"
NICE=0 bash "$HERE/build_driver_fork.sh" > "$WS/logs/${D}_build_driver.log" 2>&1 &
p_driver=$!
NICE=0 bash "$HERE/build_tests_fork.sh" > "$WS/logs/${D}_build_helper_tests.log" 2>&1 &
p_tests=$!
JOBS=2 bash "$HERE/build_gens_fork.sh" gen_dtxqcd_cfgs gen_txqcd_cfgs_2plus1 > "$WS/logs/${D}_build_gens.log" 2>&1 &
p_gens=$!
fail=0
for name in driver tests gens; do
  pid_var=p_$name
  wait "${!pid_var}"
  rc=$?
  echo "build $name exit=$rc"
  [ "$rc" -eq 0 ] || fail=$((fail + 1))
done
exit "$fail"
