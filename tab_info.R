output$dl_manual_pdf <- downloadHandler(

  filename = function() {
    return("manual of SSP2.pdf")
  },
  content = function(file) {
    file.copy("demo/manual of SSP2.pdf", file)

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
               "demo/manual of SSP2.pdf",
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
    shiny::h3("About SSP2"),
    shiny::p(
      "Signature Search Polestar 2 (SSP2) is the upgraded version of the SSP webserver ",
      "for signature-based drug repurposing. It evaluates signature search methods (SSMs) ",
      "against pharmacotranscriptomic datasets and queries promising drugs for a customized ",
      "oncogenic signature."
    ),

    shiny::h4("Authors"),
    shiny::tags$ul(
      shiny::tags$li(shiny::strong("Jinbo Zhang"), " - Department of Phytochemistry, School of Pharmacy, Second Military Medical University, Shanghai 200433, China; Department of Pharmacy, Tianjin Rehabilitation Center of Joint Logistics Support Force, Tianjin 300110, China"),
      shiny::tags$li(shiny::strong("Shunling Yuan"), " - Department of Phytochemistry, School of Pharmacy, Second Military Medical University, Shanghai 200433, China"),
      shiny::tags$li(shiny::strong("Wen Cao"), " - Department of Phytochemistry, School of Pharmacy, Second Military Medical University, Shanghai 200433, China"),
      shiny::tags$li(shiny::strong("Xianrui Jiang"), " - Changhai Hospital, Second Military Medical University, Shanghai 200433, China"),
      shiny::tags$li(shiny::strong("Cheng Yang"), " - Department of Clinical Nutrition, Tianjin Rehabilitation Center of Joint Logistics Support Force, Tianjin 300110, China"),
      shiny::tags$li(shiny::strong("Chenchao Jiang"), " - Department of Pharmacy, Tianjin Rehabilitation Center of Joint Logistics Support Force, Tianjin 300110, China"),
      shiny::tags$li(shiny::strong("Runhui Liu"), " - Department of Phytochemistry, School of Pharmacy, Second Military Medical University, Shanghai 200433, China"),
      shiny::tags$li(shiny::strong("Wei Yang"), " - Department of Pharmacy, Tianjin Rehabilitation Center of Joint Logistics Support Force, Tianjin 300110, China"),
      shiny::tags$li(shiny::strong("Saisai Tian"), " - Department of Phytochemistry, School of Pharmacy, Second Military Medical University, Shanghai 200433, China; Key Laboratory of Molecular Pharmacology and Drug Evaluation (Yantai University), Ministry of Education, Yantai University, Yantai 264005, China")
    ),

    shiny::h4("Corresponding author"),
    shiny::p("Saisai Tian", shiny::em("(TODO: institutional email)")),

    shiny::h4("How to cite"),
    shiny::p(
      "Zhang J, Yuan S, Cao W, Jiang X, Yang C, Jiang C, Liu R, Yang W, Tian S. ",
      "Signature Search Polestar: a comprehensive drug repurposing method evaluation ",
      "assistant for customized oncogenic signature. ",
      shiny::em("Bioinformatics"), ". 2024;40(9):btae536. ",
      "doi:10.1093/bioinformatics/btae536."
    ),

    shiny::downloadButton("dl_manual_pdf", "Download manual (PDF)",
                          class = "btn-outline-primary"),

    shiny::h4("Funding"),
    shiny::p("National Key Research and Development Program of China (2022YFC3502000)."),

    shiny::h4("License"),
    shiny::p("Mulan Permissive Software License, Version 2 (MulanPSL-2.0)."),

    shiny::h4("Data sources"),
    shiny::p(
      "LINCS L1000 (GSE92742), LINCS2020 beta, Tahoe-100M. ",
      "Gene and drug identifier conversion is supported by Ensembl, UniProt and PubChem."
    ),

    shiny::h4("Version history"),
    shiny::tags$ul(
      shiny::tags$li(shiny::strong("SSP2"), " (current) - expanded to 155 LINCS tumor cell lines plus Tahoe-100M, seven SSMs (adding PLAGE and QuSAGE), rebuilt ranking-quality metrics, Job Center and Converter modules."),
      shiny::tags$li(shiny::strong("SSP v1"), " - Zhang et al., Bioinformatics, 2024;40(9):btae536.")
    ),

    shiny::hr(),

    shiny::h4("Session information"),
    shiny::p("Provided for users who want to reproduce the analysis on their own computer."),
    renderPrint(sessionInfo())
  )


})

