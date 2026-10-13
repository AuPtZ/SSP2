# In this script include packages, functions, datasets and anyting that will be 
# used both by UI and server


############################.
##Packages ----
############################.
library(shiny)
library(shinyBS) #modals
library(bslib)        # Bootstrap 5 modern UI
library(bsicons)      # Bootstrap icons
library(dplyr) # data manipulation
library(ggplot2) #data visualization
library(DT) # for data tables
library(plotly) # interactive graphs
library(shinyWidgets) # for extra widgets
library(tibble) # rownames to column in techdoc
library(shinyjs)
library(shinycssloaders) #for loading icons, see line below
# it uses github version devtools::install_github("andrewsali/shinycssloaders")
# This is to avoid issues with loading symbols behind charts and perhaps with bouncing of app
library(rmarkdown)
library(pROC)
library(dplyr)
library(rio)
library(tidyr)

library(magrittr)

# 方案C：重型计算已迁移到独立的 worker.R 进程（作业队列模式），
# app / global 不再需要 future / promises / plan(multisession)，启动更快。

# 加载可视化的数据，用于UI显示
load("data_preload/others/drug_num_list1.rdata") # 读取数据内容
# 每个数据集的基因数（LINCS 12,328 landmark / Tahoe 62,710 全基因）
gene_num_list1 <- NULL
if (file.exists("data_preload/others/gene_num_list1.rdata")) {
  load("data_preload/others/gene_num_list1.rdata")
}

