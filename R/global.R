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

dl_files   <- unname(drug_num_list1)
dl_names   <- names(drug_num_list1)
dl_cl      <- sub("^LINCS_([^_]+)_.*", "\\1", dl_files)
dl_tissue  <- cellline_tissue[dl_cl]
dl_tissue[is.na(dl_tissue)] <- "Other"

drug_num_list_by_tissue <- list()
for (t in sort(unique(dl_tissue))) {
  idx <- which(dl_tissue == t)
  drug_num_list_by_tissue[[t]] <- setNames(dl_files[idx], dl_names[idx])
}
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
  XCos = "SS_XCos"
)

# 首页统计卡片用到的汇总数字（动态计算，避免硬编码）
n_tissue   <- length(drug_num_list_by_tissue)   # tissue（组织来源）类别数
n_cellline <- length(unique(dl_cl))             # 细胞系数
n_method   <- length(ss_list)                   # Signature Search Method 数
n_gene     <- 12328                             # LINCS2020 landmark 基因数

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
    return( ifelse( cores> 15, round(0.25*cores), round(0.5*cores)))
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


