#!/usr/bin/env Rscript
# ============================================================
# SSP2 数据预处理 - 步骤14: 生成统一数据集注册表 dataset_registry.rdata
#
# 目标：给 data_preload/drugexp/ 下所有表达谱一个统一的注册表，供后续
#       按数据源 / 扰动类型 / 组织 / 细胞系 检索数据集。
#
# 重要：
#   - 只读 data_preload/drugexp/*.rdata，绝不修改任何现有数据文件；
#   - 唯一输出（新文件）: data_preload/others/dataset_registry.rdata
#     （若已存在，先备份为 dataset_registry.rdata.bak-<timestamp>）
#   - 现有 831 个化合物数据集 (687 LINCS cp + 144 Tahoe) 的显示名沿用
#     data_preload/others/drug_num_list1.rdata 的命名，保证 UI 不跳变；
#   - 新增 LINCS CRISPR KO (trt_xpr) 数据集 pert_class="xpr"，
#     source="LINCS-CRISPR"，filename 前缀 LINCSxpr_。
#
# 输出: data.frame `dataset_registry`，列:
#   profile_file, pert_class, source, cell_iname, tissue, pert_time, dose_label,
#   n_pert, n_sig, n_unannot, display_name, build_date, gene_num
#
# 用法: 在项目根目录运行
#   /usr/lib/R/bin/Rscript maintain/14_build_dataset_registry.R
# ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(parallel)
})

proj_root <- function() {
  cand <- getwd()
  if (file.exists(file.path(cand, "data_preload/others/drug_num_list.rdata"))) return(cand)
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f)) return(normalizePath(file.path(dirname(f[1]), "..")))
  normalizePath("~/rprojects/SSP2")
}
ROOT        <- proj_root()
drugexp_dir <- file.path(ROOT, "data_preload/drugexp")
base_dir    <- "/home/data/dataportal/LINCS2020"
out_file    <- file.path(ROOT, "data_preload/others/dataset_registry.rdata")
cat(sprintf("[cfg] ROOT=%s\n[cfg] out=%s\n", ROOT, out_file))

# ------------------------------------------------------------------
# 1) 现有 cp 数据集显示名（与 maintain/02获取选项文件.R 的命名完全一致）
# ------------------------------------------------------------------
e1 <- new.env(); load(file.path(ROOT, "data_preload/others/drug_num_list1.rdata"), envir = e1)
drug_num_list1 <- get("drug_num_list1", envir = e1)   # named character: display_name -> file
cp_display <- data.frame(
  profile_file = unname(drug_num_list1),
  display_name = names(drug_num_list1),
  stringsAsFactors = FALSE
)
cat(sprintf("[cp] 现有数据集显示名: %d 条\n", nrow(cp_display)))

# ------------------------------------------------------------------
# 2) tissue 映射：与 R/global.R 完全相同的逻辑
#    cellinfo_beta.txt: cell_lineage -> subtype -> Other；Tahoe 用 cellline_organ 补
# ------------------------------------------------------------------
ci <- fread(file.path(base_dir, "cellinfo_beta.txt"), sep = "\t", showProgress = FALSE,
            select = c("cell_iname", "cell_lineage", "subtype"))
ci <- as.data.frame(ci); ci <- ci[!duplicated(ci$cell_iname), ]
tissue_raw <- ci$cell_lineage
na_idx <- is.na(tissue_raw) | tissue_raw %in% c("", "unknown", "Unknown")
tissue_raw[na_idx] <- ci$subtype[na_idx]
na_idx <- is.na(tissue_raw) | tissue_raw %in% c("", "unknown", "Unknown")
tissue_raw[na_idx] <- "Other"
tissue_raw <- tools::toTitleCase(gsub("_", " ", tissue_raw))
cellline_tissue <- setNames(tissue_raw, ci$cell_iname)

tahoe_organ_f <- file.path(ROOT, "data_preload/tahoe/cellline_organ.rdata")
if (file.exists(tahoe_organ_f)) {
  te <- new.env(); load(tahoe_organ_f, envir = te)
  if (exists("cellline_organ", envir = te)) {
    tahoe_organ <- get("cellline_organ", envir = te)
    tahoe_safe <- setNames(tahoe_organ, gsub("[/\\\\:*?\"<>|]", "-", names(tahoe_organ)))
    tahoe_all <- c(tahoe_organ, tahoe_safe); tahoe_all <- tahoe_all[!duplicated(names(tahoe_all))]
    add_cells <- setdiff(names(tahoe_all), names(cellline_tissue))
    cellline_tissue <- c(cellline_tissue, tahoe_all[add_cells])
  }
}
tissue_of <- function(cell) {
  t <- unname(cellline_tissue[cell])
  t[is.na(t)] <- "Other"
  t[cell == "PAN"] <- "Pan-cell line"
  t
}
cat(sprintf("[tissue] 映射细胞系: %d 个\n", length(cellline_tissue)))