# 药物基本信息表：LINCS 药物名 -> PubChem 化学身份/理化性质/别名/作用机制。
# 由 maintain/09抓取PubChem药物信息.R 离线抓取生成（不存在则跳过，功能自动降级）。
# 用途：Application 结果表点某一行时弹出该药物的详情。
drug_info_pubchem <- NULL
DRUG_INFO_FILE <- "data_preload/drugconvertor/drug_info_pubchem.Rdata"
if (file.exists(DRUG_INFO_FILE)) {
  di_env <- new.env(); load(DRUG_INFO_FILE, envir = di_env)   # 不依赖文件里的对象名
  drug_info_pubchem <- as.data.frame(get(ls(di_env)[1], envir = di_env),
                                     stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------------------
# 各页面两级联动（tissue -> dataset）所需数据结构
# tissue 由 cellinfo_beta.txt 的 cell_iname -> cell_lineage（组织来源）推导；
# cell_lineage 缺失时回退到 subtype，再缺失归为 "Other"。
# 若需覆盖某个 cell line 的 tissue 归属，在下方 cellline_tissue_override 中指定即可。
# ---------------------------------------------------------------------------
cellinfo_path <- "/home/data/dataportal/LINCS2020/cellinfo_beta.txt"
if (file.exists(cellinfo_path)) {
  ci_raw <- data.table::fread(
    cellinfo_path, sep = "\t", header = TRUE,
    select = c("cell_iname", "cell_lineage", "subtype")
  )
  ci <- data.frame(
    cell_iname = ci_raw$cell_iname,
    lineage    = ci_raw$cell_lineage,
    subtype    = ci_raw$subtype,
    stringsAsFactors = FALSE
  )
  ci <- ci[!duplicated(ci$cell_iname), ]

  tissue_raw <- ci$lineage
  na_idx <- is.na(tissue_raw) | tissue_raw %in% c("", "unknown", "Unknown")
  tissue_raw[na_idx] <- ci$subtype[na_idx]
  na_idx <- is.na(tissue_raw) | tissue_raw %in% c("", "unknown", "Unknown")
  tissue_raw[na_idx] <- "Other"
  # 轻度美化：首字母大写、下划线转空格（skin -> Skin, large_intestine -> Large Intestine）
  tissue_raw <- tools::toTitleCase(gsub("_", " ", tissue_raw))

  cellline_tissue <- setNames(tissue_raw, ci$cell_iname)
} else {
  # 兜底：保留原有手写映射（cellinfo 不可用时）
  cellline_tissue <- c(
    A375     = "Skin", A549 = "Lung", ASC = "Other", HA1E = "Liver",
    HCC515   = "Lung", HELA = "Cervix", HEPG2 = "Liver", HT29 = "Colon",
    MCF10A   = "Breast", MCF7 = "Breast", NPC = "Nasopharynx", PC3 = "Prostate",
    U2OS     = "Bone", VCAP = "Prostate", `XC.L10` = "Breast", YAPC = "Pancreas"
  )
}
# 可选的手写覆盖（优先级最高）
cellline_tissue_override <- c()
cellline_tissue[names(cellline_tissue_override)] <- cellline_tissue_override

# Tahoe-100M 的细胞系不在 LINCS cellinfo 里，用官方 cell_line_metadata 的 Organ 补上。
# 只补 LINCS 映射里没有的，避免覆盖已有的手写覆盖。
if (file.exists("data_preload/tahoe/cellline_organ.rdata")) {
  tahoe_env <- new.env()
  load("data_preload/tahoe/cellline_organ.rdata", envir = tahoe_env)
  if (exists("cellline_organ", envir = tahoe_env)) {
    tahoe_organ <- get("cellline_organ", envir = tahoe_env)
    # 文件名里的细胞系名做过安全化（HepG2/C3A -> HepG2-C3A），两种写法都要能匹配上
    tahoe_safe  <- setNames(tahoe_organ, gsub("[/\\\\:*?\"<>|]", "-", names(tahoe_organ)))
    tahoe_all   <- c(tahoe_organ, tahoe_safe)
    tahoe_all   <- tahoe_all[!duplicated(names(tahoe_all))]
    add_cells   <- setdiff(names(tahoe_all), names(cellline_tissue))
    cellline_tissue <- c(cellline_tissue, tahoe_all[add_cells])
  }
}

dl_files   <- unname(drug_num_list1)
dl_names   <- names(drug_num_list1)
# 数据源：LINCS（12,328 基因 × 1,000+ 药）或 Tahoe-100M（62,710 基因 × 379 药 × 47 细胞系）
dl_src     <- ifelse(grepl("^Tahoe_", dl_files), "Tahoe-100M", "LINCS")
# 细胞系名可能含空格/连字符/下划线（Hs 766T、SW 1088、HepG2-C3A），
# 所以不能"取到第一个下划线为止"；改为剥掉前缀和尾部的"剂量(_时间)"再取剩余部分。
# LINCS:  LINCS_MCF7_10uM_6h.rdata      -> MCF7
# Tahoe:  Tahoe_COLO 205_0.05uM.rdata   -> COLO 205（无时间维度）
dl_cl      <- sub("^(?:LINCS|Tahoe)_", "", dl_files)
dl_cl      <- sub("_[0-9.]+uM(_[0-9]+h)?\\.rdata$", "", dl_cl)
dl_tissue  <- cellline_tissue[dl_cl]
dl_tissue[is.na(dl_tissue)] <- "Other"
# 跨细胞系聚合的 PAN 不是一个真实细胞系，单独给个组织名
dl_tissue[dl_cl == "PAN"] <- "Pan-cell line"

# 三级结构：数据源 -> 组织 -> 数据集（app.R 的两级联动升级为三级）
DATA_SOURCES <- c("LINCS", "Tahoe-100M")
drug_num_list_by_source_tissue <- list()
for (s in DATA_SOURCES) {
  idx_s <- which(dl_src == s)
  if (!length(idx_s)) next
  ts <- sort(unique(dl_tissue[idx_s]))
  drug_num_list_by_source_tissue[[s]] <- setNames(
    lapply(ts, function(t) {
      k <- idx_s[dl_tissue[idx_s] == t]
      setNames(dl_files[k], dl_names[k])
    }), ts)
}
# 默认数据源：Tahoe-100M（本平台的主数据源），没有 Tahoe 数据时回退到 LINCS
DEFAULT_SOURCE <- if ("Tahoe-100M" %in% names(drug_num_list_by_source_tissue)) {
  "Tahoe-100M"
} else names(drug_num_list_by_source_tissue)[1]
# 兼容旧代码：drug_num_list_by_tissue 指向默认数据源的组织->数据集列表
drug_num_list_by_tissue <- drug_num_list_by_source_tissue[[DEFAULT_SOURCE]]

# 各页面默认选中项：随默认数据源自动适配
# （Tahoe 的器官里没有 Bone，硬编码会在切换数据源后变成空下拉）
first_in <- function(t) if (t %in% names(drug_num_list_by_tissue)) {
  unname(drug_num_list_by_tissue[[t]][1])
} else unname(drug_num_list_by_tissue[[1]][1])
DEFAULT_TISSUE_BM <- if ("Bone"   %in% names(drug_num_list_by_tissue)) "Bone"   else names(drug_num_list_by_tissue)[1]
DEFAULT_TISSUE_SM <- if ("Breast" %in% names(drug_num_list_by_tissue)) "Breast" else names(drug_num_list_by_tissue)[1]
DEFAULT_DS_BM     <- first_in(DEFAULT_TISSUE_BM)
DEFAULT_DS_SM     <- first_in(DEFAULT_TISSUE_SM)
load("data_preload/annotation/disinfo_vector.Rdata")
load("data_preload/annotation/disinfo_vector2.Rdata")
load("data_preload/others/landmark.rdata")

# Step 标题后显示一个 ? 问号图标，点击该图标弹出说明文字
# 参考 bslib Shiny Workflows 4.6：popovers 由触发元素点击展开
step_pop <- function(title, help, popover_title = NULL) {
  help_icon <- span(
    bs_icon("question-circle"),
    class = "step-pop-help ms-1",
    style = "cursor: help; color: #0d6efd; vertical-align: -0.1em;"
  ) |>
    popover(HTML(help), title = popover_title)

  tagList(title, help_icon)
}




# 从数据中动态获取细胞系、剂量、时间列表
# combinations.Rdata 由 maintain/00_生成基因映射和组合信息.R 生成
load("data_preload/combinations.Rdata")  # combinations data.frame
cellline_list <- sort(unique(combinations$cell_iname))
dose_list     <- sort(unique(combinations$pert_idose_str))
time_list     <- sort(unique(combinations$pert_itime_str))

ss_list <- list(
  Xsum = "SS_Xsum",
  CMap = "SS_CMap",
  GSEA = "SS_GSEA",
  ZhangScore = "SS_ZhangScore",
  XCos = "SS_XCos",
  PLAGE = "SS_PLAGE",
  QuSAGE = "SS_QuSAGE"
)

# 首页统计卡片用到的汇总数字（动态计算，避免硬编码）
n_tissue   <- length(unique(unlist(lapply(drug_num_list_by_source_tissue, names))))
n_cellline <- length(unique(dl_cl))             # 细胞系数
n_method   <- length(ss_list)                   # Signature Search Method 数
n_gene     <- if (!is.null(gene_num_list1) && length(gene_num_list1)) {
  max(gene_num_list1, na.rm = TRUE)             # 取各数据集的最大值（Tahoe 62,710 / LINCS 12,328）
} else 12328

sm_quadrant <- list(
  Q1 = "Q1",
  Q2="Q2",
  Q3="Q3",
  Q4="Q4",
  all = "all"
)


sm_direct <- list(
  up = "Up",
  down = "Down"
)



name_for_res_col <- data.frame(
  Jobid="Job id",
  Submitted_time="Submission time",
  main_module="Main module",
  table_num="Number of table",
  method_bm="Signature Search method used",
  signature_file1="Signature file name",
  fda_file="Annotation file name for ES",
  ic50_file="Annotation file name for AUC",
  drug_profile="Drug profile name",
  sub_module="Sub module",
  method_sm1="Signature Search method used",
  direction_sm="direction (For SS_all)",
  method_sm2="Signature Search method used",
  signature_file2="Signature file name",
  signature_file3="Signature file 1 name",
  signature_file4="Signature file 2 name",
  signature_name1="Signature annotation 1",
  signature_name2="Signature annotation 1",
  sel_num_gene="Number of gene used",
  filter_mode="Filter mode",
  filter_value="Filter value"
)

# 将多个算法输出的结果进行替换
rename_col_rules <- c("XSum" = "auc_xsum", 
                      "CMap" = "auc_ks",
                      "GSEA" = "auc_gs", 
                      "ZhangScore" = "auc_zh", 
                      "XCos" = "auc_cos",
                      "XSum" = "es_xsum", 
                      "CMap" = "es_ks",
                      "GSEA" = "es_gs", 
                      "ZhangScore" = "es_zh", 
                      "XCos"= "es_cos",
                      "TopN" = "topn",
                      "XSum" = "SS_Xsum", 
                      "CMap" = "SS_CMap",
                      "GSEA" = "SS_GSEA", 
                      "ZhangScore" = "SS_ZhangScore", 
                      "XCos" = "SS_XCos",
                      "XSum" = "xsum", 
                      "CMap" = "cmap",
                      "GSEA" = "gsea", 
                      "ZhangScore" = "zhangscore", 
                      "XCos" = "cos",
                      "PLAGE" = "auc_plage", "QuSAGE" = "auc_qusage",
                      "PLAGE" = "es_plage",  "QuSAGE" = "es_qusage",
                      "PLAGE" = "SS_PLAGE",  "QuSAGE" = "SS_QuSAGE",
                      "PLAGE" = "plage",     "QuSAGE" = "qusage",
                      "Name" = "name",
                      "ScoreSum" = "cal_label",
                      "P_value" = "nominal_padj",
                      "Block" = "block",
                      "Method" = "method",
                      "P_adjust" = "p.adjust",
                      "P_value" = "pvalue"
                      
                    
)


# 决定使用多少个核心
get_cores <- function(){
  if(Sys.info()[[1]] != "Linux" ){
    return(1L)
  }else{
    cores <-  parallel::detectCores()
    # 原本对大核机器(>15)按 0.25 折算，96 核机器因此只用到 24 核：实测 load
    # 长期停在 27/96（约 28% 利用率），内存也远未吃满（可用 554G）。
    # Benchmark 的 mclapply 只在「扫描点」维度并行，而扫描点数(991)远多于核数，
    # 并行效率很高，所以提高并发是实打实的收益。统一按 0.5 折算
    # （96 核 -> 48 进程），同样负载下约快一倍。
    return( round(0.5*cores))
  }
}

print(paste0("WE DECIDED TO USE ",get_cores()," CORES"))

# update sessionInfo when NECESSARY
if(F){
  sI = sessioninfo::session_info()
  save(sI,file = "sessioninfo.rdata" )
}


# 将输入的名字规范化
find_original_names <- function(input_names) {
  # 使用lapply遍历输入向量，并为每个元素找到原始键名
  original_names <- lapply(input_names, function(input_name) {
    reversed_rules <- names(rename_col_rules)[match(input_name, rename_col_rules)]
    if (length(reversed_rules) == 0) {
      return(NA)  # 如果没有找到匹配项，返回NA
    } else {
      return(reversed_rules[1])  # 返回找到的第一个匹配项
    }
  })
  
  # 将列表转换为向量
  return(unlist(original_names))
}


