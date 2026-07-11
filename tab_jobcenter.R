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


# 运行层
observeEvent(input$jobid_get, {
  # 报警子层
  
  
  output$display_jc <- renderUI({
    
    isolate({
      
      # print("开始判断~")
      
      if(gsub("[^[:alnum:]]","",input$jobid_input) == "" | is.null(input$jobid_input)){
        shinyWidgets::sendSweetAlert(
          session = session,
          title = "Error...",
          text = "Please input vaild jobid",
          type = "error"
        )
      }
      
      
      req(gsub("[^[:alnum:]]","",input$jobid_input) != "")
      req(!is.null(input$jobid_input))
      
      # print("开始获取job_info~")
      # print(input$jobid_input)
      job_info =  read_from_db(input$jobid_input)
      # save(job_info,file = paste0("demo/",input$jobid_input,".rdata"))
      # print(paste0("job_info is",job_info))

      # 方案C：作业尚未完成 / 失败时的明确提示
      if(!is.null(job_info$state)){
        is_err <- job_info$state == "error"
        msg <- switch(job_info$state,
          pending = "Your job is queued and waiting to start. Please check back later.",
          running = "Your job is running in background. Please check back later.",
          error   = paste("Your job failed:", job_info$error),
          "Unknown job status.")
        shinyWidgets::sendSweetAlert(
          session = session,
          title = if (is_err) "Error..." else "Please wait",
          text = msg,
          type = if (is_err) "error" else "info"
        )
      }
      req(is.null(job_info$state))

      if(length(job_info) <= 1){
        shinyWidgets::sendSweetAlert(
          session = session,
          title = "Error...",
          text = "Please Check the your jobid, \n or maybe your job submitted is still running background.",
          type = "error"
        )
      }
      
      # print("job_info判断")
      req(length(job_info) >1)
      req(job_info$yourtable)
      req(job_info$yourmodule)
      
      res_plot(job_info, prefix = "jc")
      # save(job_info,file = "demo/BEN1712624574ZFX.rdata")
      
    }) # isolate end
  })
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
      
    }
    
    # 按列名对齐：build_df1（方案 C）只写相关列（如 Benchmark 12 列），
    # 而 name_for_res_col 定义了全部 21 个标签。取两者交集并按
    # name_for_res_col 的顺序对齐，避免 t() 后行数不一致导致 cbind 报错
    # （旧 write_in_db 写满 21 列故一直对齐，方案 C 改为按需写列）。
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