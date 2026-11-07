#!/usr/bin/env Rscript
# ============================================================
# Pilot 数据准备 (cp / 化合物): 按细胞系池化现有多剂量/时间数据集
#
# 目的: cp 侧“留一条件自检索”：query = 某药某条件签名，真值 = 同一药物的其他条件。
#   对每个细胞系，把 data_preload/drugexp/LINCS_<cell>_<dose>_<time>.rdata
#   的 exp_LINCS2020 按基因行对齐后 cbind 成池化矩阵：
#       M[g, c] = 药物在该 (dose,time) 条件下的签名, 列名 = "<drug>@<dose>_<time>h"
#   另存列注释: col, drug(=cmap_name), dose_label, pert_time, condition, file
#
# 输出 ( /tmp/pilot/data/ ):
#   cp_<cell>.bin / .dims / _cols.csv      (float64 列主序, G x N_pooled)
#
# 只读 data_preload/drugexp；不写任何项目文件。
# 用法: /usr/lib/R/bin/Rscript /tmp/pilot/prep_cp.R
# ============================================================
suppressPackageStartupMessages({ library(data.table) })

ROOT <- "/home/data/auptz/rprojects/SSP2"
DRUGEXP <- file.path(ROOT, "data_preload/drugexp")
OUT  <- "/tmp/pilot/data"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

CELLS <- c("A549", "PC3", "MCF7")

e <- new.env(); load(file.path(ROOT, "data_preload/others/gene_info.rdata"), envir = e)
gene_info <- get("gene_info", envir = e)
gene_order <- gene_info$pr_gene_symbol

for (cell in CELLS) {
  files <- sort(list.files(DRUGEXP, pattern = sprintf("^LINCS_%s_.*\\.rdata$", cell)))
  cat(sprintf("\n=== [%s] %d 个条件数据集 ===\n", cell, length(files)))
  if (length(files) == 0L) next
  t0 <- Sys.time()
  mats <- vector("list", length(files))
  anns <- vector("list", length(files))
  for (i in seq_along(files)) {
    f <- files[i]
    cond <- sub("\\.rdata$", "", sub(sprintf("^LINCS_%s_", cell), "", f))
    ee <- new.env(parent = emptyenv())
    load(file.path(DRUGEXP, f), envir = ee)
    m <- get("exp_LINCS2020", envir = ee)
    s <- get("sig_LINCS2020", envir = ee)
    rm(ee); gc()
    # 基因行对齐到 canonical 顺序（所有 LINCS cp 数据集都应含全部 12,328 基因）
    if (!all(gene_order %in% rownames(m))) {
      miss <- setdiff(gene_order, rownames(m))
      stop(sprintf("%s: 缺少 %d 个基因（如 %s）", f, length(miss), paste(head(miss, 3), collapse = ",")))
    }
    m <- m[gene_order, , drop = FALSE]
    drug <- colnames(m)
    cond_lab <- sub("_", "__", cond)   # 仅用于显示, 不参与匹配
    colnames(m) <- paste0(drug, "@", cond)
    mats[[i]] <- m
    anns[[i]] <- data.table(col = colnames(m), drug = drug,
                            condition = cond,
                            dose_label = sub("_[0-9]+h$", "", cond),
                            pert_time = as.integer(sub(".*_([0-9]+)h$", "\\1", cond)),
                            file = f)
    cat(sprintf("  [%2d/%2d] %-38s %4d drugs\n", i, length(files), f, ncol(m)))
    if (i %% 10 == 0) gc()
  }
  pooled <- do.call(cbind, mats)
  ann <- rbindlist(anns)
  stopifnot(ncol(pooled) == nrow(ann))
  fbin <- file.path(OUT, sprintf("cp_%s.bin", cell))
  con <- file(fbin, "wb"); writeBin(as.numeric(pooled), con, size = 8); close(con)
  writeLines(c(sprintf("G %d", nrow(pooled)), sprintf("N %d", ncol(pooled))),
             file.path(OUT, sprintf("cp_%s.dims", cell)))
  fwrite(ann, file.path(OUT, sprintf("cp_%s_cols.csv", cell)))
  cat(sprintf("  [DONE] %d x %d | %.0f MB | %.1fs | drugs with >=2 cond: %d\n",
              nrow(pooled), ncol(pooled), file.size(fbin) / 1e6,
              as.numeric(difftime(Sys.time(), t0, units = "secs")),
              ann[, .N, by = drug][N >= 2, .N]))
  rm(pooled, mats, anns, ann); gc()
}
cat("\n[prep_cp] 全部完成\n")
