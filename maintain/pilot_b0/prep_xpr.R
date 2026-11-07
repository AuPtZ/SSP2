#!/usr/bin/env Rscript
# ============================================================
# Pilot 数据准备 (xpr / CRISPR-KO): 导出 guide 级 trt_xpr 矩阵到 /tmp
#
# 目的: 做“留一 guide 自检索”需要 guide 级（未按靶基因聚合）的签名矩阵。
#   M[g, s] = level5 moderated z-score, 行 = 12,328 landmark genes (canonical 顺序),
#   列 = 单个 guide 签名 (colnames = sig_id)
#   另存列注释: sig_id, pert_id, gene(=cmap_name 靶基因), cell, pert_time
#
# 输出 ( /tmp/pilot/data/ ):
#   xpr_<cell>.bin        float64 列主序矩阵 (G x N)
#   xpr_<cell>.dims       "G <n>" / "N <n>"
#   xpr_<cell>_cols.csv   列注释
#
# 只读原始 gctx；不写 data_preload。
# 用法: /usr/lib/R/bin/Rscript /tmp/pilot/prep_xpr.R
# ============================================================
suppressPackageStartupMessages({ library(cmapR); library(data.table) })

ROOT <- "/home/data/auptz/rprojects/SSP2"
BASE <- "/home/data/dataportal/LINCS2020"
OUT  <- "/tmp/pilot/data"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

CELLS <- c("U251MG", "A549", "PC3", "MCF7")
GCTX  <- file.path(BASE, "level5_beta_trt_xpr_n142901x12328.gctx")

e <- new.env(); load(file.path(ROOT, "data_preload/others/gene_info.rdata"), envir = e)
gene_info <- get("gene_info", envir = e)
gene_order <- gene_info$pr_gene_symbol
eid <- gene_info$pr_gene_id
stopifnot(!anyDuplicated(gene_order), !anyDuplicated(eid))

si <- fread(file.path(BASE, "siginfo_beta.txt"), sep = "\t", showProgress = FALSE,
  select = c("sig_id", "pert_type", "pert_id", "cmap_name", "cell_iname",
             "pert_time", "qc_pass"))
si[, qc_pass := suppressWarnings(as.integer(qc_pass))]
sel_all <- si[pert_type == "trt_xpr" & qc_pass == 1L & cmap_name != ""]

for (cell in CELLS) {
  sel <- sel_all[cell_iname == cell & pert_time == 96]
  cat(sprintf("\n=== [%s] %d guide signatures / %d target genes ===\n",
              cell, nrow(sel), uniqueN(sel$cmap_name)))
  if (nrow(sel) == 0L) { cat("  [SKIP] 无签名\n"); next }
  t0 <- Sys.time()
  mat <- tryCatch({
    gct <- parse_gctx(GCTX, cid = sel$sig_id, matrix_only = FALSE)
    gct@mat
  }, error = function(er) { cat("  [ERROR] ", conditionMessage(er), "\n"); NULL })
  if (is.null(mat)) next
  stopifnot(all(sel$sig_id %in% colnames(mat)))
  mat <- mat[, match(sel$sig_id, colnames(mat)), drop = FALSE]

  # 行按 canonical gene 顺序（所有 level5 文件基因集合相同，按 ENTREZ 校验）
  rid <- suppressWarnings(as.integer(rownames(mat)))
  idx <- match(eid, rid)
  if (anyNA(idx)) stop(sprintf("%s: %d 个基因在 gctx 中缺失", cell, sum(is.na(idx))))
  mat <- mat[idx, , drop = FALSE]
  rownames(mat) <- gene_order

  fbin <- file.path(OUT, sprintf("xpr_%s.bin", cell))
  con <- file(fbin, "wb"); writeBin(as.numeric(mat), con, size = 8); close(con)
  writeLines(c(sprintf("G %d", nrow(mat)), sprintf("N %d", ncol(mat))),
             file.path(OUT, sprintf("xpr_%s.dims", cell)))
  fwrite(data.table(sig_id = colnames(mat), pert_id = sel$pert_id,
                    gene = sel$cmap_name, cell = cell, pert_time = sel$pert_time),
         file.path(OUT, sprintf("xpr_%s_cols.csv", cell)))
  cat(sprintf("  [DONE] %d x %d | %.0f MB | %.1fs | %s\n",
              nrow(mat), ncol(mat), file.size(fbin) / 1e6,
              as.numeric(difftime(Sys.time(), t0, units = "secs")), fbin))
  rm(mat, gct); gc()
}
cat("\n[prep_xpr] 全部完成\n")
