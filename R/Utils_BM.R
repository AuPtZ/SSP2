library(memoise)
library(pROC)
library(ggplot2)

local_cache_folder_BM <- cache_filesystem("cache/BM/")

get_auc_all_i <- function(topn=5,refMatrix,sig_input,IC50_drug,get_ss){
  # print("get_auc_all_i is using")
  sig1_up = sig_input %>%
    dplyr::filter(log2FC > 0) %>%
    dplyr::arrange(desc(log2FC))
  sig1_up = sig1_up$Gene
  
  sig1_dn = sig_input %>%
    dplyr::filter(log2FC < 0)%>%
    dplyr::arrange(log2FC)
  sig1_dn = sig1_dn$Gene
  
  # save(refMatrix,file = "111.Rdata")
  
  res_dr_auc <- list(topn=topn)
  
  # method function
  if ("SS_Xsum" %in% get_ss){
    res_xsum_raw <- XSumScore(refMatrix,
                              queryUp = na.omit(sig1_up[1:topn]) ,
                              queryDown = na.omit(sig1_dn[1:topn]),
                              topN = nrow(refMatrix)/2)
    # save(res_xsum_raw,file = "res_xsum_raw.Rdata")
    res_xsum_roc <- res_xsum_raw %>% process_raw1(drug_info = IC50_drug)
    auc_xsum <- as.numeric(res_xsum_roc$auc)/100
    res_dr_auc[["auc_xsum"]] <- auc_xsum
    
  } 
  
  if ("SS_CMap" %in% get_ss){
    res_ks_raw <- KSScore(refMatrix,
                          queryUp = na.omit(sig1_up[1:topn]) ,
                          queryDown = na.omit(sig1_dn[1:topn]))
    res_ks_roc <- res_ks_raw %>% process_raw1(drug_info = IC50_drug)
    auc_ks <- as.numeric(res_ks_roc$auc)/100
    res_dr_auc[["auc_ks"]] <- auc_ks
    
  }
  
  if ("SS_GSEA" %in% get_ss){
    res_gs_raw <- GSEAweight1Score(refMatrix,
                                   queryUp = na.omit(sig1_up[1:topn]) ,
                                   queryDown = na.omit(sig1_dn[1:topn]))
    res_gs_roc <- res_gs_raw %>% process_raw1(drug_info = IC50_drug)
    auc_gs <- as.numeric(res_gs_roc$auc)/100
    res_dr_auc[["auc_gs"]] <- auc_gs
    
  }
  if ("SS_ZhangScore" %in% get_ss){
    res_zh_raw <- ZhangScore(refMatrix,
                             queryUp = na.omit(sig1_up[1:topn]) ,
                             queryDown = na.omit(sig1_dn[1:topn]))
    res_zh_roc <- res_zh_raw %>% process_raw1(drug_info = IC50_drug)
    auc_zh <- as.numeric(res_zh_roc$auc)/100
    res_dr_auc[["auc_zh"]] <- auc_zh
    
  }
  if ("SS_XCos" %in% get_ss){
    sig_input1 <- sig_input %>% dplyr::filter(log2FC<0) %>% slice_min(log2FC,n = topn)
    sig_input2 <- sig_input %>% dplyr::filter(log2FC>0) %>% slice_max(log2FC,n = topn)
    sig_input3 <- rbind(sig_input2,sig_input1)
    sig_input4 <- setNames(sig_input3$log2FC,sig_input3$Gene)
    res_cos_raw <- XCosScore(refMatrix,
                             query = sig_input4,
                             topN = nrow(refMatrix)/2)
    res_cos_roc <- res_cos_raw %>% process_raw1(drug_info = IC50_drug)
    auc_cos <- as.numeric(res_cos_roc$auc)/100
    res_dr_auc[["auc_cos"]] <- auc_cos
    
  }
  
  # PLAGE / QuSAGE：与 XSum / CMap / GSEA / ZhangScore 同属 up/down 基因集路线。
  # 性能提示：topN 从 10 扫到 1000 约 1000 次调用，PLAGE 每次要做一次特征分解、
  # QuSAGE 每次要估一次基因集内两两相关，首次计算明显慢于原 5 法；
  # get_auc_all 按 topn 做了 memoise，已算过的 topn 会命中缓存。
  if ("SS_PLAGE" %in% get_ss){
    res_plage_raw <- PLAGEScore(refMatrix,
                                queryUp = na.omit(sig1_up[1:topn]) ,
                                queryDown = na.omit(sig1_dn[1:topn]))
    res_plage_roc <- res_plage_raw %>% process_raw1(drug_info = IC50_drug)
    auc_plage <- as.numeric(res_plage_roc$auc)/100
    res_dr_auc[["auc_plage"]] <- auc_plage
    
  }
  
  if ("SS_QuSAGE" %in% get_ss){
    res_qusage_raw <- QuSAGEScore(refMatrix,
                                  queryUp = na.omit(sig1_up[1:topn]) ,
                                  queryDown = na.omit(sig1_dn[1:topn]))
    res_qusage_roc <- res_qusage_raw %>% process_raw1(drug_info = IC50_drug)
    auc_qusage <- as.numeric(res_qusage_roc$auc)/100
    res_dr_auc[["auc_qusage"]] <- auc_qusage
    
  }
  
  # gc()
  # print(paste0("AUC ",topn))
  return(res_dr_auc %>% lapply(round,4))
}

