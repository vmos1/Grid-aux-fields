import re, sys
from collections import defaultdict
for path in sys.argv[1:]:
    mp = defaultdict(float); dp = defaultdict(float); nmp = ndp = 0
    traj = None
    for line in open(path, errors="replace"):
        if "Total time for trajectory" in line:
            traj = float(line.split(":")[-1])
        if "[DTXQCD-CG timing] mixed-prec" in line:
            nmp += 1
            body = line.split("(s):")[1]
            for k, v in re.findall(r"([A-Za-z+\-/]+)=([0-9.eE+-]+)", body):
                mp[k] += float(v)
        elif "[DTXQCD-CG timing] double-prec" in line:
            ndp += 1
            body = line.split("(s):")[1]
            for k, v in re.findall(r"([A-Za-z+\-/]+)=([0-9.eE+-]+)", body):
                dp[k] += float(v)
    print(path)
    print(f"  trajectory {traj} s;  mixed-prec solves {nmp}, double-prec solves {ndp}")
    keys = ["iters", "main-loop", "op", "hop", "site", "other", "precChange", "shift-updates",
            "reliable", "rest", "cleanup+verify", "time"]
    for k in keys:
        if k in mp:
            print(f"  MP {k:16s} total {mp[k]:9.2f}   per solve {mp[k]/max(nmp,1):8.3f}")
    for k in ["iters", "total", "op"]:
        if k in dp:
            print(f"  DP {k:16s} total {dp[k]:9.2f}   per solve {dp[k]/max(ndp,1):8.3f}")
