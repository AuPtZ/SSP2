# ============================================================
# SSP2 数据预处理 - 步骤0: 生成基因映射和组合信息
#
# 功能:
#   1. 从 gctx 读取全部 12,328 个基因，映射 ENTREZ ID → Gene Symbol
#   2. 使用 nearest_dose 字段归并剂量分组（67种 vs 1037种原始剂量）
#   3. 生成 combinations.Rdata (cell_line × nearest_dose × pert_time)
#
# 输出:
#   data_preload/others/gene_info.rdata    - 基因映射表
#   data_preload/combinations.Rdata        - 需处理的组合列表
#   data_preload/others/comb_stats.rdata   - 所有组合统计
# ============================================================

library(cmapR)
library(org.Hs.eg.db)
library(data.table)

# ============================================================
# 配置
# ============================================================
gctx_path    <- "/home/data/dataportal/LINCS2020/level5_beta_trt_cp_n720216x12328.gctx"
siginfo_path <- "/home/data/dataportal/LINCS2020/siginfo_beta.txt"
out_gene     <- "data_preload/others/gene_info.rdata"
out_comb     <- "data_preload/combinations.Rdata"
out_stats    <- "data_preload/others/comb_stats.rdata"

# ============================================================
# Part 1: 基因映射（全部 12,328 基因）
# ============================================================
cat("============================================================\n")
cat("Part 1: 生成基因映射 (全部 12,328 基因)\n")
cat("============================================================\n")

rids <- read_gctx_ids(gctx_path, dim = "row")
cat(sprintf("gctx 基因总数: %d\n", length(rids)))

# ENTREZ ID → Gene Symbol
gene_map <- AnnotationDbi::select(org.Hs.eg.db, keys = rids,
                                   columns = "SYMBOL", keytype = "ENTREZID")
gene_info <- data.frame(
  pr_gene_id   = as.integer(rids),
  pr_gene_symbol = gene_map$SYMBOL[match(rids, gene_map$ENTREZID)],
  stringsAsFactors = FALSE
)
na_cnt <- sum(is.na(gene_info$pr_gene_symbol))
gene_info$pr_gene_symbol[is.na(gene_info$pr_gene_symbol)] <-
  paste0("LOC", gene_info$pr_gene_id[is.na(gene_info$pr_gene_symbol)])
cat(sprintf("无法映射的基因: %d (已用 LOC+ID 填充)\n", na_cnt))

save(gene_info, file = out_gene)
cat(sprintf("基因映射已保存: %s\n", out_gene))

# ============================================================
# Part 2: 读取 siginfo，使用 nearest_dose 生成组合
# ============================================================
cat("\n============================================================\n")
cat("Part 2: 读取 siginfo，按 nearest_dose + pert_time 分组\n")
cat("============================================================\n")

siginfo <- fread(siginfo_path, sep = "\t", header = TRUE,
  select = c("pert_type", "cell_iname", "pert_dose", "pert_dose_unit",
             "pert_idose", "pert_itime", "pert_time", "pert_time_unit",
             "nearest_dose", "sig_id", "cmap_name", "qc_pass"),
  showProgress = TRUE)

# 筛选 trt_cp + 质控通过
trt <- siginfo[pert_type == "trt_cp" & qc_pass == 1]
rm(siginfo); gc()
cat(sprintf("trt_cp + qc_pass 签名数: %d\n", nrow(trt)))

# 处理 nearest_dose 为 NA 的行：使用 pert_dose 替代
na_nd <- sum(is.na(trt$nearest_dose))
cat(sprintf("nearest_dose 为 NA 的签名数: %d (使用 pert_dose 替代)\n", na_nd))
trt[is.na(nearest_dose), nearest_dose := pert_dose]

# ---- 按 cell_iname × nearest_dose × pert_time 分组统计 ----
comb <- trt[, .(
  n_sigs  = .N,
  n_drugs = uniqueN(cmap_name),
  # 保留第一个 pert_idose/pert_itime 字符串用于文件命名
  pert_idose_str = pert_idose[1],
  pert_itime_str = pert_itime[1],
  nearest_dose_val = nearest_dose[1],
  pert_time_val    = pert_time[1]
), by = .(cell_iname, nearest_dose, pert_time)]

cat(sprintf("原始组合数: %d\n", nrow(comb)))

# ---- 筛选：药物数 >= 1000 ----
comb_f <- comb[n_drugs >= 1000][order(-n_drugs)]
cat(sprintf("药物数 >= 1000 的组合数: %d\n", nrow(comb_f)))

# 生成文件名（兼容旧格式）
comb_f[, file_name := sprintf("LINCS_%s_%s_%s.rdata",
                               cell_iname,
                               gsub(" ", "", pert_idose_str),
                               gsub(" ", "", pert_itime_str))]
comb_f[, display_name := sprintf("LINCS %s %s %s",
                                  cell_iname, pert_idose_str, pert_itime_str)]

# 输出统计
cat("\n=== Top 20 组合（按药物数降序）===\n")
print(comb_f[1:20, .(cell_iname, pert_idose_str, pert_itime_str, n_drugs, n_sigs)])

cat(sprintf("\n涵盖细胞系: %d 种\n", uniqueN(comb_f$cell_iname)))
cat(sprintf("涵盖 nearest_dose: %s\n", paste(sort(unique(comb_f$nearest_dose)), collapse=", ")))
cat(sprintf("涵盖 pert_time: %s\n", paste(sort(unique(comb_f$pert_time)), collapse=", ")))

# ---- 保存 ----
# 完整统计
comb_stats <- comb
save(comb_stats, file = out_stats)

# 筛选后组合（用于数据预生成）
combinations <- comb_f[, .(cell_iname, nearest_dose, pert_time,
                            pert_idose_str, pert_itime_str,
                            n_drugs, n_sigs, file_name, display_name)]
save(combinations, file = out_comb)

cat(sprintf("\n组合信息已保存: %s (%d 组合)\n", out_comb, nrow(combinations)))
cat("完成!\n")
