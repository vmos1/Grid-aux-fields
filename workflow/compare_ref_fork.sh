#!/bin/bash
# Compare the collaborator-code results of two tags (default: ref = his branch as
# committed, fork = the imported tree): per-test verdicts and exit codes, and the
# physics lines of the two generator smokes with Grid's timestamps stripped.
#   bash compare_ref_fork.sh [ref_tag] [fork_tag]
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
source "$HERE/paths.sh"
A=${1:-ref}
B=${2:-fork}
TA=$WS/reference/tests/$A
TB=$WS/reference/tests/$B
GA=$WS/reference/gen/$A
GB=$WS/reference/gen/$B
strip() { sed 's/^Grid : [A-Za-z]* : *[0-9.]* s : //'; }

echo "==== tests: verdict and exit code, $A vs $B"
for log in "$TA"/Test_*.log; do
  t=$(basename "$log" .log)
  va=$(grep -a "^$t " "$TA/SUMMARY.txt" | tail -1 | sed "s/^$t *//")
  vb=$(grep -a "^$t " "$TB/SUMMARY.txt" | tail -1 | sed "s/^$t *//")
  if [ "$va" = "$vb" ]; then s=same; else s=DIFFERENT; fi
  printf '%-44s %-10s %s | %s\n' "$t" "$s" "$va" "$vb"
done

echo
echo "==== tests: numeric check lines ([ok]/[FAIL]/rel/numeric), $A vs $B (identical files = PASS)"
for log in "$TA"/Test_*.log; do
  t=$(basename "$log" .log)
  [ -f "$TB/$t.log" ] || { printf '%-44s %s\n' "$t" "missing in $B"; continue; }
  if diff <(grep -a -E '\[ok\]|\[FAIL\]|rel |rel=|numeric|PASS|FAIL' "$log" | grep -v MemoryManager | strip) <(grep -a -E '\[ok\]|\[FAIL\]|rel |rel=|numeric|PASS|FAIL' "$TB/$t.log" | grep -v MemoryManager | strip) > /dev/null; then
    printf '%-44s identical check lines\n' "$t"
  else
    n=$(diff <(grep -a -E '\[ok\]|\[FAIL\]|rel |rel=|numeric|PASS|FAIL' "$log" | grep -v MemoryManager | strip) <(grep -a -E '\[ok\]|\[FAIL\]|rel |rel=|numeric|PASS|FAIL' "$TB/$t.log" | grep -v MemoryManager | strip) | grep -c '^[<>]')
    printf '%-44s %d differing check lines\n' "$t" "$n"
  fi
done

echo
for g in dtxqcd txqcd2p1; do
  echo "==== generator $g: H, dH, plaquette lines, $A vs $B"
  if diff <(grep -a -E 'Total H before|Total H after|Plaquette|Metropolis' "$GA/$g/run.log" | strip) <(grep -a -E 'Total H before|Total H after|Plaquette|Metropolis' "$GB/$g/run.log" | strip); then
    echo "    IDENTICAL"
  fi
done
