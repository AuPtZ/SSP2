library(memoise)
library(dplyr) # 为了future正常运行使用的
library(tidyr)
library(tidyverse)

local_cache_folder_SM <- cache_filesystem("cache/SM/")

# 主要函数
get_single_method_i  <- function(drug_profile, topn = NULL, filter_mode = "topN",
                               fc_threshold = NULL, sel_model_sm1, i.need.logfc,
                               funcname, funcname_mul,
                               direct, bioname1, bioname2){

  # print("进入get_single_method_i")
  req(!is.null(drug_profile))
  load(paste0("data_preload/drugexp/",drug_profile))
  
  # 按需计算排序索引（不在 01 中预存，节省磁盘和预处理时间）
  # 对 ~7000 药物 × 12328 基因的矩阵，此处约需 0.5~2 秒
  if (!exists("drug_rank_idx") || is.null(drug_rank_idx)) {
    ncores <- min(parallel::detectCores() - 2, ncol(exp_LINCS2020))
    drug_rank_idx <- do.call(cbind, parallel::mclapply(
      1:ncol(exp_LINCS2020),
      function(i) order(exp_LINCS2020[, i], decreasing = TRUE),
      mc.cores = ncores
    ))
  }
  
  if(sel_model_sm1 == "singlemethod"){
    
    res_sm <- get_single_res(funcname = funcname,
                             refMatrix = exp_LINCS2020,
                             sig_input = i.need.logfc,
                             topn = topn,
                             filter_mode = filter_mode,
                             fc_threshold = fc_threshold,
                             drug_profile = drug_profile,
                             drug_rank_idx = drug_rank_idx)
    p_sm <- draw_single(res_sm)
  }
  
  if(sel_model_sm1 == "SS_all"){
    
    res_sm <- get_ss_all_res(refMatrix = exp_LINCS2020,
                             sig_input = i.need.logfc,
                             funcname_mul = funcname_mul,
                             topn = topn,
                             filter_mode = filter_mode,
                             fc_threshold = fc_threshold,
                             direct = direct,
                             drug_profile = drug_profile,
                             drug_rank_idx = drug_rank_idx)
    p_sm <- draw_all(res_sm)
    
  }
  
  if(sel_model_sm1 == "SS_cross"){
    # print("SS_corss!")
    
    i.need.logfc1 = i.need.logfc$i.need.logfc1
    i.need.logfc2 = i.need.logfc$i.need.logfc2
    
    res_sm <- get_ss_cross_res(funcname = funcname,
                               refMatrix = exp_LINCS2020,
                               sig_input1 = i.need.logfc1,
                               sig_input2 = i.need.logfc2,
                               topn = topn,
                               filter_mode = filter_mode,
                               fc_threshold = fc_threshold,
                               drug_profile = drug_profile,
                               drug_rank_idx = drug_rank_idx)
    
    p_sm <- draw_cross(res_sm, bioname1=bioname1, 
                       bioname2=bioname2)
    
  }
  
  req(res_sm)
  req(p_sm)
  
  return(list(
    res_sm = res_sm,
    p_sm = p_sm
  ))
}

