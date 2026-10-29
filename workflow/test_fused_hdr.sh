#!/bin/bash
# Gate the collaborator's DTXQCDFusedAuxClover.h (dtxqcd-v2 b5cd4506, replacing our local
# stub) in the fork, inside an EXISTING 1-node allocation, one step at a time:
#   1. build the four of his tests that apply the full operator M() (the only caller of
#      the fused kernel; the EO Schur path of the HMC never calls it);
#   2. run them with DTXQCD_FUSED_HERMOP unset (tag fork_fused0) and =1 (fork_fused1);
#   3. the 8^3x16 DTXQCD smoke with the knob unset, which must be identical to
#      reference/gen/fork;
#   4. the 16^3x48 generator setup alone (TRAJ=0: import + saddle init, whose stochastic
#      Tr M^-1 is a full-operator CG), knob off and on, for the wall-clock of M();
#   5. the 8^3x16 smoke with the knob set (dH must agree with the reference to roundoff);
#   6. compare both tags against tag fork.
#   SLURM_JOB_ID=<id> bash test_fused_hdr.sh
# Run once on 2026-10-29 with the pre-template layout (results in
# __docs/2026_10_29_fused_aux_clover_header_gate.md); paths now from workflow/paths.sh.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
: "${SLURM_JOB_ID:?set SLURM_JOB_ID to an existing allocation}"
export TREE BUILD
TESTS_M="Test_dtxqcd_wilson_clover_fermion_eo Test_dtxqcd_zero_aux_doubled_qcd Test_dtxqcd_trminv_zeroaux Test_dtxqcd_rational_full_force"
step() { echo "=== $* $(date '+%Y-%m-%d %H:%M:%S %Z')"; }

step "fork HEAD $(git -C "$TREE" rev-parse --short HEAD), status: $(git -C "$TREE" status --porcelain --untracked-files=no | tr '\n' ' ')"
step "1. build tests"
env -u DTXQCD_FUSED_HERMOP TAG=fork_fused0 TESTS="$TESTS_M" bash "$HERE/run_ref_gates.sh" build
step "2a. tests, knob off"
env -u DTXQCD_FUSED_HERMOP TAG=fork_fused0 TESTS="$TESTS_M" bash "$HERE/run_ref_gates.sh" run
step "2b. tests, knob on"
env DTXQCD_FUSED_HERMOP=1 TAG=fork_fused1 TESTS="$TESTS_M" bash "$HERE/run_ref_gates.sh" run
step "3. 8^3x16 smoke, knob off"
env -u DTXQCD_FUSED_HERMOP TAG=fork_fused0 GENS=dtxqcd bash "$HERE/run_ref_generators.sh" run
step "4a. 16^3x48 setup, knob off"
env -u DTXQCD_FUSED_HERMOP RUN=2026_10_29_setup16_fused0 TRAJ=0 NO_METROP=0 bash "$HERE/run_profile_dtxqcd.sh"
step "4b. 16^3x48 setup, knob on"
env -u DTXQCD_FUSED_HERMOP RUN=2026_10_29_setup16_fused1 TRAJ=0 NO_METROP=0 bash "$HERE/run_profile_dtxqcd.sh" DTXQCD_FUSED_HERMOP=1
step "5. 8^3x16 smoke, knob on"
env DTXQCD_FUSED_HERMOP=1 TAG=fork_fused1 GENS=dtxqcd bash "$HERE/run_ref_generators.sh" run
step "6. compare"
bash "$HERE/compare_ref_fork.sh" fork_fused0 fork
bash "$HERE/compare_ref_fork.sh" fork_fused1 fork
step "done"
