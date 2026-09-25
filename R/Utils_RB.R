get_rb_plot <- function(dir_rb,func_sel){
  load(dir_rb)
  library(dplyr)
  library(ggplot2)
  library(ggsci)

  
  colnames(res_topn2) <- c("SS_Xsum","SS_CMap","SS_GSEA","SS_ZhangScore","SS_XCos","TopN")
  
  res_rb <- res_topn2 %>% dplyr::select(c('TopN', all_of(func_sel))) %>%
    mutate_at(vars(-1), round, digits = 4) %>%
    dplyr::rename(any_of(rename_col_rules))
  
  # 找到整个表格中最大值所在的列的列名
  max_col_name <- colnames(res_rb[-1])[which(res_rb[-1] == max(res_rb[-1], na.rm = TRUE), arr.ind = TRUE)[1, "col"]]
  
  # 按照该列从大到小排序
  res_rb <- res_rb %>% dplyr::arrange(desc(!!rlang::sym(max_col_name)))

  first_row_value <- res_rb[1,1] %>% as_tibble() %>% pull()
  
  # 挑选选择的算法的得分
  res_topn11 <- res_rb %>% mutate(Average = rowMeans(dplyr::select(., -TopN), na.rm = TRUE)) %>%
    tidyr::pivot_longer(data = .,cols = -TopN,
                        names_to = "Method", 
                        values_to = "Score") %>% 
    dplyr::mutate(Score = round(Score,4),
                  Method = factor(Method, levels = c("CMap", "GSEA", "XCos","XSum","ZhangScore","Average"))
    )

  
  # 绘图
  pic_out <- ggplot(res_topn11, mapping = aes(x = TopN, y = Score,color = Method) ) + 
    geom_line(data = subset(res_topn11, Method != "Average") ,alpha=1,linewidth = 2) +  
    geom_line(data = subset(res_topn11, Method == "Average"), alpha = 1, linewidth = 2, linetype= "dashed") +
    geom_vline(xintercept = first_row_value, linetype="dashed", color = "black") + 
    scale_color_npg() + 
    labs(x= "TopN",y="Robustness")+ theme_test() 

  return(list(pic_out = pic_out,res_rb = res_rb))
  
}