get_single_res_i <- function(funcname,refMatrix,sig_input,topn = NULL, 
                             filter_mode = "topN", fc_threshold = NULL,
                             drug_profile = NULL, drug_rank_idx = NULL, threshold = 1){
  
  # print("进入get_single_res")
  library(dplyr)
  
  if (filter_mode == "logFC" && !is.null(fc_threshold)) {
    # FC 模式：过滤 |log2FC| > fc_threshold 的所有基因
    sig_up <- sig_input %>%
      dplyr::filter(log2FC > fc_threshold) %>%
      dplyr::arrange(desc(log2FC)) %>%
      pull(Gene)
    sig_dn <- sig_input %>%
      dplyr::filter(log2FC < -fc_threshold) %>%
      dplyr::arrange(log2FC) %>%
      pull(Gene)
  } else {
    # topN 模式（默认）
    sig_up <- sig_input %>%
      dplyr::filter(log2FC > threshold) %>%
      dplyr::arrange(desc(log2FC)) %>%
      pull(Gene)
    sig_up <- sig_up[1:min(length(sig_up), topn)]
    
    sig_dn <- sig_input %>%
      dplyr::filter(log2FC < -threshold) %>%
      dplyr::arrange(log2FC) %>%
      pull(Gene)
    sig_dn <- sig_dn[1:min(length(sig_dn), topn)]
  }
  
  if(funcname == "SS_Xsum"){
    res_raw <- XSumScore(refMatrix = refMatrix,
                         queryUp = na.omit(sig_up),
                         queryDown = na.omit(sig_dn),
                         topN = ifelse(filter_mode == "logFC", length(sig_up), topn))
  }
  
  if(funcname == "SS_CMap"){
    res_raw <- KSScore(refMatrix = refMatrix,
                       queryUp = na.omit(sig_up),
                       queryDown = na.omit(sig_dn))
  }
  
  if(funcname == "SS_GSEA"){
    res_raw <- GSEAweight1Score(refMatrix = refMatrix,
                                queryUp = na.omit(sig_up),
                                queryDown = na.omit(sig_dn))
  }
  
  if(funcname == "SS_ZhangScore"){
    res_raw <- ZhangScore(refMatrix = refMatrix,
                          queryUp = na.omit(sig_up),
                          queryDown = na.omit(sig_dn))
  }
  
  if(funcname == "SS_XCos"){
    # XCos 需要 log2FC 数值，FC 模式下用全部超过阈值的基因
    if (filter_mode == "logFC") {
      sig_input_f <- sig_input %>% dplyr::filter(abs(log2FC) > fc_threshold)
    } else {
      sig_input_f <- sig_input %>%
        dplyr::filter(abs(log2FC) > threshold) %>%
        slice_max(abs(log2FC), n = topn * 2)
    }
    sig_input4 <- setNames(sig_input_f$log2FC, sig_input_f$Gene)
    res_raw <- XCosScore(refMatrix = refMatrix,
                         query = sig_input4,
                         topN = nrow(refMatrix) / 2)
  }
  
  res_raw <- res_raw %>% 
    dplyr::arrange(desc(abs(Score)))
  
  used_topn <- ifelse(filter_mode == "logFC", max(length(sig_up), length(sig_dn)), topn)
  return(get_pval(res_raw = res_raw,
                  refMatrix = refMatrix,
                  drug_rank_idx = drug_rank_idx,
                  funcname = funcname,
                  topn = used_topn))
}

get_ss_all_res_i <- function(refMatrix,sig_input,funcname_mul,topn,direct,
                             filter_mode = "topN", fc_threshold = NULL,
                             drug_profile = NULL, drug_rank_idx = NULL){
  
  # print("进入SS_all")
  res_mul <- purrr::map(funcname_mul,get_single_res,
                        refMatrix = refMatrix,
                        sig_input = sig_input,
                        topn = topn,
                        filter_mode = filter_mode,
                        fc_threshold = fc_threshold,
                        drug_profile = drug_profile,
                        drug_rank_idx = drug_rank_idx)
  
  get_rra <- function(res_order,funcname_one,direct = "Down",only.name =F){
    
    ll <- data.frame(
      name = res_mul[[res_order]] %>% arrange(desc(abs(Score))) %>%
        dplyr::filter(Direction == direct) %>% select(name) %>% unlist(use.names = F),
      method = funcname_one
    )
    
    if(only.name){
      return(ll[[1]])
    }else{
      return(ll)
    }
  }
  
  # get data frame for summary
  res_mul2 <- purrr::map2_dfr(.x = 1:length(funcname_mul), .y = funcname_mul,
                              .f = get_rra, direct = direct, only.name =F)
  
  # get list for rra
  res_mul3 <- purrr::map2(.x = 1:length(funcname_mul), .y = funcname_mul,
                          .f = get_rra, direct = direct, only.name = T)
  
  # save(res_mul, res_mul2,res_mul3,rename_col_rules,file="1.rdata")
  summary <- res_mul2 %>% mutate(method = case_when(
    method == "SS_Xsum" ~ "XSum",
    method == "SS_CMap" ~ "CMap",
    method == "SS_GSEA" ~ "GSEA",
    method == "SS_ZhangScore"~"ZhangScore",
    method == "SS_XCos" ~ "XCos",
    TRUE ~ as.character(method)  # 如果都不匹配，保持原样
  )) %>%
    group_by(name) %>%
    summarise(Freq=n(), method = paste(method, collapse = ", ")) %>%
    na.omit() %>% arrange(desc(Freq))
  
  star_rra <- RobustRankAggreg::aggregateRanks(res_mul3)
  # star_rra <- cbind(star_rra, "rra_rank" = seq(1,nrow(star_rra)))
  
  summary <- left_join(star_rra, summary, by=c("Name" = "name") )
  summary$Score <- -log2(summary$Score)
  # 
  # rio::export(summary,"111.TXT")
  return(summary %>% mutate_if(is.numeric, round, digits = 10))
  # }else{
  #   print("at least two methods!")
  # }
  
}

