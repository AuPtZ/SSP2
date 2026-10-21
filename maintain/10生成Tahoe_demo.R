# ============================================================
## 生成 Tahoe 版 demo 输入文件（maintain/06 的 Tahoe 对应物）
##
## 说明：平台设计里「药物注释」由用户上传，这里生成的注释只是 demo 用的示例，
##      不是内置真值。真值素材取自官方 drug_metadata 的 MOA-fine
##      （紫杉烷/微管抑制剂类效应最强、跨细胞系最一致，见 tahoe_prep/08 的实测）。
## 输出（demo/）：
##   tahoe_signature.txt        查询签名（Gene / log2FC，Tab 分隔）
##   tahoe_annotation.txt       药物注释（Compound_name / Group，两类齐全）
## ============================================================
suppressPackageStartupMessages({ library(dplyr); library(rio) })

DEMO_DIR <- "demo"
REF_DS   <- "Tahoe_PAN_0.5uM.rdata"        # 跨细胞系聚合谱（对 MOA 信号最稳）
QDRUG    <- "Paclitaxel"
MOA      <- "Microtubule inhibitor"
TOPN     <- 1000L

dir.create(DEMO_DIR, showWarnings = FALSE, recursive = TRUE)
e <- new.env(); load(file.path("data_preload/drugexp", REF_DS), envir = e)
m <- get("exp_LINCS2020", envir = e)
stopifnot(QDRUG %in% colnames(m))

## ---- 1. 查询签名：某药表达谱的极端基因（演示"逆转检索"的标准用法）----
v <- m[, QDRUG]; v <- v[!is.na(v)]
sig <- data.frame(
  Gene   = c(names(sort(v, decreasing = TRUE))[1:TOPN], names(sort(v))[1:TOPN]),
  log2FC = c(sort(v, decreasing = TRUE)[1:TOPN], sort(v)[1:TOPN]),
  stringsAsFactors = FALSE)
rio::export(sig, file.path(DEMO_DIR, "tahoe_signature.txt"), format = "tsv", row.names = FALSE)
cat(sprintf("签名: %d 基因（%s 在 PAN-0.5uM 的 top%d up/down）\n", nrow(sig), QDRUG, TOPN))

## ---- 2. 药物注释：MOA 类 = Effective，其余 = Ineffective ----
ea <- new.env(); load("data_preload/tahoe/tahoe_drug_ann.rdata", envir = ea)
ann <- get(ls(ea)[1], envir = ea)
eff <- intersect(ann$drug[!is.na(ann$moa_fine) & ann$moa_fine == MOA], colnames(m))
grp <- ifelse(colnames(m) %in% eff, "Effective", "Ineffective")
out <- data.frame(Compound_name = colnames(m), Group = grp, stringsAsFactors = FALSE)
rio::export(out, file.path(DEMO_DIR, "tahoe_annotation.txt"), format = "tsv", row.names = FALSE)
cat(sprintf("注释: %d 药 | Effective %d (%s) | Ineffective %d\n",
            nrow(out), sum(grp == "Effective"), MOA, sum(grp == "Ineffective")))
stopifnot(length(unique(out$Group)) == 2)   # tab_benchmark.R 要求两类齐全
cat("[10] 完成 -> demo/tahoe_signature.txt, demo/tahoe_annotation.txt\n")
