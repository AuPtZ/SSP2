###############################################.
## Bechmark - common objects ----
###############################################.

#####################.
# Generate data
# read gctx
# library(cmapR)
# 方案C：计算已迁移到独立 worker.R，模块内不再使用 future/promises
library(memoise)

# cores <- get_cores()
# dir = "~/dataportal/LINCS/GSE92742_Broad_LINCS_Level5_COMPZ.MODZ_n473647x12328.gctx"

# 读取sig数据，用于提取数据


### 交互相应区域

# 初始化
output$display_bm <- renderUI(initial_bm)

# === 方案C：作业轮询显示 ===
rv_bm_job  <- reactiveVal(NULL)   # 当前正在等待结果的 jobid
rv_bm_prog <- reactiveVal(list(done = 0L, total = 0L))   # worker 写回的进度

# 真实进度条：渲染 worker 写入 job_progress 的打点数。
# 注意不能用 shiny::Progress —— 计算在 worker 进程里，Shiny 会话内的
# Progress 对象无法反映其进度，且生命周期只有毫秒级，浏览器根本来不及显示。
output$bm_progress <- renderUI({
  pr <- rv_bm_prog()
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
  jid <- rv_bm_job()
  req(jid)
  st <- get_job_status(jid)
  status <- if (nrow(st) == 0) "pending" else st$status[1]
  if (status %in% c("pending", "running")) {
    rv_bm_prog(get_job_progress(jid))   # 未完成 -> 同步 worker 进度
    invalidateLater(3000)               # 3 秒后再查（完成后自动停止）
  } else if (status == "error") {
    rv_bm_job(NULL)
    rv_bm_prog(list(done = 0L, total = 0L, msg = ""))  # 收尾：total=0 -> 进度条隐藏
    emsg <- if (nrow(st)) st$error_msg[1] else "unknown error"
    sendSweetAlert(session, title = "Error...",
                   text = paste("Computation failed:", emsg), type = "error")
    output$display_bm <- renderUI(initial_bm)
  } else {                        # done
    rv_bm_job(NULL)
    # 轮询到此为止，rv_bm_prog 若不复位就会永远停在最后一次读到的进度
    # （如 "Computed 50 / 102"），和已渲染的结果图并排显示，像是没跑完。
    rv_bm_prog(list(done = 0L, total = 0L, msg = ""))
    job_info <- read_from_db(jid)
    show_page_spinner()
    output$display_bm <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "bm") })
  }
})


# 重置
observeEvent(input$reset, {
  rv_bm_job(NULL)
  reset("bm_input")
  
  # system(paste0("rm ",input$file_sig$datapath))
  # 
  # print(input$file_sig)
  output$display_bm <- renderUI(initial_bm)
  
  
})



