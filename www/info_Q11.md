### Frequently asked questions

#### 1. How is a query signature defined?
In SSP2, a query signature is a **two-column table** (`Gene`, `log2FC`) derived from
differential expression analysis of tumor cell lines, animal models or patient cohorts
(e.g. ICGC, TCGA, GEO). We recommend using statistically significant genes (adjusted
p-value / FDR < 0.05), with at least 10 up-regulated and 10 down-regulated genes. Hover the
**?** icon next to each input step for the exact file format, or use the **Converter** page
to map other identifiers to gene symbols.

#### 2. How should I choose a drug profile dataset?
SSP2 provides three data sources: **LINCS2020 beta** (155 tumor cell lines, 12,328 landmark
genes, multiple doses and 6 h / 24 h time points), **Tahoe-100M** (47 cell lines plus a
pan-cell-line aggregate, three doses, 62,710 genes, 24 h) and **LINCS-CRISPR** (19 cell
lines, CRISPR knockout signatures at 96 h, ~5,000 target genes each). Choose a dataset whose
cell line or tissue is close to the cancer of interest and that contains many perturbations.

Because the optimal treatment time and dose are not known in advance, we encourage running
**several datasets** and looking for drugs that rank consistently high across doses, time
points and cell lines - such consistency is more likely to reflect a real effect. For
LINCS2020, the commonly used conditions are 10 uM at 6 h or 24 h; Tahoe-100M profiles are
all at 24 h.

#### 3. Can I retrieve a result later without keeping the page open?
Yes. Each submission returns a job ID and a bookmarkable link of the form
`.../?job=<jobid>`. Bookmark it: reopening the link loads the Job Center with the result or
its current queued / running / finished status. Keep the link private, because the job ID
is the access credential for your uploaded data.

#### 4. Where can I find example input and results?
Every module has a **demo** button that loads example input automatically, and the
**Info → Data** page provides downloadable demo files and example results. Step-by-step
guides are in the **Info → Help** pages.

#### 5. Can I query CRISPR knockout perturbations?
Yes. In the **Application** module choose data source **`LINCS-CRISPR`** (19 cell lines,
96 h). The ranked entities are then **target genes**: a negative score means that knocking
out that gene produces a transcriptional response opposite to your query signature
(a candidate target), while a positive score indicates mimicry. Drug-detail popups are
disabled for these datasets. Because method/topN benchmarking for genetic perturbations is
not yet available in the Benchmark module, the Application shows an **offline pilot
calibration** for the selected cell line (leave-one-guide-out self-retrieval, AUC against a
permutation null). Treat it as a starting point, not as a per-job calibrated recommendation.