get_es_all_i <- function(topn=5,refMatrix,sig_input,drug_sig,get_ss){
  # print("get_es_all_i is using")
  sig1_up = sig_input %>%
    dplyr::filter(log2FC > 0) %>%
    dplyr::arrange(desc(log2FC))
  sig1_up = sig1_up$Gene
  
  sig1_dn = sig_input %>%
    dplyr::filter(log2FC < 0)%>%
    dplyr::arrange(log2FC)
  sig1_dn = sig1_dn$Gene
  
  res_dr_es <- list(topn=topn)
  
  # method function
  if ("SS_Xsum" %in% get_ss){
    res_xsum_raw <- XSumScore(refMatrix,
                              queryUp = na.omit(sig1_up[1:topn]) ,
                              queryDown = na.omit(sig1_dn[1:topn]),
                              topN = nrow(refMatrix)/2)
    
    es_xsum <- process_raw2(res_ss_list = setNames(res_xsum_raw[ ,1],rownames(res_xsum_raw)),drug_sig_input = drug_sig)
    
    res_dr_es[["es_xsum"]] <- es_xsum
    
    # rm(res_xsum_raw)
    # rm(es_xsum)
    
  }
  
  
  if ("SS_CMap" %in% get_ss){
    res_ks_raw <- KSScore(refMatrix,
                          queryUp = na.omit(sig1_up[1:topn]) ,
                          queryDown = na.omit(sig1_dn[1:topn]))
    
    es_ks <- process_raw2(res_ss_list = setNames(res_ks_raw[ ,1],rownames(res_ks_raw)),drug_sig_input = drug_sig)
    
    res_dr_es[["es_ks"]] <- es_ks
    
    # rm(res_ks_raw)
    # rm(es_ks)
    
  }
  
  if ("SS_GSEA" %in% get_ss){
    res_gs_raw <- GSEAweight1Score(refMatrix,
                                   queryUp = na.omit(sig1_up[1:topn]) ,
                                   queryDown = na.omit(sig1_dn[1:topn]))
    es_gs <- process_raw2(res_ss_list = setNames(res_gs_raw[ ,1],rownames(res_gs_raw)),drug_sig_input = drug_sig)
    res_dr_es[["es_gs"]] <- es_gs
    
    # rm(res_gs_raw)
    # rm(es_gs)
    
  }
  
  if ("SS_ZhangScore" %in% get_ss){
    res_zh_raw <- ZhangScore(refMatrix,
                             queryUp = na.omit(sig1_up[1:topn]) ,
                             queryDown = na.omit(sig1_dn[1:topn]))
    es_zh <- process_raw2(res_ss_list = setNames(res_zh_raw[ ,1],rownames(res_zh_raw)),drug_sig_input = drug_sig)
    res_dr_es[["es_zh"]] <- es_zh
    
    # rm(res_zh_raw)
    # rm(es_zh)
    
  }
  
  if ("SS_XCos" %in% get_ss){
    sig_input1 <- sig_input %>% dplyr::filter(log2FC<0) %>% slice_min(log2FC,n = topn)
    sig_input2 <- sig_input %>% dplyr::filter(log2FC>0) %>% slice_max(log2FC,n = topn)
    sig_input3 <- rbind(sig_input2,sig_input1)
    sig_input4 <- setNames(sig_input3$log2FC,sig_input3$Gene)
    res_cos_raw <- XCosScore(refMatrix,
                             query = sig_input4,
                             topN = nrow(refMatrix)/2)
    es_cos <- process_raw2(res_ss_list = setNames(res_cos_raw[ ,1],rownames(res_cos_raw)),drug_sig_input = drug_sig)
    res_dr_es[["es_cos"]] <- es_cos
    
  }
  
  # PLAGE / QuSAGE（同 get_auc_all_i 的性能提示：在 topN 扫描下首次计算更慢，
  # get_es_all 按 topn memoise，缓存命中后复用）
  if ("SS_PLAGE" %in% get_ss){
    res_plage_raw <- PLAGEScore(refMatrix,
                                queryUp = na.omit(sig1_up[1:topn]) ,
                                queryDown = na.omit(sig1_dn[1:topn]))
    es_plage <- process_raw2(res_ss_list = setNames(res_plage_raw[ ,1],rownames(res_plage_raw)),drug_sig_input = drug_sig)
    res_dr_es[["es_plage"]] <- es_plage
    
  }
  
  if ("SS_QuSAGE" %in% get_ss){
    res_qusage_raw <- QuSAGEScore(refMatrix,
                                  queryUp = na.omit(sig1_up[1:topn]) ,
                                  queryDown = na.omit(sig1_dn[1:topn]))
    es_qusage <- process_raw2(res_ss_list = setNames(res_qusage_raw[ ,1],rownames(res_qusage_raw)),drug_sig_input = drug_sig)
    res_dr_es[["es_qusage"]] <- es_qusage
    
  }
  
  # print(paste0("ES ",topn))
  return( res_dr_es %>% lapply(round,4) )
  
}

