# ============================================================
## 生成 Tahoe demo2（Benchmark ALL 模式 + 新指标曲线）
##
## 产物：demo/BEN_Tahoe_demo2.rdata（对象名 job_info，与现有 demo 同构，
##       yourtable 里多一张 METRICS 长表 → 结果页多出 5 个指标 tab）
## 数据：Tahoe_PAN_0.5uM（跨细胞系聚合）
## 签名：demo/tahoe_signature.txt（Paclitaxel PAN 谱 top1000 up/down）
## 注释：demo/tahoe_annotation.txt（Effective = 微管抑制剂 7 个）
## ============================================================
suppressPackageStartupMessages({library(dplyr); library(magrittr); library(rio)})
source("R/global.R")          # ← get_cores / rename_col_rules（与 worker.R 的加载一致）
source("R/SS.R"); source("R/Utils_BM.R"); source("R/Utils_BM_metrics.R")
get_job_context    <- function(...) NULL
init_job_progress  <- function(...) invisible(NULL)
tick_job_progress  <- function(...) invisible(NULL)

sig_input <- rio::import("demo/tahoe_signature.txt")
ann       <- rio::import("demo/tahoe_annotation.txt")
sel_exp   <- "Tahoe_PAN_0.5uM.rdata"
get_ss    <- c("SS_Xsum", "SS_CMap", "SS_GSEA", "SS_ZhangScore",
               "SS_XCos", "SS_PLAGE", "SS_QuSAGE")

# 平台有两个注释槽：ES 注释 = "真药清单"（只列真药），AUC 注释 = 两类标签齐全。
# 与 UI 的 file_FDA / file_IC50 一一对应。
es_ann <- data.frame(Compound_name = ann$Compound_name[ann$Group == "Effective"],
                     stringsAsFactors = FALSE)
rio::export(es_ann, "demo/tahoe_annotation_ES.txt", format = "tsv", row.names = FALSE)
cat(sprintf("ES 真药清单 %d 个：%s\n", nrow(es_ann), paste(es_ann$Compound_name, collapse = ", ")))

cat("== 1/3 AUC + ES 全扫描（get_benchmark，10→1000 逐点）==\n"); t0 <- Sys.time()
res_bm <- get_benchmark(IC50_drug = ann, FDA_drug = es_ann, i.need.logfc = sig_input,
                        sel_exp = sel_exp, sel_ss = get_ss, filter_mode = "topN")
stopifnot(length(res_bm) == 3)
cat(sprintf("   %.1f min | AUC %s | ES %s\n", as.numeric(difftime(Sys.time(), t0, units = "mins")),
            paste(dim(res_bm[[1]]), collapse = "x"), paste(dim(res_bm[[2]]), collapse = "x")))

cat("== 2/3 指标曲线（calc_benchmark_metrics，同参数）==\n"); t0 <- Sys.time()
metrics_tab <- calc_benchmark_metrics(sel_exp = sel_exp, sig_input = sig_input,
  drug_sig = es_ann$Compound_name, get_ss = get_ss, filter_mode = "topN",
  cores = get_cores(), nperm = 1000)
stopifnot(!is.null(metrics_tab))
cat(sprintf("   %.1f min | METRICS %s\n", as.numeric(difftime(Sys.time(), t0, units = "mins")),
            paste(dim(metrics_tab), collapse = "x")))

cat("== 3/3 组装 job_info（沿用现有 demo 的 11 键骨架）==\n")
e <- new.env(); load(list.files("demo", pattern = "^BEN.*\\.rdata$", full.names = TRUE)[1], envir = e)
old <- get(ls(e)[1], e)$yourjob
setv <- function(key, val) old$V1[old$V2 == key] <<- val
setv("Job id", "BEN_Tahoe_demo2")
setv("Submission time", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
setv("Number of table", "3")
setv("Signature file name", "demo/tahoe_signature.txt")
setv("Annotation file name for ES", "demo/tahoe_annotation.txt")
setv("Annotation file name for AUC", "demo/tahoe_annotation.txt")
setv("Drug profile name", sel_exp)

job_info <- list(yourjob = old, yourmodule = "ALL (ES and AUC)",
                 yourtable = list(AUC = res_bm[[1]], ES = res_bm[[2]], METRICS = metrics_tab),
                 signame1 = NA, signame2 = NA)

# ---- 预构建 7 个 plotly widget（2026-10-15 性能方案②：demo 点开即用，秒出）----
# res_plot 读 job_info$yourtable$PICS 灌进会话缓存，跳过现场构建。
# 构建口径与 res_plot 的 build_pic 完全一致（抽稀 150 + tooltip + WebGL + 无 modebar）。
cat("== 3b 预构建 plotly widget（供 demo 秒开）==\n"); t0 <- Sys.time()
suppressPackageStartupMessages(library(plotly))
mk_pic <- function(gp) plotly::config(plotly::toWebGL(ggplotly(gp, tooltip = c("x", "y"))),
                                     displayModeBar = FALSE)
mtab_p  <- as.data.frame(metrics_tab)
mtab_p  <- mtab_p[mtab_p$Metric != "ES_abs", , drop = FALSE]
mets    <- intersect(c("ES_rank", "AUPRC", "RecallAtK", "EFpct", "AUROC"), unique(mtab_p$Metric))
pics <- list(AUC = mk_pic(draw_dr_auc(res_bm[[1]])), ES = mk_pic(draw_dr_es(res_bm[[2]])))
for (mm in mets) pics[[mm]] <- mk_pic(draw_dr_metrics(mtab_p, mm))
job_info$yourtable$PICS <- pics
cat(sprintf("   %.0f s | PICS %d 个: %s\n", as.numeric(difftime(Sys.time(), t0, units = "secs")),
            length(pics), paste(names(pics), collapse = ", ")))

save(job_info, file = "demo/BEN_Tahoe_demo2.rdata")
cat(sprintf("已保存 demo/BEN_Tahoe_demo2.rdata（%.1f MB）\n[11] 完成\n",
            file.size("demo/BEN_Tahoe_demo2.rdata") / 1024 / 1024))
