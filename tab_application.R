###############################################.
## sigle method - common objects ----
###############################################.

# 读取数据库


library(ggplot2)
library(ggrepel)
# 方案C：计算已迁移到独立 worker.R，模块内不再使用 future/promises
library(memoise)


### 交互相应区域

# 初始化
output$display_sm <- renderUI({initial_sm})

# 路线B：当前数据集类别提示（化合物 vs CRISPR KO 靶基因）。
# 只影响展示语义；打分/队列/结果结构完全复用现有链路。
output$sm_dataset_class_hint <- renderUI({
  f <- input$sel_experiment_sm
  if (is.null(f) || !length(f) || is.na(f[1]) || !nzchar(f[1])) return(NULL)
  cls <- profile_pert_class(f)
  if (identical(cls, "xpr")) {
    shiny::div(
      class = "alert alert-info py-2 px-3 small mt-2 mb-1",
      shiny::strong("CRISPR KO dataset selected. "),
      "SSP2 ranks ", shiny::strong("target genes"), " (CRISPR knockouts) by how well their ",
      "knockout signature reverses your query signature. The ranked entities are therefore ",
      "gene targets, not drugs; drug-detail popups and PubChem links are disabled for this dataset."
    )
  } else {
    shiny::div(class = "small text-muted mt-2 mb-1",
               "Compound dataset: the ranked entities are drugs/compounds.")
  }
})

# 路线B：xpr 数据集展示离线 pilot 校准（方法/topN 起点 + AUC/null/显著比例）。
# 数据来自 maintain/15_build_calibration.R（B0 pilot 汇总）；没有该细胞系校准时回退类别级。
output$sm_calibration_hint <- renderUI({
  f <- input$sel_experiment_sm
  if (is.null(f) || !length(f) || is.na(f[1]) || !nzchar(f[1])) return(NULL)
  if (!identical(profile_pert_class(f), "xpr")) return(NULL)
  cal <- calibration_for_dataset(f)
  if (is.null(cal) || is.null(cal$rows) || !nrow(cal$rows)) return(NULL)
  rows <- cal$rows
  if (!all(c("method", "topn", "auc") %in% names(rows))) return(NULL)
  rows <- rows[is.finite(rows$auc), , drop = FALSE]
  if (!nrow(rows)) return(NULL)
  best <- do.call(rbind, lapply(split(rows, rows$method), function(d) d[which.max(d$auc), , drop = FALSE]))
  best <- best[order(-best$auc), , drop = FALSE]
  best <- utils::head(best, 3)
  nq <- suppressWarnings(max(rows$n_queries, na.rm = TRUE))
  if (!is.finite(nq)) nq <- NA_integer_
  fmt <- function(x, d = 3) ifelse(is.finite(x), formatC(x, format = "f", digits = d), "NA")
  items <- lapply(seq_len(nrow(best)), function(i) {
    r <- best[i, ]
    sig <- if ("frac_sig_auc" %in% names(r) && is.finite(r$frac_sig_auc))
      sprintf("; %.0f%% of queries significant", 100 * r$frac_sig_auc) else ""
    shiny::tags$li(sprintf("%s @ topN %s - AUC %s (permutation null %s%s)",
                           r$method, r$topn, fmt(r$auc), fmt(r$null_auc), sig))
  })
  level_note <- if (identical(cal$level, "cell"))
    sprintf("cell line %s", cal$cell) else "perturbation-class fallback"
  shiny::div(
    class = "alert alert-secondary py-2 px-3 small mt-2 mb-1",
    shiny::strong("Offline method/topN calibration. "),
    sprintf("From the SSP2 pilot (leave-one-out guide self-retrieval, n = %s queries per cell line; %s). Best combinations: ",
            ifelse(is.na(nq), "n/a", nq), level_note),
    shiny::tags$ul(class = "mb-1", items),
    shiny::em("This is an offline pilot calibration, not a live per-job calibration. Treat the recommended method/topN as a starting point; see Help Q3 for caveats.")
  )
})

# === 方案C：作业轮询显示 ===
rv_sm_job  <- reactiveVal(NULL)   # 当前正在等待结果的 jobid
rv_sm_prog <- reactiveVal(list(done = 0L, total = 0L))   # worker 写回的进度