get_benchmark_i <- function(IC50_drug,FDA_drug, i.need.logfc ,sel_exp,sel_ss,
                             filter_mode = "topN"){
  
  # print("进入get_benchmark_i")
  cores = get_cores()
  
  # ---- 进度总步数：AUC 与 ES 各扫一遍，扫描点数之和即为总步数 ----
  # 每个扫描点完成时会由 get_dr_auc_i / get_dr_es_i 打点一次。
  n_scan <- function() {
    if (filter_mode == "logFC")
      length(seq(0.5, min(get_fcth(i.need.logfc), 3.0), by = 0.05))
    else
      # topN 模式：扫到「单方向签名基因数」为止（封顶 1000），下限保底 10
      length(seq(from = 10, to = max(10L, min(get_topn(i.need.logfc), 1000L)), by = 1))
  }
  n_auc <- if (is.null(IC50_drug)) 0L else n_scan()
  n_es  <- if (is.null(FDA_drug))  0L else n_scan()
  init_job_progress(get_job_context(), n_auc + n_es, "Benchmark scanning")
  
  ###################
  ### AUC part
  ###################
  if(!is.null(IC50_drug)){

    if (filter_mode == "logFC") {
      res_ic50 <- get_dr_auc_fc(IC50_drug = IC50_drug,
                                 i.need.logfc = i.need.logfc,
                                 sel_exp = sel_exp,
                                 sel_ss = sel_ss,
                                 cores = cores) %>% rename(any_of(rename_col_rules))
    } else {
      res_ic50 <- get_dr_auc(IC50_drug = IC50_drug,
                             i.need.logfc = i.need.logfc,
                             sel_exp = sel_exp,
                             sel_ss = sel_ss,
                             cores = cores) %>% rename(any_of(rename_col_rules))
    }
    
    if(is.null(FDA_drug)){
      lab <- if (filter_mode == "logFC") "AUC_FC" else "AUC"
      return(list(patch_output = res_ic50, label_output = lab))
    }
  }
  
  ###################
  ### ES part
  ###################
  if(!is.null(FDA_drug)){

    if (filter_mode == "logFC") {
      res_fda <- get_dr_es_fc(FDA_drug = FDA_drug,
                               i.need.logfc = i.need.logfc,
                               sel_exp = sel_exp,
                               sel_ss = sel_ss,
                               cores = cores) %>% rename(any_of(rename_col_rules))
    } else {
      res_fda <- get_dr_es(FDA_drug = FDA_drug,
                           i.need.logfc = i.need.logfc,
                           sel_exp = sel_exp,
                           sel_ss = sel_ss,
                           cores = cores) %>% rename(any_of(rename_col_rules))
    }
    
    if(is.null(IC50_drug)){
      lab <- if (filter_mode == "logFC") "ES_FC" else "ES"
      return(list(patch_output = res_fda, label_output = lab))
    }
  }
  
  # both exist
  if(!is.null(FDA_drug) & !is.null(IC50_drug)){
    return(list(patch_output_auc = res_ic50,
                patch_output_es = res_fda,
                label_output = if (filter_mode == "logFC") "ALL_FC" else "ALL"))
  }
}

get_dr_auc_i <- function(IC50_drug,i.need.logfc,sel_exp,sel_ss,cores){
  
  load(paste0("data_preload/drugexp/",sel_exp))
  
  IC50_GSE92742 <- exp_LINCS2020[, colnames(exp_LINCS2020) %in% IC50_drug$`Compound_name`,drop=F]
  
  # topN 扫描范围：10 到「单方向签名基因数」（封顶 1000）。
  # 超过该基因数后 up/down 基因集已取满，再增大 topn 打分不变（曲线进平台），
  # 故截断到饱和点，不再算无意义的平台段。小签名时下限保底 10，避免 seq 反向。
  # get_auc_all 按 topn 值 memoise，已算过的 topn 会命中缓存。
  topn_seq <- seq(from = 10, to = max(10L, min(get_topn(i.need.logfc), 1000L)), by = 1)
  patch_auc_sum <- parallel::mclapply(topn_seq, function(tn) {
    out <- get_auc_all(tn,
                       refMatrix = IC50_GSE92742,
                       sig_input = i.need.logfc,
                       IC50_drug = IC50_drug,
                       get_ss = sel_ss)
    tick_job_progress()   # fork 子进程内打点：完成一个 topN 扫描点
    out
  }, mc.cores = cores)
  # save(patch_auc_sum,file = "patch_auc_sum.Rdata")
  patch_auc_sum <- do.call(rbind, patch_auc_sum) %>% tibble::as_tibble() %>% 
    dplyr::transmute( across(where(is.list),unlist )) 

  # 找到整个表格中最大值所在的列的列名
  max_col_name <- colnames(patch_auc_sum[-1])[which(patch_auc_sum[-1] == max(patch_auc_sum[-1], na.rm = TRUE), arr.ind = TRUE)[1, "col"]]
  
  # 按照该列从大到小排序
  sorted_max_df <- patch_auc_sum %>% dplyr::arrange(desc(!!rlang::sym(max_col_name)))
  
  return(sorted_max_df)
  
}

get_dr_es_i <- function(FDA_drug, i.need.logfc, sel_exp,sel_ss,cores){

  load(paste0("data_preload/drugexp/",sel_exp))
  
  # 同 AUC：topN 扫描上限取「单方向签名基因数」（封顶 1000），扫到饱和为止。
  topn_seq <- seq(from = 10, to = max(10L, min(get_topn(i.need.logfc), 1000L)), by = 1)
  patch_es_sum <- parallel::mclapply(topn_seq, function(tn) {
    out <- get_es_all(tn,
                      refMatrix = exp_LINCS2020,
                      sig_input = i.need.logfc,
                      drug_sig = FDA_drug$`Compound_name`,
                      get_ss = sel_ss)
    tick_job_progress()   # fork 子进程内打点：完成一个 topN 扫描点
    out
  }, mc.cores = cores)
  
  
  patch_es_sum <- do.call(rbind, patch_es_sum) %>% tibble::as_tibble() %>% 
    dplyr::transmute( across(where(is.list),unlist )) 

  # 找到整个表格中最小值所在的列的列名
  min_col_name <- colnames(patch_es_sum[-1])[which(patch_es_sum[-1] == min(patch_es_sum[-1], na.rm = TRUE), arr.ind = TRUE)[1, "col"]]
  
  # 按照该列从小到大排序
  sorted_min_df <- patch_es_sum %>% dplyr::arrange(!!rlang::sym(min_col_name))
  return(sorted_min_df)
}

# ============================================================
# FC 版本：按 |log2FC| 阈值筛选基因
# ============================================================

