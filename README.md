# SSP2 — Signature Search Polestar 2

A free, open-access R/Shiny webserver for signature-based drug and perturbation search:
**Benchmark** evaluates seven signature search methods (SSMs) and selects the best method
and signature size for a user-supplied query signature on compound datasets; **Application**
queries candidate compounds (single method, SS_all, SS_cross) and also ranks **CRISPR
knockout target genes** (`LINCS-CRISPR` data source, with an offline method/topN
calibration panel); **Converter** maps gene and drug identifiers; **Job Center** retrieves
asynchronous results.

- Live server: <https://web.biotcm.net/SSP2/>
- Source code: <https://github.com/AuPtZ/SSP2>
- Licence (code): [Mulan Permissive Software License v2](LICENSE)
- Previous version: Zhang J *et al.*, *Bioinformatics* 2024;40(9):btae536.
  doi:10.1093/bioinformatics/btae536 (PubMed 39213324)

---

## Data provenance

SSP2 does not generate new experimental data. It redistributes **derived** drug-response
profiles computed from two public resources. This section records the exact inputs so the
build can be reproduced and audited.

### 1. LINCS2020 beta (CMap LINCS 2020 release)

| Item | Value |
|---|---|
| Resource | Broad Institute CLUE, "CMap2020 / LINCS2020" (Phase 2 L1000 release, December 2020) |
| Original entry point | `https://clue.io/data/CMap2020#LINCS2020` |
| Primary data file | `level5_beta_trt_cp_n720216x12328.gctx` |
| File size | 35,518,405,386 bytes |
| SHA-256 | `fbb04a94d8aa8a4fa6daf01f7d94dcd938fb9b7937730f81bfba3d8d0f1472a8` |
| Local snapshot date | 2024-07-01 |
| Signature metadata | `siginfo_beta.txt`, 465,242,319 bytes, SHA-256 `1a38d7ea2a804be79804af4a27aff9f2537af8f13d3c8af1fdc1fef780f40201` |
| Cell-line metadata | `cellinfo_beta.txt`, 37,979 bytes, SHA-256 `d26a08f7f290f6a94bff593cdea4dcfc3fe17177e05593cd381cb65aebc63fc2` |
| Dimensions | 720,216 Level-5 compound-treatment (`trt_cp`) signatures x 12,328 genes |

The file name contains `beta` because that is the official release name; **no newer L1000
release supersedes it** (the LINCS program has concluded, and L1000 data generation ended
with this release). The 12,328 genes consist of **978 directly measured L1000 landmark
genes** (see `data_preload/others/landmark.rdata`) plus computationally inferred genes.

**Processing** (`maintain/00_生成基因映射和组合信息.R`, `maintain/01处理数据预生成.R`):
map Entrez IDs to gene symbols; retain `pert_type == "trt_cp"` signatures with
`qc_pass == 1`; collapse doses with the `nearest_dose` field; group by
`(cell_iname, nearest_dose, pert_time)`; average signatures per compound (`cmap_name`).
This yields 687 dataset files (`data_preload/drugexp/LINCS_*.rdata`) covering **155 tumor
cell lines**, multiple doses, and 6 h / 24 h treatment times. Each file contains
`exp_LINCS2020` (genes x drugs matrix) and `sig_LINCS2020` (signature annotation).

**Availability note.** The CLUE portal was retired on 2026-01-31; its public data are
archived at NCBI GEO (the L1000 series include GSE70138 and GSE92742). When citing the
source data, prefer a stable GEO accession or DOI over the retired `clue.io` URL.

### 2. Tahoe-100M

| Item | Value |
|---|---|
| Resource | Tahoe-100M single-cell drug-perturbation atlas (Tahoe Biosciences / Parse Biosciences) |
| Upstream object used | official `pseudobulk_differential_expression` tables (DESeq2 log2FC vs plate-matched DMSO controls) |
| Gene space | 62,710 genes (Ensembl 109 / GRCh38) |
| Drugs | 379 |
| Doses | 0.05, 0.5, 5 uM |
| Treatment time | 24 h (single time point) |
| Cell lines | 47 individual lines + 1 pan-cell-line aggregate ("PAN") |
| Resulting profiles | 144 files (`Tahoe_*.rdata`) = 48 x 3 doses |
| Source licence | CC0 1.0 (public-domain dedication) |

**Processing** (`tahoe_prep/00_common.R`, `02_build_cells.R`, `03_export_profiles.R`):
start from the official pseudobulk differential-expression tables; require at least
`MIN_CELLS = 50` cells in both treated and control conditions; exclude three
low-abundance cell lines (NCI-H661, NCI-H596, NCI-H2122) following the source paper;
build one genes x drugs matrix per `(cell line, dose)` from `log2FoldChange`, filling
missing values with 0; build the PAN aggregate by averaging across cell lines. All
profiles are labelled `pert_time = 24`.

