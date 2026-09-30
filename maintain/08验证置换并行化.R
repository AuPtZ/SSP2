#!/usr/bin/env Rscript
# =============================================================
# 置换循环并行化 —— 结果一致性验证
#
# 并行化最怕的是"悄悄改变结果"：null 分布一旦与串行版不一致，同一任务的
# p 值就会变，历史结果无法复现。本脚本做三重对照：
#   1) 基线：改动前跑一遍，结果存 log/pval_baseline.rds
#   2) 串行：改动后强制 1 核（mclapply mc.cores=1），应与基线逐位相同
#   3) 并行：改动后多核，应与串行逐位相同
# 只要 2、3 都等于 1，就说明并行化没有改变 null 基因集的抽取顺序。
#
# 用法（项目根目录）：Rscript maintain/08验证置换并行化.R
# =============================================================

local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f) == 1 && nzchar(f)) setwd(dirname(normalizePath(dirname(f))))
})

for (d in c("cache", "cache/BM", "cache/SM", "cache/SS", "cache/queue", "log")) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

suppressPackageStartupMessages({
  source("R/global.R")
  source("R/SS.R")
  source("R/Utils_BM.R")
  source("R/Utils_SM.R")
  source("R/queue_utils.R")   # tick_job_progress
})

set.seed(42)
n_gene <- 300L; n_drug <- 60L
refMatrix <- matrix(rnorm(n_gene * n_drug), nrow = n_gene,
                    dimnames = list(paste0("g", seq_len(n_gene)),
                                    paste0("d", seq_len(n_drug))))
drug_rank_idx <- apply(refMatrix, 2, order, decreasing = TRUE)
res_raw <- data.frame(Score = rnorm(n_drug), row.names = colnames(refMatrix))

methods <- c("SS_Xsum", "SS_XCos", "SS_CMap", "SS_GSEA", "SS_ZhangScore")

CORES_ORIG <- get_cores()

run_one <- function(cores) {
  # 覆盖 global.R 的定义，模拟不同核数（source() 把函数都放进 globalenv）
  assign("get_cores", function() cores, envir = globalenv())
  lapply(methods, function(fn)
    get_pval(res_raw = res_raw, refMatrix = refMatrix, drug_rank_idx = drug_rank_idx,
             funcname = fn, topn = 20))
}

cat("串行（1 核）...\n")
t_serial <- system.time(res_serial <- run_one(1L))[["elapsed"]]
cat("并行（", min(8L, CORES_ORIG), " 核）...\n", sep = "")
t_par <- system.time(res_par <- run_one(min(8L, CORES_ORIG)))[["elapsed"]]

cat(sprintf("耗时：串行 %.1fs，并行 %.1fs，加速 %.1fx\n",
            t_serial, t_par, t_serial / t_par))

same <- function(a, b) identical(a, b)
ok_par <- all(mapply(same, res_serial, res_par))
cat("并行 == 串行：", if (ok_par) "OK" else "*** 不一致 ***", "\n")

basef <- "log/pval_baseline.rds"
if (file.exists(basef)) {
  base <- readRDS(basef)
  ok_base <- all(mapply(same, base, res_serial))
  cat("串行 == 基线(改动前)：", if (ok_base) "OK" else "*** 不一致 ***", "\n")
  if (!ok_base) for (i in seq_along(methods)) {
    d <- max(abs(base[[i]]$pvalue - res_serial[[i]]$pvalue), na.rm = TRUE)
    cat(sprintf("  %-14s pvalue 最大差 %.3g\n", methods[i], d))
  }
} else {
  saveRDS(res_serial, basef)
  cat("已保存基线 ->", basef, "\n")
}
