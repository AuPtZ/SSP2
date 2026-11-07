#!/usr/bin/env python3
# ============================================================
# 内核对拍 (Python 侧): 与 validate_r.R 在同一个 2,000 列小矩阵上算分,
# 逐 (query, method, topN, ref_col) 比较绝对值与排序。
# ============================================================
import sys
import numpy as np
import pandas as pd

sys.path.insert(0, "/tmp/pilot")
from run_pilot import precompute_ranks, score_all  # noqa

VAL = "/tmp/pilot/val"
genes = open(f"{VAL}/val_genes.txt").read().split()
cols = open(f"{VAL}/val_cols.txt").read().split()
M = np.fromfile(f"{VAL}/val_M.bin", dtype=np.float64).reshape((len(genes), len(cols)), order="F")
print(f"[load] {M.shape}")
Rank, SR, max_theo = precompute_ranks(M)
G, N = M.shape

qsamp = [cols[0], cols[499], cols[1499]]
topns = [25, 200]
rows = []
for qc in qsamp:
    qcol = cols.index(qc)
    order = np.argsort(-M[:, qcol], kind="stable")
    out = score_all(M, Rank, SR, max_theo, order, qcol, topns)
    for (m, topN), sc in out.items():
        rows.append(pd.DataFrame(dict(query_col=qc, topN=topN, method=m,
                                      ref_col=cols, score=sc)))
py = pd.concat(rows, ignore_index=True)

r = pd.read_csv(f"{VAL}/r_scores.csv")
mg = r.merge(py, on=["query_col", "topN", "method", "ref_col"], how="outer",
             suffixes=("_r", "_py"), indicator=True)
print("[merge]", mg["_merge"].value_counts().to_dict())
bad = mg[mg["_merge"] != "both"]
if len(bad):
    print("[warn] unmatched:\n", bad.head())
m = mg[mg["_merge"] == "both"].copy()
m["absdiff"] = (m["score_r"] - m["score_py"]).abs()
print("\n=== max abs diff by (method, topN) ===")
print(m.groupby(["method", "topN"])["absdiff"].agg(["max", "mean", "count"]).to_string())
print("\n=== ranking agreement ===")
for (meth, tn), g in m.groupby(["method", "topN"]):
    rr = g["score_r"].rank(ascending=False)
    pp = g["score_py"].rank(ascending=False)
    rho = np.corrcoef(rr, pp)[0, 1]
    print(f"  {meth:5s} topN={tn:3d}: spearman={rho:.8f}  max|diff|={g['absdiff'].max():.3e}")
worst = m.loc[m["absdiff"].idxmax()]
print(f"\nworst: {worst[['query_col','topN','method','ref_col']].to_dict()} "
      f"r={worst['score_r']!r} py={worst['score_py']!r}")
print(f"\noverall max abs diff = {m['absdiff'].max():.3e}")
assert m["absdiff"].max() < 1e-8, "内核与 R/SS.R 不一致!"
print("[OK] Python kernels numerically match R/SS.R")
