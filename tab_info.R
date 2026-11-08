# v1 (2024) 手册已下线：内容仍是旧版（含已删除的 Robustness 模块、five SSMs、
# 旧 URL），不再通过 UI 提供下载。归档件见 archive/，说明见 www/info_Q10.md。

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
      "Signature Search Polestar 2 (SSP2) is the upgraded version of the SSP2 webserver ",
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
    shiny::p("Jinbo Zhang"),

    shiny::h4("Contact"),
    shiny::p(
      "For questions, data removal requests and correspondence, please contact ",
      shiny::tags$a("zhangjb@smmu.edu.cn", href = "mailto:zhangjb@smmu.edu.cn"),
      ". The personal address ",
      shiny::tags$a("jbzhangs@foxmail.com", href = "mailto:jbzhangs@foxmail.com"),
      " is kept as a fallback."
    ),

    shiny::h4("How to cite"),
    shiny::p(
      "Zhang J, Yuan S, Cao W, Jiang X, Yang C, Jiang C, Liu R, Yang W, Tian S. ",
      "Signature Search Polestar: a comprehensive drug repurposing method evaluation ",
      "assistant for customized oncogenic signature. ",
      shiny::em("Bioinformatics"), ". 2024;40(9):btae536. ",
      "doi:10.1093/bioinformatics/btae536."
    ),

    shiny::h4("Funding"),
    shiny::p("National Key Research and Development Program of China (2022YFC3502000)."),

    shiny::h4("License"),
    shiny::p("Mulan Permissive Software License, Version 2 (MulanPSL-2.0)."),

    shiny::h4("Privacy and data retention"),
    shiny::p(
      "User-uploaded signatures and drug annotations are used only to run the requested ",
      "calculation and are never shared with third parties. SSP2 does not use tracking ",
      "cookies or third-party analytics, and requires no login or registration. ",
      "Results are accessible only to anyone holding the job-specific link (job ID), ",
      "which acts as an access credential; please keep it private. Results are retained ",
      "for at least 90 days, and can be removed earlier on request by contacting the authors."
    ),

    shiny::h4("Data sources and provenance"),
    shiny::tags$ul(
      shiny::tags$li(
        shiny::strong("LINCS2020 beta (CMap LINCS 2020 release, Dec 2020). "),
        "Level-5 compound-treatment signatures ",
        shiny::tags$code("level5_beta_trt_cp_n720216x12328.gctx"),
        " (720,216 signatures x 12,328 genes), with ",
        shiny::tags$code("siginfo_beta.txt"), " and ", shiny::tags$code("cellinfo_beta.txt"),
        " metadata. The 12,328 genes comprise 978 directly measured L1000 landmark genes ",
        "plus computationally inferred genes. Signatures passing QC were grouped by cell line, ",
        "dose and 6 h / 24 h treatment time and averaged per compound, giving 155 tumor cell ",
        "lines. This is the final L1000 release; the CLUE data portal was retired on ",
        "2026-01-31 and the public data are now archived at GEO."
      ),
      shiny::tags$li(
        shiny::strong("Tahoe-100M. "),
        "Single-cell perturbation data aggregated into pseudobulk differential-expression ",
        "profiles (DESeq2 log2FC versus plate-matched DMSO controls); conditions with fewer ",
        "than 50 treated or control cells and three low-abundance cell lines were excluded. ",
        "SSP2 provides 47 cell lines plus one pan-cell-line aggregate, each at three doses ",
        "(0.05, 0.5, 5 uM) and a single 24 h time point, covering 379 drugs on 62,710 genes."
      ),
      shiny::tags$li(
        shiny::strong("Annotation services. "),
        "Gene and drug identifier conversion is supported by Ensembl, UniProt and PubChem; ",
        "drug annotations additionally draw on ChEMBL, DrugBank and ClinicalTrials.gov."
      )
    ),
    shiny::p(
      "Gene-expression profiles are provided for academic research use under the terms of ",
      "their original sources; please cite the LINCS/CMap and Tahoe-100M resources when ",
      "publishing results obtained with SSP2. Full version, file checksums, processing ",
      "parameters and licence notes are documented in the project ",
      shiny::tags$code("README.md"), "."
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

