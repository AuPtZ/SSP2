# ============================================================
# SSP2 数据预处理 - 步骤2: 生成下拉选项列表
#
# 功能: 扫描 data_preload/drugexp/ 下所有药物表达谱文件，
#       统计药物数量，生成 Shiny 下拉选项
#
# 输出:
#   data_preload/others/drug_num_list.rdata
#   data_preload/others/drug_num_list1.rdata
# ============================================================

library(dplyr)
library(purrr)

cat("扫描 drug expression profiles ...\n")

profile_list <- list.files("data_preload/drugexp/", pattern = "\\.rdata$")

if (length(profile_list) == 0) {
  stop("data_preload/drugexp/ 中没有找到 .rdata 文件，请先运行 01处理数据预生成.R")
}

get_drug_num <- function(profile_file) {
  load(file.path("data_preload/drugexp/", profile_file))
  drug_num <- ncol(exp_GSE92742)
  rm(exp_GSE92742, sig_GSE92742)
  
  # 生成显示名称
  disp_name <- gsub("\\.rdata$", "", profile_file)
  disp_name <- gsub("_", " ", disp_name)
  disp_name <- gsub("LINCS ", "", disp_name)
  disp_name <- paste0("LINCS ", disp_name, " (", drug_num, " drugs)")
  
  gc()
  return(data.frame(
    profile_file = profile_file,
    profile_name = disp_name,
    drug_num     = drug_num,
    stringsAsFactors = FALSE
  ))
}

drug_num_list <- map_dfr(profile_list, get_drug_num)
drug_num_list <- drug_num_list[order(-drug_num_list$drug_num), ]

# 命名字符向量（UI 下拉用）
drug_num_list1 <- setNames(drug_num_list$profile_file, drug_num_list$profile_name)

cat(sprintf("共 %d 个药物表达谱\n", nrow(drug_num_list)))
print(head(drug_num_list, 10))

save(drug_num_list,  file = "data_preload/others/drug_num_list.rdata")
save(drug_num_list1, file = "data_preload/others/drug_num_list1.rdata")
cat("完成! drug_num_list 已保存\n")
