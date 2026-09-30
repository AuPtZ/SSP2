## ============================================================
## 生成 demo/ 下的示例输入文件（2026-09-29 重写）
##
## 设计原则（与 app 的实际校验逻辑一致）：
##  1. 一律 Tab 分隔 + 表头，列名严格为 Gene/log2FC、Compound_name(/Group)。
##  2. 基因必须是 HGNC Symbol 且在参考矩阵 12328 个基因内（SS.R 用
##     intersect() 静默丢弃不匹配的基因，写进去等于白写）。
##  3. 药物名必须与数据集列名（小写 cmap_name / pert_iname）逐字一致：
##     process_raw1() 用 left_join(by = c("pert_iname" = "Compound_name"))，
##     大小写或拼写对不上整条丢失；GSDCIC50/DrugReHub 里混有大写名，故统一 tolower()。
##  4. AUC 注释必须两类标签齐全（tab_benchmark.R 校验
##     sort(unique(Group)) == c("Effective","Ineffective")）。
##
## demo 目标数据集：LINCS_MCF7_10uM_6h（Application 默认 Breast/BRCA，
## 也是 GSDC IC50 与 DrugReHub 命中最多的数据集）。
## 注意：Benchmark 默认数据集 Bone/LINCS_U2OS_10uM_6h 上 GSDC 只命中 33 个药
## 且 Ineffective = 0，做不出合法的两类标注，故 demo 注释按 MCF7/BRCA 生成，
## 用 Benchmark 时需把数据集切到 Breast。
## ============================================================
suppressPackageStartupMessages({
  library(dplyr); library(rio); library(clusterProfiler); library(org.Hs.eg.db)
})

DEMO_DIR   <- "demo"
REF_DS     <- "LINCS_MCF7_10uM_6h.rdata"    # 主 demo（Application 默认数据集）
REF_DS_CS  <- "LINCS_MCF7_10uM_24h.rdata"   # case study（同为乳腺癌，24h）
CANCER     <- "BRCA"

ld <- function(ds) {
  e <- new.env(); load(file.path("data_preload/drugexp", ds), envir = e)
  get(ls(e)[1], envir = e)
}

ref_mat    <- ld(REF_DS)
ref_mat_cs <- ld(REF_DS_CS)
ref_genes  <- rownames(ref_mat)

e <- new.env(); load("data_preload/annotation/GSDCIC50_update.Rdata", envir = e)
GSDCIC50 <- as.data.frame(get("GSDCIC50", envir = e))
e <- new.env(); load("data_preload/annotation/DrugReHub.Rdata", envir = e)
DrugReHub <- as.data.frame(get("DrugReHub", envir = e))
e <- new.env(); load("data_preload/drugconvertor/LINCS2020_drug_info.Rdata", envir = e)
CMAP_druginfo <- as.data.frame(get(ls(e)[1], envir = e))

## ---------- 1. 签名清洗：只保留参考矩阵内的基因 ----------
clean_sig <- function(f) {
  s <- rio::import(file.path(DEMO_DIR, f))
  stopifnot(all(c("Gene", "log2FC") %in% names(s)))
  s %>% mutate(Gene = as.character(Gene), log2FC = as.numeric(log2FC)) %>%
    filter(!is.na(log2FC), Gene != "") %>% distinct(Gene, .keep_all = TRUE) %>%
    filter(Gene %in% ref_genes) %>% arrange(desc(log2FC))
}
sig1 <- clean_sig("signature.txt")
sig2 <- clean_sig("signature2.txt")
ogs  <- clean_sig("CS_OGS.txt")

## ---------- 2. 药物注释（AUC / ES）----------
build_auc <- function(cols, cancer) {
  GSDCIC50 %>% filter(TCGA_DESC == cancer) %>%
    mutate(Compound_name = tolower(Compound_name)) %>%
    filter(Compound_name %in% cols, Group %in% c("Effective", "Ineffective")) %>%
    distinct(Compound_name, Group) %>% arrange(Compound_name) %>% dplyr::select(Compound_name, Group)
}
build_es <- function(cols, cancer) {
  DrugReHub %>% filter(ID == cancer) %>%
    mutate(Compound_name = tolower(Compound_name)) %>%
    filter(Compound_name %in% cols) %>%
    distinct(Compound_name) %>% arrange(Compound_name) %>% dplyr::select(Compound_name)
}
auc_main <- build_auc(colnames(ref_mat),    CANCER)
es_main  <- build_es(colnames(ref_mat),     CANCER)
auc_cs   <- build_auc(colnames(ref_mat_cs), CANCER)
es_cs    <- build_es(colnames(ref_mat_cs),  CANCER)

## ---------- 3. Converter 的 demo ----------
bit <- bitr(sig1$Gene, fromType = "SYMBOL", toType = "ENTREZID", OrgDb = org.Hs.eg.db)
sig_entrez <- sig1 %>% inner_join(bit %>% filter(!is.na(ENTREZID)), by = c("Gene" = "SYMBOL")) %>%
  transmute(Gene = ENTREZID, log2FC = log2FC) %>% distinct(Gene, .keep_all = TRUE)