get_ss_cross_res_i <- function(funcname,refMatrix,sig_input1,sig_input2,topn,
                               filter_mode = "topN", fc_threshold = NULL,
                               drug_profile = NULL, drug_rank_idx = NULL){
  
  # print("进入SS_cross")
  res1 <-  get_single_res(funcname = funcname ,refMatrix = refMatrix,
                          sig_input = sig_input1, topn = topn,
                          filter_mode = filter_mode, fc_threshold = fc_threshold,
                          drug_profile = drug_profile, drug_rank_idx = drug_rank_idx)
  res2 <-  get_single_res(funcname = funcname ,refMatrix = refMatrix,
                          sig_input = sig_input2, topn = topn,
                          filter_mode = filter_mode, fc_threshold = fc_threshold,
                          drug_profile = drug_profile, drug_rank_idx = drug_rank_idx)
  
  res_m <- full_join(res1,res2,by="name")
  res_m <- res_m %>% 
    rowwise() %>%  # 使用rowwise()以确保函数在每一行上分别应用
    mutate(nominal_padj = combine_p_values(p.adjust.x, p.adjust.y),
           cal_label = sqrt(abs(Scale_score.x * Scale_score.y)),
           block = add_block(Scale_score.x,Scale_score.y)
           ) %>% ungroup() # 移除分组，以避免后续操作中的潜在问题


  
  # res_m$block <- apply(res_m[,c("Scale_score.x","Scale_score.y")],FUN = add_block,MARGIN=1)
  
  # save(res_m, file = "res_m.rdata")
  
  res_m <- res_m %>% 
    dplyr::select(name,cal_label, nominal_padj, block, Scale_score.x,Scale_score.y) %>% 
    dplyr::arrange(desc(cal_label)) %>% mutate_if(is.numeric, round, digits = 4)
  
  return(res_m)
}

## 尽可能存储缓存，试一试
get_single_method <- memoise::memoise(get_single_method_i,cache = local_cache_folder_SM)
get_single_res <- memoise::memoise(get_single_res_i,cache = local_cache_folder_SM)
get_ss_all_res <- memoise::memoise(get_ss_all_res_i,cache = local_cache_folder_SM)
get_ss_cross_res <- memoise::memoise(get_ss_cross_res_i,cache = local_cache_folder_SM)



# ============================================================
# 实时 null 分布 + p 值计算
# 使用预排序 drug_rank_idx 避免重复排序，采用自适应排列策略
# ============================================================
get_pval <- function(res_raw, refMatrix, drug_rank_idx, funcname, topn = 489) {
  n_drugs   <- ncol(refMatrix)
  all_genes <- rownames(refMatrix)
  n_genes   <- length(all_genes)
  
  # 自适应排列：先从 200 次开始，必要时追加到 2000
  n_init <- 200
  n_max  <- 2000
  
  null_scores <- matrix(NA_real_, n_drugs, n_max)
  
  for (iter in 1:n_max) {
    rand_genes <- sample(all_genes, topn * 2)
    up_genes   <- rand_genes[1:topn]
    dn_genes   <- rand_genes[(topn + 1):(topn * 2)]
    
    if (funcname %in% c("SS_Xsum", "SS_XCos")) {
      # XSum / XCos：只需查 topN，极快
      null_scores[, iter] <- .null_topn(refMatrix, drug_rank_idx, 
                                         up_genes, dn_genes, topn, funcname)
    } else {
      # KS / GSEA / ZhangScore：使用完整排名
      null_scores[, iter] <- .null_full(refMatrix, drug_rank_idx,
                                         up_genes, dn_genes, n_genes, funcname)
    }
  }
  
  # 计算 p 值
  obs_scores <- setNames(res_raw$Score, rownames(res_raw))
  common     <- intersect(names(obs_scores), colnames(refMatrix))
  
  if (length(common) == 0) {
    res_raw$pvalue <- 1; res_raw$p.adjust <- 1
    res_raw$Scale_score <- .S(res_raw$Score)
    res_raw$Direction   <- .D(res_raw$Scale_score)
    return(res_raw %>% dplyr::select(name, Score, Scale_score, Direction, pvalue, p.adjust) %>%
             mutate_if(is.numeric, round, digits = 4))
  }
  
  obs  <- obs_scores[common]
  null <- null_scores[match(common, colnames(refMatrix)), , drop = FALSE]
  pvals <- rowMeans(abs(null) >= abs(obs), na.rm = TRUE)
  
  result <- data.frame(
    name   = common,
    Score  = obs,
    pvalue = pvals,
    stringsAsFactors = FALSE
  )
  result$Scale_score <- .S(result$Score)
  result$Direction   <- .D(result$Scale_score)
  result$p.adjust    <- p.adjust(result$pvalue)
  
  return(result %>% 
           dplyr::select(name, Score, Scale_score, Direction, pvalue, p.adjust) %>%
           mutate_if(is.numeric, round, digits = 4))
}