get_auc_fc_i <- function(fc = 0.5, refMatrix, sig_input, IC50_drug, get_ss) {
  sig_up <- sig_input %>%
    dplyr::filter(log2FC > fc) %>%
    dplyr::arrange(desc(log2FC)) %>%
    pull(Gene)
  sig_dn <- sig_input %>%
    dplyr::filter(log2FC < -fc) %>%
    dplyr::arrange(log2FC) %>%
    pull(Gene)

  res_dr_auc <- list(FC = fc)
  halfN <- nrow(refMatrix) / 2

  if ("SS_Xsum" %in% get_ss) {
    r <- XSumScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn), topN = halfN)
    res_dr_auc[["auc_xsum"]] <- as.numeric(process_raw1(r, IC50_drug)$auc) / 100
  }
  if ("SS_CMap" %in% get_ss) {
    r <- KSScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_auc[["auc_ks"]] <- as.numeric(process_raw1(r, IC50_drug)$auc) / 100
  }
  if ("SS_GSEA" %in% get_ss) {
    r <- GSEAweight1Score(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_auc[["auc_gs"]] <- as.numeric(process_raw1(r, IC50_drug)$auc) / 100
  }
  if ("SS_ZhangScore" %in% get_ss) {
    r <- ZhangScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_auc[["auc_zh"]] <- as.numeric(process_raw1(r, IC50_drug)$auc) / 100
  }
  if ("SS_XCos" %in% get_ss) {
    sig_f <- sig_input %>% dplyr::filter(abs(log2FC) > fc)
    qv <- setNames(sig_f$log2FC, sig_f$Gene)
    r <- XCosScore(refMatrix, query = qv, topN = halfN)
    res_dr_auc[["auc_cos"]] <- as.numeric(process_raw1(r, IC50_drug)$auc) / 100
  }
  # PLAGE / QuSAGE（性能同 topN 版：首次计算更慢，get_auc_fc 按 fc 值 memoise）
  if ("SS_PLAGE" %in% get_ss) {
    r <- PLAGEScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_auc[["auc_plage"]] <- as.numeric(process_raw1(r, IC50_drug)$auc) / 100
  }
  if ("SS_QuSAGE" %in% get_ss) {
    r <- QuSAGEScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_auc[["auc_qusage"]] <- as.numeric(process_raw1(r, IC50_drug)$auc) / 100
  }
  return(res_dr_auc %>% lapply(round, 4))
}

get_es_fc_i <- function(fc = 0.5, refMatrix, sig_input, drug_sig, get_ss) {
  sig_up <- sig_input %>%
    dplyr::filter(log2FC > fc) %>%
    dplyr::arrange(desc(log2FC)) %>%
    pull(Gene)
  sig_dn <- sig_input %>%
    dplyr::filter(log2FC < -fc) %>%
    dplyr::arrange(log2FC) %>%
    pull(Gene)

  res_dr_es <- list(FC = fc)
  halfN <- nrow(refMatrix) / 2

  if ("SS_Xsum" %in% get_ss) {
    r <- XSumScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn), topN = halfN)
    res_dr_es[["es_xsum"]] <- process_raw2(setNames(r[,1], rownames(r)), drug_sig)
  }
  if ("SS_CMap" %in% get_ss) {
    r <- KSScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_es[["es_ks"]] <- process_raw2(setNames(r[,1], rownames(r)), drug_sig)
  }
  if ("SS_GSEA" %in% get_ss) {
    r <- GSEAweight1Score(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_es[["es_gs"]] <- process_raw2(setNames(r[,1], rownames(r)), drug_sig)
  }
  if ("SS_ZhangScore" %in% get_ss) {
    r <- ZhangScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_es[["es_zh"]] <- process_raw2(setNames(r[,1], rownames(r)), drug_sig)
  }
  if ("SS_XCos" %in% get_ss) {
    sig_f <- sig_input %>% dplyr::filter(abs(log2FC) > fc)
    qv <- setNames(sig_f$log2FC, sig_f$Gene)
    r <- XCosScore(refMatrix, query = qv, topN = halfN)
    res_dr_es[["es_cos"]] <- process_raw2(setNames(r[,1], rownames(r)), drug_sig)
  }
  # PLAGE / QuSAGE（性能同 topN 版：首次计算更慢，get_es_fc 按 fc 值 memoise）
  if ("SS_PLAGE" %in% get_ss) {
    r <- PLAGEScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_es[["es_plage"]] <- process_raw2(setNames(r[,1], rownames(r)), drug_sig)
  }
  if ("SS_QuSAGE" %in% get_ss) {
    r <- QuSAGEScore(refMatrix, queryUp = na.omit(sig_up), queryDown = na.omit(sig_dn))
    res_dr_es[["es_qusage"]] <- process_raw2(setNames(r[,1], rownames(r)), drug_sig)
  }
  return(res_dr_es %>% lapply(round, 4))
}

get_dr_auc_fc_i <- function(IC50_drug, i.need.logfc, sel_exp, sel_ss, cores) {
  load(paste0("data_preload/drugexp/", sel_exp))
  IC50_mat <- exp_LINCS2020[, colnames(exp_LINCS2020) %in% IC50_drug$`Compound_name`, drop = FALSE]
  fc_max <- min(get_fcth(i.need.logfc), 3.0)
  fc_seq <- seq(0.5, fc_max, by = 0.05)

  patch <- parallel::mclapply(fc_seq, function(fc) {
    out <- get_auc_fc(fc, refMatrix = IC50_mat, sig_input = i.need.logfc,
                      IC50_drug = IC50_drug, get_ss = sel_ss)
    tick_job_progress()   # fork 子进程内打点：完成一个 logFC 阈值点
    out
  }, mc.cores = cores)
  patch <- do.call(rbind, patch) %>% tibble::as_tibble() %>%
    dplyr::transmute(across(where(is.list), unlist))
  colnames(patch)[1] <- "logFC"

  max_col <- colnames(patch[-1])[which(patch[-1] == max(patch[-1], na.rm = TRUE), arr.ind = TRUE)[1, "col"]]
  return(patch %>% dplyr::arrange(desc(!!rlang::sym(max_col))))
}