# 真实进度条：渲染 worker 写入 job_progress 的打点数
output$sm_progress <- renderUI({
  pr <- rv_sm_prog()
  req(is.list(pr), pr$total > 0)
  pct <- max(0L, min(100L, floor(100L * as.numeric(pr$done) / as.numeric(pr$total))))
  shiny::tagList(
    shiny::tags$div(
      class = "progress", style = "height: 24px; margin: 14px 0 6px 0;",
      shiny::tags$div(
        class = "progress-bar progress-bar-striped progress-bar-animated",
        role = "progressbar",
        style = sprintf("width: %d%%; background-color: #0275d8;", pct),
        sprintf("%d%%", pct)
      )
    ),
    shiny::tags$p(sprintf("Computed %d / %d steps", pr$done, pr$total),
                  style = "margin:0; color:#666;")
  )
})

observe({
  jid <- rv_sm_job()
  req(jid)
  st <- get_job_status(jid)
  status <- if (nrow(st) == 0) "pending" else st$status[1]
  if (status %in% c("pending", "running")) {
    rv_sm_prog(get_job_progress(jid))   # 未完成 -> 同步 worker 进度
    invalidateLater(3000)
  } else if (status == "error") {
    rv_sm_job(NULL)
    rv_sm_prog(list(done = 0L, total = 0L, msg = ""))  # 收尾：total=0 -> 进度条隐藏
    emsg <- if (nrow(st)) st$error_msg[1] else "unknown error"
    sendSweetAlert(session, title = "Error...",
                   text = paste("Computation failed:", emsg), type = "error")
    output$display_sm <- renderUI({initial_sm})
  } else {                        # done
    rv_sm_job(NULL)
    # 同 benchmark：不复位就会把最后一格的进度读数留在已渲染的结果旁边
    rv_sm_prog(list(done = 0L, total = 0L, msg = ""))
    job_info <- read_from_db(jid)
    output$display_sm <- renderUI({ res_plot(job_info, prefix = "sm") })
  }
})

# 重置
observeEvent(input$reset_sm, {
  rv_sm_job(NULL)
  # runjs("history.go(0)")
  reset("sm_input")
  output$display_sm <- renderUI({initial_sm})
})




