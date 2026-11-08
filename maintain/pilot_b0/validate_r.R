#!/usr/bin/env Rscript
# ============================================================
# 内核对拍：用 R/SS.R 原生 *_i 函数在小型矩阵上算分，供 Python 内核逐值比较
#
# 输入: data_preload/drugexp/LINCSxpr_U251MG_96h.rdata (聚合矩阵)
# 输出: /tmp/pilot/val/val_M.bin, val_genes.txt, val_cols.txt, r_scores.csv
# 用法: /usr/lib/R/bin/Rscript /tmp/pilot/validate_r.R
# ============================================================
suppressPackageStartupMessages({ library(data.table) })
setwd("/tmp/pilot")
dir.create("val", showWarnings = FALSE, recursive = TRUE)
dir.create("cache/SS", showWarnings = FALSE, recursive = TRUE)

ROOT <- "/home/data/auptz/rprojects/SSP2"
t0 <- Sys.time()
e <- new.env(); load(file.path(ROOT, "data_preload/drugexp/LINCSxpr_U251MG_96h.rdata"), envir = e)
M <- get("exp_LINCS2020", envir = e)
cat(sprintf("[load] %d x %d in %.1fs\n", nrow(M), ncol(M),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

set.seed(20261108)
cols <- sort(sample(colnames(M), 2000))
Msub <- M[, cols]
rm(M); gc()
genes <- rownames(Msub)
writeBin(as.numeric(Msub), file.path("val", "val_M.bin"), size = 8)
writeLines(genes, file.path("val", "val_genes.txt"))
writeLines(colnames(Msub), file.path("val", "val_cols.txt"))

source(file.path(ROOT, "R/SS.R"))   # 定义 *_i 函数（if(T) 分支）

TOPN <- c(25, 200)
qsamp <- colnames(Msub)[c(1, 500, 1500)]
rows <- list()
for (qc in qsamp) {
  v <- Msub[, qc]
  o <- order(v, decreasing = TRUE)
  for (topN in TOPN) {
    up <- rownames(Msub)[o[1:topN]]
    dn <- rownames(Msub)[o[(nrow(Msub) - topN + 1):nrow(Msub)]]
    qv <- c(setNames(Msub[c(up, dn), qc], c(up, dn)))   # XCos 查询向量
    cat(sprintf("  query=%s topN=%d\n", qc, topN))
    calls <- list(
      XSum  = function() XSumScore_i(Msub, up, dn, topN = topN),
      CMap  = function() KSScore_i(Msub, up, dn),
      GSEA  = function() GSEAweight1Score_i(Msub, up, dn),
      Zhang = function() ZhangScore_i(Msub, up, dn),
      XCos  = function() XCosScore_i(Msub, qv, topN = nrow(Msub) / 2)
    )
    for (m in names(calls)) {
      tt <- Sys.time()
      sc <- calls[[m]]()
      rows[[length(rows) + 1]] <- data.table(
        query_col = qc, topN = topN, method = m,
        ref_col = rownames(sc), score = sc$Score)
      cat(sprintf("    %-5s %4d cols %.1fs\n", m, nrow(sc),
                  as.numeric(difftime(Sys.time(), tt, units = "secs"))))
    }
  }
}
res <- rbindlist(rows)
fwrite(res, file.path("val", "r_scores.csv"))
cat(sprintf("[DONE] %d rows -> /tmp/pilot/val/r_scores.csv (%.1fs)\n", nrow(res),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