get_dr_es_fc_i <- function(FDA_drug, i.need.logfc, sel_exp, sel_ss, cores) {
  load(paste0("data_preload/drugexp/", sel_exp))
  fc_max <- min(get_fcth(i.need.logfc), 3.0)
  fc_seq <- seq(0.5, fc_max, by = 0.05)

  patch <- parallel::mclapply(fc_seq, function(fc) {
    out <- get_es_fc(fc, refMatrix = exp_LINCS2020, sig_input = i.need.logfc,
                     drug_sig = FDA_drug$`Compound_name`, get_ss = sel_ss)
    tick_job_progress()   # fork 子进程内打点：完成一个 logFC 阈值点
    out
  }, mc.cores = cores)
  patch <- do.call(rbind, patch) %>% tibble::as_tibble() %>%
    dplyr::transmute(across(where(is.list), unlist))
  colnames(patch)[1] <- "logFC"

  min_col <- colnames(patch[-1])[which(patch[-1] == min(patch[-1], na.rm = TRUE), arr.ind = TRUE)[1, "col"]]
  return(patch %>% dplyr::arrange(!!rlang::sym(min_col)))
}

get_auc_fc  <- memoise::memoise(get_auc_fc_i,  cache = local_cache_folder_BM)
get_es_fc   <- memoise::memoise(get_es_fc_i,   cache = local_cache_folder_BM)
get_dr_auc_fc <- memoise::memoise(get_dr_auc_fc_i, cache = local_cache_folder_BM)
get_dr_es_fc  <- memoise::memoise(get_dr_es_fc_i,  cache = local_cache_folder_BM)

get_auc_all <- memoise::memoise(get_auc_all_i,cache = local_cache_folder_BM)
get_es_all <- memoise::memoise(get_es_all_i,cache = local_cache_folder_BM)
get_benchmark <- memoise::memoise(get_benchmark_i,cache = local_cache_folder_BM)
get_dr_auc <- memoise::memoise(get_dr_auc_i,cache = local_cache_folder_BM)
get_dr_es <- memoise::memoise(get_dr_es_i,cache = local_cache_folder_BM)


process_raw1 <- function(res_ss_raw, drug_info) {
  roc1 <- tryCatch({
    # 原有的函数内容
    res_ss <- res_ss_raw %>% rownames_to_column(var = "pert_iname") %>%
      left_join(drug_info, by = c("pert_iname" = "Compound_name")) %>%
      dplyr::select(c("pert_iname", "Group", "Score")) %>%
      distinct(pert_iname, .keep_all = TRUE) %>%
      column_to_rownames(var = "pert_iname") %>%
      mutate(Group = factor(Group, levels = c("Ineffective", "Effective")))
    
    # ★ 2026-10-16：direction 由 ">" 改为 "<"（真 bug 修复）
    #   原写法在 Group levels = c("Ineffective","Effective") 下算出的 AUC 恰好是
    #   `1 - AUROC`：实测真值药平均分数 105.39 vs 非真值 28.91（真药确实排在前），
    #   但旧代码给出 0.477；改为 "<" 后得 0.523，与不依赖 pROC 的 Mann-Whitney
    #   直算（0.6528 @ topN=10）一致。旧作业里已存的 AUC 表是反向的，需重算才一致。
    roc(Group ~ Score, res_ss,
        percent = TRUE,
        ci = FALSE,
        plot = FALSE,
        print.auc = TRUE,
        direction = "<",
        quiet = TRUE)
  }, error = function(e) {
    # 错误处理：创建一个具有ROC值为0的对象（保持原有行为，不中断整条扫描）
    # 2026-10-15：补 message()——此前这里完全静默，导致一次环境相关的失败把整张
    # AUC 表写成 0，而页面/日志都看不出异常（demo2 曾因此 AUC 全零）。
    message(sprintf("[process_raw1] AUC 计算失败，回退为 0：%s", conditionMessage(e)))
    list(auc = 0)
  })
  
  return(roc1)
}

process_raw2 <- function(res_ss_list,drug_sig_input){
  res_drug1 <- gsea1(reflist = sort(res_ss_list,decreasing = T),
                     set = drug_sig_input)
  return(res_drug1)
}

gsea1 <- function(reflist, set, w=1) {
  
  
  # Get elements in set that are in the ref list
  set <- intersect(names(reflist), set)
  
  # Sort the reference list
  # Get the list order, from higher (1)to smaller (n)
  ix <- order(reflist, decreasing=TRUE)
  reflist <- reflist[ix] # Reorder the reference list
  
  # Initialize variables for running sum
  es <- 0
  nes <- 0
  p.value <- 1
  
  # Identify indexes of set within the sorted reference list
  inSet <- rep(0, length(reflist))
  inSet[which(names(reflist) %in% set)] <- 1
  
  ### Compute Enrichment Score
  # Compute running sum for hits
  hits<-abs(reflist*inSet) # Get the values for the elements in the set
  hits<-hits^w # Raise this score to the power of w
  score_hit <- cumsum(hits) # Cumulative sum of hits' scores
  # The cumulative sum is divided by the final  sum value
  score_hit <- score_hit / score_hit[length(score_hit)]
  
  # Compute running sum for non-hits
  score_miss <- cumsum(1-inSet)
  score_miss <- score_miss/score_miss[length(score_miss)]
  
  # The Running Score is the difference between the two scores! Hits - nonhits
  running_score <- score_hit - score_miss
  
  # Safety measure, in the case the random genes have all a weight of 0
  if(all(is.na(running_score))){
    running_score<-rep(0,length(running_score))
  }
  
  # The ES is actually the minimum or maximum Running Scores
  if(abs(max(running_score))>abs(min(running_score))){
    es<-max(running_score)
  } else {
    es<-min(running_score)
  }
  
  return(es)
}