# 运行层
observeEvent(input$runSM, {
  
  # 正式的运行层
  
  
  isolate({
    
    req(judge_sm())
    # 报警子层，函数在下面
    if(judge_sm()){
      jobid_sm <- make_jobid("APP")
      submitted_time =  as.character(Sys.time()) 
      shinyWidgets::sendSweetAlert(
        session = session,
        title = "Success !!",
        text = paste0("Your jobid is ",
                      jobid_sm,
                      ". Please remember it for retrieve results in Job Center") ,
        type = "success"
      )
    }else{
      output$display_sm <- renderUI({initial_sm})
    }
    
    
    #### 校验输入（进度显示见 output$sm_progress，由轮询 worker 进度驱动）
    drug_profile = input$sel_experiment_sm
    filter_mode  = input$filter_mode_sm
    topn         = input$sel_topn_sm
    fc_threshold = input$sel_fc_sm
    sel_model_sm1 = input$sel_model_sm
    funcname = input$sel_ss_sm
    sub_module = input$sel_model_sm
    funcname_mul = input$sel_all_sm
    direct = input$sel_direct_sm
    bioname1 = input$file_name1
    bioname2 = input$file_name2
    
    
    if(sel_model_sm1 == "singlemethod"){
      req(input$file_sig_sm$datapath)
      req(input$sel_ss_sm)
      
      i.need.logfc <- rio::import(input$file_sig_sm$datapath) %>% dplyr::select(c("Gene","log2FC"))
      
      
    }
    if(sel_model_sm1 == "SS_all"){
      req(input$file_sig_sm$datapath)
      req(length(input$sel_all_sm) > 1 )
      
      i.need.logfc <- rio::import(input$file_sig_sm$datapath) %>% dplyr::select(c("Gene","log2FC"))
    }
    if(sel_model_sm1 == "SS_cross"){
      req(input$file_sig_sm1$datapath)
      req(input$file_sig_sm2$datapath)
      req(input$file_name1 != "")
      req(input$file_name2 != "")
      
      i.need.logfc1 <- rio::import(input$file_sig_sm1$datapath) %>% dplyr::select(c("Gene","log2FC"))
      i.need.logfc2 <- rio::import(input$file_sig_sm2$datapath) %>% dplyr::select(c("Gene","log2FC"))
      
      i.need.logfc <- list(
        "i.need.logfc1" = i.need.logfc1,
        "i.need.logfc2" = i.need.logfc2
      )
      
    }
    # === 方案C：把计算入队，由独立 worker 执行；前端轮询 job_queue 状态显示 ===
    nz <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else x
    meta <- list(
      sel_experiment_sm = drug_profile,
      sel_model_sm      = sub_module,
      method_sm2        = find_original_names(funcname),
      method_sm1_all    = paste0(find_original_names(funcname_mul), collapse = ", "),
      direction_sm      = direct,
      file_sig_sm_name  = nz(input$file_sig_sm$name),
      file_sig_sm1_name = nz(input$file_sig_sm1$name),
      file_sig_sm2_name = nz(input$file_sig_sm2$name),
      file_name1        = nz(input$file_name1),
      file_name2        = nz(input$file_name2),
      sel_topn_sm       = input$sel_topn_sm,
      filter_mode       = filter_mode,
      filter_value      = if (filter_mode == "logFC") input$sel_fc_sm else input$sel_topn_sm
    )
    enqueue_job(
      jobid = jobid_sm, module = "Application", sub_module = sub_module,
      submitted_time = submitted_time,
      params = list(drug_profile = drug_profile, topn = topn,
                    filter_mode = filter_mode, fc_threshold = fc_threshold,
                    sel_model_sm1 = sel_model_sm1, i.need.logfc = i.need.logfc,
                    funcname = funcname, funcname_mul = funcname_mul,
                    direct = direct, bioname1 = bioname1, bioname2 = bioname2),
      meta = meta
    )
    rv_sm_job(jobid_sm)
    register_recent_job(jobid_sm)

    output$display_sm <- renderUI({ 
      shiny::tagList(
        shiny::h3("Loading... Please wait."),
        shiny::h3("It may take 15~30 mins to get result"),
        shiny::h3(paste0("Your jobid is ",jobid_sm)),
        job_bookmark_ui(jobid_sm, session, job_status_label(jobid_sm)),
        shiny::uiOutput("sm_progress"),
        # 添加一个JS代码块来通知Shiny服务器端
        tags$script(HTML("
                $(document).on('shiny:visualchange', function(event) {
                  if (event.target.id === 'display_sm') {
                    Shiny.setInputValue('display_sm_loaded', false);
                  }
                });
              "))
      )
      
    }) # renderUI
    
  })
  
  
  
  
  
  
  
})



# 判断函数
judge_sm <- function(){
  # library(shinyWidgets)
  if(input$sel_model_sm == "singlemethod" | input$sel_model_sm == "SS_all"){
    
    if(is.null(input$file_sig_sm$datapath)){
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = "Please Check the uploaded file",
        type = "error"
      )
      return(F)
    }
    
    # 读取文件以后判定
    if(!is.null(input$file_sig_sm$datapath)){
      sig2 <- rio::import(input$file_sig_sm$datapath)
      if(!all(c("Gene","log2FC" ) %in% colnames(sig2))){
        sendSweetAlert(
          session = session,
          title = "Error...",
          text = 'Please make sure your signature table contains column "Gene" and "log2FC" !',
          type = "error"
        )
        return(F)
      }
    }
    
    
    
  } 
  
  if(input$sel_model_sm == "SS_cross"){
    if(is.null(input$file_sig_sm1$datapath) | is.null(input$file_sig_sm2$datapath)){
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = "Please Check the uploaded files",
        type = "error"
      )
      return(F)
    } 
    if(input$file_name1 == "" | input$file_name2 ==""){
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = "Please Check biological names",
        type = "error"
      )
      return(F)
    }
    
    # 读取文件以后判定
    if(!(is.null(input$file_sig_sm1$datapath) | is.null(input$file_sig_sm2$datapath))){
      sig21 <- rio::import(input$file_sig_sm1$datapath)
      sig22 <- rio::import(input$file_sig_sm2$datapath)
      if(!(all(c("Gene","log2FC" ) %in% colnames(sig21)) & all(c("Gene","log2FC" ) %in% colnames(sig22)))){
        sendSweetAlert(
          session = session,
          title = "Error...",
          text = 'Please make sure your signature table contains column "Gene" and "log2FC" !',
          type = "error"
        )
        return(F)
      }
    }
    
    
    
  } 
  
  if(input$sel_model_sm == "SS_all"){
    if(length(input$sel_all_sm) < 2 ){
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = "Please select at least two methods",
        type = "error"
      )
      return(F)
    }
    # 读取文件以后判定
    if(!is.null(input$file_sig_sm$datapath)){
      sig2 <- rio::import(input$file_sig_sm$datapath)
      if(!all(c("Gene","log2FC" ) %in% colnames(sig2))){
        sendSweetAlert(
          session = session,
          title = "Error...",
          text = 'Please make sure your signature table contains column "Gene" and "log2FC" !',
          type = "error"
        )
        return(F)
      }
    }
    
    
  }
  return(T)
}



# 初始化
initial_sm <- tagList(
  includeMarkdownExternal("www/tab_application.md")
)
