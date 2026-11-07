#!/usr/bin/env python3
# 附加分析: 生成 pilot 报告所需的表格
import numpy as np
import pandas as pd

RES = "/tmp/pilot/results"
df = pd.read_csv(f"{RES}/perquery_all.csv")
print(f"[load] {len(df)} rows")

# ---- 一致性检查: n_pos=1 时 mrr 与 auc 应满足 rank = n_valid+1 - (n_v+1 - auc*n_neg) ----
d1 = df[df.n_pos == 1].copy()
n_v = d1.n_pos + d1.n_neg
d1["rank_from_auc"] = n_v - d1.auc * d1.n_neg
d1["rank_from_mrr"] = 1.0 / d1.mrr
print("metric consistency (n_pos=1): median |rank diff| =",
      float(np.median(np.abs(d1.rank_from_auc - d1.rank_from_mrr))))

pd.set_option("display.width", 250)
pd.set_option("display.float_format", lambda v: f"{v:.4f}")

# ---- Table: 每类每方法 AUC 在 4 个 topN 下 ----
by_cmt = df.groupby(["kind", "method", "topn"]).agg(
    n=("auc", "size"), auc=("auc", "mean"), auc_sd=("auc", "std"),
    recall10=("recall10", "mean"), recall20=("recall20", "mean"),
    mrr=("mrr", "mean"), null_auc=("null_auc_mean", "mean"),
    sig=("p_auc", lambda x: (x <= 0.05).mean())).reset_index()
piv = by_cmt.pivot_table(index=["method", "topn"], columns="kind", values="auc")
print("\n=== AUC: method x topN, xpr vs cp ===")
print(piv.assign(diff=lambda d: d["cp"] - d["xpr"]).to_string())

print("\n=== per-method AUC averaged over topN ===")
m = by_cmt.groupby(["kind", "method"])["auc"].mean().unstack("kind")
print(m.assign(diff=lambda d: d["cp"] - d["xpr"]).to_string())

# ---- 每类最优配置（AUC / MRR / Recall@10）----
print("\n=== best config per class by metric ===")
for metric in ["auc", "mrr", "recall10", "recall20", "hit10"]:
    rows = []
    for k in ["xpr", "cp"]:
        g = df[df.kind == k].groupby(["method", "topn"])[metric].mean().sort_values(ascending=False)
        rows.append(f"{k}: {g.index[0][0]} topN={g.index[0][1]} {metric}={g.iloc[0]:.4f}")
    print(f"[{metric:8s}] " + " | ".join(rows))

# ---- per-cell ----
print("\n=== per-cell: best config & AUC of the class-optimal config ===")
best = {}
for k in ["xpr", "cp"]:
    g = df[df.kind == k].groupby(["method", "topn"])["auc"].mean().sort_values(ascending=False)
    best[k] = g.index[0]
    per_cell = df[(df.kind == k) & (df.method == best[k][0]) &
                  (df.topn == best[k][1])].groupby("cell")["auc"].agg(["size", "mean", "std"])
    print(f"\n[{k}] class-best = {best[k][0]} topN={best[k][1]}")
    print(per_cell.to_string())

# ---- 跨类 Spearman（不同切分）----
def rankdata(x):
    x = np.asarray(x, float)
    order = np.argsort(x, kind="stable")
    xs = x[order]
    uniq, inv, counts = np.unique(xs, return_inverse=True, return_counts=True)
    start = np.concatenate(([0.0], np.cumsum(counts)[:-1]))
    avg = start + (counts + 1) / 2.0
    r = np.empty(len(x)); r[order] = avg[inv]
    return r


def spear(a, b):
    return float(np.corrcoef(rankdata(a), rankdata(b))[0, 1])


print("\n=== cross-class Spearman (AUC) ===")
print(f"overall (20 method x topN configs): {spear(piv['xpr'].values, piv['cp'].values):.4f}")
for topn in [25, 50, 100, 200]:
    sub = piv.xs(topn, level="topn")
    print(f"  topN={topn:3d}: {spear(sub['xpr'].values, sub['cp'].values):.4f}")
for meth in piv.index.get_level_values(0).unique():
    sub = piv.xs(meth, level="method")
    print(f"  method={meth:5s}: {spear(sub['xpr'].values, sub['cp'].values):.4f}")

# ---- topN 最优方向 ----
print("\n=== xpr vs cp: AUC by topN (averaged over methods) ===")
print(by_cmt.groupby(["kind", "topn"])["auc"].mean().unstack("kind").to_string())

# ---- 分类别 null 与显著性 ----
print("\n=== null / significance ===")
for (k, meth, tn), g in by_cmt.set_index(["kind", "method", "topn"]).iterrows():
    if (k, meth, tn) in [("xpr", best["xpr"][0], best["xpr"][1]),
                         ("cp", best["cp"][0], best["cp"][1])]:
        print(f"  {k} {meth} topN={tn}: AUC={g['auc']:.4f} null={g['null_auc']:.4f} "
              f"sig_frac={g['sig']:.3f} recall10={g['recall10']:.4f} mrr={g['mrr']:.4f}")
