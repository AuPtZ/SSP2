#!/usr/bin/env python3
# xpr LOO 协议 sanity check:
#   同一基因的不同 guide 之间签名相关性 vs 随机 guide 对；
#   并用 Pearson 相关直接算"其他 guide"在全部 guide 中的 rank percentile
import numpy as np, pandas as pd, sys
CELL = sys.argv[1] if len(sys.argv) > 1 else "A549"
prefix = f"/tmp/pilot/data/xpr_{CELL}"
dims = dict(l.split() for l in open(prefix + ".dims"))
G, N = int(dims["G"]), int(dims["N"])
M = np.fromfile(prefix + ".bin", dtype=np.float64).reshape((G, N), order="F")
cols = pd.read_csv(prefix + "_cols.csv")
print(f"[load] {CELL}: {G} x {N}")

rng = np.random.default_rng(42)
groups = cols.groupby("gene").indices
elig = [g for g, ix in groups.items() if len(ix) >= 2]
print(f"genes with >=2 guides: {len(elig)} / {len(groups)}; "
      f"guide-per-gene: {pd.Series([len(v) for v in groups.values()]).value_counts().to_dict()}")

# 1) same-gene guide pair correlation vs random pair
Mcent = M - M.mean(0, keepdims=True)
sd = Mcent.std(0, keepdims=True); sd[sd == 0] = 1
Z = Mcent / sd

n_pair = 600
same, rand = [], []
for g in rng.choice(elig, size=n_pair, replace=False):
    ix = groups[g]
    a, b = rng.choice(ix, size=2, replace=False)
    same.append(float(np.mean(Z[:, a] * Z[:, b])))
    c, d = rng.choice(N, size=2, replace=False)
    rand.append(float(np.mean(Z[:, c] * Z[:, d])))
same, rand = np.array(same), np.array(rand)
print(f"[pair] same-gene guide corr: mean={same.mean():.3f} median={np.median(same):.3f} "
      f"q10={np.quantile(same,0.1):.3f} q90={np.quantile(same,0.9):.3f}")
print(f"[pair] random guide corr   : mean={rand.mean():.3f} median={np.median(rand):.3f} "
      f"q90={np.quantile(rand,0.9):.3f}")

# 2) rank percentile of other guides by raw Pearson corr with query guide
qs = rng.choice(elig, size=200, replace=False)
pct = []
for g in qs:
    ix = groups[g]
    q = int(rng.choice(ix, size=1)[0])
    pos = [i for i in ix if i != q]
    c = Z[:, q] @ Z / G                     # correlation of query with every column
    r = 1.0 - (np.argsort(np.argsort(-c, kind="stable"), kind="stable") + 1) / N  # percentile
    pct.extend(r[pos].tolist())
pct = np.array(pct)
print(f"[rank] other-guide correlation percentile: mean={pct.mean():.3f} "
      f"median={np.median(pct):.3f} q90={np.quantile(pct,0.9):.3f}; "
      f"top-1%={np.mean(pct>=0.99):.3f} top-10%={np.mean(pct>=0.90):.3f}")