# ---- 绘图拟合方式（2026-09-29 改，仅视觉）----
# 原用 stat_smooth(method="lm", formula=y~I(x^(-1))) 把曲线强制成 1/x 形状：
# 画不出真实的「先降→后升→再进平台」形态（后段会僵成水平线），且 RMSE 比 LOESS 高一倍
# （AUC 0.0353 vs 0.0178；ES 0.1547 vs 0.0763，实测于 991 点 × 7 方法的结果表）。
# 现统一改为 LOESS(span=.75)，se=FALSE 去掉 7 条互相叠加的置信带。
# 关于 span：.3 时每条曲线平均有约 250 个局部极值，视觉上明显发抖；.75 降到约 5 个，
# 与论文 Figure 4B 的观感一致，而 RMSE 仅由 0.0178 升到 0.0260，仍优于原参数化的 0.0353。
# 散点 size=.8 / alpha=.45：alpha=.10 时 7 种方法颜色几乎认不出来（用户反馈）；
# .45 既能分辨颜色，又不至于在近千点密集体把曲线糊掉（对标 eLife 2022, Yang et al., Figure 4B）。
# 注意：最优点虚线仍按原逻辑取单点极值 res_input[1,1]，本次只改视觉，未动推荐逻辑。
# ---- 散点抽稀（2026-10-15 性能优化）----
# 每方法散点超过 max_points 时等间隔取样（默认 150）；loess 仍用全数据拟合
# （geom_smooth 显式传全量 data），曲线形态不变。FC 模式 51 点通常不触发。
.thin_by_method <- function(df, max_points = 150) {
  if (is.null(max_points) || max_points <= 0 || nrow(df) == 0) return(df)
  df %>%
    dplyr::group_by(method) %>%
    dplyr::group_modify(function(d, ...) {
      if (nrow(d) <= max_points) return(d)
      d[sort(seq(1, nrow(d), by = ceiling(nrow(d) / max_points))), , drop = FALSE]
    }) %>%
    dplyr::ungroup()
}

draw_dr_metrics <- function(curve, metric, max_points = 150) {
# 指标曲线绘图：x = 扫描自变量（topN 或 logFC 阈值），y = 指标值
# 水平参考线 = 标签置换零分布（均值虚线 + 95% 分位点线，与扫描自变量无关）
# 散点抽稀到 max_points/方法，loess 平滑仍用全量数据（long_full），曲线形态不变
sweep_col <- names(curve)[1]
d  <- curve[curve$Metric == metric, , drop = FALSE]
dp <- d[, c(sweep_col, "Method", "Value")] %>%
tidyr::pivot_wider(names_from = Method, values_from = Value) %>%
dplyr::mutate(dplyr::across(-1, ~ as.numeric(.)))
long_full <- dp %>% tidyr::pivot_longer(-1, names_to = "method", values_to = "Value") %>%
  dplyr::mutate(method = unname(.bm_disp[method]))    # 显示名与 AUC/ES 表一致
long <- .thin_by_method(long_full, max_points)
# 零分布不再画进图里：95% 参考带会把 y 轴撑得很宽（如 AUROC 的 0.39-0.62），
# 把实际数据压成一条窄带。零分布数值保留在图**下方数据表**的 null_mean / null_q975
# 两列，显著性判据在 Summary 页（置换 p 值）。
ggplot(long, aes(x = .data[[sweep_col]], y = Value)) +
geom_point(aes(color = method), size = 0.8, alpha = 0.45) +
geom_smooth(data = long_full, aes(color = method), method = "loess", span = 0.75,
se = FALSE, linewidth = 0.8) +
    labs(title = .bm_metric_label(metric), x = sweep_col, y = .bm_metric_label(metric),
         subtitle = .bm_peak_label(long_full, sweep_col, "Value", sweep_col)) +
    theme_test() + ggsci::scale_color_npg() +
    theme(plot.subtitle = element_text(size = 9, colour = "grey30"))
}
# ---- 各方法的峰值标记（2026-10-16 方案 B）----
# 用"每条曲线自己的最高点"取代原来贯穿全图的竖线：竖线既与参考线视觉冲突，
# 又只能代表全表最大值那一个点，而各方法的最优 TopN/logFC 并不相同。
.bm_peaks <- function(df, xcol, ycol) {
  df %>% dplyr::group_by(method) %>%
    dplyr::slice_max(order_by = .data[[ycol]], n = 1, with_ties = FALSE) %>%
    dplyr::ungroup()
}

# 图上方的小字：整体最优（哪个方法、在哪个扫描点、值多少）
.bm_peak_label <- function(df, xcol, ycol, xname) {
  p <- .bm_peaks(df, xcol, ycol)
  if (!nrow(p)) return(NULL)
  b <- p[which.max(p[[ycol]]), ]
  mname <- as.character(b$method)
  if (mname %in% names(.bm_disp)) mname <- unname(.bm_disp[mname])
  sprintf("Best: %s at %s = %g  (%s = %.3f)", mname,
          xname, b[[xcol]], ycol, b[[ycol]])
}

