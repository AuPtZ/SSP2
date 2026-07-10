###############################################.
## Bechmark - common objects ----
###############################################.

#####################.
# Generate data
# read gctx
# library(cmapR)
library(future)
library(promises)
# plan(multisession)

library(memoise)

# cores <- get_cores()
# dir = "~/dataportal/LINCS/GSE92742_Broad_LINCS_Level5_COMPZ.MODZ_n473647x12328.gctx"

# 读取sig数据，用于提取数据


### 交互相应区域

# 初始化
output$display_bm <- renderUI(initial_bm)


# 重置
observeEvent(input$reset, {
  reset("bm_input")
  
  # system(paste0("rm ",input$file_sig$datapath))
  # system(paste0("rm ",input$file_IC50$datapath))
  # system(paste0("rm ",input$file_FDA$datapath))
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
    
    #### Create a Progress object
    progress_bm <- shiny::Progress$new()
    
    # Make sure it closes when we exit this reactive, even if there's an error
    # on.exit(progress$close())
    
    progress_bm$set(message = paste0("Performing ", jobid_bm), value = 0)
    #### 
    
    
    req(length(input$sel_ss)>1)
    req(!(is.null(input$file_IC50) & is.null(input$file_FDA)))
    req(!is.null(input$file_sig))
    
    IC50_drug = input$file_IC50$datapath
    FDA_drug = input$file_FDA$datapath
    i.need.logfc = input$file_sig$datapath
    
    # 使用一个trick读取IC50,FDA和logfc，如果没有的话，那就认为为NULL，如果有的话，那就读取
    if(!is.null(IC50_drug)){
      IC50_drug <- rio::import(input$file_IC50$datapath)
    }
    if(!is.null(FDA_drug)){
      FDA_drug <- rio::import(input$file_FDA$datapath)
    }
    if(!is.null(i.need.logfc)){
      i.need.logfc <- rio::import(input$file_sig$datapath) %>% dplyr::select(c("Gene","log2FC"))
    }
    
    
    sel_exp = input$sel_experiment
    sel_ss = input$sel_ss
    filter_mode = input$filter_mode_bm
    
    ###
    progress_bm$inc(0.2, detail = paste("file loaded, computing"))
    ###
    
    # 正式的运行层
    future_promise({ ## future 需要单独加载包，global的不行
      library(dplyr)
      library(tidyr)
      library(ggplot2)
      library(tibble)
      library(pROC)
      library(rio)
      library(tidyverse)
      
      
      isolate({
        
        # print("we are going to res_bm!")
        res_bm <- get_benchmark(
          IC50_drug = IC50_drug,
          FDA_drug = FDA_drug, 
          i.need.logfc = i.need.logfc, 
          sel_exp = sel_exp,
          sel_ss = sel_ss,
          filter_mode = filter_mode
        )
        # save(res_bm,file = "1.rdata")

        return(res_bm)
      })
    }, seed = TRUE) %...>% (
      function(res_bm){
        # print("we get result!")
        # res_bm <- result
        
        ###
        progress_bm$inc(0.6, detail = paste("get result, ploting"))
        ###
        
        if(length(res_bm) ==3){
          
          # print(res_bm)
          write_in_db(Jobid = jobid_bm, 
                      Submitted_time = submitted_time, 
                      module_name = "Benchmark",
                      sub_module = "ALL (ES and AUC)",
                      table_num = 2, 
                      table_res = list(
                        "AUC" = res_bm[[1]],
                        "ES" = res_bm[[2]]
                      ) )
          
          res_bm1 <- res_bm[[1]]
          res_bm2 <- res_bm[[2]]
          
          if (filter_mode == "logFC") {
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
            
          
          
          output$display_bm <- renderUI({ ## renderUI 
            tagList(
              shiny::h3("Results of AUC",actionButton("intro_res_bm_AUC","Quick Tip",class = "btn-success")),
              renderPlotly(pic_out1),
              DT::renderDataTable(DT_res_bm1),
              shiny::br(),
              shiny::h3("Results of ES",actionButton("intro_res_bm_ES","Quick Tip",class = "btn-success")),
              renderPlotly(pic_out2),
              DT::renderDataTable(DT_res_bm2),
              # 添加一个JS代码块来通知Shiny服务器端
              tags$script(HTML("
                $(document).on('shiny:visualchange', function(event) {
                  if (event.target.id === 'display_bm') {
                    Shiny.setInputValue('display_bm_loaded', true);
                  }
                });
              "))
            )
          }) ## renderUI
        } else if (length(res_bm) ==2){
          
          write_in_db(Jobid = jobid_bm, 
                      Submitted_time = submitted_time, 
                      module_name = "Benchmark",
                      sub_module = res_bm[[2]],
                      table_num = 1, 
                      table_res = res_bm[[1]])
          
          res_title = res_bm[[2]]
          res_bm = res_bm[[1]]

          is_FC <- grepl("FC", res_title)
          if(grepl("AUC", res_title)){
            pic_out <- if (is_FC) ggplotly(draw_dr_auc_fc(res_bm)) else ggplotly(draw_dr_auc(res_bm))
            DT_res_bm <- datatable(res_bm) %>% 
              formatStyle(names(res_bm)[which.max(res_bm[1,-1]) + 1],
                          backgroundColor = styleEqual(res_bm[1, which.max(res_bm[1,-1])+ 1], c('yellow')))
          }
          if(grepl("ES", res_title) && !grepl("AUC", res_title)){
            pic_out <- if (is_FC) ggplotly(draw_dr_es_fc(res_bm)) else ggplotly(draw_dr_es(res_bm))
            DT_res_bm <- datatable(res_bm) %>% 
              formatStyle(names(res_bm)[which.min(res_bm[1,-1]) + 1],
                          backgroundColor = styleEqual(res_bm[1, which.min(res_bm[1,-1])+ 1], c('yellow')))
          }
          
          output$display_bm <- renderUI({ ## renderUI
            tagList(
              shiny::h3(paste0("Plot summary of"),
                        res_title,actionButton(paste0("intro_res_bm_",res_title),"Quick Tip",class = "btn-success")),
              renderPlotly(pic_out),
              shiny::br(),
              shiny::h3(paste0("Results of "),res_title),
              DT::renderDataTable(DT_res_bm),
              # 添加一个JS代码块来通知Shiny服务器端
              tags$script(HTML("
                $(document).on('shiny:visualchange', function(event) {
                  if (event.target.id === 'display_bm') {
                    Shiny.setInputValue('display_bm_loaded', true);
                  }
                });
              "))
            )
          }) ## renderUI
        } else{
          output$display_bm <- renderUI({ ## renderUI
            tagList(
            shiny::h3("Please Check Iput Files!"),
            tags$script(HTML("
                $(document).on('shiny:visualchange', function(event) {
                  if (event.target.id === 'display_bm') {
                    Shiny.setInputValue('display_bm_loaded', true);
                  }
                });
              "))
            )
          }) ## renderUI
        }

        progress_bm$close()
      }
    ) %...!% (function(e) {
      progress_bm$close()
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = paste("Computation failed:", conditionMessage(e)),
        type = "error"
      )
    })
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
          else "SSP will compute the topN from 10 to maximum."),
        shiny::h3(paste0("Your jobid is ",jobid_bm)),
        shiny::h3("Please remember it for retrieve results in Job Center."),

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
  
  if(is.null(input$file_IC50) & is.null(input$file_FDA)){
    sendSweetAlert(
      session = session,
      title = "Error...",
      text = "Please upload at least 1 annotation file!",
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
  if(!is.null(input$file_FDA)){
    fda1 <-  rio::import(input$file_FDA$datapath)
    if(!all(c("Compound_name" ) %in% colnames(fda1))){
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = 'Please make sure your FDA table contains column "Compound_name" !',
        type = "error"
      )
      return(F)
    }
  }
  
  if(!is.null(input$file_IC50)){
    ic501 <-  rio::import(input$file_IC50$datapath)
    if(!all(c("Compound_name","Group" ) %in% colnames(ic501))){
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = 'Please make sure your AUC table contains column "Compound_name" and "Group" !',
        type = "error"
      )
      return(F)
    }
    
    if(!all(sort(unique(ic501$Group)) == c("Effective","Ineffective")) ){
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = 'Please make sure your AUC table column "Group" only contain "Effective" and "Ineffective" !',
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
  includeMarkdown("www/tab_benchmark.md")
)