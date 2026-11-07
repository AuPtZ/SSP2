import numpy as np
import pandas as pd

df = pd.read_csv("/tmp/pilot/results/perquery_all.csv")

# n_pos per (kind, cell, query)
q = df[df.method == "XSum"].groupby(["kind", "cell"]).agg(
    n_queries=("query", "nunique"),
    n_pos_median=("n_pos", "median"),
    n_pos_mean=("n_pos", "mean"),
    n_pos_max=("n_pos", "max"),
    n_pos_min=("n_pos", "min"),
    n_negmedian=("n_neg", "median"),
)
print("=== queries / positives per dataset ===")
print(q.to_string())

print("\n=== n_pos distribution (xpr all) ===")
print(df[df.kind == "xpr"].drop_duplicates(["cell", "query"]).n_pos.value_counts().sort_index().to_string())
print("\n=== n_pos distribution (cp all) ===")
print(df[df.kind == "cp"].drop_duplicates(["cell", "query"]).n_pos.value_counts().sort_index().to_string())

# best config per cell by AUC and by MRR
print("\n=== per-cell best config ===")
for k in ["xpr", "cp"]:
    for cell in sorted(df[df.kind == k].cell.unique()):
        sub = df[(df.kind == k) & (df.cell == cell)]
        g = sub.groupby(["method", "topn"])[["auc", "mrr"]].mean()
        ba = g["auc"].idxmax(); bm = g["mrr"].idxmax()
        print(f"  {k:3s} {cell:7s}: AUC best {ba[0]}@{ba[1]}={g.loc[ba,'auc']:.4f} | "
              f"MRR best {bm[0]}@{bm[1]}={g.loc[bm,'mrr']:.4f}")
