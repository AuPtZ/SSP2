###############################################.
## convert - common objects ----
###############################################.

### convert gene ##############################.
if(T){
  library(clusterProfiler)
  library(org.Hs.eg.db)
  
  # 初始化
  output$display_ctg <- renderUI({initial_ctg})
  
  # demo触发
  observeEvent(input$runCTGdemo, {  # 添加这个observeEvent
    demo_text <- readLines("demo/demo_signature_entrezid.txt")
    updateRadioButtons(session, "format_ctg", selected = "ENTREZID")
    updateCheckboxInput(session, "header_check_ctg", value = TRUE)
    updateTextAreaInput(session, "text_ctg", value = paste(demo_text, collapse = "\n"))
  })
  
  
  # 构建用于跨函数传递的参数
  rv_ctg <- reactiveValues()
  
  observeEvent(input$runCTG, {
    
    req(judge_ctg())
    
    if(judge_ctg()){
      isolate({
        df_ctg <- read.delim(file = textConnection(input$text_ctg), 
                             header = input$header_check_ctg, 
                             sep = "\t",
                             stringsAsFactors = FALSE)
        
        colnames(df_ctg) = c("Gene","Log2FC")
        rv_ctg$df_ctg <- df_ctg
        
        tryCatch({
          rv_ctg$df_ctg$Gene <- bitr(
            df_ctg$Gene,
            fromType = input$format_ctg,
            toType = "SYMBOL",
            OrgDb = org.Hs.eg.db,
            drop = F
          )$SYMBOL
          # print(landmark)
          rv_ctg$df_ctg <- rv_ctg$df_ctg[rv_ctg$df_ctg$Gene %in% landmark,]
          
        }, error = function(e) {
          rv_ctg$df_ctg$Gene <- NA
        }
        )
        rv_ctg$df_ctg <-  na.omit(rv_ctg$df_ctg)
        
        
        output$display_ctg <-  renderUI({ # renderUI 
          tagList(
            shiny::h3("Result"),
            shiny::strong(paste(round(nrow(rv_ctg$df_ctg)/nrow(df_ctg) *100,digits = 1) ,
                                "% were successfully mapped." )),
            shiny::strong("You may check the input and output and download by click the button."),
            downloadButton(outputId = "download_ctg",
                           label = "Download Output",class = "btn-success"),
            shiny::p(),
            shiny::strong("Please note that output file only contains successfully mapped genes."),
            shiny::p(),
            layout_columns(
              tagList(shiny::h4("Input Preview"),  renderDataTable(df_ctg)),
              tagList(shiny::h4("Output Preview"), renderDataTable(rv_ctg$df_ctg))
            )
          )
        }) # renderUI
        
        
      })
    }
    
    
    
  })
  
  judge_ctg <- function(){
    # 读取文件以后判定
    if(input$text_ctg == ""){
      
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = 'Please enter signature !',
        type = "error"
      )
      return(F)
    }
    if(input$text_ctg != ""){
      
      tryCatch({
        df_ctg <- read.delim(file = textConnection(input$text_ctg), 
                             row.names = NULL,
                             header = input$header_check_ctg, 
                             stringsAsFactors = FALSE)
        
        if (ncol(df_ctg) != 2){
          sendSweetAlert(
            session = session,
            title = "Error...",
            text = 'Please make sure your signature is a two-column list!',
            type = "error"
          )
          return(F)
        }
        
        return(T)
        
      }, error = function(e) {
        sendSweetAlert(
          session = session,
          title = "Error...",
          text = 'Please make sure your signature is a list!',
          type = "error"
        )
        return(F)
      })
      
    }
  }
  
  # 初始化
  initial_ctg <- tagList(
    includeMarkdown("www/tab_converter_g.md")
  )
  
  # 下载转换后的文件
  output$download_ctg <- downloadHandler(
    filename = function() {
      # Use the selected dataset as the suggested file name
      paste0("signature_",format(Sys.time(), "%Y_%m_%d_%H_%M_%S") ,".txt")
    },
    content = function(file) {
      # Write the dataset to the `file` that will be downloaded
      rio::export(rv_ctg$df_ctg %>% na.omit(), file,format = "tsv",row.names = F)
      
    }
  )
}

### convert gene ##############################.

