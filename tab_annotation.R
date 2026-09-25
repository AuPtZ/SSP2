###############################################.
## annotation - common objects ----
###############################################.
library(dplyr)
library(tidyr)


### 交互相应区域

if(T){
  load("data_preload/annotation/GSDCIC50_update.Rdata")
  
  output$display_an_auc <- renderUI(initial_an_auc)
  
  output$display_an_auc_tb <- renderDataTable(GSDCIC50 %>%
                                                ungroup() %>% 
                                                mutate(`IC50 value` = round(`IC50 value`, 5)) %>%
                                                dplyr::filter(TCGA_DESC == input$an_auc_input) %>%
                                                dplyr::arrange(PubChem_Cid),
                                              server = FALSE,
                                              options = list(scrollX = TRUE,
                                                             fixedColumns = TRUE))
  
  
  output$run_an_auc <- downloadHandler(
    filename = function() {
      return(paste0(input$an_auc_input,"_AUC_","drug_annotation.txt"))
    },
    content = function(file) {

        rio::export(GSDCIC50 %>% ungroup() %>% 
                      dplyr::filter(TCGA_DESC == input$an_auc_input) %>%
                      dplyr::select(c(Compound_name,Group)),
                    file,format = "tsv",row.names = F)

    }
  )
  
  initial_an_auc <- tagList(
    includeMarkdown("www/tab_annotation_auc.md")
  )
}


if(T){
  # 这里需要修改！
  load("data_preload/annotation/DrugReHub.Rdata")
  # 这里需要修改！
  
  output$display_an_es <- renderUI(initial_an_es)
  
  output$display_an_es_tb <- renderDataTable(DrugReHub %>% 
                                                dplyr::filter(ID == input$an_es_input) %>%
                                                dplyr::arrange(PubChem_Cid),
                                              server = FALSE,
                                              options = list(scrollX = TRUE,
                                                             fixedColumns = TRUE))
  
  
  output$run_an_es <- downloadHandler(
    filename = function() {
      return(paste0(input$an_es_input,"_ES_","drug_annotation.txt"))
    },
    content = function(file) {
      
      # 这里需要修改！
      rio::export(DrugReHub %>% ungroup() %>% 
                    dplyr::filter(ID == input$an_es_input) %>%
                    dplyr::select(Compound_name),
                  file,format = "tsv",row.names = F)
      # 这里需要修改！
      
    }
  )
  
  initial_an_es <- tagList(
    includeMarkdown("www/tab_annotation_es.md")
  )
}