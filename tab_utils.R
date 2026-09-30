# benchmark和application的结果保存
# 这个页面提供的是需要在不同页面使用的，超过2次以上的功能

# Quick Tip 弹窗。res_plot 已把 actionButton 的 id 按 prefix+jobid 唯一化
# （bm_ / sm_ / jc_ 前缀），避免同会话两处渲染同一结果导致的
# 「IDs were used for more than one input」警告。
# 检测点击用「逐键记录已见点击数」：只有当某按钮的点击计数较上次
# 增大时才弹窗；结果重渲染（按钮 id 变化、新按钮初始为 0）不会误触发。
if (!exists("tip_seen", mode = "environment") || is.null(tip_seen)) {
  tip_seen <- new.env(hash = TRUE, parent = emptyenv())
}

.observe_tip <- function(pattern, md_file, title) {
  observe({
    ks <- grep(pattern, names(input), value = TRUE)
    for (k in ks) {
      v <- input[[k]]
      seen <- if (exists(k, envir = tip_seen, inherits = FALSE)) tip_seen[[k]] else 0
      if (!is.null(v) && v > seen) {
        tip_seen[[k]] <- v
        showModal(modalDialog(
          includeMarkdown(md_file),
          title = title, size = "l", easyClose = TRUE
        ))
      }
    }
  })
}

.observe_tip("intro_res_bm_AUC_",   "www/info_Q9_bm_AUC.md",
            "How to find optimal method and topN in Benchmark? (AUC)")
.observe_tip("intro_res_bm_ES_",    "www/info_Q9_bm_ES.md",
            "How to find optimal method and topN in Benchmark? (ES)")
.observe_tip("intro_res_sm_sm_",    "www/info_Q9_sm_sm.md",    "Quick Tip")
.observe_tip("intro_res_sm_cross_", "www/info_Q9_sm_cross.md", "Quick Tip")
.observe_tip("intro_res_sm_all_",  "www/info_Q9_sm_all.md",  "Quick Tip")

# 读取 demo 结果 rdata：不硬依赖文件里的对象名。
# 历史教训（2026-09-30）：生成脚本曾把对象存成 ji，而页面 load() 之后按
# job_info 取，8 个 demo 按钮全部报 "object 'job_info' not found"。这里先看
# 有没有 job_info，没有就用文件里唯一的对象，让两侧彻底解耦。
.load_demo <- function(f) {
  e <- new.env(parent = emptyenv())
  load(f, envir = e)
  if (exists("job_info", envir = e, inherits = FALSE)) return(get("job_info", envir = e))
  nms <- ls(e)
  if (length(nms) == 1L) return(get(nms, envir = e))
  stop("demo 文件 ", f, " 里的对象名无法识别：", paste(nms, collapse = ", "))
}

# FOR EACH PAGE
observeEvent(input$runBENdemo,{
  job_info <- .load_demo("demo/BEN1790672381JTV.rdata")
  output$display_bm <- renderUI({res_plot(job_info, prefix = "bm")})
})
observeEvent(input$runAPPdemo1,{
  job_info <- .load_demo("demo/APP1790669686URX.rdata")
  output$display_sm <- renderUI({res_plot(job_info, prefix = "sm")})
})
observeEvent(input$runAPPdemo2,{
  job_info <- .load_demo("demo/APP1790669691LXK.rdata")
  output$display_sm <- renderUI({res_plot(job_info, prefix = "sm")})
})
observeEvent(input$runAPPdemo3,{
  job_info <- .load_demo("demo/APP1790735151KID.rdata")
  output$display_sm <- renderUI({res_plot(job_info, prefix = "sm")})
})
# FOR JOB PAGE
observeEvent(input$runjcBENdemo,{
  job_info <- .load_demo("demo/BEN1790672381JTV.rdata")
  output$display_jc <- renderUI({res_plot(job_info, prefix = "jc")})
})
observeEvent(input$runjcAPPdemo1,{
  job_info <- .load_demo("demo/APP1790669686URX.rdata")
  output$display_jc <- renderUI({res_plot(job_info, prefix = "jc")})
})
observeEvent(input$runjcAPPdemo2,{
  job_info <- .load_demo("demo/APP1790669691LXK.rdata")
  output$display_jc <- renderUI({res_plot(job_info, prefix = "jc")})
})
observeEvent(input$runjcAPPdemo3,{
  job_info <- .load_demo("demo/APP1790735151KID.rdata")
  output$display_jc <- renderUI({res_plot(job_info, prefix = "jc")})
})



