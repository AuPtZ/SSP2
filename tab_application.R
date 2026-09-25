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

# === 方案C：作业轮询显示 ===
rv_sm_job <- reactiveVal(NULL)   # 当前正在等待结果的 jobid
observe({
  jid <- rv_sm_job()
  req(jid)
  st <- get_job_status(jid)
  status <- if (nrow(st) == 0) "pending" else st$status[1]
  if (status %in% c("pending", "running")) {
    invalidateLater(3000)
  } else if (status == "error") {
    rv_sm_job(NULL)
    emsg <- if (nrow(st)) st$error_msg[1] else "unknown error"
    sendSweetAlert(session, title = "Error...",
                   text = paste("Computation failed:", emsg), type = "error")
    output$display_sm <- renderUI({initial_sm})
  } else {                        # done
    rv_sm_job(NULL)
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
      jobid_sm <- paste0("APP",as.integer(Sys.time()),paste0(sample(LETTERS,3),collapse = ""))
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
    
    
    #### Create a Progress object
    progress_sm <- shiny::Progress$new()
    
    # Make sure it closes when we exit this reactive, even if there's an error
    # on.exit(progress$close())
    
    progress_sm$set(message = paste0("Performing ", jobid_sm), value = 0)
    #### 
    
    
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
    ###
    progress_sm$inc(0.2, detail = paste("file loaded, computing"))
    ###

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
    progress_sm$close()


    output$display_sm <- renderUI({ 
      shiny::tagList(
        shiny::h3("Loading... Please wait."),
        shiny::h3("It may take 15~30 mins to get result"),
        shiny::h3(paste0("Your jobid is ",jobid_sm)),
        shiny::h3("Please remember it for retrieve results in Job Center."),
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
  includeMarkdown("www/tab_application.md")
)