# ---- 内部辅助：topN 方法 (XSum / XCos) ----
.null_topn <- function(refMatrix, drug_rank_idx, up_genes, dn_genes, topn, funcname) {
  n_drugs <- ncol(refMatrix)
  scores  <- numeric(n_drugs)
  gene_names <- rownames(refMatrix)
  
  for (d in seq_len(n_drugs)) {
    # 该药物的 topN 上调和下调基因
    top_up_idx   <- drug_rank_idx[1:topn, d]
    top_up_names <- gene_names[top_up_idx]
    top_up_vals  <- refMatrix[top_up_idx, d]
    
    bottom_idx    <- drug_rank_idx[(nrow(refMatrix) - topn + 1):nrow(refMatrix), d]
    bottom_names  <- gene_names[bottom_idx]
    bottom_vals   <- refMatrix[bottom_idx, d]
    
    if (funcname == "SS_Xsum") {
      up_match  <- match(up_genes, top_up_names)
      dn_match  <- match(dn_genes, bottom_names)
      scores[d] <- sum(top_up_vals[up_match], na.rm = TRUE) -
                   sum(bottom_vals[dn_match], na.rm = TRUE)
    } else {  # XCos
      # 构造向量：topN up和bottom，取交集
      all_top  <- c(top_up_names, bottom_names)
      all_vals <- c(top_up_vals, bottom_vals)
      # 对查询的上下调基因分别匹配
      up_match  <- match(up_genes, all_top)
      dn_match  <- match(dn_genes, all_top)
      query_vals <- all_vals[c(up_match, dn_match)]
      query_vals <- query_vals[!is.na(query_vals)]
      top_vals   <- all_vals[!is.na(match(all_top, c(up_genes, dn_genes)))]
      # 简化：计算余弦相似度
      if (length(query_vals) > 0 && length(top_vals) > 0) {
        scores[d] <- crossprod(query_vals, top_vals[1:length(query_vals)]) /
                      sqrt(crossprod(query_vals) * crossprod(top_vals[1:length(query_vals)]))
      }
    }
  }
  scores[is.na(scores)] <- 0
  return(scores)
}

# ---- 内部辅助：全排方法 (KS / GSEA / ZhangScore) ----
.null_full <- function(refMatrix, drug_rank_idx, up_genes, dn_genes, n_genes, funcname) {
  n_drugs <- ncol(refMatrix)
  scores  <- numeric(n_drugs)
  gene_names <- rownames(refMatrix)
  
  for (d in seq_len(n_drugs)) {
    # 该药物的完整排序基因名
    ranked <- gene_names[drug_rank_idx[, d]]
    
    if (funcname == "SS_CMap") {
      # KS 统计量
      scores[d] <- .ks_stat(ranked, up_genes, dn_genes)
    } else if (funcname == "SS_GSEA") {
      # GSEA weight1
      scores[d] <- .gsea_stat(refMatrix, drug_rank_idx[, d], gene_names, up_genes, dn_genes, d)
    } else if (funcname == "SS_ZhangScore") {
      # ZhangScore
      scores[d] <- .zhang_stat(ranked, up_genes, dn_genes, n_genes)
    }
  }
  scores[is.na(scores)] <- 0
  return(scores)
}

