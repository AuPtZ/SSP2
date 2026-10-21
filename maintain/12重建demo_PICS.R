# ============================================================
## 重建两个 demo（新契约 2026-10-17）：yourtable 仅含 METRICS，
## yourmodule = "METRICS"，yourjob 增加 "Annotation type"（effective/toxic）
##
## 背景：Benchmark 只计算新指标（旧 AUC/ES 两遍扫描已取消），
##       注释上传改为单列药物清单 + 有效/毒性 radio。
## 幂等：METRICS 已含 p_null 则不重算（重算约 3-24 min）。
## 用法：Rscript maintain/12重建demo_PICS.R
# ============================================================
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(rio))
source("R/global.R")
source("R/SS.R"); source("R/Utils_BM.R"); source("R/Utils_BM_metrics.R")
get_job_context    <- function(...) NULL
init_job_progress  <- function(...) invisible(NULL)
tick_job_progress  <- function(...) invisible(NULL)

SS7   <- c("SS_Xsum", "SS_CMap", "SS_GSEA", "SS_ZhangScore", "SS_XCos",
           "SS_PLAGE", "SS_QuSAGE")

rebuild <- function(file, tag, DS, sig_file, anno_file, anno_type) {
  e <- new.env(); load(file, envir = e); ji <- get(ls(e)[1], e)
  cat(sprintf("\n== %s ==\n", tag))

  if (is.null(ji$yourtable$METRICS) || !"p_null" %in% names(as.data.frame(ji$yourtable$METRICS))) {
    ref <- new.env(); load(file.path("data_preload/drugexp", DS), envir = ref)
    refm <- get("exp_LINCS2020", envir = ref)
    sig <- rio::import(sig_file)
    sig <- sig %>% dplyr::mutate(Gene = as.character(Gene), log2FC = as.numeric(log2FC)) %>%
      dplyr::filter(!is.na(log2FC), Gene != "") %>%
      dplyr::distinct(Gene, .keep_all = TRUE) %>%
      dplyr::filter(Gene %in% rownames(refm)) %>%
      dplyr::arrange(dplyr::desc(log2FC))
    lst <- rio::import(anno_file)
    lst <- data.frame(Compound_name = as.character(lst$Compound_name), stringsAsFactors = FALSE)
    t0 <- Sys.time()
    mt <- calc_benchmark_metrics(sel_exp = DS, sig_input = sig, drug_sig = lst$Compound_name,
                                 get_ss = SS7, filter_mode = "topN", cores = get_cores(),
                                 nperm = 1000, anno_type = anno_type)
    stopifnot(!is.null(mt), "p_null" %in% names(mt))
    ji$yourtable$METRICS <- mt
    cat(sprintf("   metrics recompute %.1f min | METRICS %s\n",
                as.numeric(difftime(Sys.time(), t0, units = "mins")), paste(dim(mt), collapse = "x")))
  } else {
    cat(sprintf("   METRICS %s has p_null, skip recompute\n",
                paste(dim(as.data.frame(ji$yourtable$METRICS)), collapse = "x")))
  }

  ji$yourtable <- list(METRICS = ji$yourtable$METRICS)
  ji$yourmodule <- "METRICS"

  yj <- ji$yourjob
  yj <- yj[yj$V2 != "Annotation file name for AUC", , drop = FALSE]
  if ("Annotation type" %in% yj$V2) {
    yj$V1[yj$V2 == "Annotation type"] <- anno_type
  } else {
    yj <- rbind(yj, data.frame(V1 = anno_type, V2 = "Annotation type", stringsAsFactors = FALSE))
  }
  if ("Number of table" %in% yj$V2) yj$V1[yj$V2 == "Number of table"] <- "1"
  ji$yourjob <- yj

  save(ji, file = file)
  cat(sprintf("   saved %s (%.2f MB) | yourtable: %s | anno_type: %s\n", file,
              file.size(file) / 1024 / 1024, paste(names(ji$yourtable), collapse = ","), anno_type))
}

rebuild("demo/BEN_Tahoe_demo2.rdata", "demo2 (Tahoe)",
        DS = "Tahoe_PAN_0.5uM.rdata", sig_file = "demo/tahoe_signature.txt",
        anno_file = "demo/tahoe_annotation_ES.txt", anno_type = "effective")

rebuild("demo/BEN1790672381JTV.rdata", "demo1 (LINCS)",
        DS = "LINCS_MCF7_10uM_6h.rdata", sig_file = "demo/signature.txt",
        anno_file = "demo/drug_annotation_ES.txt", anno_type = "effective")

cat("\n[12] done\n")
