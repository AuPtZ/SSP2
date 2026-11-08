This tab is the **overview** of the whole Benchmark run: every signature search method (SSM) against every ranking-quality metric, summarised in one picture. Use it first — the per-metric tabs that follow are the detail view.

**The heat map.** Rows are the seven SSMs, columns are the five metrics. Each tile shows

- **colour** = `(median − null mean) / (null 95% − null mean)`, where the null is the label-permutation reference. **1.0 (white) means the method's median is exactly at the 95% percentile of what random labelling produces**; blue = below the null mean, red = above the 95% line. The scale is capped at 2.0 so that a single exceptional method cannot flatten the rest.
- **cell text** = the raw median of that metric over the swept signature sizes (TopN or the |log2FC| threshold).
- **\*** = **significant**: more than half of the swept signature sizes give a one-sided permutation *p* < 0.05 for that method × metric. The permutation p counts ties (*P*(null ≥ observed)), which is the correct one-sided test.

Because the five metrics have completely different units (AUROC ≈ 0.5, EF can reach 20, ES spans negative to positive), they cannot be compared on a raw scale — hence the null-relative colouring.

**The table below** lists the same numbers without colour coding: `median`, `max` over the sweep, the two null reference values, `rel_null` (the colour value), `p_best` (the smallest permutation p reached anywhere in the sweep), `frac_p05` (the fraction of signature sizes with p < 0.05 — the criterion behind the asterisk) and `sig`.

**How to use it.** Pick the method whose row is red across several metrics — that is a method that beats random consistently rather than on a single metric. A row that is red on one metric and blue on another is telling you something real about that method (e.g. it is good at the head of the ranking but poor overall), so do not average the tiles into a single score.