# ------------------------------------------------------------------
# 3) 新增 xpr 数据集的每组合统计（从 siginfo 重算，不依赖构建脚本状态）
# ------------------------------------------------------------------
si <- fread(file.path(base_dir, "siginfo_beta.txt"), sep = "\t", showProgress = FALSE,
            select = c("pert_type", "cell_iname", "cmap_name", "pert_time", "qc_pass"))
si[, qc_pass := suppressWarnings(as.integer(qc_pass))]
x <- si[pert_type == "trt_xpr" & qc_pass == 1L]
xcomb <- x[, .(x_n_sig = .N,
               x_n_unannot = sum(cmap_name == ""),
               x_n_target = uniqueN(cmap_name[cmap_name != ""])),
           by = .(cell_iname, pert_time)]
rm(si, x); gc()
cat(sprintf("[xpr] siginfo 统计组合: %d 个 (cell x time)\n", nrow(xcomb)))

# ------------------------------------------------------------------
# 4) 读取每个 .rdata 的维度（并行；只读，不修改）
# ------------------------------------------------------------------
files <- sort(list.files(drugexp_dir, pattern = "\\.rdata$"))
cat(sprintf("[scan] data_preload/drugexp/ 下 .rdata 文件: %d 个\n", length(files)))
stopifnot(length(files) > 0)

read_dims <- function(f) {
  ee <- new.env(parent = emptyenv())
  ok <- tryCatch({ load(file.path(drugexp_dir, f), envir = ee); TRUE },
                 error = function(e) FALSE)
  if (!ok || !exists("exp_LINCS2020", envir = ee, inherits = FALSE)) {
    return(data.table(profile_file = f, gene_num = NA_integer_, n_pert = NA_integer_,
                      n_sig = NA_integer_, load_ok = FALSE))
  }
  m <- get("exp_LINCS2020", envir = ee)
  s <- if (exists("sig_LINCS2020", envir = ee, inherits = FALSE)) get("sig_LINCS2020", envir = ee) else NULL
  data.table(profile_file = f, gene_num = nrow(m), n_pert = ncol(m),
             n_sig = if (is.null(s)) NA_integer_ else nrow(s), load_ok = TRUE)
}
ncores <- min(8L, max(1L, parallel::detectCores() - 1L))
cat(sprintf("[scan] 读取维度 (mc.cores=%d) ...\n", ncores))
t0 <- Sys.time()
dims <- rbindlist(mclapply(files, read_dims, mc.cores = ncores, mc.preschedule = FALSE))
cat(sprintf("[scan] 完成 %.1fs ; load_ok=%d / %d\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs")), sum(dims$load_ok), nrow(dims)))
if (any(!dims$load_ok)) print(dims[load_ok == FALSE])

# ------------------------------------------------------------------
# 5) 组装注册表
# ------------------------------------------------------------------
f <- dims$profile_file
reg <- data.table(profile_file = f)
reg[, pert_class := fifelse(grepl("^LINCSxpr_", f), "xpr", "cp")]
reg[, source := fifelse(pert_class == "xpr", "LINCS-CRISPR",
                        fifelse(grepl("^Tahoe_", f), "Tahoe-100M", "LINCS"))]

# ---- 细胞系解析：去掉前缀后剥离尾部的 "<剂量>(_<时间>h)"，避免空格/连字符误伤 ----
cell <- rep(NA_character_, length(f))
cell[reg$pert_class == "xpr"]  <- sub("^LINCSxpr_(.*)_[0-9]+h\\.rdata$", "\\1", f[reg$pert_class == "xpr"])
cell[grepl("^LINCS_", f)]      <- sub("^LINCS_(.*)_[0-9.]+uM_[0-9]+h\\.rdata$", "\\1", f[grepl("^LINCS_", f)])
cell[grepl("^Tahoe_", f)]      <- sub("^Tahoe_(.*)_[0-9.]+uM\\.rdata$", "\\1", f[grepl("^Tahoe_", f)])
if (any(is.na(cell))) stop("细胞系解析失败: ", paste(head(f[is.na(cell)], 5), collapse = ", "))
reg[, cell_iname := cell]

# ---- 时间 / 剂量 ----
time_h <- rep(NA_integer_, length(f))
time_h[reg$pert_class == "xpr"] <- as.integer(sub(".*_([0-9]+)h\\.rdata$", "\\1", f[reg$pert_class == "xpr"]))
time_h[grepl("^LINCS_", f)]     <- as.integer(sub(".*_([0-9]+)h\\.rdata$", "\\1", f[grepl("^LINCS_", f)]))
time_h[grepl("^Tahoe_", f)]     <- 24L   # Tahoe-100M 只有 24h 一个作用时间点（文件名无时间维度）
reg[, pert_time := time_h]

dose <- rep("", length(f))
dose[grepl("^LINCS_", f)] <- sub("^LINCS_.*_([0-9.]+uM)_[0-9]+h\\.rdata$", "\\1", f[grepl("^LINCS_", f)])
dose[grepl("^Tahoe_", f)] <- sub("^Tahoe_.*_([0-9.]+uM)\\.rdata$", "\\1", f[grepl("^Tahoe_", f)])
reg[, dose_label := dose]

