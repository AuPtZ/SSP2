# benchmark和application的结果保存
# 这个页面提供的是需要在不同页面使用的，超过2次以上的功能
write_in_db <- function(Jobid, Submitted_time, module_name,
                        sub_module, table_num = 1, table_res){
  # 获取公用的 filter mode 信息
  if (module_name == "Benchmark") {
    fm <- input$filter_mode_bm
  } else {
    fm <- input$filter_mode_sm
  }
  fv <- if (fm == "logFC") input$sel_fc_sm else input$sel_topn_sm

  if(module_name == "Benchmark"){
    if(sub_module == "AUC"){
      df1 <- data.frame(
        Jobid = Jobid,
        Submitted_time = Submitted_time,
        main_module = module_name,
        table_num = table_num,
        drug_profile = input$sel_experiment,
        method_bm = paste0(find_original_names(input$sel_ss),collapse = ", "),
        signature_file1 = input$file_sig$name,
        ic50_file = input$file_IC50$name,
        sub_module = sub_module,
        filter_mode = fm,
        filter_value = fv
      )
    }
    if(sub_module == "ES"){
      df1 <- data.frame(
        Jobid = Jobid,
        Submitted_time = Submitted_time,
        main_module = module_name,
        table_num = table_num,
        drug_profile = input$sel_experiment,
        method_bm = paste0(find_original_names(input$sel_ss),collapse = ", "),
        signature_file1 = input$file_sig$name,
        fda_file = input$file_FDA$name,
        sub_module = sub_module,
        filter_mode = fm,
        filter_value = fv
      )
    }
    if(sub_module == "ALL (ES and AUC)"){
      df1 <- data.frame(
        Jobid = Jobid,
        Submitted_time = Submitted_time,
        main_module = module_name,
        table_num = table_num,
        drug_profile = input$sel_experiment,
        method_bm = paste0(find_original_names(input$sel_ss),collapse = ", "),
        signature_file1 = input$file_sig$name,
        fda_file = input$file_FDA$name,
        ic50_file = input$file_IC50$name,
        sub_module = sub_module,
        filter_mode = fm,
        filter_value = fv
      )
    }
  }
  if(module_name == "Application"){
    if(sub_module == "singlemethod"){
      df1 <- data.frame(
        Jobid = Jobid,
        Submitted_time = Submitted_time,
        main_module = module_name,
        table_num = table_num,
        drug_profile = input$sel_experiment_sm,
        sub_module = input$sel_model_sm,
        method_sm2 = find_original_names(input$sel_ss_sm),
        signature_file2 = input$file_sig_sm$name,
        sel_num_gene = input$sel_topn_sm,
        filter_mode = fm,
        filter_value = fv
      )
    }
    if(sub_module == "SS_cross"){
      df1 <- data.frame(
        Jobid = Jobid,
        Submitted_time = Submitted_time,
        main_module = module_name,
        table_num = table_num,
        drug_profile = input$sel_experiment_sm,
        sub_module = input$sel_model_sm,
        method_sm2 = find_original_names(input$sel_ss_sm),
        signature_file3 = input$file_sig_sm1$name,
        signature_file4 = input$file_sig_sm2$name,
        signature_name1 = input$file_name1,
        signature_name2 = input$file_name2,
        sel_num_gene = input$sel_topn_sm,
        filter_mode = fm,
        filter_value = fv
      )
    }
    if(sub_module == "SS_all"){
      df1 <- data.frame(
        Jobid = Jobid,
        Submitted_time = Submitted_time,
        main_module = module_name,
        table_num = table_num,
        drug_profile = input$sel_experiment_sm,
        sub_module = input$sel_model_sm,
        method_sm1 = paste0(find_original_names(input$sel_all_sm),collapse = ", "),
        direction_sm = input$sel_direct_sm,
        signature_file2 = input$file_sig_sm$name,
        sel_num_gene = input$sel_topn_sm,
        filter_mode = fm,
        filter_value = fv
      )
    }
  }
  
  library(RSQLite)
  con_res <- dbConnect(RSQLite::SQLite(), "results/resinfo.db")
  # print(df1)
  
  if(table_num == 1){
    # print("写入一个表1")
    # print(Jobid)
    # print(table_res)
    # save(table_res,Jobid,file = "X1.rdata")
    dbWriteTable(con_res, Jobid, table_res)
    # print("增加一个表1")
    dbAppendTable(con_res, "res", df1)
    # print("Sucess!")
  } else if(table_num == 2) {
    # print("写入一个表2")
    dbWriteTable(con_res, paste0(Jobid,"_AUC"), table_res[["AUC"]])
    # print("写入一个表2")
    dbWriteTable(con_res, paste0(Jobid,"_ES"), table_res[["ES"]])
    # print("增加一个表2")
    dbAppendTable(con_res, "res", df1)
    # print("wrting to dababase Sucess!")
  } else {
    # print("WARING! NO TABLE INPUT!")
  }
  
  dbDisconnect(con_res)
}

