#!/usr/bin/env Rscript
# ============================================================
# 重算 demo/ 下 4 个预置结果对象（Benchmark x 1 + Application x 3）
#
# 走真实任务链路，保证结构与线上一致：
#   写 params rds -> run_job()(get_benchmark / get_single_method)
#   -> write_result_from_meta 写 resinfo.db -> read_from_db() -> save 到 demo/
#
# 与线上唯一区别：不进 job_queue 的 pending（避免被常驻 worker 抢走重复算），
# 直接以 status='running' 插行，本地同步跑完后 mark done。
#
# 配置原则：UI 默认值 + 新的 demo 输入文件，数据集统一 LINCS_MCF7_10uM_6h
# （Application 默认，也是 demo 注释对应的数据集）。
# ============================================================
local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f) == 1 && nzchar(f)) setwd(dirname(dirname(normalizePath(f))))
})
for (d in c("cache", "cache/BM", "cache/SM", "cache/SS", "cache/queue", "log")) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}
suppressPackageStartupMessages({
  library(dplyr); library(RSQLite)
  source("R/global.R"); source("R/SS.R"); source("R/Utils_BM.R")
  source("R/Utils_SM.R"); source("R/queue_utils.R")
})
## read_from_db 定义在 tab_jobcenter.R（该整文件依赖 Shiny 的 output/session，
## 不能直接 source），这里只把这一个函数定义抠出来 eval。
code <- parse("tab_jobcenter.R")
i <- which(vapply(code, function(e) any(grepl("^read_from_db <- function", deparse(e))), logical(1)))
stopifnot(length(i) == 1)
eval(code[[i]], envir = globalenv())

