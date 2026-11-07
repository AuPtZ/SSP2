#!/usr/bin/env python3
# cp (化合物) 留一条件协议 sanity check:
#   同一药物不同 (dose,time) 条件之间的签名相关性 vs 随机药物对
#   以及原始 Pearson 相关下"同药其他条件"的 rank percentile
import sys
import numpy as np
import pandas as pd

CELL = sys.argv[1] if len(sys.argv) > 1 else "MCF7"
prefix = f"/tmp/pilot/data/cp_{CELL}"
dims = dict(l.split() for l in open(prefix + ".dims"))
G, N = int(dims["G"]), int(dims["N"])
M = np.fromfile(prefix + ".bin", dtype=np.float64).reshape((G, N), order="F")
cols = pd.read_csv(prefix + "_cols.csv")
print(f"[load] cp_{CELL}: {G} x {N} ({cols['condition'].nunique()} conditions, "
      f"{cols['drug'].nunique()} drugs)")

# z-score columns (correlation = mean of products)
M -= M.mean(0, keepdims=True)
sd = M.std(0, keepdims=True); sd[sd == 0] = 1
M /= sd

rng = np.random.default_rng(42)
groups = cols.groupby("drug").indices
elig = [g for g, ix in groups.items() if len(ix) >= 2]
print(f"drugs with >=2 conditions: {len(elig)} / {len(groups)}; "
      f"conds per drug: {pd.Series([len(v) for v in groups.values()]).value_counts().head(8).to_dict()}")
print(f"n_pos (other conditions) median: "
      f"{np.median([len(groups[g]) - 1 for g in elig]):.0f}")

n_pair = 400
same, rand = [], []
for g in rng.choice(elig, size=n_pair, replace=False):
    ix = groups[g]
    a, b = rng.choice(ix, size=2, replace=False)
    same.append(float(np.mean(M[:, a] * M[:, b])))
    c, d = rng.choice(N, size=2, replace=False)
    rand.append(float(np.mean(M[:, c] * M[:, d])))
same, rand = np.array(same), np.array(rand)
print(f"[pair] same-drug diff-condition corr: mean={same.mean():.3f} median={np.median(same):.3f} "
      f"q10={np.quantile(same,0.1):.3f} q90={np.quantile(same,0.9):.3f}")
print(f"[pair] random pair corr             : mean={rand.mean():.3f} median={np.median(rand):.3f} "
      f"q90={np.quantile(rand,0.9):.3f}")

qs = rng.choice(elig, size=150, replace=False)
pct = []
for g in qs:
    ix = groups[g]
    q = int(rng.choice(ix, size=1)[0])
    pos = [i for i in ix if i != q]
    c = M[:, q] @ M / G
    r = 1.0 - (np.argsort(np.argsort(-c, kind="stable"), kind="stable") + 1) / N
    pct.extend(r[pos].tolist())
pct = np.array(pct)
print(f"[rank] other-condition correlation percentile: mean={pct.mean():.3f} "
      f"median={np.median(pct):.3f} q90={np.quantile(pct,0.9):.3f}; "
      f"top-1%={np.mean(pct>=0.99):.3f} top-10%={np.mean(pct>=0.90):.3f}")
