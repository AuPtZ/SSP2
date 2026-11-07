###############################################.
## JOBCENTER - common objects ----
###############################################.


library(dplyr)
library(shinyjs)
### 交互相应区域

# 初始化
output$display_jc <- renderUI(initial_jc)

## 替换
## renderPlot((
## renderPlotly(ggplotly(

# 重置
observeEvent(input$reset_jc, {
  reset("jc_input")
  output$display_jc <- renderUI(initial_jc)
})

# 报警层


# 统一的取结果逻辑：供 Retrieve 按钮与 ?job= 深链共用（NAR D7）。
load_job_from_id <- function(jobid) {
  show_page_spinner()
  output$display_jc <- renderUI({
    on.exit(hide_page_spinner(), add = TRUE)

    isolate({
      if (is.null(jobid) || gsub("[^[:alnum:]]", "", jobid) == "") {
        shinyWidgets::sendSweetAlert(
          session = session,
          title = "Error...",
          text = "Please input a valid jobid",
          type = "error"
        )
        return(shiny::tagList())
      }

      job_info <- read_from_db(jobid)

      # read_from_db 找不到时返回 NA：给友好提示，避免对 NA 取 $ 报错
      if (!is.list(job_info)) {
        return(shiny::tagList(
          shiny::h3("Result not available"),
          shiny::p(paste0("No result was found for job ID '", jobid, "'.")),
          shiny::p("Please check the job ID, or the job may still be running in the background.")
        ))
      }

      # 方案C：作业尚未完成 / 失败时的明确提示
      if (!is.null(job_info$state)) {
        is_err <- job_info$state == "error"
        msg <- switch(job_info$state,
          pending = "Your job is queued and waiting to start. Please check back later.",
          running = "Your job is running in background. Please check back later.",
          error   = paste("Your job failed:", job_info$error),
          "Unknown job status.")
        return(shiny::tagList(
          shiny::h3("Job status"),
          shiny::p(shiny::strong(jobid), " - ", msg),
          job_bookmark_ui(jobid, session, job_status_label(jobid))
        ))
      }

      if (length(job_info) <= 1) {
        return(shiny::tagList(
          shiny::h3("Result not available"),
          shiny::p("Please check the jobid, or the job may still be running in the background.")
        ))
      }

      shiny::tagList(
        job_bookmark_ui(jobid, session, job_status_label(jobid)),
        res_plot(job_info, prefix = "jc")
      )
    }) # isolate end
  })
}

# 运行层
observeEvent(input$jobid_get, {
  load_job_from_id(input$jobid_input)
})

# NAR D7：?job=<jobid> 可收藏链接 —— 打开即自动切到 Job Center 并加载结果/状态
jc_deeplink_done <- reactiveVal(FALSE)
observeEvent(session$clientData$url_search, {
  q <- shiny::parseQueryString(session$clientData$url_search)
  jobid <- q$job
  if (is.null(jobid) || !nzchar(jobid) || jc_deeplink_done()) return()
  jc_deeplink_done(TRUE)
  shiny::updateTextInput(session, "jobid_input", value = jobid)
  nav_select(id = "intabset", selected = "jobcenter", session = session)
  load_job_from_id(jobid)
})




