#!/usr/bin/env python3
# ============================================================
# Pilot 结果汇总: 读 perquery_<kind>_<cell>.csv, 输出
#   1) by class x method x topN 的 AUC/Recall/MRR/置换 null
#   2) by cell x method x topN
#   3) 跨类方法/topN 排名比较 (Spearman)
# ============================================================
import glob, os
import numpy as np
import pandas as pd

RES = "/tmp/pilot/results"
files = sorted(f for f in glob.glob(os.path.join(RES, "perquery_*.csv"))
               if not f.endswith("perquery_all.csv"))
assert files, "没有 perquery 结果"
df = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
df.to_csv(os.path.join(RES, "perquery_all.csv"), index=False)
print(f"[load] {len(files)} files, {len(df)} rows, "
      f"kinds={df['kind'].unique().tolist()}, cells={df['cell'].unique().tolist()}")


def agg_by(keys):
    g = df.groupby(keys)
    out = g.agg(
        n_queries=("auc", "size"),
        auc=("auc", "mean"), auc_sd=("auc", "std"),
        null_auc=("null_auc_mean", "mean"),
        null_auc_q95=("null_auc_q95", "mean"),
        recall10=("recall10", "mean"), recall20=("recall20", "mean"),
        hit10=("hit10", "mean"), hit20=("hit20", "mean"),
        mrr=("mrr", "mean"), null_mrr=("null_mrr_mean", "mean"),
        p_auc=("p_auc", "median"), frac_sig_auc=("p_auc", lambda x: (x <= 0.05).mean()),
    ).reset_index()
    out["auc_over_null"] = out["auc"] - out["null_auc"]
    return out


by_class = agg_by(["kind", "method", "topn"])
by_cell = agg_by(["kind", "cell", "method", "topn"])
by_class.to_csv(os.path.join(RES, "summary_by_class_method_topn.csv"), index=False)
by_cell.to_csv(os.path.join(RES, "summary_by_cell_method_topn.csv"), index=False)

pd.set_option("display.width", 200)
pd.set_option("display.float_format", lambda v: f"{v:.4f}")
print("\n================ by class x method x topN ================")
print(by_class[["kind", "method", "topn", "n_queries", "auc", "auc_sd",
                "null_auc", "recall10", "recall20", "mrr", "null_mrr",
                "frac_sig_auc"]].to_string(index=False))

# ---------------- 跨类排名比较 ----------------
print("\n================ cross-class rank comparison ================")
cfg = by_class.pivot_table(index=["method", "topn"], columns="kind",
                           values=["auc", "mrr", "recall10"])


def rankdata_average(x):
    x = np.asarray(x, dtype=float)
    order = np.argsort(x, kind="stable")
    xs = x[order]
    uniq, inv, counts = np.unique(xs, return_inverse=True, return_counts=True)
    start = np.concatenate(([0.0], np.cumsum(counts)[:-1]))
    avg = start + (counts + 1) / 2.0
    r = np.empty(len(x)); r[order] = avg[inv]
    return r


def spearman(a, b):
    return float(np.corrcoef(rankdata_average(a), rankdata_average(b))[0, 1])


if set(cfg["auc"].columns) == {"cp", "xpr"}:
    tab = cfg["auc"].dropna()
    sp = spearman(tab["xpr"].values, tab["cp"].values)
    sp_mrr = spearman(cfg["mrr"].dropna()["xpr"].values,
                      cfg["mrr"].dropna()["cp"].values)
    print(tab.sort_values("xpr", ascending=False).to_string())
    print(f"\nSpearman(AUC_xpr, AUC_cp) over {len(tab)} method x topN configs = {sp:.3f}")
    print(f"Spearman(MRR_xpr, MRR_cp) = {sp_mrr:.3f}")
    print("\nbest config per class (by mean AUC):")
    for k in ["xpr", "cp"]:
        sub = by_class[by_class["kind"] == k].sort_values("auc", ascending=False)
        top1 = sub.iloc[0]
        print(f"  {k}: {top1['method']} topN={int(top1['topn'])} AUC={top1['auc']:.4f} "
              f"(2nd: {sub.iloc[1]['method']} topN={int(sub.iloc[1]['topn'])} "
              f"AUC={sub.iloc[1]['auc']:.4f})")
    best_x = by_class[by_class["kind"] == "xpr"].sort_values("auc", ascending=False).iloc[0]
    best_c = by_class[by_class["kind"] == "cp"].sort_values("auc", ascending=False).iloc[0]
    print(f"\nbest-AUC gap |xpr-cp| = {abs(best_x['auc'] - best_c['auc']):.4f}")
    print(f"best method same? {best_x['method'] == best_c['method']}; "
          f"best topN same? {int(best_x['topn']) == int(best_c['topn'])}")
    # 每个方法自己的最优 topN
    print("\nbest topN per method:")
    for k in ["xpr", "cp"]:
        sub = by_class[by_class["kind"] == k]
        print(f"  [{k}] " + "; ".join(
            f"{m}:{int(s.sort_values('auc', ascending=False).iloc[0]['topn'])}"
            f"({s.sort_values('auc', ascending=False).iloc[0]['auc']:.3f})"
            for m, s in sub.groupby("method")))
    cfg.to_csv(os.path.join(RES, "crossclass_matrix.csv"))
    with open(os.path.join(RES, "crossclass_stats.txt"), "w") as f:
        f.write(f"spearman_auc={sp:.4f}\nspearman_mrr={sp_mrr:.4f}\n")
else:
    print("[warn] 只有一类结果，跳过跨类比较")