# ---- 指标显示名（内部键 -> 界面标签）----
# ES_rank 在界面上就叫 ES：它就是 GSEA 原文的未加权 ES，旧的 |score| 加权 ES
# （零分布偏正 +0.26）已退役，没必要再带 _rank 后缀。内部键保持不变，
# 以免影响 METRICS 结果表、缓存键与旧作业的兼容。
.bm_metric_label <- function(x) {
  # 内部键 -> 界面标签：ES_rank 就是未加权 ES（旧加权 ES 已退役）；
  # RecallAtK / EFpct 用文献里的标准写法（K 默认 20 个药、pct 默认 5%）。
  m <- c(ES_rank = "ES", RecallAtK = "Recall@K", EFpct = "EF@5%")
  ifelse(x %in% names(m), unname(m[x]), x)
}

draw_dr_auc <- function(res_input, max_points = 150){
  
  res_auc <- res_input %>%  as_tibble() %>% pivot_longer(
    cols = -TopN,
    names_to = "method",
    values_to = "AUC") %>% as_tibble() %>%
    mutate(`AUC` = as.numeric(`AUC`),
           `TopN` =as.numeric(`TopN`),
           method = factor(method, levels = c("CMap", "GSEA", "XCos","XSum","ZhangScore","PLAGE","QuSAGE")),
           )
  
  res_pts <- .thin_by_method(res_auc, max_points)
  p1 <- ggplot(data=res_pts, mapping = aes(x=TopN, y=`AUC`)) +
    geom_point(aes(color = method), size = 0.8, alpha = 0.45) +
    geom_smooth(data = res_auc, aes(color = method), method = "loess", span = 0.75,
                se = FALSE, linewidth = 0.8) +
    labs(subtitle = .bm_peak_label(res_auc, "TopN", "AUC", "TopN")) +
    theme_test() + ggsci::scale_color_npg() +
    theme(plot.subtitle = element_text(size = 9, colour = "grey30"))
  
  return(p1)
}

# =============================================================================
# Summary 页：方法 × 指标 总览（2026-10-16）
#
#   metrics_overview()  长表：每个 (Method, Metric) 的 median / max / 零分布 /
#                       相对零分布位置 / 是否显著
#   draw_dr_summary()   热图：填色 = 相对零分布位置（1.0 = 恰好压到置换零分布 95% 分位），
#                       格内文字 = 原始 median，* = median 超过零分布 95% 分位
#
# 为什么颜色用"相对零分布"而非原始值：5 个指标量纲完全不同（AUROC≈0.5、EF 可到 20、
# ES_rank 跨负正），归一化后才能用一张图横向比较"谁比随机好多少"。
#
# ★ 显著性来自结果表里的**逐点置换 p 值** p_null（见 R/Utils_BM_metrics.R 的
#   calc_benchmark_metrics）：frac_p05 = 过半 sweep 点 p < 0.05 的比例，p_best = 最好的 p。
#   不用"median > null_q975"是因为离散指标（Recall@K 只有 k/真值药数 个取值）的 95% 分位
#   恰好落在可达取值上，严格大于号会把"刚好达标"判成不显著；p 值按 P(null >= obs) 计入并列。
#   旧结果文件没有 p_null 列时自动退回保守判据（见 has_p 分支）。
# =============================================================================
.bm_disp <- c(SS_Xsum = "XSum", SS_CMap = "CMap", SS_GSEA = "GSEA",
              SS_ZhangScore = "ZhangScore", SS_XCos = "XCos",
              SS_PLAGE = "PLAGE", SS_QuSAGE = "QuSAGE")