insert_job_row <- function(jobid, module, sub_module, st) {
  con <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
  on.exit(RSQLite::dbDisconnect(con))
  RSQLite::dbExecute(con, "PRAGMA busy_timeout=8000;")
  ensure_job_queue_table(con)
  RSQLite::dbExecute(con,
    "INSERT OR REPLACE INTO job_queue (jobid, module, sub_module, status, submitted_time)
     VALUES (?, ?, ?, 'running', ?)", params = list(jobid, module, sub_module, st))
}
run_one <- function(tag, prefix, module, sub_module, params, meta) {
  jobid <- paste0(prefix, as.integer(Sys.time()), paste0(sample(LETTERS, 3), collapse = ""))
  st    <- as.character(Sys.time())
  saveRDS(list(jobid = jobid, module = module, sub_module = sub_module,
               submitted_time = st, params = params, meta = meta),
          file.path(QUEUE_DIR, paste0(jobid, ".rds")))
  insert_job_row(jobid, module, sub_module, st)
  cat(sprintf("[%s] %s %s 开始 ...\n", format(Sys.time()), tag, jobid)); flush.console()
  t0 <- Sys.time()
  run_job(list(jobid = jobid))
  mark_job(jobid, "done")
  # 注意对象名必须是 job_info：tab_utils.R 的 8 个 demo 按钮都是
  # load("demo/xxx.rdata") 之后直接 res_plot(job_info, ...)，
  # 名字对不上就会 "object 'job_info' not found"（2026-09-30 踩过：这里曾存成 ji）。
  job_info <- read_from_db(jobid)
  stopifnot(is.list(job_info), !is.null(job_info$yourtable))
  save(job_info, file = file.path("demo", paste0(jobid, ".rdata")))
  cat(sprintf("[%s] %s 完成，耗时 %.1f 分钟 -> demo/%s.rdata\n",
      format(Sys.time()), tag, as.numeric(difftime(Sys.time(), t0, units = "mins")), jobid))
  flush.console()
  jobid
}

## ---------- 输入（新的 demo 文件）----------
sig1 <- rio::import("demo/signature.txt")  %>% dplyr::select(Gene, log2FC)
sig2 <- rio::import("demo/signature2.txt") %>% dplyr::select(Gene, log2FC)
ic50 <- rio::import("demo/drug_annotation_AUC.txt")
fda  <- rio::import("demo/drug_annotation_ES.txt")
DS   <- "LINCS_MCF7_10uM_6h.rdata"
SS7  <- unname(unlist(ss_list))
cat("方法集:", paste(SS7, collapse = ", "), "\n")
cat("签名:", nrow(sig1), "基因; AUC 药物:", nrow(ic50), "; FDA 药物:", nrow(fda), "\n")
args0 <- commandArgs(trailingOnly = TRUE)
tasks <- if (length(args0)) args0 else c("single", "all", "cross", "ben")
cat("本次执行任务:", paste(tasks, collapse = ", "), "\n")
ids <- list()

## ---------- 1. Application / singlemethod（GSEA）----------
if ("single" %in% tasks) ids$single <- run_one("APP-singlemethod", "APP", "Application", "singlemethod",
  params = list(drug_profile = DS, topn = 150, filter_mode = "topN", fc_threshold = 1,
                sel_model_sm1 = "singlemethod", i.need.logfc = sig1,
                funcname = "SS_Xsum", funcname_mul = NULL, direct = "Down",
                bioname1 = NA, bioname2 = NA),
  meta = list(sel_experiment_sm = DS, sel_model_sm = "singlemethod",
              method_sm2 = find_original_names("SS_Xsum"), method_sm1_all = NA_character_,
              direction_sm = NA_character_, file_sig_sm_name = "signature.txt",
              file_sig_sm1_name = NA_character_, file_sig_sm2_name = NA_character_,
              file_name1 = NA_character_, file_name2 = NA_character_,
              sel_topn_sm = 150, filter_mode = "topN", filter_value = 150))

## ---------- 2. Application / SS_all（XSum + CMap）----------
## 方法选择：单轮置换耗时 XSum 0.22s / XCos 0.49s / Zhang 2.8s / CMap 4.3s /
## GSEA 8.1s（MCF7 5222 列实测）。2026-09-30 起置换循环已并行（48 核约 28x），
## 2000 轮 CMap 约 5 分钟、GSEA 约 10 分钟，不再是"串行 4.5 小时"的旧账；
## 这里仍用 XSum / XCos，是让 demo 结果与生产默认的 2000 次分辨率保持一致。
if ("all" %in% tasks) ids$all <- run_one("APP-SS_all", "APP", "Application", "SS_all",
  params = list(drug_profile = DS, topn = 150, filter_mode = "topN", fc_threshold = 1,
                sel_model_sm1 = "SS_all", i.need.logfc = sig1,
                funcname = NULL, funcname_mul = c("SS_Xsum", "SS_XCos"), direct = "Down",
                bioname1 = NA, bioname2 = NA),
  meta = list(sel_experiment_sm = DS, sel_model_sm = "SS_all", method_sm2 = NA_character_,
              method_sm1_all = paste0(find_original_names(c("SS_Xsum", "SS_XCos")), collapse = ", "),
              direction_sm = "Down", file_sig_sm_name = "signature.txt",
              file_sig_sm1_name = NA_character_, file_sig_sm2_name = NA_character_,
              file_name1 = NA_character_, file_name2 = NA_character_,
              sel_topn_sm = 150, filter_mode = "topN", filter_value = 150))

## ---------- 3. Application / SS_cross（signature + signature2）----------
## 方法选 CMap（2026-09-30 由用户指定）：交叉图是按 (Scale_score.x, Scale_score.y)
## 的象限着色画的，落在坐标轴上的点（block = NQ）才看得出"十字"结构；而 NQ 只在
## 某一侧 Scale_score 恰好为 0 时出现。实测 NQ 个数：CMap 3603、GSEA 3089、
## XSum 33、XCos/ZhangScore 各 1 —— 只有 CMap/GSEA 这类"整条排序"的方法会给出
## 大量 0 值，XSum/XCos 几乎不给 0，交叉图上就没有坐标轴那一簇点，不好看。
if ("cross" %in% tasks) ids$cross <- run_one("APP-SS_cross", "APP", "Application", "SS_cross",
  params = list(drug_profile = DS, topn = 150, filter_mode = "topN", fc_threshold = 1,
                sel_model_sm1 = "SS_cross",
                i.need.logfc = list(i.need.logfc1 = sig1, i.need.logfc2 = sig2),
                funcname = "SS_CMap", funcname_mul = NULL, direct = "Down",
                bioname1 = "Signature1", bioname2 = "Signature2"),
  meta = list(sel_experiment_sm = DS, sel_model_sm = "SS_cross",
              method_sm2 = find_original_names("SS_CMap"), method_sm1_all = NA_character_,
              direction_sm = NA_character_, file_sig_sm_name = NA_character_,
              file_sig_sm1_name = "signature.txt", file_sig_sm2_name = "signature2.txt",
              file_name1 = "Signature1", file_name2 = "Signature2",
              sel_topn_sm = 150, filter_mode = "topN", filter_value = 150))

## ---------- 4. Benchmark（7 方法 x topN 扫描）----------
if ("ben" %in% tasks) ids$ben <- run_one("BEN(ALL)", "BEN", "Benchmark", "ALL (ES and AUC)",
  params = list(IC50_drug = ic50, FDA_drug = fda, i.need.logfc = sig1,
                sel_exp = DS, sel_ss = SS7, filter_mode = "topN"),
  meta = list(sel_experiment = DS,
              sel_ss_names = paste0(find_original_names(SS7), collapse = ", "),
              file_sig_name = "signature.txt", file_IC50_name = "drug_annotation_AUC.txt",
              file_FDA_name = "drug_annotation_ES.txt",
              filter_mode = "topN", filter_value = NA_character_))
cat("\n================ 全部完成 ================\n")
for (n in names(ids)) cat(sprintf("%-8s %s\n", n, ids[[n]]))

## ---------- 出图自检（等价于点 demo 按钮时 res_plot 干的事）----------
cat("\n---- 绘图自检 ----\n")
for (n in names(ids)) {
  f <- file.path("demo", paste0(ids[[n]], ".rdata"))
  e <- new.env(); load(f, envir = e); ji <- get(ls(e)[1], envir = e)
  tab <- ji$yourtable
  cat(sprintf("[%s] module=%s\n", n, ji$yourmodule))
  if (is.data.frame(tab)) {
    cat(sprintf("   表 %d 行 x %d 列  列: %s\n", nrow(tab), ncol(tab), paste(names(tab), collapse = ",")))
    if (ji$yourmodule == "singlemethod") {
      p <- tryCatch({ draw_single(tab); "OK" }, error = function(e) paste("FAILED:", conditionMessage(e))) }
    if (ji$yourmodule == "SS_all") {
      p <- tryCatch({ draw_all(tab); "OK" }, error = function(e) paste("FAILED:", conditionMessage(e))) }
    if (ji$yourmodule == "SS_cross") {
      p <- tryCatch({ draw_cross(tab, ji$signame1, ji$signame2); "OK" },
                    error = function(e) paste("FAILED:", conditionMessage(e))) }
    cat("   绘图:", p, "\n")
  } else {
    cat(sprintf("   AUC %d x %d  列: %s\n", nrow(tab$AUC), ncol(tab$AUC), paste(names(tab$AUC), collapse = ",")))
    cat(sprintf("   ES  %d x %d  列: %s\n", nrow(tab$ES), ncol(tab$ES), paste(names(tab$ES), collapse = ",")))
    p1 <- tryCatch({ draw_dr_auc(as_tibble(tab$AUC)); "OK" }, error = function(e) paste("FAILED:", conditionMessage(e)))
    p2 <- tryCatch({ draw_dr_es(as_tibble(tab$ES));  "OK" }, error = function(e) paste("FAILED:", conditionMessage(e)))
    cat("   AUC 绘图:", p1, " / ES 绘图:", p2, "\n")
    cat("   AUC 首行(推荐):", paste(unlist(tab$AUC[1, ]), collapse = " "), "\n")
  }
}
cat("\n新 jobid（用于更新 tab_utils.R）:\n"); cat(paste(unlist(ids), collapse = "\n"), "\n")
