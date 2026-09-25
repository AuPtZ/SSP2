output$dl_manual_pdf <- downloadHandler(

  filename = function() {
    return("manual of SSP.pdf")
  },
  content = function(file) {
    file.copy("demo/manual of SSP V5.pdf", file)

  }
)



output$dl_drug_exp <- downloadHandler(
  filename = function() {
    stringr::str_split(input$sel_experiment_dl,".rdata")[[1]][1]
    return(paste0(stringr::str_split(input$sel_experiment_dl,".rdata")[[1]][1],"_profiles.txt"))
  },
  content = function(file) {
    load(paste0("data_preload/drugexp/",input$sel_experiment_dl))
    rio::export(exp_LINCS2020, file,format = "tsv",row.names = T)
    
  }
)


output$dl_drug_ann <- downloadHandler(
  filename = function() {
    stringr::str_split(input$sel_experiment_dl,".rdata")[[1]][1]
    return(paste0(stringr::str_split(input$sel_experiment_dl,".rdata")[[1]][1],"_annotations.txt"))
  },
  content = function(file) {
    load(paste0("data_preload/drugexp/",input$sel_experiment_dl))
    load("data_preload/annotation/drug_GSE92742.Rdata")
    
    # 只保留必要的内容
    sig_LINCS2020 <- sig_LINCS2020 %>% 
      left_join(drug_GSE92742 %>% dplyr::select(-pert_iname), by = "pert_id") %>%
      dplyr::select(pert_iname,cell_id,pert_idose,pert_itime,pubchem_cid,inchi_key,canonical_smiles)
    
    rio::export(sig_LINCS2020, file, format = "tsv",row.names = T)
  }
)


output$dl_demo <- downloadHandler(
  filename = function() {
    return("demo.zip")
  },
  content = function(file) {
    zip::zip(zipfile = file,
             c("demo/drug_annotation_ES.txt",
               "demo/drug_annotation_AUC.txt",
               "demo/signature.txt",
               "demo/signature2.txt",
               "demo/manual of SSP V5.pdf",
               "demo/CS_AUC.txt",
               "demo/CS_ES.txt",
               "demo/CS_OGS.txt"
               ),
             mode = "cherry-pick")
  }
)

output$dl_script <- downloadHandler(
  filename = function() {
    return("demoscript.zip")
  },
  content = function(file) {
    zip::zip(zipfile = file,
             c("R/global.R","R/Utils_BM.R","R/Utils_SM.R","R/SS.R"),
             mode = "cherry-pick")
  }
)







output$display_about =  renderUI({
  
  tagList(
    shiny::h3("Session info"),
    shiny::p("We provide session info for users who want to perform our job in self computer"),
    renderPrint(sessionInfo())
    # shiny::h3("Browsing Map"),
    # div(
    #   tags$script(src="//rf.revolvermaps.com/0/0/7.js?i=5jq3pohyu8j&amp;m=0&amp;c=ff0000&amp;cr1=ffffff&amp;sx=0",
    #               async="async"
    #   ),style = "width:80%;margin:0 auto;"
    # ),
    
  )

  
})