.ks_stat <- function(ranked, up_genes, dn_genes) {
  up_rank  <- match(up_genes, ranked)
  dn_rank  <- match(dn_genes, ranked)
  up_rank  <- sort(up_rank[!is.na(up_rank)])
  dn_rank  <- sort(dn_rank[!is.na(dn_rank)])
  
  ks_up <- if (length(up_rank) > 0) {
    d_u <- (1:length(up_rank)) / length(up_rank) - up_rank / length(ranked)
    max(d_u)
  } else 0
  ks_dn <- if (length(dn_rank) > 0) {
    d_d <- (1:length(dn_rank)) / length(dn_rank) - dn_rank / length(ranked)
    max(d_d)
  } else 0
  
  a <- max(c(ks_up, 0)); b <- -min(c(ks_dn, 0)) + 1/max(1, length(dn_rank))
  ifelse(a > b, a, -b)
}

.gsea_stat <- function(refMatrix, rank_idx, gene_names, up_genes, dn_genes, d) {
  ranked_vals  <- abs(refMatrix[rank_idx, d])
  ranked_names <- gene_names[rank_idx]
  
  tag_up <- sign(match(ranked_names, up_genes, nomatch = 0))
  tag_dn <- sign(match(ranked_names, dn_genes, nomatch = 0))
  
  up_es <- if (sum(tag_up) > 0) {
    norm_tag <- 1 / sum(ranked_vals[tag_up == 1])
    norm_no  <- 1 / sum(tag_up == 0)
    res <- cumsum(tag_up * ranked_vals * norm_tag - (1 - tag_up) * norm_no)
    ifelse(max(res, na.rm = TRUE) > -min(res, na.rm = TRUE),
           max(res, na.rm = TRUE), min(res, na.rm = TRUE))
  } else 0
  
  dn_es <- if (sum(tag_dn) > 0) {
    norm_tag <- 1 / sum(ranked_vals[tag_dn == 1])
    norm_no  <- 1 / sum(tag_dn == 0)
    res <- cumsum(tag_dn * ranked_vals * norm_tag - (1 - tag_dn) * norm_no)
    ifelse(max(res, na.rm = TRUE) > -min(res, na.rm = TRUE),
           max(res, na.rm = TRUE), min(res, na.rm = TRUE))
  } else 0
  
  ifelse(up_es * dn_es <= 0, up_es - dn_es, 0)
}

.zhang_stat <- function(ranked, up_genes, dn_genes, n_genes) {
  query_vec <- setNames(c(rep(1, length(up_genes)), rep(-1, length(dn_genes))),
                         c(up_genes, dn_genes))
  query_pos <- match(names(query_vec), ranked)
  valid <- !is.na(query_pos)
  if (sum(valid) == 0) return(0)
  
  ref_rank  <- rank(query_pos[valid]) * sign(query_vec[valid])
  score <- sum(query_vec[valid] * ref_rank) / sum(abs(query_vec[valid]) * length(query_pos[valid]))
  return(score)
}


draw_single <- function(data){
  
  # save(data,file = "data.rdata")
  data = as.data.frame(data)
  data1 = rbind(slice_max(data, Scale_score,
                          n = 10,with_ties = FALSE),
                slice_min(data, Scale_score,
                          n = 10,with_ties = FALSE)) %>% #  distinct() %>%
  mutate(name = factor(name, levels = name[order(Scale_score)]),
         logP = -log10(pvalue+0.0001),
         tooltip_text = paste("Name:", name, 
                               "<br>Scale_score:", round(Scale_score, 2), 
                               "<br>logP:", round(logP, 2))
         )



  
  p1 <- ggplot2::ggplot(data1, aes(x = Scale_score, y = name,xend = 0, yend = name, text =tooltip_text )) +
    geom_segment(linetype = 2) +
    geom_point(aes(col = logP , size = abs(Scale_score))) +
    scale_colour_gradientn(colors = c("blue", "red")) +
    scale_size_continuous(range = c(2, 6)) +
    ylab(NULL) +
    theme_minimal() +
    theme(panel.background = element_rect(
      colour = "black",
      size = 0.5
    )) +
    labs(
      x = "Scaled Score", y = "Drugs",
      size = "Scaled Score",
      col = "logP"
    ) + scale_y_discrete(position = "left",labels= function(x) str_wrap(x,width=30))
  
  # 使用plotly::ggplotly转换p，并指定tooltip参数
  plotly_p1 <- plotly::ggplotly(p1, tooltip = "text") # 使用text作为工具提示
  
  return(plotly_p1)



}