observeEvent(input$intro_res_bm_AUC, {
  
  showModal(modalDialog(
    includeMarkdown("www/info_Q9_bm_AUC.md"),
    title = "How to find optimal method and topN in Benchmark? (AUC)",
    size = "l",
    easyClose = T
  ))
  
})

observeEvent(input$intro_res_bm_ES, {
  
  showModal(modalDialog(
    includeMarkdown("www/info_Q9_bm_ES.md"),
    title = "How to find optimal method and topN in Benchmark? (ES)",
    size = "l",
    easyClose = T
  ))
  
})

observeEvent(input$intro_res_rb, {
  
  showModal(modalDialog(
    includeMarkdown("www/info_Q9_rb.md"),
    title = "Quick Tip",
    size = "l",
    easyClose = T
  ))
  
})


observeEvent(input$intro_res_sm_sm, {

  showModal(modalDialog(
    includeMarkdown("www/info_Q9_sm_sm.md"),
    title = "Quick Tip",
    size = "l",
    easyClose = T
  ))
})

observeEvent(input$intro_res_sm_cross, {
  
  showModal(modalDialog(
    includeMarkdown("www/info_Q9_sm_cross.md"),
    title = "Quick Tip",
    size = "l",
    easyClose = T
  ))
})

observeEvent(input$intro_res_sm_all, {
  
  showModal(modalDialog(
    includeMarkdown("www/info_Q9_sm_all.md"),
    title = "Quick Tip",
    size = "l",
    easyClose = T
  ))
})

# FOR EACH PAGE
observeEvent(input$runBENdemo,{
  load("demo/BEN1712624574ZFX.rdata")
  output$display_bm <- renderUI({res_plot(job_info)})
})
observeEvent(input$runAPPdemo1,{
  load("demo/APP1709824554ILK.rdata")
  output$display_sm <- renderUI({res_plot(job_info)})
})
observeEvent(input$runAPPdemo2,{
  load("demo/APP1709818711RFU.rdata")
  output$display_sm <- renderUI({res_plot(job_info)})
})
observeEvent(input$runAPPdemo3,{
  load("demo/APP1709818670ZIA.rdata")
  output$display_sm <- renderUI({res_plot(job_info)})
})
# FOR JOB PAGE
observeEvent(input$runjcBENdemo,{
  load("demo/BEN1712624574ZFX.rdata")
  output$display_jc <- renderUI({res_plot(job_info)})
})
observeEvent(input$runjcAPPdemo1,{
  load("demo/APP1709824554ILK.rdata")
  output$display_jc <- renderUI({res_plot(job_info)})
})
observeEvent(input$runjcAPPdemo2,{
  load("demo/APP1709818711RFU.rdata")
  output$display_jc <- renderUI({res_plot(job_info)})
})
observeEvent(input$runjcAPPdemo3,{
  load("demo/APP1709818670ZIA.rdata")
  output$display_jc <- renderUI({res_plot(job_info)})
})