# 运行层
observeEvent(input$runBM, {
  
  
  
  
  isolate({ # isolate
    
    req(judge_bm()) 
    
    # 报警子层，函数在下面
    if(judge_bm()){
      jobid_bm <- paste0("BEN",as.integer(Sys.time()),paste0(sample(LETTERS,3),collapse = ""))
      submitted_time =  as.character(Sys.time()) 
      shinyWidgets::sendSweetAlert(
        session = session,
        title = "Success !!",
        text = paste0("Your jobid is ",
                      jobid_bm,
                      ".\n Process may take 15~30mins. \n Please remember it for retrieve results in Job Center.") ,
        type = "success"
      )
    }else{
      output$display_bm <- renderUI(initial_bm)
    }
    
#### 校验输入（进度显示见 output$bm_progress，由轮询 worker 进度驱动）
req(length(input$sel_ss)>1)
req(!is.null(input$file_anno))
req(!is.null(input$file_sig))

drug_anno <- rio::import(input$file_anno$datapath)
i.need.logfc = input$file_sig$datapath
if(!is.null(i.need.logfc)){
i.need.logfc <- rio::import(input$file_sig$datapath) %>% dplyr::select(c("Gene","log2FC"))
}
# 注释格式校验：单列 Compound_name（给明确报错，而不是让 worker 静默失败）
if (!"Compound_name" %in% names(drug_anno)) {
shiny::showNotification(
"The drug annotation must be a one-column table with header Compound_name.",
type = "error", duration = 10)
return()
}

anno_type = input$anno_type
sel_exp = input$sel_experiment
sel_ss = input$sel_ss
filter_mode = input$filter_mode_bm


# === 方案C：把计算入队，由独立 worker 执行；前端轮询 job_queue 状态显示 ===
nz <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else x
meta <- list(
sel_experiment = sel_exp,
sel_ss_names   = paste0(find_original_names(sel_ss), collapse = ", "),
file_sig_name  = nz(input$file_sig$name),
file_anno_name = nz(input$file_anno$name),
anno_type      = anno_type,
filter_mode    = filter_mode,
filter_value   = if (filter_mode == "logFC") input$sel_fc_sm else input$sel_topn_sm
)
enqueue_job(
jobid = jobid_bm, module = "Benchmark", sub_module = "METRICS",
submitted_time = submitted_time,
params = list(drug_anno = drug_anno, anno_type = anno_type,
i.need.logfc = i.need.logfc, sel_exp = sel_exp,
sel_ss = sel_ss, filter_mode = filter_mode),
meta = meta
)
    rv_bm_job(jobid_bm)
    register_recent_job(jobid_bm)

    output$display_bm <- renderUI({ ## renderUI 
      shiny::tagList(
        shiny::h3("Loading... Please wait."),
        shiny::h3("It may take 15~30 mins to get result."),
        if (filter_mode == "logFC") {
          shiny::h3(paste0("Filter mode: |log2FC| threshold, scanning from 0.50 to ",
                           get_fcth(i.need.logfc), " step 0.05."))
        } else {
          shiny::h3(paste0("As your uploaded signature has a maximum of ",
                           get_topn(i.need.logfc), " in one direction (Up or Down)."))
        },
        shiny::h3(if (filter_mode == "logFC") 
          "SSP will compute the |log2FC| threshold from 0.50 to maximum."
          else "SSP will compute the topN from 10 to the number of genes in one direction (Up or Down), capped at 1000."),
        shiny::h3(paste0("Your jobid is ",jobid_bm)),
        shiny::h3("Please remember it for retrieve results in Job Center."),
        shiny::uiOutput("bm_progress"),

        tags$script(HTML("
                $(document).on('shiny:visualchange', function(event) {
                  if (event.target.id === 'display_bm') {
                    Shiny.setInputValue('display_bm_loaded', false);
                  }
                });
              "))
      )
    }) ## renderUI

  }) # isolate
  
  
  
})

## 判断
judge_bm <- function(){
  
  if(is.null(input$file_sig)){
    sendSweetAlert(
      session = session,
      title = "Error...",
      text = "Please upload signature!",
      type = "error"
    )
    return(F)
  }
  
if(is.null(input$file_anno)){
sendSweetAlert(
session = session,
title = "Error...",
text = "Please upload the drug annotation file (a one-column drug list)!",
type = "error"
)
return(F)
}
  
  if(length(input$sel_ss)<2){
    sendSweetAlert(
      session = session,
      title = "Error...",
      text = "Please select at least 2 methods",
      type = "error"
    )
    return(F)
  }
  
  # 对于有上传文件的情况进行判断
  
  
  if(!is.null(input$file_sig)){
    sig1 <-  rio::import(input$file_sig$datapath)
    if(!all(c("Gene","log2FC" ) %in% colnames(sig1))){
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = 'Please make sure your signature table contains column "Gene" and "log2FC" !',
        type = "error"
      )
      return(F)
    }
  }
  
# 读取文件以后判定
if(!is.null(input$file_anno)){
anno1 <-  rio::import(input$file_anno$datapath)
if(!all(c("Compound_name" ) %in% colnames(anno1))){
sendSweetAlert(
session = session,
title = "Error...",
text = 'Please make sure your drug annotation contains column "Compound_name" !',
type = "error"
)
return(F)
}
}
  
  
  
  return(T)
}

output$dl_drug_ann_bm <- downloadHandler(
  filename = function() {
    stringr::str_split(input$sel_experiment,".rdata")[[1]][1]
    return(paste0(stringr::str_split(input$sel_experiment,".rdata")[[1]][1],"_blank_annotations.txt"))
  },
  content = function(file) {
    load(paste0("data_preload/drugexp/",input$sel_experiment))
    # 兼容新旧数据：优先用 cmap_name（新），fallback pert_iname（旧）
    drug_names <- if ("cmap_name" %in% colnames(sig_LINCS2020)) {
      unique(sig_LINCS2020$cmap_name)
    } else if ("pert_iname" %in% colnames(sig_LINCS2020)) {
      unique(sig_LINCS2020$pert_iname)
    } else {
      colnames(exp_LINCS2020)  # fallback: expression matrix colnames
    }
    n_drugs <- length(drug_names)
    df_ann_export1 <- data.frame(
      "Compound_name" = drug_names,
      "Group" = c("Effective","Ineffective",rep(NA, times = max(0, n_drugs - 2)))
    )
    rio::export(df_ann_export1, file, format = "tsv", row.names = F)
  }
)


# output$dl_solo_sig1 <- downloadHandler(
#   filename = function() {
#     return("signature.txt")
#   },
#   content = function(file) {
#     file.copy("demo/signature.txt", file)
#   }
# )




initial_bm <- tagList(
  includeMarkdownExternal("www/tab_benchmark.md")
)