# ============================================================
# SSP2 数据预处理 - 步骤8: 药物名称标准化（完整版）
#
# 功能:
#   - 从 siginfo_beta.txt 提取药物基础信息 (pert_id, cmap_name)
#   - 从旧 pert_info 文件补充 pubchem/smiles/inchi 化学信息
#   - 生成药物转换器所需数据
#
# 输出:
#   data_preload/drugconvertor/LINCS2020_drug_info.Rdata
# ============================================================

library(data.table)
library(dplyr)

siginfo_path   <- "/home/data/dataportal/LINCS2020/siginfo_beta.txt"
old_pert_info  <- "/home/data/auptz/rprojects_drop/SSP/data_preload/drugconvertor/GSE92742_Broad_LINCS_pert_info.txt"
out_dir        <- "data_preload/drugconvertor/"
out_file       <- file.path(out_dir, "LINCS2020_drug_info.Rdata")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ============================================================
# Part 1: 从 siginfo_beta 提取药物基础信息
# ============================================================
cat("Part 1: 读取 siginfo 提取药物信息\n")
siginfo <- fread(siginfo_path, sep = "\t", header = TRUE,
  select = c("pert_type", "pert_id", "cmap_name", "qc_pass"),
  showProgress = TRUE)

df <- siginfo[pert_type == "trt_cp" & qc_pass == 1]
rm(siginfo); gc()

# 去重、按 cmap_name 聚合
df <- df[, .(pert_id_list = paste(unique(pert_id), collapse = "|")), by = cmap_name]
setnames(df, "cmap_name", "pert_iname")
cat(sprintf("唯一药物名: %d\n", nrow(df)))

# ============================================================
# Part 2: 从旧 pert_info 补充化学信息
# ============================================================
cat("\nPart 2: 从旧 pert_info 补充化学信息\n")

old <- fread(old_pert_info, sep = "\t", header = TRUE)
old <- old[pert_type == "trt_cp"]
old <- old[, .(pert_iname, pubchem_cid, canonical_smiles, inchi_key, inchi_key_prefix)]
old <- unique(old)

# 标准化：将 "-666" / "restricted" 转为 NA
old <- old %>% mutate(across(everything(), ~ ifelse(. %in% c("-666", "restricted"), NA, .)))

# 合并且去重
CMAP_druginfo <- df %>%
  left_join(old, by = "pert_iname") %>%
  unique()

# 处理缺失值
na_pubchem <- sum(is.na(CMAP_druginfo$pubchem_cid))
cat(sprintf("缺少 pubchem_cid 的药物数: %d / %d\n", na_pubchem, nrow(CMAP_druginfo)))

# 生成净药物名（去除空格和连字符，小写）
CMAP_druginfo$net_drug_name <- tolower(gsub("[- ]", "", CMAP_druginfo$pert_iname))

cat(sprintf("最终药物信息: %d 行\n", nrow(CMAP_druginfo)))

save(CMAP_druginfo, file = out_file)
cat(sprintf("药物信息已保存: %s\n", out_file))
