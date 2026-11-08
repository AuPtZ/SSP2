#!/usr/bin/env Rscript
# ============================================================
# SSP2 数据预处理 - 步骤13: 构建 CRISPR KO (trt_xpr) 扰动表达谱
#
# 与 maintain/01处理数据预生成.R 的化合物 (cp) 流程完全独立：
#   - 不读取、不重写 data_preload/drugexp/LINCS_*.rdata / Tahoe_*.rdata
#   - 只新增 data_preload/drugexp/LINCSxpr_<cell>_<time>h.rdata
#
# 数据源: /home/data/dataportal/LINCS2020/level5_beta_trt_xpr_n142901x12328.gctx
#   * gctx 内混有 ctl_vector (1,128) + ctl_untrt (828) 对照列，必须按
#     pert_type == "trt_xpr" 过滤（绝不能“取文件所有列”）。
#   * trt_xpr 的 cmap_name 是靶基因符号（不是药物名）；同一靶基因的多个 guide
#     按 mean 聚合（与 cp 中同一药物多批次按 mean 聚合一致）。
#   * level5 已是板内对照校准的 moderated z-score，无需重算对照。
#   * combo = (cell_iname, pert_time)，没有剂量轴；每个数据集要求 >= 100 靶基因。
#   * cmap_name == "" 的无靶基因签名必须显式丢弃并记录 n_unannot。
#
# 输出对象（与 cp 数据集同名，现有 loader 可直接读取）:
#   exp_LINCS2020 : matrix[12,328 genes x N target genes]，行=gene symbol，
#                   列=靶基因 symbol (cmap_name)
#   sig_LINCS2020 : data.frame，每个进入聚合的 guide 签名一行（含 sig_id/pert_id/
#                   cmap_name/cell_iname/pert_time/qc_pass 等），pert_iname 为兼容别名
#
# 用法（在项目根目录 ~/rprojects/SSP2 下运行）:
#   /usr/lib/R/bin/Rscript maintain/13_build_xpr.R                # 全部数据集
#   /usr/lib/R/bin/Rscript maintain/13_build_xpr.R --shard 2/5    # 并行分片 2/5
#   /usr/lib/R/bin/Rscript maintain/13_build_xpr.R --dry-run      # 只打印计划
# ============================================================

suppressPackageStartupMessages({
  library(cmapR)
  library(data.table)
})

# ---------------- 路径 / 参数 ----------------
proj_root <- function() {
  cand <- getwd()
  if (file.exists(file.path(cand, "data_preload/others/gene_info.rdata"))) return(cand)
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f)) return(normalizePath(file.path(dirname(f[1]), "..")))
  normalizePath("~/rprojects/SSP2")
}
ROOT        <- proj_root()
base_dir    <- "/home/data/dataportal/LINCS2020"
gctx_path   <- file.path(base_dir, "level5_beta_trt_xpr_n142901x12328.gctx")
siginfo_path<- file.path(base_dir, "siginfo_beta.txt")
gene_info_f <- file.path(ROOT, "data_preload/others/gene_info.rdata")
output_dir  <- file.path(ROOT, "data_preload/drugexp")
PERT_CLASS  <- "trt_xpr"
MIN_TARGETS <- 100L

args <- commandArgs(trailingOnly = TRUE)
shard <- 1L; nshard <- 1L; dry_run <- FALSE
i <- 1L
while (i <= length(args)) {
  a <- args[i]
  if (a == "--dry-run") { dry_run <- TRUE; i <- i + 1L }
  else if (a == "--shard") {
    sp <- strsplit(args[i + 1L], "/")[[1]]
    shard <- as.integer(sp[1]); nshard <- as.integer(sp[2]); i <- i + 2L
  } else stop(sprintf("未知参数: %s", a))
}
stopifnot(shard >= 1L, nshard >= 1L, shard <= nshard)
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat(sprintf("[cfg] ROOT=%s\n", ROOT))
cat(sprintf("[cfg] class=%s min_targets=%d shard=%d/%d dry_run=%s\n",
            PERT_CLASS, MIN_TARGETS, shard, nshard, dry_run))

