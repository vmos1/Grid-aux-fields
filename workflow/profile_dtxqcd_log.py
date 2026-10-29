#!/usr/bin/env python3
"""Per-trajectory time breakdown of a gen_dtxqcd_cfgs log (python 3.6).

Usage: python3 -I profile_dtxqcd_log.py <run.log>

Sums, per trajectory (lines between "Total H before" and "Total time for
trajectory"), the integrator's "[l][m] P update elapsed time" per monomial, the
rational action's "deriv timing" sub-timers, the multishift solves, the stout
smearing and the smeared-force chain rule, and prints what is left unaccounted.
"""
import re
import sys
from collections import OrderedDict

STAMP = re.compile(r'^Grid : \w+ : +([0-9.]+) s : ')
PUPD = re.compile(r'(\[\d\]\[\d\]) P update elapsed time: ([0-9.]+) ms \(force: ([0-9.]+) ms\)')
MONO = re.compile(r'update_P : Level (\[\d\]\[\d\]) (\S+)')
DERIV = re.compile(r'\[(\w+)\] deriv timing: (.*)')
KV = re.compile(r'([A-Za-z-]+)=([0-9.]+)')
MSCG = re.compile(r'\[(DTXQCDMultiShiftCG\w*)\] converged iter=(\d+) nshift=(\d+)')
SMEAR = re.compile(r'Smearing in ([0-9.]+) ms')
CHAIN = re.compile(r'Smeared Force chain rule took ([0-9.]+) ms')
TOTAL = re.compile(r'Total time for trajectory \(s\): ([0-9.]+)')
HBEFORE = re.compile(r'Total H before trajectory')
DH = re.compile(r'dH = (\S+)')


def new_traj():
    return {'pupd': OrderedDict(), 'deriv': OrderedDict(), 'mscg': OrderedDict(),
            'smear': [0, 0.0], 'chain': [0, 0.0], 'total': None, 'dH': None}


def add(d, key, n, *vals):
    cur = d.setdefault(key, [0] + [0.0] * len(vals))
    cur[0] += n
    for i, v in enumerate(vals):
        cur[i + 1] += v


def main(path):
    names = {}
    trajs = []
    cur = None
    last_mscg_t = None
    with open(path, 'r', errors='replace') as f:
        for line in f:
            m = MONO.search(line)
            if m:
                names[m.group(1)] = m.group(2)
            if HBEFORE.search(line):
                cur = new_traj()
                trajs.append(cur)
                continue
            if cur is None:
                continue
            m = PUPD.search(line)
            if m:
                add(cur['pupd'], m.group(1), 1, float(m.group(2)) / 1e3, float(m.group(3)) / 1e3)
                continue
            m = DERIV.search(line)
            if m:
                for k, v in KV.findall(m.group(2)):
                    add(cur['deriv'], k, 1, float(v))
                continue
            m = MSCG.search(line)
            if m:
                add(cur['mscg'], m.group(1), 1, float(m.group(2)))
                continue
            m = SMEAR.search(line)
            if m:
                cur['smear'][0] += 1
                cur['smear'][1] += float(m.group(1)) / 1e3
                continue
            m = CHAIN.search(line)
            if m:
                cur['chain'][0] += 1
                cur['chain'][1] += float(m.group(1)) / 1e3
                continue
            m = DH.search(line)
            if m and 'Total H after' in line:
                cur['dH'] = m.group(1)
                continue
            m = TOTAL.search(line)
            if m:
                cur['total'] = float(m.group(1))
                cur = None

    for i, t in enumerate(trajs):
        print('=== trajectory %d  total %s s  dH %s' % (
            i + 1, '%.1f' % t['total'] if t['total'] is not None else '(incomplete)', t['dH']))
        acc = 0.0
        for k, (n, el, fo) in t['pupd'].items():
            acc += el
            print('  P %s %-48s calls %5d  elapsed %8.2f s  force %8.2f s  per call %8.1f ms' % (
                k, names.get(k, '?'), n, el, fo, 1e3 * el / n))
        print('  U smearing                                             calls %5d  elapsed %8.2f s' % tuple(t['smear']))
        acc += t['smear'][1]
        print('  (inside P) smeared-force chain rule                    calls %5d  elapsed %8.2f s' % tuple(t['chain']))
        for k, (n, s) in t['deriv'].items():
            print('  (inside P) rational deriv %-12s calls %5d  total %8.2f s  per call %8.1f ms' % (
                k, n, s, 1e3 * s / n))
        for k, (n, it) in t['mscg'].items():
            print('  solves %-30s count %5d  mean iter %6.1f' % (k, n, it / n))
        if t['total'] is not None:
            print('  sum of P updates + smearing %.1f s, rest of trajectory %.1f s' % (acc, t['total'] - acc))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
