The five metric tabs answer a different question from the classical ES / AUC curves. ES and AUC ask *"how strongly are the annotated drugs enriched"*, whereas these metrics ask **"when your signature contains the top-N genes, are the drugs you annotated as active pushed to the top of the ranking?"** — i.e. they evaluate the *ranking quality* of each signature search method (SSM).

| tab | metric | random value | what it measures |
|---|---|---|---|
| ES | unweighted (rank-based) GSEA enrichment score | 0 | replaces the old weighted ES, whose permutation null was off-centre (+0.26 instead of 0) |
| AUPRC | average precision | ≈ fraction of active drugs | sensitive under strong class imbalance (few active vs. many inactive) |
| Recall@K | recall in the **top 20 drugs** (K = 20 by default) | ≈ 20 / n_drugs | matches how you actually use the platform (take the top 20 drugs forward). K = 20 **drugs**, unrelated to TopN |
| EF@5% | enrichment factor in the top 5% of drugs | 1 | early-recognition of the true drugs |
| AUROC | area under the ROC curve | 0.5 | classical, threshold-free (the classical threshold-free metric; the legacy AUC tab has been retired) |

**How to read one metric tab.** The x-axis is the signature size being swept: **TopN** (number of up/down genes) in topN mode, or the **|log2FC| threshold** in logFC mode. The horizontal dashed line is the mean of the **permutation null** — the metric you would get if your annotated drugs were placed at random positions in the ranking; the two dotted lines are its 95% interval. A curve above the dotted band means that at this signature size the method ranks your drugs better than chance. The permutation null does not depend on TopN, so the band is horizontal.

**The table below the chart has the same shape as the AUC and ES tables**: the first column is the swept signature size (**TopN**, or the |log2FC| threshold in logFC mode) and each signature search method occupies one column, so methods can be compared side by side at a given signature size. Rows are sorted by the best value reached by any method (descending — higher is better for all five metrics) and the best cell of the first row is highlighted in yellow. The two trailing columns `null_mean` and `null_q975` repeat the permutation null for this metric at every signature size, so a number can be judged directly against it: **a value above `null_q975` means that method ranks your drugs better than chance at that signature size**.

**Significance** is reported on the **Summary tab**, where each method × metric cell carries a permutation *p* (< 0.05, ties counted) computed for every swept signature size; a cell is starred when more than half of the signature sizes are significant. For the discrete metrics (Recall@K, EF@K%) read the star together with the number of actives in the job information panel, because their p-values are coarse at small active counts.

**Which number should I trust?** Start with the **sig** column — a method that is not significantly better than random should not be taken forward. Among the significant ones, **Recall@20** corresponds most directly to your downstream use (take the top 20 drugs into the next experiment), while **AUPRC** is the better choice when comparing methods under heavy class imbalance. Do not average several metrics into one score: the disagreement between them is itself information (a method may excel only at the head of the ranking).

**A single query is noisy.** Most annotations contain only 5-26 active drugs, so one curve rarely separates methods. Draw conclusions from several queries (for example one query per mechanism-of-action class) rather than from a single run.