The single-cell nature of Tahoe-100M exists only in the upstream raw data (~100 million
cells). SSP2 consumes the published **pseudobulk** differential-expression summaries,
in which individual cells have already been collapsed into one value per condition;
`n_cells_trt` / `n_cells_ctrl` are retained only for QC.

### 3. CRISPR knockout signatures (route B addition)

| Item | Value |
|---|---|
| Resource | LINCS2020 beta CRISPR knockout, `level5_beta_trt_xpr_n142901x12328.gctx` |
| Signatures | 140,945 Level-5 `trt_xpr` signatures |
| Target genes / cell lines | 5,158 target genes; 27 cell lines |
| Time point | single 96 h |
| Filtering | `pert_type == "trt_xpr" & qc_pass == 1 & cmap_name != ""`; guides averaged per target gene |
| Derived datasets | **19** `LINCSxpr_<cell>_96h.rdata` (cell lines with >=100 target genes; ~5,000 target genes each) |
| Resulting profiles | 53,262 target-gene columns, ~3.2 GB |
| Registry | `data_preload/others/dataset_registry.rdata` (850 rows = 687 LINCS cp + 144 Tahoe + 19 xpr) |
| Calibration | `data_preload/others/calibration_pilot.rdata`, built by `maintain/15_build_calibration.R` from the B0 pilot summary tables in `maintain/pilot_b0/results/` |

In the Application module these datasets are exposed as data source `LINCS-CRISPR`; the
ranked entities are **target genes** (negative score = knockout reverses the query
signature), drug-detail popups are disabled, and an **offline** method/topN calibration
derived from a leave-one-guide-out self-retrieval pilot is shown for each cell line. The
calibration is a starting point, not a per-job calibrated recommendation; the pilot's
guide-level reproducibility is weak (same-gene guide correlation 0.03-0.08) and the pilot
should be re-run on aggregated matrices before publication. Benchmark mode for genetic
perturbations is **not** implemented yet.

### 4. Annotation resources

Drug identifier mapping uses LINCS compound metadata (`pert_iname`, `pert_id`,
`pubchem_cid`, `canonical_smiles`, `inchi_key`); result pages link to PubChem and ChEMBL,
and users can source annotations from DrugBank / ClinicalTrials.gov as described in Help Q6.
Gene identifier conversion uses Ensembl, UniProt and `org.Hs.eg.db`. These are third-party
resources with their own terms of use; they are queried or linked, not redistributed.

### 5. Licence and usage of the derived profiles

- SSP2 source code is released under **MulanPSL-2.0** (see `LICENSE`).
- **Tahoe-100M** is released under **CC0 1.0**; derived profiles may be reused with
  attribution to the source resource.
- **LINCS/CMap data** (both compound `trt_cp` and CRISPR knockout `trt_xpr` derived
  profiles) were obtained under the CLUE terms of use, which restrict access to
  academic / non-profit research use and do not permit redistribution of the original
  data files. SSP2 therefore ships **derived average profiles**, not the original GCTX
  files; users who need the original data should obtain them from GEO or the LINCS Data
  Portal and observe the original terms.
- Users publishing results obtained with SSP2 should cite the LINCS/CMap and Tahoe-100M
  resources and the SSP v1 paper (doi:10.1093/bioinformatics/btae536).

---

## Reproducing the derived profiles

```bash
cd /path/to/SSP2
Rscript maintain/00_生成基因映射和组合信息.R   # gene map + cell/dose/time combinations
Rscript maintain/01处理数据预生成.R              # build data_preload/drugexp/*.rdata
Rscript maintain/02获取选项文件.R                # dataset selector + display names (compound only)
# Tahoe-100M profiles: tahoe_prep/00_common.R -> 02_build_cells.R -> 03_export_profiles.R
# Route-B CRISPR KO profiles + registry:
Rscript maintain/13_build_xpr.R                  # build data_preload/drugexp/LINCSxpr_*.rdata
Rscript maintain/14_build_dataset_registry.R     # build data_preload/others/dataset_registry.rdata
Rscript maintain/15_build_calibration.R          # offline method/topN calibration table
```

The `tahoe_prep/` scripts and the `maintain/` scripts are included in this repository;
they read the raw resources from a local data portal and write the derived profiles into
`data_preload/drugexp/`. The original expression files (`data_preload/`, ~26 GB), the
raw LINCS/Tahoe source data and the production result database
(`results/resinfo.db`) are **not** part of the source tree; they must be obtained from
their original providers.

## MCP interface for AI clients

`mcp/` provides an optional [Model Context Protocol](https://modelcontextprotocol.io/)
server that exposes SSP2's read-only queries, ID conversion and asynchronous compute
submission to local AI clients. It requires Python 3.10+ with `fastmcp` and the same R
environment as the webserver. See `mcp/README.md` for setup, the tool list and the
**security limitations** (no authentication by default; do not expose the HTTP transport
to an untrusted network without adding access control).
