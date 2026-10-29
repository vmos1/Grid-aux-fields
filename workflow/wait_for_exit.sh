#!/bin/bash
# Block until the given HMC log contains its final "exit=<rc>" line, polling once a
# minute, then print that line and the trajectory summary lines. Used to get a
# completion notification for detached (setsid) launches.
# Usage: bash wait_for_exit.sh <hmc.log> [max_minutes, default 180]
LOG=$1
MAX=${2:-180}
n=0
until grep -q '^exit=' "$LOG" 2>/dev/null; do
  sleep 60
  n=$((n + 1))
  if [ "$n" -ge "$MAX" ]; then echo "wait_for_exit: gave up after $MAX minutes on $LOG"; exit 2; fi
done
grep -a -E '^exit=|Total H before trajectory|Total H after trajectory|Metropolis_test|Total time for trajectory|Plaquette: \[' "$LOG"