res_plot <- function(job_info, prefix = "res"){
  # 每个调用上下文（Benchmark / Job Center / Application）传不同 prefix，
  # 使 actionButton 的 id 在会话内唯一，避免 "IDs were used for more than one input"。
  jid <- job_info$yourjob$V1[job_info$yourjob$V2 == "Job id"]
  jid <- if (length(jid) && nzchar(jid[1])) jid[1] else "x"
  tid <- function(base) paste0(prefix, "_", base, "_", jid)

  # 模式判定：**以结果表首列名为准**（topN 模式首列 "TopN"，|log2FC| 模式首列 "logFC"）。
  # 不能靠 filter_mode 元数据判定：yourjob 是 V1/V2 键值表，$filter_mode 恒为 NULL；
  # 且 logFC 任务的 sub_module 仍写作 "ALL (ES and AUC)"（_FC 后缀只出现在 label_output），
  # 于是 grepl("FC", module) 也判不出来。2026-09-29 实测：两条依据同时失效，
  # logFC 任务被送进 topN 分支，崩在 draw_dr_auc 的 pivot_longer(cols = -TopN)。
  is_fc_mode <- function(df) !identical(tolower(names(df)[1]), "topn")

  if(job_info$yourmodule == "ALL (ES and AUC)" || 
     grepl("^ALL_FC$", job_info$yourmodule)) {
    
    res_bm1 <- job_info$yourtable$`AUC` %>% as_tibble()
    res_bm2 <- job_info$yourtable$`ES` %>% as_tibble()
    
    if (is_fc_mode(res_bm1)) {
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
      shiny::h3("Results of AUC",actionButton(tid("intro_res_bm_AUC"),"Quick Tip",class = "btn-success")),
      renderPlotly(pic_out1),
      DT::renderDataTable(DT_res_bm1),
      shiny::br(),
      shiny::h3("Results of ES",actionButton(tid("intro_res_bm_ES"),"Quick Tip",class = "btn-success")),
      renderPlotly(pic_out2),
      DT::renderDataTable(DT_res_bm2),
    )
    
  } else if(job_info$yourmodule == "AUC" || job_info$yourmodule == "AUC_FC") {
    
    res_bm = job_info$yourtable %>% as_tibble()
    res_title = job_info$yourmodule
    tip_id <- if (res_title == "AUC_FC") "AUC" else res_title

    pic_out <- if (is_fc_mode(res_bm))
      ggplotly(draw_dr_auc_fc(res_bm)) else ggplotly(draw_dr_auc(res_bm))

    DT_res_bm <- datatable(res_bm) %>% 
      formatStyle(names(res_bm)[which.max(res_bm[1,-1]) + 1],
                  backgroundColor = styleEqual(res_bm[1, which.max(res_bm[1,-1])+ 1], c('yellow')))

    tagList(
      shiny::h3("Job info"),
      renderTable(job_info$yourjob, striped = T, hover = T, spacing = "l",
                  bordered = T, rownames = F, colnames = F ),
      shiny::h3(paste0("Plot summary of ",res_title),
                actionButton(tid(paste0("intro_res_bm_",tip_id)),"Quick Tip",class = "btn-success")),
      renderPlotly(pic_out),
      shiny::br(),
      shiny::h3(paste0("Results of "),res_title),
      DT::renderDataTable(DT_res_bm)
    )
  } else if(job_info$yourmodule == "ES" || job_info$yourmodule == "ES_FC") {
    
    res_bm = job_info$yourtable %>% as_tibble()
    res_title = job_info$yourmodule

    pic_out <- if (is_fc_mode(res_bm))
      ggplotly(draw_dr_es_fc(res_bm)) else ggplotly(draw_dr_es(res_bm))

    DT_res_bm <- datatable(res_bm) %>% 
      formatStyle(names(res_bm)[which.min(res_bm[1,-1]) + 1],
                  backgroundColor = styleEqual(res_bm[1, which.min(res_bm[1,-1])+ 1], c('yellow')))

    tagList(
      shiny::h3("Job info"),
      renderTable(job_info$yourjob, striped = T, hover = T, spacing = "l",
                  bordered = T, rownames = F, colnames = F ),
      shiny::h3(paste0("Plot summary of ",res_title),
                actionButton(tid(paste0("intro_res_bm_",tip_id)),"Quick Tip",class = "btn-success")),
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
      shiny::h3("Plot summary",actionButton(tid("intro_res_sm_sm"),"Quick Tip",class = "btn-success")),
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
      shiny::h3("Plot summary",actionButton(tid("intro_res_sm_cross"),"Quick Tip",class = "btn-success")),
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
      shiny::h3("Plot summary",actionButton(tid("intro_res_sm_all"),"Quick Tip",class = "btn-success")),
      renderPlotly(ggplotly(draw_all(job_info$yourtable))),
      shiny::br(),
      shiny::h3("Results"),
      DT::renderDataTable(job_info$yourtable %>%
                            dplyr::rename(any_of(rename_col_rules)),
                          server = FALSE),
    )
  }
}