# 结果读取
read_from_db <- function(Jobid_query){
  
  library(RSQLite)
  # library(stringr)
  # con_red_res <- dbConnect(RSQLite::SQLite(), "App-1//results/resinfo.db")
  con_red_res <- dbConnect(RSQLite::SQLite(), "results/resinfo.db")

  # 方案C：先查作业队列状态，未完成/失败时直接返回状态给上层提示
  if (dbExistsTable(con_red_res, "job_queue")) {
    qs <- dbGetQuery(con_red_res,
      "SELECT status, error_msg FROM job_queue WHERE jobid = ?",
      params = list(Jobid_query))
    if (nrow(qs) == 1 && qs$status != "done") {
      dbDisconnect(con_red_res)
      return(list(state = qs$status, error = qs$error_msg))
    }
  }

  # AAAa =  tbl(con_red_res,"res") %>% as_tibble()
  retrieve_job <- tbl(con_red_res,"res") %>% 
    dplyr::filter(Jobid == Jobid_query) %>%  
    as.data.frame() 
  
  signature_name1 = retrieve_job$signature_name1
  signature_name2 = retrieve_job$signature_name2
  
  if(nrow(retrieve_job) != 1){
    dbDisconnect(con_red_res)
    return(NA)
  } else {
    res_module  <- retrieve_job$sub_module
    
    if(retrieve_job$table_num == 1){
      retrieve_table <- tbl(con_red_res,retrieve_job$Jobid ) %>%  
        as.data.frame() 
      
    }else if(retrieve_job$table_num == 2){
      
      retrieve_table <- list(
        "AUC" =  tbl(con_red_res, paste0(retrieve_job$Jobid,"_AUC")) %>% 
          as.data.frame() ,
        "ES" =  tbl(con_red_res, paste0(retrieve_job$Jobid,"_ES")) %>% 
          as.data.frame()
      )
      
    } else if (retrieve_job$table_num == 4) {   # 2026-10-17 新契约：仅 METRICS
      retrieve_table <- list(
        "METRICS" = tbl(con_red_res, paste0(retrieve_job$Jobid,"_METRICS")) %>% as.data.frame()
      )

    } else if (retrieve_job$table_num == 3) {
      retrieve_table <- list(
        "AUC"     = tbl(con_red_res, paste0(retrieve_job$Jobid, "_AUC")) %>% as.data.frame(),
        "ES"      = tbl(con_red_res, paste0(retrieve_job$Jobid, "_ES")) %>% as.data.frame(),
        "METRICS" = tbl(con_red_res, paste0(retrieve_job$Jobid, "_METRICS")) %>% as.data.frame()
      )
      
    }
    
    # 按列名对齐：build_df1（方案 C）只写相关列（如 Benchmark 12 列），
    # 而 name_for_res_col 定义了全部 21 个标签。取两者交集并按
    # name_for_res_col 的顺序对齐，避免 t() 后行数不一致导致 cbind 报错
    # （res 表按需写列：本次任务用不到的列不会出现，靠 .ensure_res_cols 自动扩列）。
    keep <- intersect(names(name_for_res_col), names(retrieve_job))
    retrieve_job <- data.frame(
      V2 = unname(unlist(name_for_res_col[keep])),
      V1 = unname(unlist(retrieve_job[keep])),
      stringsAsFactors = FALSE
    ) %>% dplyr::filter(!is.na(V1))
    
    dbDisconnect(con_red_res)
    
    job_info <- list("yourjob" = retrieve_job,
                     "yourmodule" = res_module,
                     "yourtable" = retrieve_table,
                     "signame1" = signature_name1,
                     "signame2" = signature_name2)
    # save(job_info,file = paste0("demo/",Jobid_query,".rdata"))
    return(job_info)
  }
}


# 右侧说明页面
initial_jc <- tagList(
  h3("Welcome to Job Center module!"),
  p("In this module, you can retrieve results from previous modules.",
    "When you submit a job, you may notice the info window tell you a ",
    strong("Jobid"),".",
    br(),
    div(style = "text-align:center",
        img(src ="imgjc1.png",width = "300px")
    ),
    br(),
    "You can just input the ",strong("Jobid")," in the left pannel and get the results",
    br(),
    "It is useful when a job is running for a long time. Actually, 15~30 minutes is the average running time for each job.",

    
    ),
)

# 侧栏：输入 jobid 即显示该任务的可收藏链接与状态（NAR D7）
output$jc_bookmark_hint <- renderUI({
  jid <- input$jobid_input
  if (is.null(jid) || !nzchar(jid)) return(NULL)
  shiny::div(
    class = "small mt-2",
    shiny::strong("Share / bookmark:"), shiny::br(),
    shiny::tags$a(href = bookmarkable_job_url(jid, session),
                  bookmarkable_job_url(jid, session), target = "_blank"),
    shiny::br(),
    "Status: ", job_status_label(jid)
  )
})

# ---- 最近任务列表（P2：本会话提交的 jobid，点击填入输入框）----
output$jc_recent_jobs <- renderUI({
  ids <- recent_jobs$ids
  if (length(ids) == 0) {
    return(shiny::p("No jobs submitted in this session yet.",
                    class = "text-muted small mb-0"))
  }
  shiny::tags$div(
    lapply(ids, function(id) {
      shiny::tags$a(
        href = "#",
        onclick = sprintf("$('#jobid_input').val('%s').trigger('change'); return false;", id),
        id,
        class = "d-block small text-truncate mb-1"
      )
    })
  )
})