res_plot <- function(job_info){
  isFC <- !is.null(job_info$yourjob$filter_mode) && job_info$yourjob$filter_mode == "logFC"

  if(job_info$yourmodule == "ALL (ES and AUC)" || 
     grepl("^ALL_FC$", job_info$yourmodule)) {
    
    res_bm1 <- job_info$yourtable$`AUC` %>% as_tibble()
    res_bm2 <- job_info$yourtable$`ES` %>% as_tibble()
    
    if (isFC || grepl("FC", job_info$yourmodule)) {
      pic_out1 <- ggplotly(draw_dr_auc_fc(res_bm1))
      pic_out2 <- ggplotly(draw_dr_es_fc(res_bm2))
    } else {
      pic_out1 <- ggplotly(draw_dr_auc(res_bm1))
      pic_out2 <- ggplotly(draw_dr_es(res_bm2))
    }

    DT_res_bm1 <- datatable(res_bm1) %>% 
      formatStyle(names(res_bm1)[which.max(res_bm1[1,-1]) + 1],
                  backgroundColor = styleEqual(res_bm1[1, which.max(res_bm1[1,-1]) + 1], c('yellow')))
    DT_res_bm2 <- datatable(res_bm2) %>% 
      formatStyle(names(res_bm2)[which.min(res_bm2[1,-1])+1],
                  backgroundColor = styleEqual(res_bm2[1, which.min(res_bm2[1,-1]) + 1], c('yellow')))
    
    tagList(
      shiny::h3("Job info"),
      renderTable(job_info$yourjob, striped = T, hover = T, spacing = "l",
                  bordered = T, rownames = F, colnames = F ),
      shiny::h3("Results of AUC",actionButton("intro_res_bm_AUC","Quick Tip",class = "btn-success")),
      renderPlotly(pic_out1),
      DT::renderDataTable(DT_res_bm1),
      shiny::br(),
      shiny::h3("Results of ES",actionButton("intro_res_bm_ES","Quick Tip",class = "btn-success")),
      renderPlotly(pic_out2),
      DT::renderDataTable(DT_res_bm2),
    )
    
  } else if(job_info$yourmodule == "AUC" || job_info$yourmodule == "AUC_FC") {
    
    res_bm = job_info$yourtable %>% as_tibble()
    res_title = job_info$yourmodule
    tip_id <- if (res_title == "AUC_FC") "AUC" else res_title

    pic_out <- if (isFC || grepl("FC", job_info$yourmodule))
      ggplotly(draw_dr_auc_fc(res_bm)) else ggplotly(draw_dr_auc(res_bm))

    DT_res_bm <- datatable(res_bm) %>% 
      formatStyle(names(res_bm)[which.max(res_bm[1,-1]) + 1],
                  backgroundColor = styleEqual(res_bm[1, which.max(res_bm[1,-1])+ 1], c('yellow')))

    tagList(
      shiny::h3("Job info"),
      renderTable(job_info$yourjob, striped = T, hover = T, spacing = "l",
                  bordered = T, rownames = F, colnames = F ),
      shiny::h3(paste0("Plot summary of ",res_title),
                actionButton(paste0("intro_res_bm_",tip_id),"Quick Tip",class = "btn-success")),
      renderPlotly(pic_out),
      shiny::br(),
      shiny::h3(paste0("Results of "),res_title),
      DT::renderDataTable(DT_res_bm)
    )
  } else if(job_info$yourmodule == "ES" || job_info$yourmodule == "ES_FC") {
    
    res_bm = job_info$yourtable %>% as_tibble()
    res_title = job_info$yourmodule

    pic_out <- if (isFC || grepl("FC", job_info$yourmodule))
      ggplotly(draw_dr_es_fc(res_bm)) else ggplotly(draw_dr_es(res_bm))

    DT_res_bm <- datatable(res_bm) %>% 
      formatStyle(names(res_bm)[which.min(res_bm[1,-1]) + 1],
                  backgroundColor = styleEqual(res_bm[1, which.min(res_bm[1,-1])+ 1], c('yellow')))

    tagList(
      shiny::h3("Job info"),
      renderTable(job_info$yourjob, striped = T, hover = T, spacing = "l",
                  bordered = T, rownames = F, colnames = F ),
      shiny::h3(paste0("Plot summary of ",res_title),
                actionButton(paste0("intro_res_bm_",tip_id),"Quick Tip",class = "btn-success")),
      renderPlotly(pic_out),
      shiny::br(),
      shiny::h3(paste0("Results of "),res_title),
      DT::renderDataTable(DT_res_bm)
    )
    
  } else if(job_info$yourmodule == "singlemethod") {
    
    tagList(
      shiny::h3("Job info"),
      renderTable(job_info$yourjob, striped = T, hover = T, spacing = "l",
                  bordered = T, rownames = F, colnames = F ),
      shiny::h3("Plot summary",actionButton("intro_res_sm_sm","Quick Tip",class = "btn-success")),
      renderPlotly(ggplotly(draw_single(job_info$yourtable))),
      shiny::h3("Results"),
      DT::renderDataTable(job_info$yourtable %>%
                            dplyr::rename(any_of(rename_col_rules)),
                          server = FALSE),
    )
    
  } else if(job_info$yourmodule == "SS_cross"){
    tagList(
      shiny::h3("Job info"),
      renderTable(job_info$yourjob, striped = T, hover = T, spacing = "l",
                  bordered = T, rownames = F, colnames = F ),
      shiny::h3("Plot summary",actionButton("intro_res_sm_cross","Quick Tip",class = "btn-success")),
      renderPlotly(ggplotly(draw_cross(job_info$yourtable, 
                                       bioname1=job_info$signame1,bioname2=job_info$signame2))),
      shiny::br(),
      shiny::h3("Results"),
      DT::renderDataTable(job_info$yourtable %>%
                            dplyr::rename(any_of(rename_col_rules)),
                          server = FALSE),
    )
  } else if(job_info$yourmodule == "SS_all"){
    tagList(
      shiny::h3("Job info"),
      renderTable(job_info$yourjob, striped = T, hover = T, spacing = "l",
                  bordered = T, rownames = F, colnames = F ),
      shiny::h3("Plot summary",actionButton("intro_res_sm_all","Quick Tip",class = "btn-success")),
      renderPlotly(ggplotly(draw_all(job_info$yourtable))),
      shiny::br(),
      shiny::h3("Results"),
      DT::renderDataTable(job_info$yourtable %>%
                            dplyr::rename(any_of(rename_col_rules)),
                          server = FALSE),
    )
  }
}