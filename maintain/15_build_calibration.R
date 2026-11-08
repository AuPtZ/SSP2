#!/usr/bin/env Rscript
# ============================================================
# 步骤 15：构建路线B 离线校准表（calibration_pilot.rdata）
#
# 输入（由 maintain/pilot_b0 产生、已复制到仓库的汇总表）：
#   maintain/pilot_b0/results/summary_by_cell_method_topn.csv
#   maintain/pilot_b0/results/summary_by_class_method_topn.csv
# 输出：
#   data_preload/others/calibration_pilot.rdata
#     calib_cell  : 每一 (kind, cell, method, topn) 一行
#     calib_class : 每一 (kind, method, topn) 一行（跨细胞系汇总）
#     meta        : 来源、seed、样本量、限制说明
#
# 说明：这是**离线 pilot 校准**（xpr 用 guide 级留一自检索；cp 用条件级留一），
# 不是对每个新任务实时校准；用于在 Application 里给出 method/topN 起点。
# 复现完整 pilot 需重跑 maintain/pilot_b0 的 prep/run/aggregate 流程（见其 README）。
# ============================================================
suppressMessages(library(utils))

in_dir <- "maintain/pilot_b0/results"
out_file <- "data_preload/others/calibration_pilot.rdata"

cell_csv <- file.path(in_dir, "summary_by_cell_method_topn.csv")
class_csv <- file.path(in_dir, "summary_by_class_method_topn.csv")
if (!file.exists(cell_csv) || !file.exists(class_csv)) {
  stop("找不到 pilot 汇总表: ", cell_csv, " / ", class_csv)
}

calib_cell  <- utils::read.csv(cell_csv,  stringsAsFactors = FALSE)
calib_class <- utils::read.csv(class_csv, stringsAsFactors = FALSE)

keep <- c("kind", "cell", "method", "topn", "n_queries", "auc", "auc_sd",
          "null_auc", "null_auc_q95", "recall10", "recall20", "hit10", "hit20",
          "mrr", "p_auc", "frac_sig_auc", "auc_over_null")
calib_cell  <- calib_cell[,  intersect(keep, names(calib_cell)),  drop = FALSE]
calib_class <- calib_class[, intersect(keep, names(calib_class)), drop = FALSE]

meta <- list(
  source = "SSP2 route-B B0 pilot (maintain/pilot_b0)",
  design = paste("Leave-one-out self-retrieval: xpr = guide-level (query = one guide,",
                 "truth = other guides of the same target gene); cp = condition-level",
                 "(query = one drug at one dose/time, truth = other conditions of the same drug)."),
  xpr_cells = sort(unique(calib_cell$cell[calib_cell$kind == "xpr"])),
  cp_cells  = sort(unique(calib_cell$cell[calib_cell$kind == "cp"])),
  seed = 20261108,
  build_date = as.character(Sys.Date()),
  caveat = paste("Offline calibration, not live per-job calibration. xpr guide-level",
                 "reproducibility is weak; treat the recommended method/topN as a starting point,",
                 "and re-run the pilot on aggregated matrices before publication.")
)

dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
save(calib_cell, calib_class, meta, file = out_file, compress = "xz")
cat(sprintf("[15] saved %s\n", out_file))
cat(sprintf("     calib_cell: %d rows (%s xpr cells, %s cp cells)\n",
            nrow(calib_cell),
            length(unique(calib_cell$cell[calib_cell$kind == "xpr"])),
            length(unique(calib_cell$cell[calib_cell$kind == "cp"]))))
cat(sprintf("     calib_class: %d rows\n", nrow(calib_class)))