metrics_overview <- function(curve) {
  if (is.null(curve) || nrow(curve) == 0) return(NULL)
  d <- as.data.frame(curve)
  d <- d[d$Metric != "ES_abs", , drop = FALSE]        # 退役对照（无零分布）不进总览
  if (!nrow(d)) return(NULL)
  has_p <- "p_null" %in% names(d)          # 旧结果文件没有 p 列 → 退回保守判据
  parts <- lapply(split(d, list(d$Method, d$Metric), drop = TRUE), function(x) {
    if (!nrow(x)) return(NULL)
    nmv <- unique(x$NullMean)[1]; q <- unique(x$NullQ975)[1]
    den <- q - nmv
    med <- stats::median(x$Value, na.rm = TRUE)
    p_ok <- if (has_p) !all(is.na(x$p_null)) else FALSE
    data.frame(Method    = unname(.bm_disp[unique(x$Method)[1]]),
               Metric    = unique(x$Metric)[1],
               median    = med,
               max       = max(x$Value, na.rm = TRUE),
               null_mean = nmv,
               null_q975 = q,
               # 1.0 = 恰好等于置换零分布 95% 分位；> 1 表示优于随机
               rel_null  = if (is.na(den) || den <= 0) NA_real_ else (med - nmv) / den,
               # 逐点置换 p（计入并列）：最小 p = 扫描里最好的那个签名大小
               p_best    = if (p_ok) min(x$p_null, na.rm = TRUE) else NA_real_,
               # 过半 sweep 点显著优于随机的比例 —— 主判据（比"是否超过 Q975"可靠：
               # 离散指标的 Q975 恰好落在可达取值上时，严格大于号会把"刚好达标"判否）
               frac_p05  = if (p_ok) mean(x$p_null < 0.05, na.rm = TRUE) else NA_real_,
               sig       = if (p_ok) isTRUE(mean(x$p_null < 0.05, na.rm = TRUE) >= 0.5)
                           else isTRUE(med > q),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, parts)
  if (is.null(out)) return(NULL)
  rownames(out) <- NULL
  out$Metric <- .bm_metric_label(out$Metric)   # 界面显示名（ES / Recall@K / EF@5%）
  out[order(out$Metric, -out$rel_null), ]
}

draw_dr_summary <- function(curve) {
  s <- metrics_overview(curve)
  if (is.null(s) || !nrow(s)) return(NULL)
  ord <- .bm_metric_label(c("ES_rank", "AUPRC", "RecallAtK", "EFpct", "AUROC"))
  s$Method <- factor(s$Method, levels = rev(sort(unique(s$Method))))
  s$Metric <- factor(s$Metric, levels = c(ord, setdiff(unique(as.character(s$Metric)), ord)))
  s$lab <- sprintf("%.3f%s", s$median, ifelse(s$sig, " *", ""))
  ggplot(s, aes(x = Metric, y = Method, fill = rel_null)) +
    geom_tile(color = "white", linewidth = 0.6) +
    geom_text(aes(label = lab), size = 3.1) +
    scale_fill_gradient2(low = "#2166AC", mid = "#F7F7F7", high = "#B2182B",
                         midpoint = 1, limits = c(0, 2),
                         name = "vs permutation null\n(1.0 = null 95% line)") +
    theme_minimal(base_size = 11) +
    theme(panel.grid = element_blank(), axis.title = element_blank(),
          plot.title = element_text(size = 12, face = "bold"),
          plot.caption = element_text(size = 8, colour = "grey35"),
          plot.margin = margin(8, 8, 4, 8)) +
    labs(title = "Benchmark overview: method x metric",
         caption = paste0("Tile colour = (median - null mean) / (null 95% - null mean); 1.0 = at the 95% permutation line.\n",
                           "Cell text = raw median;  * = significant (permutation p < 0.05) in more than half of the swept signature sizes."))
}

draw_dr_es <- function(res_input, max_points = 150){
  res_es <- res_input %>% as_tibble() %>% pivot_longer(
    cols = -TopN,
    names_to = "method",
    values_to = "ES") %>% as_tibble() %>%
    mutate(`ES` = as.numeric(`ES`),
           `TopN` =as.numeric(`TopN`),
           method = factor(method, levels = c("CMap", "GSEA", "XCos","XSum","ZhangScore","PLAGE","QuSAGE")),
    )

  
  res_pts <- .thin_by_method(res_es, max_points)
  p2 <- ggplot(data=res_pts, mapping = aes(x=TopN, y=`ES`)) +
    geom_point(aes(color = method), size = 0.8, alpha = 0.45) +
    geom_smooth(data = res_es, aes(color = method), method = "loess", span = 0.75,
                se = FALSE, linewidth = 0.8) +
    labs(subtitle = .bm_peak_label(res_es, "TopN", "ES", "TopN")) +
    theme_test() + ggsci::scale_color_npg() +
    theme(plot.subtitle = element_text(size = 9, colour = "grey30"))
  return(p2)
}

# 判断上调下调的基因数量，用于设置读取的topN的值,取最大值
get_topn <- function(sig_input){
  
  n_up = sig_input %>%
    dplyr::filter(log2FC > 0) %>% nrow()
  
  n_dn = sig_input %>%
    dplyr::filter(log2FC < 0) %>% nrow()
  
  return(max(n_up, n_dn))
}

# 获取 log2FC 最大绝对值，用于 FC 模式阈值上限
get_fcth <- function(sig_input) {
  max_abs <- sig_input$log2FC %>% abs() %>% max(na.rm = TRUE)
  return(round(max_abs, 1))
}

# FC 版 AUC 绘图
draw_dr_auc_fc <- function(res_input, max_points = 150) {
  res_auc <- res_input %>% as_tibble() %>% pivot_longer(
    cols = -logFC, names_to = "method", values_to = "AUC") %>%
    mutate(AUC = as.numeric(AUC), logFC = as.numeric(logFC),
           method = factor(method, levels = c("CMap","GSEA","XCos","XSum","ZhangScore","PLAGE","QuSAGE")))

  res_pts <- .thin_by_method(res_auc, max_points)
  ggplot(res_pts, aes(x = logFC, y = AUC)) +
    geom_point(aes(color = method), size = 0.8, alpha = 0.45) +
    geom_smooth(data = res_auc, aes(color = method), method = "loess", span = 0.75,
                se = FALSE, linewidth = 0.8) +
    labs(subtitle = .bm_peak_label(res_auc, "logFC", "AUC", "|log2FC|")) +
    theme_test() + ggsci::scale_color_npg() +
    theme(plot.subtitle = element_text(size = 9, colour = "grey30")) +
    xlab("|log2FC| threshold")
}

# FC 版 ES 绘图
draw_dr_es_fc <- function(res_input, max_points = 150) {
  res_es <- res_input %>% as_tibble() %>% pivot_longer(
    cols = -logFC, names_to = "method", values_to = "ES") %>%
    mutate(ES = as.numeric(ES), logFC = as.numeric(logFC),
           method = factor(method, levels = c("CMap","GSEA","XCos","XSum","ZhangScore","PLAGE","QuSAGE")))

  res_pts <- .thin_by_method(res_es, max_points)
  ggplot(res_pts, aes(x = logFC, y = ES)) +
    geom_point(aes(color = method), size = 0.8, alpha = 0.45) +
    geom_smooth(data = res_es, aes(color = method), method = "loess", span = 0.75,
                se = FALSE, linewidth = 0.8) +
    labs(subtitle = .bm_peak_label(res_es, "logFC", "ES", "|log2FC|")) +
    theme_test() + ggsci::scale_color_npg() +
    theme(plot.subtitle = element_text(size = 9, colour = "grey30")) +
    xlab("|log2FC| threshold")
}