reg[, tissue := tissue_of(cell_iname)]
reg[, gene_num := dims$gene_num]
reg[, n_pert := dims$n_pert]
reg[, n_sig  := dims$n_sig]

# ---- n_unannot（仅 xpr 有：靶基因缺失的 guide 签名数；cp 为 0）----
reg[, n_unannot := 0L]
idx_x <- which(reg$pert_class == "xpr")
if (length(idx_x)) {
  key_reg <- paste(reg$cell_iname, reg$pert_time, sep = "\u0001")
  key_x   <- paste(xcomb$cell_iname, xcomb$pert_time, sep = "\u0001")
  n_un <- xcomb$x_n_unannot[match(key_reg[idx_x], key_x)]
  if (anyNA(n_un)) warning(sprintf("xpr 组合在 siginfo 中缺 %d 个", sum(is.na(n_un))))
  reg[idx_x, n_unannot := n_un]
}
# ---- 显示名 ----
disp <- rep(NA_character_, length(f))
disp[reg$pert_class == "cp"] <- cp_display$display_name[match(f[reg$pert_class == "cp"], cp_display$profile_file)]
disp[reg$pert_class == "xpr"] <- sprintf("LINCS CRISPR %s %dh (%d targets)",
                                         reg$cell_iname[reg$pert_class == "xpr"],
                                         reg$pert_time[reg$pert_class == "xpr"],
                                         reg$n_pert[reg$pert_class == "xpr"])
if (any(is.na(disp))) stop("display_name 缺失: ", paste(head(f[is.na(disp)], 5), collapse = ", "))
reg[, display_name := disp]

# ---- build_date = 数据文件最后修改日期 ----
reg[, build_date := format(as.Date(file.info(file.path(drugexp_dir, f))$mtime), "%Y-%m-%d")]

# ---- 列顺序 / 排序（保留 n_unannotated 作为任务书同义别名，方便下游按任一拼写取列）----
reg[, n_unannotated := n_unannot]
setcolorder(reg, c("profile_file", "pert_class", "source", "cell_iname", "tissue",
                   "pert_time", "dose_label", "n_pert", "n_sig", "n_unannot",
                   "n_unannotated", "display_name", "build_date", "gene_num"))
reg <- reg[order(source, cell_iname, pert_time, dose_label)]
dataset_registry <- as.data.frame(reg)

# ------------------------------------------------------------------
# 6) 校验 + 备份 + 保存
# ------------------------------------------------------------------
cat("\n==================== registry 校验 ====================\n")
cat(sprintf("总数据集: %d (cp=%d / xpr=%d)\n", nrow(dataset_registry),
            sum(dataset_registry$pert_class == "cp"), sum(dataset_registry$pert_class == "xpr")))
print(as.data.table(dataset_registry)[, .N, by = .(pert_class, source)])
stopifnot(nrow(dataset_registry) == length(files))
stopifnot(identical(sort(unique(dataset_registry$profile_file)), sort(files)))
exp_n <- list(LINCS = 687L, `Tahoe-100M` = 144L, `LINCS-CRISPR` = 19L)
got_n <- table(dataset_registry$source)
cat(sprintf("按 source: LINCS %d / Tahoe-100M %d / LINCS-CRISPR %d\n",
            got_n[["LINCS"]], got_n[["Tahoe-100M"]], got_n[["LINCS-CRISPR"]]))
if (got_n[["LINCS"]] != exp_n$LINCS || got_n[["Tahoe-100M"]] != exp_n$`Tahoe-100M` ||
    got_n[["LINCS-CRISPR"]] != exp_n$`LINCS-CRISPR`) {
  warning("source 计数与预期 (687/144/19) 不一致，请检查 scan 结果")
}
cat(sprintf("xpr 数据集: %d ; 总靶基因列: %d ; n_unannot 合计: %d\n",
            sum(dataset_registry$pert_class == "xpr"),
            sum(dataset_registry$n_pert[dataset_registry$pert_class == "xpr"]),
            sum(dataset_registry$n_unannot)))
cat(sprintf("cp 数据集: %d ; 基因数分布: %s\n",
            sum(dataset_registry$pert_class == "cp"),
            paste(sort(unique(dataset_registry$gene_num[dataset_registry$pert_class == "cp"])), collapse = "/")))
cat(sprintf("build_date 范围: %s ~ %s\n", min(dataset_registry$build_date), max(dataset_registry$build_date)))
cat("\nhead(dataset_registry):\n"); print(head(dataset_registry, 8))
cat("\ntail (xpr) :\n"); print(tail(dataset_registry[dataset_registry$pert_class == "xpr", ], 5))

if (file.exists(out_file)) {
  bak <- paste0(out_file, ".bak-", format(Sys.time(), "%Y%m%d-%H%M%S"))
  file.copy(out_file, bak); cat(sprintf("[backup] 已有 registry -> %s\n", bak))
}
save(dataset_registry, file = out_file)
cat(sprintf("\n[DONE] %s (%.1f KB, %d rows)\n", out_file, file.size(out_file) / 1024, nrow(dataset_registry)))