# ---------------- 基因映射（复用 cp 流程的 gene_info.rdata）----------------
e <- new.env(); load(gene_info_f, envir = e)
gene_info <- get("gene_info", envir = e)
stopifnot(!anyDuplicated(gene_info$pr_gene_id), !anyDuplicated(gene_info$pr_gene_symbol))
cat(sprintf("[gene] %d genes (ENTREZ -> symbol, 无重复)\n", nrow(gene_info)))

# ---------------- 读取 siginfo，选 trt_xpr 签名 ----------------
sig_all <- fread(siginfo_path, sep = "\t", showProgress = FALSE,
  select = c("sig_id", "pert_type", "pert_id", "cmap_name", "cell_iname",
             "pert_time", "pert_time_unit", "qc_pass", "pert_dose"))
sig_all[, qc_pass := suppressWarnings(as.integer(qc_pass))]
sel <- sig_all[pert_type == PERT_CLASS]
rm(sig_all); gc()

cat(sprintf("[sig] %s: %d signatures (raw, 含对照列不会被选中)\n", PERT_CLASS, nrow(sel)))
sel <- sel[qc_pass == 1L]
cat(sprintf("[sig] qc_pass==1: %d ; cmap_name==\"\": %d (显式丢弃并计入 n_unannot)\n",
            nrow(sel), sel[cmap_name == "", .N]))

# 每个 (cell, time) 组合的统计（组合定义不含剂量轴）
comb <- sel[, .(
  n_sig      = .N,                                  # qc_pass==1 的 guide 签名总数（含无靶基因）
  n_unannot  = sum(cmap_name == ""),                # 靶基因缺失、无法归组的签名数
  n_annot    = sum(cmap_name != ""),                # 可归组签名数
  n_target   = uniqueN(cmap_name[cmap_name != ""])  # 靶基因数（= 输出列数）
), by = .(cell_iname, pert_time)]

build <- comb[n_target >= MIN_TARGETS][order(-n_target)]
cat(sprintf("[plan] (cell x time) 组合: %d ; >=%d 靶基因的数据集: %d\n",
            nrow(comb), MIN_TARGETS, nrow(build)))
cat(sprintf("[plan] 预计输出列数合计: %d\n", sum(build$n_target)))
print(build)

if (dry_run) {
  cat("\n[dry-run] 仅打印计划，不读取 gctx。\n")
  quit(save = "no", status = 0)
}

# 分片（按 n_target 降序 round-robin，负载均衡）
if (nshard > 1L) {
  idx <- which(((seq_len(nrow(build)) - 1L) %% nshard) + 1L == shard)
  build <- build[idx]
  cat(sprintf("[plan] 本分片处理 %d 个数据集\n", nrow(build)))
}
if (nrow(build) == 0L) quit(save = "no", status = 0)