### convert drug ##############################.
if(T){
  library(dplyr)
  if (file.exists("data_preload/drugconvertor/LINCS2020_drug_info.Rdata")) {
    load("data_preload/drugconvertor/LINCS2020_drug_info.Rdata")
  } else {
    load("data_preload/drugconvertor/GSE92742_LINCS_drug_info.Rdata")
  }
  # 初始化
  output$display_ctd <- renderUI({initial_ctd})
  
  # demo触发
  observeEvent(input$runCTDdemo1, {  # 添加这个observeEvent
    demo_text <- readLines("demo/demo_drug_name.txt")
    updateRadioButtons(session, "format_ctd", selected = "net_drug_name")
    updateCheckboxInput(session, "header_check_ctd", value = TRUE)
    updateTextAreaInput(session, "text_ctd", value = paste(demo_text, collapse = "\n"))
  })
  observeEvent(input$runCTDdemo2, {  # 添加这个observeEvent
    demo_text <- readLines("demo/demo_drug_pubchem.txt")
    updateRadioButtons(session, "format_ctd", selected = "pubchem_cid")
    updateCheckboxInput(session, "header_check_ctd", value = TRUE)
    updateTextAreaInput(session, "text_ctd", value = paste(demo_text, collapse = "\n"))
  })
  observeEvent(input$runCTDdemo3, {  # 添加这个observeEvent
    demo_text <- readLines("demo/demo_drug_inchikey.txt")
    updateRadioButtons(session, "format_ctd", selected = "inchi_key")
    updateCheckboxInput(session, "header_check_ctd", value = TRUE)
    updateTextAreaInput(session, "text_ctd", value = paste(demo_text, collapse = "\n"))
  })
  
  
  # 构建用于跨函数传递的参数
  rv_ctd <- reactiveValues()
  
  observeEvent(input$runCTD, {
    
    req(judge_ctd())
    
    if(judge_ctd()){
      
      isolate({
        df_ctd <- read.delim(file = textConnection(input$text_ctd), 
                             header = input$header_check_ctd, 
                             sep = "\t",
                             stringsAsFactors = FALSE)
        
        if (ncol(df_ctd) == 1){
          colnames(df_ctd) = "inputlist"
        }
        
        if (ncol(df_ctd) == 2){
          colnames(df_ctd) = c("inputlist","Group")
        }
        
        
        
        df_ctd$inputlist <- as.character(df_ctd$inputlist)
        

        tryCatch({
          
          if(input$format_ctd == "net_drug_name"){
            
            
            rv_ctd$df_ctd = dplyr::left_join(df_ctd %>% 
                                               mutate(inputlist, net_drug_name =  tolower(gsub("[- ]", "", inputlist))),
                                             CMAP_druginfo,by = "net_drug_name") %>% 
              dplyr::select(any_of(c("inputlist", "pert_iname","Group")))  %>% 
              dplyr::rename("Compound_name" = "pert_iname") %>% distinct() 
            

            
            
            
            
          }else{
 
            # print(input$format_ctd)
            rv_ctd$df_ctd = left_join(df_ctd, CMAP_druginfo, by=c("inputlist" = input$format_ctd)) %>% 
              dplyr::select(any_of(c("inputlist", "pert_iname","Group")))   %>% 
              dplyr::rename("Compound_name" = "pert_iname") %>% distinct() 


            
          }
          
          
        }, error = function(e) {

          rv_ctd$df_ctd$Compound_name <- NA
        }
        )
        
        

        output$display_ctd <-  renderUI({ # renderUI 
          tagList(
            shiny::h3("Result"),
            shiny::strong(paste(round(sum(!is.na(rv_ctd$df_ctd$Compound_name))/nrow(df_ctd) *100,digits = 1) ,
                                "% were successfully mapped. More than 100% mapped means there may be cross-mapping." )),
            shiny::p(),
            shiny::strong("You may check the input and output and download by click the button."),
            downloadButton(outputId = "download_ctd",
                           label = "Download Output",class = "btn-success"),
            shiny::p(),
            shiny::strong("Please note that output file only contains successfully mapped drugs."),
            shiny::p(),

            layout_columns(
              widths = c(5, 7),
              tagList(shiny::h4("Input Preview"),  renderDataTable(df_ctd, options = list(searching = FALSE))),
              tagList(shiny::h4("Output Preview"), renderDataTable(rv_ctd$df_ctd))
            )
          )
        }) # renderUI
        
      })
    }
    
    
    
  })
  
  judge_ctd <- function(){
    # 读取文件以后判定
    if(input$text_ctd == ""){
      
      sendSweetAlert(
        session = session,
        title = "Error...",
        text = 'Please enter signature !',
        type = "error"
      )
      return(F)
    }
    if(input$text_ctd != ""){
      
      tryCatch({
        df_ctd <- read.delim(file = textConnection(input$text_ctd), 
                             row.names = NULL,
                             header = input$header_check_ctd, 
                             stringsAsFactors = FALSE)
        
        # print(df_ctd)
        
        if ( !(ncol(df_ctd) %in% c(1,2)) ){
          sendSweetAlert(
            session = session,
            title = "Error...",
            text = 'Please make sure your drug list is a one-column or two-column tab-separated list!',
            type = "error"
          )
          return(F)
        }
        
        return(T)
        
      }, error = function(e) {
        
        # print(e)
        
        sendSweetAlert(
          session = session,
          title = "Error...",
          text = 'Please make sure your drug list is a list!',
          type = "error"
        )
        return(F)
      })
      
    }
  }
  
  # 初始化
  initial_ctd <- tagList(
    includeMarkdown("www/tab_converter_d.md")
  )
  
  # 下载转换后的文件
  output$download_ctd <- downloadHandler(
    filename = function() {
      # Use the selected dataset as the suggested file name
      paste0("drug_",format(Sys.time(), "%Y_%m_%d_%H_%M_%S") ,".txt")
    },
    content = function(file) {
      # Write the dataset to the `file` that will be downloaded
      rio::export(rv_ctd$df_ctd %>% dplyr::select(-inputlist) %>% na.omit(), file,format = "tsv",row.names = F)
      
    }
  )

}
### convert drug ##############################.
