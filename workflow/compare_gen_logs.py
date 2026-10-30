#!/usr/bin/env python3
"""Bit-identity gate for generator logs (gen_dtxqcd_cfgs and kin).

Extracts the physics lines of two run logs -- H and dH, every action value,
plaquettes, the per-level force and Fdt averages and maxima, solver iteration
counts and reliable-update residuals -- without timestamps or timings, and
compares them in order. A shorter log is compared as a prefix of the longer
one, so a 1-trajectory run can be checked against a 2-trajectory reference.

  python3 -I compare_gen_logs.py <log A> <log B>

Prints IDENTICAL (exit 0) or the first differing lines (exit 1).
"""
import re
import sys

PATTERNS = [
    r"Total H (?:before|after) trajectory\s*=\s*\S+(?:\s+dH = \S+)?",
    r"S \[\d+\]\[\d+\] H = \S+",
    r"\[\w+\] S = \S+",
    r"Imported gauge plaquette = \S+",
    r"Traj \d+ plaq = \S+",
    r"\[\d+\]\[\d+\] (?:Force average|Force max|Fdt average|Fdt max)\s*: \S+ \S+",
    r"\[\w+\] converged iter=\d+ nshift=\d+(?: reliable_updates=\d+ sp_cleanup_shifts=\d+)?",
    r"reliable update k=\d+ replaced \|r\|\^2=\S+ with \|r\|\^2=\S+",
]
RX = re.compile("|".join("(?:%s)" % p for p in PATTERNS))


def physics_lines(path):
    out = []
    with open(path, errors="replace") as f:
        for line in f:
            out.extend(m.group(0) for m in RX.finditer(line))
    return out


def main(a_path, b_path):
    a, b = physics_lines(a_path), physics_lines(b_path)
    n = min(len(a), len(b))
    diffs = [i for i in range(n) if a[i] != b[i]]
    print(f"A: {len(a)} physics lines  {a_path}")
    print(f"B: {len(b)} physics lines  {b_path}")
    if n == 0:
        print("NOTHING TO COMPARE")
        return 1
    if not diffs:
        print(f"IDENTICAL over the first {n} lines")
        return 0
    print(f"DIFFERENT: {len(diffs)} of {n} lines; first differences:")
    for i in diffs[:10]:
        print(f"  [{i}] A: {a[i]}")
        print(f"  [{i}] B: {b[i]}")
    return 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
