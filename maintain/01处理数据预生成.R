# ============================================================
# SSP2 数据预处理 - 步骤1: 从 gctx 预生成药物表达谱
#
# 功能:
#   对每个 (cell_line × nearest_dose × pert_time) 组合，
#   从 LINCS2020 gctx 提取全部 12,328 基因的表达谱，
#   按药物名 (cmap_name) 取均值后保存。
#
# 输出 (每个组合一个 .rdata):
#   - exp_LINCS2020: matrix[genes × drugs], rownames=gene_symbols
#   - sig_LINCS2020: siginfo subset (含 pert_iname 别名)
#
# 注: drug_rank_idx 不再预存，改为 Application 查询时按需计算（~1秒/次）
# ============================================================

library(cmapR)
library(data.table)
library(dplyr)
library(tidyr)

gctx_path       <- "/home/data/dataportal/LINCS2020/level5_beta_trt_cp_n720216x12328.gctx"
siginfo_path    <- "/home/data/dataportal/LINCS2020/siginfo_beta.txt"
gene_info_rdata <- "data_preload/others/gene_info.rdata"
comb_rdata      <- "data_preload/combinations.Rdata"
output_dir      <- "data_preload/drugexp/"

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ---- 加载预计算数据 ----
load(gene_info_rdata)
load(comb_rdata)
cat(sprintf("基因数: %d, 待处理组合数: %d\n", nrow(gene_info), nrow(combinations)))

# ---- 读取 siginfo ----
cat("读取 siginfo_beta.txt ...\n")
sig_all <- fread(siginfo_path, sep = "\t", header = TRUE,
  select = c("pert_type","cell_iname","pert_dose","pert_time",
             "nearest_dose","sig_id","cmap_name","qc_pass"),
  showProgress = TRUE)

sig_trt <- sig_all[pert_type == "trt_cp" & qc_pass == 1]
sig_trt[is.na(nearest_dose), nearest_dose := pert_dose]
rm(sig_all); gc()
sig_trt[, combo_key := paste(cell_iname, nearest_dose, pert_time, sep = "||")]
cat(sprintf("trt_cp + qc_pass 签名数: %d\n", nrow(sig_trt)))

# ---- 辅助函数 ----
transpose_df <- function(df) {
  t_df <- data.table::transpose(df)
  colnames(t_df) <- rownames(df)
  rownames(t_df) <- colnames(df)
  return(t_df)
}

process_one_combo <- function(combo_row, gene_info, sig_trt, gctx_path, output_dir) {
  cell      <- combo_row$cell_iname
  nd        <- combo_row$nearest_dose
  pt        <- combo_row$pert_time
  file_name <- combo_row$file_name

  out_path <- file.path(output_dir, file_name)
  if (file.exists(out_path)) {
    cat(sprintf("  [SKIP] %s (已存在)\n", file_name))
    return(TRUE)
  }

  key <- paste(cell, nd, pt, sep = "||")
  matched <- sig_trt[combo_key == key]
  if (nrow(matched) == 0) {
    cat(sprintf("  [WARN] %s: 无匹配签名\n", file_name))
    return(FALSE)
  }

  # ---- 从 gctx 读取 ----
  cat(sprintf("  [READ] %s: %d sig_ids\n", file_name, nrow(matched)))
  gctx_data <- tryCatch({
    parse_gctx(gctx_path, cid = matched$sig_id, matrix_only = FALSE)
  }, error = function(e) {
    cat(sprintf("  [ERROR] parse_gctx: %s\n", e$message))
    return(NULL)
  })
  if (is.null(gctx_data)) return(FALSE)

  # ---- 基因 ID → 基因符号 ----
  exp_mat <- gctx_data@mat
  rm(gctx_data); gc()

  exp_df <- as.data.frame(exp_mat)
  exp_df$pr_gene_id <- as.integer(rownames(exp_df))
  exp_df <- exp_df %>%
    inner_join(gene_info, by = "pr_gene_id") %>%
    tibble::column_to_rownames(var = "pr_gene_symbol") %>%
    dplyr::select(-pr_gene_id)
  exp_mat <- as.matrix(exp_df)
  rm(exp_df); gc()

  # ---- 转置 + 按药物名取均值 ----
  exp_T <- transpose_df(as.data.frame(exp_mat))
  rm(exp_mat); gc()

  exp_T$sig_id <- rownames(exp_T)
  exp_merged <- exp_T %>%
    inner_join(matched[, .(sig_id, cmap_name)], by = "sig_id") %>%
    dplyr::select(-sig_id)
  rm(exp_T); gc()

  gene_cols <- setdiff(colnames(exp_merged), "cmap_name")
  exp_avg <- exp_merged %>%
    group_by(cmap_name) %>%
    summarise(across(all_of(gene_cols), mean, .names = "{.col}"), .groups = "drop") %>%
    tibble::column_to_rownames(var = "cmap_name")
  rm(exp_merged, gene_cols); gc()

  # ---- 转置回 genes × drugs ----
  exp_LINCS2020 <- transpose_df(as.data.frame(exp_avg))
  rm(exp_avg); gc()
  exp_LINCS2020 <- as.matrix(exp_LINCS2020)

  # ---- sig_LINCS2020 ----
  sig_LINCS2020 <- as.data.frame(matched)
  sig_LINCS2020$pert_iname <- sig_LINCS2020$cmap_name  # 兼容旧代码

  n_drugs <- ncol(exp_LINCS2020)

  if (n_drugs >= 50) {
    save(exp_LINCS2020, sig_LINCS2020, file = out_path)
    cat(sprintf("  [DONE] %s: %d genes × %d drugs\n", file_name,
                nrow(exp_LINCS2020), n_drugs))
    return(TRUE)
  } else {
    cat(sprintf("  [WARN] %s: 仅 %d 药物，跳过\n", file_name, n_drugs))
    return(FALSE)
  }
}

# ---- 主循环 ----
cat(sprintf("\n开始处理 %d 个组合...\n", nrow(combinations)))
success <- 0; fail <- 0

for (i in seq_len(nrow(combinations))) {
  cat(sprintf("\n[%d/%d] ", i, nrow(combinations)))
  combo <- as.list(combinations[i])

  res <- tryCatch({
    process_one_combo(combo, gene_info, sig_trt, gctx_path, output_dir)
  }, error = function(e) {
    cat(sprintf("  [ERROR] %s\n", e$message))
    return(FALSE)
  })

  if (isTRUE(res)) success <- success + 1 else fail <- fail + 1
}

cat(sprintf("\n========================================\n"))
cat(sprintf("完成! 成功: %d, 失败: %d\n", success, fail))