drug_ids <- CMAP_druginfo %>% filter(!is.na(pert_iname), !is.na(pubchem_cid), !is.na(inchi_key)) %>%
  transmute(Compound_name = tolower(pert_iname), pubchem_cid, inchi_key) %>% distinct(Compound_name, .keep_all = TRUE)
pick <- auc_main %>% inner_join(drug_ids, by = "Compound_name") %>% distinct(Compound_name, .keep_all = TRUE)
pick_ineff <- pick %>% filter(Group == "Ineffective")
pick_eff   <- pick %>% filter(Group == "Effective") %>% head(max(0, 15 - nrow(pick_ineff)))
pick15 <- bind_rows(pick_ineff, pick_eff) %>% arrange(Compound_name)

drug_name    <- pick15 %>% dplyr::select(Compound_name, Group)
drug_pubchem <- pick15 %>% transmute(PubchemCid = as.character(pubchem_cid))
drug_inchi   <- pick15 %>% transmute(inchikey = inchi_key)

## ---------- 4. 落盘 ----------
w <- function(x, f) rio::export(x, file.path(DEMO_DIR, f), format = "tsv", row.names = FALSE)
w(sig1, "signature.txt"); w(sig2, "signature2.txt"); w(ogs, "CS_OGS.txt")
w(auc_main, "drug_annotation_AUC.txt"); w(es_main, "drug_annotation_ES.txt")
w(auc_cs, "CS_AUC.txt"); w(es_cs, "CS_ES.txt")
w(sig_entrez, "demo_signature_entrezid.txt")
w(drug_name, "demo_drug_name.txt"); w(drug_pubchem, "demo_drug_pubchem.txt"); w(drug_inchi, "demo_drug_inchikey.txt")

## ---------- 5. 自检 ----------
cat("\n================ 生成结果 ================\n")
show <- function(f, cols) {
  d <- rio::import(file.path(DEMO_DIR, f))
  cat(sprintf("%-28s %4d 行  列[%s]  列名合规:%s\n", f, nrow(d),
              paste(names(d), collapse = ","), all(cols %in% names(d))))
  d
}
s1 <- show("signature.txt", c("Gene","log2FC")); s2 <- show("signature2.txt", c("Gene","log2FC"))
og <- show("CS_OGS.txt", c("Gene","log2FC"))
a1 <- show("drug_annotation_AUC.txt", c("Compound_name","Group"))
e1 <- show("drug_annotation_ES.txt", c("Compound_name"))
a2 <- show("CS_AUC.txt", c("Compound_name","Group")); e2 <- show("CS_ES.txt", c("Compound_name"))
se <- show("demo_signature_entrezid.txt", c("Gene","log2FC"))
dn <- show("demo_drug_name.txt", c("Compound_name","Group"))
dp <- show("demo_drug_pubchem.txt", c("PubchemCid")); di <- show("demo_drug_inchikey.txt", c("inchikey"))

cat("\n---- 签名 ----\n")
for (nm in c("signature.txt","signature2.txt","CS_OGS.txt")) {
  s <- switch(nm, "signature.txt" = s1, "signature2.txt" = s2, "CS_OGS.txt" = og)
  up <- sum(s$log2FC > 0); dnn <- sum(s$log2FC < 0)
  cat(sprintf("%-16s 基因 %d (全在参考矩阵内:%s)  up %d / down %d  |log2FC|>1: up %d / down %d  topN扫描点 %d\n",
      nm, nrow(s), all(s$Gene %in% ref_genes), up, dnn, sum(s$log2FC > 1), sum(s$log2FC < -1), max(up, dnn) - 9))
}
cat("\n---- 药物注释命中率 ----\n")
for (nm in c("drug_annotation_AUC.txt","drug_annotation_ES.txt","CS_AUC.txt","CS_ES.txt")) {
  d <- switch(nm, "drug_annotation_AUC.txt"=a1, "drug_annotation_ES.txt"=e1, "CS_AUC.txt"=a2, "CS_ES.txt"=e2)
  m <- if (grepl("^CS", nm)) ref_mat_cs else ref_mat
  grp <- if ("Group" %in% names(d)) paste("  Group:", paste(names(table(d$Group)), table(d$Group), sep="=", collapse=" ")) else ""
  cat(sprintf("%-26s 药物 %3d  命中数据集 %3d (%.0f%%)%s\n", nm, nrow(d),
      sum(d$Compound_name %in% colnames(m)), 100*mean(d$Compound_name %in% colnames(m)), grp))
}
cat("\nAUC 两类标签齐全: 主 demo", identical(sort(unique(a1$Group)), c("Effective","Ineffective")),
    " / case study", identical(sort(unique(a2$Group)), c("Effective","Ineffective")), "\n")
cat("\n---- Converter demo ----\n")
cat("EntrezID 版签名:", nrow(se), "行  示例:", paste(head(se$Gene,5), collapse=","), "\n")
cat("药物名 demo 标签:", paste(names(table(dn$Group)), table(dn$Group), sep="=", collapse=" "), "\n")
cat("Pubchem / InChIKey 行数:", nrow(dp), "/", nrow(di), "\n")
cat("\n完成。\n")