# ---------------- 逐数据集构建 ----------------
stats <- list()
for (r in seq_len(nrow(build))) {
  cell <- build$cell_iname[r]
  tt   <- build$pert_time[r]
  n_tg <- build$n_target[r]
  n_un <- build$n_unannot[r]
  out_file <- sprintf("LINCSxpr_%s_%dh.rdata", cell, tt)
  out_path <- file.path(output_dir, out_file)
  cat(sprintf("\n=== [%d/%d] %s | %s %dh | %d targets | %d sigs | %d unannot ===\n",
              r, nrow(build), out_file, cell, tt, n_tg, build$n_sig[r], n_un))
  if (file.exists(out_path)) { cat("  [SKIP] 输出已存在\n"); next }

  t0 <- Sys.time()
  m <- sel[cell_iname == cell & pert_time == tt & cmap_name != ""]
  stopifnot(nrow(m) > 0L)

  # ---- 1) 从 gctx 读该组合的 guide 签名（按 sig_id 子集）----
  t_read <- Sys.time()
  # 注意: cmapR 1.14.0 的 matrix_only=TRUE 仍返回 GCT 对象（已实测），
  # 因此统一用 matrix_only=FALSE 再取 @mat（与 maintain/01 的用法一致）。
  gx <- tryCatch({
    gct <- parse_gctx(gctx_path, cid = m$sig_id, matrix_only = FALSE)
    gct@mat
  }, error = function(err) { cat(sprintf("  [ERROR] parse_gctx: %s\n", conditionMessage(err))); NULL })
  if (is.null(gx)) { stats[[length(stats)+1L]] <- data.table(cell=cell,time=tt,status="read_error"); next }
  cat(sprintf("  [read] %d genes x %d sigs in %.1fs (%.0f MB)\n",
              nrow(gx), ncol(gx),
              as.numeric(difftime(Sys.time(), t_read, units = "secs")),
              as.numeric(object.size(gx)) / 1e6))

  # 列对齐：parse_gctx 可能按文件顺序返回，按 sig_id 重排；缺失的签名丢弃并记账
  found <- colnames(gx)
  keep_sig <- m$sig_id %in% found
  if (!all(keep_sig)) cat(sprintf("  [warn] gctx 缺列 %d 个 sig_id，已丢弃\n", sum(!keep_sig)))
  m <- m[keep_sig]
  gx <- gx[, match(m$sig_id, found), drop = FALSE]

  # ---- 2) ENTREZ ID -> gene symbol（与 maintain/01 一致，按 ID 映射，不依赖行序）----
  rid <- suppressWarnings(as.integer(rownames(gx)))
  idx <- match(rid, gene_info$pr_gene_id)
  keep_row <- !is.na(idx)
  if (!all(keep_row)) cat(sprintf("  [warn] %d 个 ENTREZ 未映射，已丢弃\n", sum(!keep_row)))
  gx <- gx[keep_row, , drop = FALSE]
  rownames(gx) <- gene_info$pr_gene_symbol[idx[keep_row]]

  # ---- 3) 按 cmap_name（靶基因）对多 guide 取 mean ----
  t_agg <- Sys.time()
  gx_t <- t(gx)                       # sigs x genes
  grp  <- m$cmap_name                 # 与列对齐
  agg  <- rowsum(gx_t, group = grp, reorder = TRUE)
  cnt  <- as.vector(table(grp)[rownames(agg)])
  agg  <- agg / cnt                   # 均值
  exp_LINCS2020 <- t(agg)             # genes x targets
  colnames(exp_LINCS2020) <- rownames(agg)
  rm(gx, gx_t, agg); gc()
  cat(sprintf("  [agg] mean over guides: %d x %d in %.1fs\n",
              nrow(exp_LINCS2020), ncol(exp_LINCS2020),
              as.numeric(difftime(Sys.time(), t_agg, units = "secs"))))

  # ---- 4) sig 元数据（每个 guide 一行；pert_iname 兼容别名）----
  sig_LINCS2020 <- as.data.frame(m)
  sig_LINCS2020$pert_class <- PERT_CLASS
  sig_LINCS2020$pert_iname <- sig_LINCS2020$cmap_name

  # 与 registry 交叉校验
  if (ncol(exp_LINCS2020) != n_tg) warning(sprintf("n_target 不一致: 实际 %d vs 计划 %d",
                                                   ncol(exp_LINCS2020), n_tg))

  # ---- 5) 原子写出（先临时文件再 rename，避免并行/中断留下半截文件）----
  t_save <- Sys.time()
  tmp <- paste0(out_path, ".tmp", Sys.getpid())
  save(exp_LINCS2020, sig_LINCS2020, file = tmp)
  file.rename(tmp, out_path)
  size_mb <- file.size(out_path) / 1e6
  sec_tot <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("  [DONE] %s : %d genes x %d targets | sigs=%d unannot=%d | %.1f MB | save %.1fs | total %.1fs\n",
              out_file, nrow(exp_LINCS2020), ncol(exp_LINCS2020), nrow(sig_LINCS2020), n_un,
              size_mb, as.numeric(difftime(Sys.time(), t_save, units = "secs")), sec_tot))
  stats[[length(stats)+1L]] <- data.table(
    cell = cell, time = tt, n_gene = nrow(exp_LINCS2020), n_target = ncol(exp_LINCS2020),
    n_sig = nrow(sig_LINCS2020), n_unannot = n_un, size_mb = round(size_mb, 1),
    sec = round(sec_tot, 1), status = "ok")
}

if (length(stats)) {
  st <- rbindlist(stats, fill = TRUE)
  cat("\n==================== 本分片汇总 ====================\n")
  print(st)
  out_stats <- file.path("/tmp/perturb_build", sprintf("stats_shard%d.csv", shard))
  dir.create(dirname(out_stats), showWarnings = FALSE, recursive = TRUE)
  fwrite(st, out_stats)
  cat(sprintf("stats -> %s\n", out_stats))
}
cat("[全部完成]\n")