draw_all <- function(sm){

  # 首先，对sm数据进行排序并选取前10个记录
  sm_sorted <- sm[order(sm$Score, decreasing = T), ][1:10, ]
  
  # 对Name进行基于rra_rank的重新排序
  sm_sorted$Name <- factor(sm_sorted$Name, levels = sm_sorted$Name[order(sm_sorted$Score)])
  
  sm_sorted$Freq <- factor(sm_sorted$Freq)
  
  sm_sorted$tooltip_text <- paste("Name:", sm_sorted$Name, 
                              "<br>Score:", round(sm_sorted$Score, 2), 
                              "<br>Freq:", sm_sorted$Freq)
  
  p2 <- ggplot(sm_sorted,aes(x = Score, y = Name, size = Freq,color=Score , text = tooltip_text)) +
    geom_point() +
    scale_color_gradient(low="green",high = "red") + labs(x="Score",
                                                          y=NULL,
                                                          title=NULL,
                                                          colour = "Score",
                                                          size = "Method")+theme_test() + theme(
                                                            axis.text = element_text(colour = "black")
                                                          )+
    scale_y_discrete(position = "left",labels= function(x) str_wrap(x,width=30))
  
  # 使用plotly::ggplotly转换p，并指定tooltip参数
  plotly_p2 <- plotly::ggplotly(p2, tooltip = "text") # 使用text作为工具提示
  
  return(plotly_p2)
  
  # 建议输出分辨率为3:4可以获得最好的效果
  
  
  
  
}

draw_cross <- function(res_m,bioname1="Biological Process 1", bioname2="Biological Process 2"){
  
  stopifnot(is.character(bioname1) & is.character(bioname2))
  
  # 筛选每个象限排序靠前的化合物
  # for_label2 <- res_m %>% filter(block != "NQ") %>% group_by(block) %>%
  #   slice_max(order_by = cal_label, n = show_n)
  # 
  # 
  # if (show_block %in% c("Q1","Q2","Q3","Q4")){
  #   for_label2 <- for_label2[for_label2$block == show_block,]
  # }
  # 
  cbPalette <- c("#999999", "#F8766D", "#B79F00", "#00BA38", "#00BFC4")
  # show_cap=paste(for_label2$name)
  
  res_m$tooltip_text <- paste("Name:", res_m$name, 
                              "<br>Scale_score.x:", round(res_m$Scale_score.x, 2), 
                              "<br>Scale_score.y:", round(res_m$Scale_score.y, 2))
  
  p3 <- res_m %>% 
    ggplot(aes(x=Scale_score.x, y=Scale_score.y,color=block,text=tooltip_text)) +
    geom_point(alpha=0.5) +theme_test()+ theme(
      axis.title = element_text( face = "bold"),
      axis.text = element_text(colour = "black"),
      legend.title = element_text(),
      legend.text = element_text())+ labs(x = bioname1, y = bioname2)+
    scale_colour_manual(values=cbPalette)+ theme(legend.position="none")
  
  # 使用plotly::ggplotly转换p，并指定tooltip参数
  plotly_p3 <- plotly::ggplotly(p3, tooltip = "text") # 使用text作为工具提示
  
  return(plotly_p3)
  
}

# 添加分区
add_block <- function(num1,num2){
  # 
  # num1 = x[1]
  # num2 = x[2]
  if(num1 >0 & num2 >0){
    return("Q1")
  }
  if(num1 <0 & num2 >0){
    return("Q2")
  }
  if(num1 <0 & num2 <0){
    return("Q3")
  }
  if(num1 >0 & num2 <0){
    return("Q4")
  }
  if(num1 ==0 | num2 ==0){
    return("NQ")
  }
}

# 计算联合p值
# cal_p <- function(x){
#   num1 = x[1]
#   num2 = x[2]
#   if (num1 ==1 | num2 ==1) {
#     return(1)
#   } else {
#     return(sqrt(num1 * num2))
#   }
# }

# Function to scale scores
.S <- function(scores) {
  p <- max(scores)
  q <- min(scores)
  ifelse(scores == 0, 0, ifelse(scores > 0, scores / p, -scores / q))
}

# 判断方向
.D <- function(scores) {
  p <- max(scores)
  q <- min(scores)
  ifelse(scores > 0.4, "Up", ifelse(scores < -0.4, "Down", "None"))
}

# 计算联合p值（逐药物 Fisher 合并）
combine_p_values <- function(p1, p2) {
  chi_squared_values <- -2 * (log(p1) + log(p2))
  combined_p_value <- pchisq(chi_squared_values, df = 4, lower.tail = FALSE)
  return(combined_p_value)
}
