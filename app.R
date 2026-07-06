#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# the UI Codes are modified from ScotPHO's Shiny profile platform
#

library(shiny)
library(shinyjs)
library(shinythemes)
library(shinyWidgets)
library(shinyBS)
library(shinycssloaders)
library(shinylogs)
# library(rintrojs)
library(future)
library(promises)
library(htmltools)
plan(multisession,workers = 64L)
plan(future.callr::callr)

shinyOptions(cache = cachem::cache_mem(max_size = 1000e6))
options(shiny.sanitize.errors = TRUE)

ui <- tagList( # needed for shinyjs
  useShinyjs(),  # Include shinyjs
  useSweetAlert(), 
  # introjsUI(),
  navbarPage(id = "intabset", #needed for landing page
             # title = "BCSS",
             title = div(tags$a(img(src="LOGO.png", height=50)),
                         style = "position: relative; top: -15px;"), # Navigation bar
             windowTitle = "Signature Search Polestar", #title for browser tab
             theme = shinytheme("cerulean"), #Theme of the app (blue navbar)
             collapsible = TRUE, #tab panels collapse into menu in small screens
             header = tags$head(includeCSS("www/styles.css"), # CSS styles
                                HTML("<html lang='en'>"),
                                tags$link(rel="shortcut icon", href="favicon.ico"), #Icon for browser tab
                                HTML("<base target='_blank'>"),
                                # cookie_box
                                ),
             ###############################################.
             ## Landing page ----
             ###############################################.
             tabPanel(
               title = "Home", icon = icon("home"),
               mainPanel(width = 12, # style="margin-left:4%; margin-right:4%",
                         
                         fluidRow(column(7,(h3("Signature Search Polestar", style="margin-top:1px;"))),
                                  (column(4,actionButton("btn_landing",
                                                         label="Help: Take tour of the SSP",
                                                         icon=icon('question-circle'),class="down")))),
                         # 第一行
                         fluidRow(

                           column(6, class="landing-page-column",br(), #spacing
                                  lp_main_box(image_name= "landing_button_time_trend",
                                              button_name = 'jump_to_bm', title_box = "Benchmark",
                                              description = 'Evalutaion of Signature Search methods based on annotation')),
                           
                           column(6, class="landing-page-column",br(), #spacing
                                  lp_main_box(image_name= "landing_button_time_trend",
                                              button_name = 'jump_to_rb', title_box = "Robustness",
                                              description = 'Evalutaion of Signature Search methods based on drug self-retrieval')),

                         ),

                         # 第二行
                         fluidRow(
                           
                           #Table box
                           column(6, class="landing-page-column",
                                  br(), #spacing
                                  
                                  lp_main_box(image_name= "landing_button_data_table",
                                              button_name = 'jump_to_sm', title_box = "Application (Query Drugs)",
                                              description = 'Drugs repurposing using Signature Search methods'),
                                  
                           ),
                           
                           #Table box
                           column(6, class="landing-page-column", br(), #spacing
                                  lp_main_box(image_name= "landing_button_other_profile",
                                              button_name = 'jump_to_an', title_box = "Annotation",
                                              description = 'Obtain preliminary annotation of Drugs from GSDC and DRH'),
                                  
                           ),
                         ),

                         # 第三行
                         fluidRow(
                           #Table box
                           column(6, class="landing-page-column", br(), #spacing
                                  lp_main_box(image_name= "landing_button_technical_resources",
                                              button_name = 'jump_to_jc', title_box = "Job Center",
                                              description = 'Retrieve your query results'),
                                  
                           ),
                           # data page
                           column(6, class="landing-page-column",br(), #spacing
                                  lp_main_box(image_name= "landing_button_related_links",
                                              button_name = 'jump_to_ct', title_box = "Converter",
                                              description = 'Easily convert gene and drug identifiers')
                           ),
                           
                         ),
                         
               ) #main Panel bracket
             ),# tab panel bracket
             ###############################################.
             ## Benchmark ----
             ###############################################.
             tabPanel("Benchmark", icon = icon("chart-area"), value = "benchmark",
                      sidebarLayout(  
                        sidebarPanel( width = 4,
                          id= "bm_input",
                          popify(
                            shiny::strong(tagList("Step 1. Select a pharmacotranscriptomic dataset",icon("circle-question"))),
                            title = NULL,
                            content = paste(
                              "SSP contains datasets of nine tumor cell lines at ",
                              as.character(strong("diifferent concentration and treat time.")),
                              "<br>In general, we recommend user to select a dataset with more drugs and highly related to cancer of interest.",
                              "<br> The blank annotation can be obtained by clicking the button provided below. Once filled out, the annotation file could be used in step 4."
                              ),
                            trigger = "click", placement = "right"
                          ),
                          
                          pickerInput("sel_experiment", label = NULL, 
                                      choices=drug_num_list1 , selected = "LINCS_HEPG2_10uM_6h.rdata"
                                      ),
                          downloadButton("dl_drug_ann_bm","Download Blank Annotation", class = "btn-success"),
                          
                          shiny::br(),

                          shiny::br(),
                          popify(
                            shiny::strong(tagList("Step 2. Select Signature Search methods",icon("circle-question"))),
                            title = NULL,
                            content = paste("Please select ",
                                            as.character(strong("at least TWO")),
                                            "methods for benchmark. More methods mean more time.",
                                            as.character(strong("The time for a full-seleted job is 15~30 mins"))
                            ),
                            trigger = "click",
                            placement = "right"
                          ),
                          shiny::p(),
                          shiny::p(),
                          awesomeCheckboxGroup("sel_ss",
                                               label = NULL,
                                               choices=ss_list,
                                               selected = list("SS_Xsum","SS_CMap")
                          ),
                          
                          shiny::br(),
                          popify(
                            shiny::strong(tagList("Step 3. upload oncogenic signature",icon("circle-question"))),
                            title = NULL,
                            content = paste("oncogenic signature is a gene list (gene symbol) with log2FC, derived from gene expression profile from cell lines or patient cohorts. A", 
                                          a(href = "demo/signature.txt", "demo signature file"),
                                          "is provided.<br>If you have other identifier (e.g. EntrezID), please go to",
                                          as.character(strong(" converter page"))," to convert your signature."
                            ),
                            trigger = "click",
                            placement = "right"
                          ),

                          fileInput(
                            inputId = "file_sig",
                            label = NULL,
                            buttonLabel = "Browse...",
                            placeholder = "No file selected",
                            accept = c(".csv",".txt")
                          ),
                          


                          shiny::br(),
                          
                          popify(
                            shiny::strong(tagList("Step 4a: upload drug annotations (for AUC)",icon("circle-question"))),
                            title = NULL,
                            content = paste("At least upload one type annotation in 4a or 4b, also you can upload both of them. For AUC, we recommend upload a list of experimentally evaluated drugs (for example, IC50 < 10μM or IC50 > 10μM). A", 
                                            a(href = "demo/drug_annotation_AUC.txt", "demo drug annotation for AUC"),
                                            "is provided.",
                                            "<br>SSP accept drug name as input, if you have other identifier (e.g. PubchemCID), please go to",
                                            as.character(strong(" converter page"))," to convert your annotation."
                            ),
                            trigger = "click",
                            placement = "right"
                          ),
                          
                          fileInput(
                            inputId = "file_IC50",
                            label = NULL,
                            buttonLabel = "Browse...",
                            placeholder = "No file selected",
                            accept = c(".csv",".txt")
                          ),
                          
                          shiny::br(),
                          
                          
                          popify(
                            shiny::strong(tagList("Step 4b: upload drug annotations (for ES)",icon("circle-question"))),
                            title = NULL,
                            content = paste("At least upload one drug annotation in 4a or 4b, also you can upload both of them. For ES, we recommend upload a list of clinically effective drugs (for example, FDA-approved drugs). A", 
                                            a(href = "demo/drug_annotation_ES.txt", "demo drug annotation for ES"),
                                            "is provided.",
                                            "<br>SSP accept drug name as input, if you have other identifier (e.g. PubchemCID), please go to",
                                            as.character(strong(" converter page"))," to convert your annotation."
                            ),
                            trigger = "click",
                            placement = "right"
                          ),
                          
                          fileInput(
                            inputId = "file_FDA",
                            label = NULL,
                            buttonLabel = "Browse...",
                            placeholder = "No file selected",
                            accept = c(".csv",".txt")
                          ),
                          
                          
                          actionButton("runBM", "Run", class = "btn-success"),
                          actionButton("reset","Reset"),
                          actionButton("runBENdemo", "demo(Benchmark)")

                          
                        ), # end of side pannel
                        
                        mainPanel(id= "bm_out",
                                  uiOutput(outputId = "display_bm") %>% withSpinner(),
                        )
                      ) # slidelayout
             ), #Tab panel bracket
             
             ###############################################.
             ## Robustness ----
             ###############################################.
             tabPanel("Robustness", icon = icon("chart-area"), value = "robustness",
                      sidebarLayout(  
                        sidebarPanel( width = 4,
                                      id= "rb_input",
                                      
                                      popify(
                                        shiny::strong(tagList("Step 1. Select a pharmacotranscriptomic dataset",icon("circle-question"))),
                                        title = NULL,
                                        content = paste(
                                          "SSP contains datasets of nine tumor cell lines at ",
                                          as.character(strong("diifferent concentration and treat time.")),
                                          "<br>In general, we recommend user to select a dataset with more drugs and highly related to cancer of interest"
                                        ),
                                        trigger = "click", placement = "right"
                                      ),
                                      
                                      pickerInput("sel_experiment_rb", label = NULL, 
                                                  choices=drug_num_list1 , selected = "LINCS_A549_1.11uM_6h.rdata"
                                      ),

                                      shiny::br(),
                                      
                                      popify(
                                        shiny::strong(tagList("Step 2. Select Signature Search:",icon("circle-question"))),
                                        title = NULL,
                                        content = paste(
                                          "Robustness pre-computes the performance of signature search methods at different datasets.<br>",
                                          as.character(strong("Just select your interested methods.")),
                                          "<br>The methods over average(red) are reconmmended to use in application module."
                                        ),
                                        trigger = "click", placement = "right"
                                      ),
                                      shiny::p(),
                                      shiny::p(),
                                      awesomeCheckboxGroup("sel_ss_rb",
                                                           NULL,
                                                           choices=ss_list,
                                                           selected = list("SS_Xsum","SS_CMap","SS_GSEA","SS_ZhangScore","SS_XCos")
                                      ),
                                      shiny::br(),
                                      actionButton("runRB", "Run", class = "btn-success"),
                                      actionButton("reset_rb","Reset")
                        ), # end of side pannel
                        mainPanel(id= "rb_out",
                                  uiOutput(outputId = "display_rb") %>% withSpinner()
                        ),
                      ) # slidelayout
             ), #Tab panel bracket
             
             ###############################################.
             ## Application ----
             ###############################################.
             tabPanel("Application (Query Drugs)", icon = icon("list-ul"), value = "singlemethod",
                      sidebarLayout( 
                        sidebarPanel(  width = 4,
                          id= "sm_input",
                          
                          popify(
                            shiny::strong(tagList("Step 1. Select module:",icon("circle-question"))),
                            title = NULL,
                            content = paste(
                              as.character(strong("Single Search")),
                              " is the traditional method to query promising drugs, just like GSEA.<br>",
                              as.character(strong("SS_all")),
                              "query promising drugs integrating the results of all SSMs.<br>",
                              as.character(strong("SS_corss")),
                              " use two oncogenic signatures to query promising drugs with consensus."
                            ),
                            trigger = "click", placement = "right"
                          ),
                          
                          # 设定网页模块
                          pickerInput(inputId = "sel_model_sm", label = NULL, 
                                      choices = list("Single method" = "singlemethod", 
                                                     "SS cross" = "SS_cross", 
                                                     "SS all" = "SS_all"), 
                                      selected = "singlemethod"),
                          shiny::br(),
                          
                          # 设定三个子页面的状态
                          # 单个模块界面，只要确定选择哪个算法就行
                          conditionalPanel(
                            condition = "input.sel_model_sm == 'singlemethod' | input.sel_model_sm == 'SS_cross'" ,
                            
                            popify(
                              shiny::strong(tagList("Step 2. Select Signature Search method:",icon("circle-question"))),
                              title = NULL,
                              content = paste(
                                "Just select one method of your interest."
                              ),
                              trigger = "click", placement = "right"
                            ),
                            shiny::p(),
                            awesomeRadio("sel_ss_sm",
                                         NULL,
                                         choices=ss_list,
                                         selected = list("SS_GSEA")
                            ),
                          ),
                          
                          # 交叉模块，需要确定选择哪个算法
                          # （目前来看和single算法一致，此处预留拓展空间）
                          # conditionalPanel(
                          #   condition = "" ,
                          #   radioButtons("sel_ss_sm",
                          #                "Step 2. Select method",
                          #                choices=ss_list,
                          #                selected = list("SS_Xsum"),
                          #   ),
                          # ),
                          
                          # 全部运算模块
                          # 需要，选择算法，设定汇总排序的区域
                          conditionalPanel(
                            condition = "input.sel_model_sm == 'SS_all'" ,
                            
                            popify(
                              shiny::strong(tagList("Step 2a. Select methods",icon("circle-question"))),
                              title = NULL,
                              content = paste(
                                "Please at least two methods of your interest, More methods mean more time.",
                                as.character(strong("The time for a full-seleted job is 20~40 mins"))
                              ),
                              trigger = "click", placement = "right"
                            ),
                            shiny::p(),
                            
                            awesomeCheckboxGroup("sel_all_sm", 
                                               "",
                                               choices=ss_list,
                                               selected = list("SS_Xsum","SS_CMap"),
                                               
                            ),
                            
                            popify(
                              shiny::strong(tagList("Step 2b: Select direction:",icon("circle-question"))),
                              title = NULL,
                              content = paste(
                                "SS_all only compare the drugs in same direction (scores both > 0 or < 0). Down is default for oncogenic signature. Other type signature is not recommended."
                              ),
                              trigger = "click", placement = "right"
                            ),
                            shiny::p(),
                            
                            awesomeRadio("sel_direct_sm", 
                                         NULL,
                                         choices=sm_direct,inline = T,
                                         selected = list("Down")
                            ),
                          ),
                          
                          # 确定选择哪个算法作为比较基准
                          shiny::br(),
                          popify(
                            shiny::strong(tagList("Step 3. Select a pharmacotranscriptomic dataset",icon("circle-question"))),
                            title = NULL,
                            content = paste(
                              "SSP contains datasets of nine tumor cell lines at ",
                              as.character(strong("diifferent concentration and treat time.")),
                              "<br>In general, we recommend user to select a dataset with more drugs and highly related to cancer of interest"
                            ),
                            trigger = "click", placement = "right"
                          ),
                          pickerInput("sel_experiment_sm", label = NULL, 
                                      choices=drug_num_list1 , selected = "LINCS_MCF7_10uM_6h.rdata"
                                      ),

                          shiny::br(),
                          
                          conditionalPanel(
                            condition = "input.sel_model_sm == 'SS_all' | input.sel_model_sm == 'singlemethod'" ,
                            
                            popify(
                              shiny::strong(tagList("Step 4. upload oncogenic signature",icon("circle-question"))),
                              title = NULL,
                              content = paste("Oncogenic signature is a gene list (gene symbol) with log2FC, derived from gene expression profile from cell lines or patient cohorts. A", 
                                              a(href = "demo/signature.txt", "demo signature file"),
                                              "is provided.<br>If you have other identifier (e.g. EntrezID), please go to",
                                              as.character(strong(" converter page"))," to convert your signature."
                              ),
                              trigger = "click",
                              placement = "right"
                            ),
                            
                            # 上传signature (普通情况)
                            fileInput(
                              inputId = "file_sig_sm",
                              label = NULL,
                              buttonLabel = "Browse...",
                              placeholder = "No file selected",
                              accept = c(".csv",".txt")
                            ),
                          ),
                          
                          conditionalPanel(
                            condition = "input.sel_model_sm == 'SS_cross'" ,
                            
                            # 上传signature (特殊情况)
                            popify(
                              shiny::strong(tagList("Step 4a: upload oncogenic signature 1 and name it",icon("circle-question"))),
                              title = NULL,
                              content = paste("oncogenic signature is a gene list (gene symbol) with log2FC, derived from gene expression profile from cell lines or patient cohorts. A", 
                                              a(href = "demo/signature.txt", "demo signature file"),
                                              "is provided.<br>If you have other identifier (e.g. EntrezID), please go to",
                                              as.character(strong(" converter page"))," to convert your signature."
                              ),
                              trigger = "click",
                              placement = "right"
                            ),
                            
                            textInput("file_name1", label = NULL, value = "Signature1"),
                            fileInput(
                              inputId = "file_sig_sm1",
                              label = NULL,
                              buttonLabel = "Browse...",
                              placeholder = "No file selected",
                              accept = c(".csv",".txt")
                            ),
                            
                            popify(
                              shiny::strong(tagList("Step 4b: upload oncogenic signature 2 and name it",icon("circle-question"))),
                              title = NULL,
                              content = paste("oncogenic signature is a gene list (gene symbol) with log2FC, derived from gene expression profile from cell lines or patient cohorts. A", 
                                              a(href = "demo/signature2.txt", "demo signature file"),
                                              "is provided.<br>If you have other identifier (e.g. EntrezID), please go to",
                                              as.character(strong(" converter page"))," to convert your signature."
                              ),
                              trigger = "click",
                              placement = "right"
                            ),
                            textInput("file_name2",label = NULL , value = "Signature2"),
                            fileInput(
                              inputId = "file_sig_sm2",
                              label = NULL,
                              buttonLabel = "Browse...",
                              placeholder = "No file selected",
                              accept = c(".csv",".txt")
                            ),
                          ),
                          # 设定使用排序多少的内容进行计算？
                          popify(
                            shiny::strong(tagList("Step 5. Set topN",icon("circle-question"))),
                            title = NULL,
                            content = paste("topN is determined by Benchmark or Robustness. <br>",
                                            "If this score is monotonically increasing in Benchmark and Robustness, ",
                                            "we recommend setting topN to length of oncogenic signature."),
                            trigger = "click",
                            placement = "right"
                          ),
                          
                          numericInput("sel_topn_sm", label = NULL, 
                                       value = 150, min = 10, max = 489),
                          
                          shiny::br(),
                          actionButton("runSM", "Run", class = "btn-success"),
                          actionButton("reset_sm","Reset"),
                          shiny::br(),
                          actionButton("runAPPdemo1", "demo(Single method)"),
                          actionButton("runAPPdemo2", "demo(SS_all)"),
                          actionButton("runAPPdemo3", "demo(SS_cross)"),
                          
                        ),
                        mainPanel( id= "sm_out",
                          uiOutput(outputId = "display_sm") %>% withSpinner()
                        ),

                      )
             ), #Tab panel bracket
             
             
             ###############################################.
             ## Job Center ---- 
             ###############################################.
             tabPanel("Job Center", icon = icon("signal"), value = "jobcenter",
                      sidebarLayout( 
                        sidebarPanel(  width = 4,
                          id = "job_page",
                          textInput("jobid_input", label = "Input Jobid", value = "BEN1712624574ZFX"),
                          shiny::br(),
                          actionButton("jobid_get","Retrieve", class = "btn-success"),
                          actionButton("reset_jc","Reset"),
                          shiny::br(),
                          actionButton("runjcBENdemo", "demo(Benchmark)"),
                          shiny::br(),
                          actionButton("runjcAPPdemo1", "demo(Single method)"),
                          actionButton("runjcAPPdemo2", "demo(SS_all)"),
                          actionButton("runjcAPPdemo3", "demo(SS_cross)"),
                          shiny::p(
                            br(),
                            # "Here we provide some jobid for demo result presentation.",
                            strong("Please be aware that the \"Quick Tip\" button may become unresponsive when you're viewing identical result types across two different modules, such as seeing AUC in both the Job Center and Benchmark, or SS_all in both the Job Center and Application."),
                            strong("In such cases, kindly use the \"Reset\" button within the respective module to reactivate the \"Quick Tip\" functionality in the other module.")
                          )

                        ),
                        mainPanel(id= "jc_out",
                                  tableOutput("display_jc_info"),
                                  uiOutput(outputId = "display_jc") %>% withSpinner()
                        ), # main panel bracket
                      ),

             ), #Tab panel bracket
             
             ###############################################.
             ## Annotation ---- 
             ###############################################.
             navbarMenu("Annotation", icon = icon("table"),
             tabPanel("For AUC", value = "an_auc",
                      sidebarLayout(
                        sidebarPanel(width = 4,
                                     shiny::p(
                                       br(),
                                       "Select a cancer and download annotations.",
                                       br(),
                                       "The drug annotation are display on the right table.",
                                       br(),
                                       "Here are two types of annotation files for different methods.",
                                       br(),
                                     ),
                                     selectInput("an_auc_input","Please select cancer",
                                                 choices = disinfo_vector,
                                                 selected = "PRAD"),
                                     # selectInput("an_auc_input_type","Step 2. Select annotation type",
                                     #             choices = c("Area Under Curve(AUC)" = "AUC",
                                     #                         "Enrichment Score(ES)" = "ES"),
                                     #             selected = "AUC"),
                                     shiny::br(),
                                     downloadButton("run_an_auc","Download annotations", class = "btn-success"),
                        ),
                        mainPanel(id= "an_auc_out",
                                  uiOutput(outputId = "display_an_auc") %>% withSpinner(),
                                  dataTableOutput("display_an_auc_tb")

                        ), # main panel bracket
                      ),

             ), #Tab panel bracket
             tabPanel("For ES", value = "an_es",
                      sidebarLayout(
                        sidebarPanel(width = 4,
                                     shiny::p(
                                       br(),
                                       "Select a cancer and download annotations.",
                                       br(),
                                       "The drug annotation are display on the right table.",
                                       br(),
                                       "Here are two types of annotation files for different methods.",
                                       br(),
                                     ),
                                     selectInput("an_es_input","Please select cancer",
                                                 choices = disinfo_vector2,
                                                 selected = "BRCA"),
                                     # selectInput("an_es_input_type","Step 2. Select annotation type",
                                     #             choices = c("Area Under Curve(AUC)" = "AUC",
                                     #                         "Enrichment Score(ES)" = "ES"),
                                     #             selected = "AUC"),
                                     shiny::br(),
                                     downloadButton("run_an_es","Download annotations", class = "btn-success"),
                        ),
                        mainPanel(id= "an_es_out",
                                  uiOutput(outputId = "display_an_es") %>% withSpinner(),
                                  dataTableOutput("display_an_es_tb")

                        ), # main panel bracket
                      ),

             ), #Tab panel bracket
             ),
             
             ###############################################.
             ## Converter ----
             ###############################################.
             navbarMenu("Converter", icon = icon("table"),
                        tabPanel("Gene", value = "ct_gene",
                                 #Sidepanel for filtering data
                                 sidebarLayout(
                                   sidebarPanel(
                                     textAreaInput("text_ctg", "Step 1. Input your signature",height = "200px"),
                                     actionButton("runCTGdemo", "demo"),
                                     shiny::p(),
                                     radioButtons("format_ctg", "Step 2. Select the \"From\" ID", 
                                                  inline = T,
                                                  choices = c("ENTREZID", "ENSEMBL","UNIPROT","GENENAME")),
                                     checkboxInput("header_check_ctg", label = strong("Step 3. Header or non-header?") ,
                                                   value = TRUE),
                                     actionButton("runCTG", "Convert", class = "btn-success")
                                   ),
                                   
                                   mainPanel(id= "ctg_out",
                                             uiOutput(outputId = "display_ctg") %>% withSpinner()
                                   )  # main panel bracket
                                 ),
                                 
                        ), #Tab panel bracket
                        tabPanel("Drug", value = "ct_drug",
                                 #Sidepanel for filtering data
                                 sidebarLayout(
                                   sidebarPanel(
                                     textAreaInput("text_ctd", "Step 1. Input your drug ID",height = "200px"),
                                     actionButton("runCTDdemo1", "demo1"),
                                     actionButton("runCTDdemo2", "demo2"),
                                     actionButton("runCTDdemo3", "demo3"),
                                     shiny::p(),
                                     radioButtons("format_ctd", "Step 2. Select the \"From\" ID", 
                                                  inline = T,
                                                  choices = 
                                                    c("Drug Name" = "net_drug_name",
                                                      "SMILES(Canonical)" = "canonical_smiles",
                                                      "PubChem Cid" = "pubchem_cid",
                                                      "InChIKeys" = "inchi_key",
                                                      "CMAP ID(BRD-)" = "pert_id"
                                                      )
                                                  ),
                                     checkboxInput("header_check_ctd", label = strong("Step 3. Header or non-header?") ,
                                                   value = TRUE),
                                     actionButton("runCTD", "Convert", class = "btn-success")
                                   ),
                                   
                                   mainPanel(id= "ctd_out",
                                             uiOutput(outputId = "display_ctd") %>% withSpinner()
                                   )  # main panel bracket
                                 ),
                                 
                        ), #Tab panel bracket
                        
                        
                        
                        
             ),
             
             ###############################################.             
             ##############NavBar Menu----
             ###############################################.
             #Starting navbarMenu to have tab with dropdown list
             navbarMenu("Info", icon = icon("info-circle"),
                        ###############################################.
                        ## About ----
                        ###############################################.

                        tabPanel("Help", value = "help",
                                 fluidRow(
                                   column(1,
                                          # "sidebar1"
                                   ),
                                   column(10,
                                          navlistPanel(
                                            "Help info",
                                            tabPanel("Q1: Why we built SSP?", 
                                                     includeMarkdown("www/info_Q1.md")
                                                     # uiOutput(outputId = "display_Q1") %>% withSpinner()
                                            ),
                                            tabPanel("Q2: How to use Benchmark and interpret the results?",
                                                     includeMarkdown("www/info_Q2.md")
                                                     # uiOutput(outputId = "display_Q2") %>% withSpinner()
                                            ),
                                            tabPanel("Q3: How to use Robustness and interpret the results?",
                                                     includeMarkdown("www/info_Q3.md")
                                                     # uiOutput(outputId = "display_Q3") %>% withSpinner()
                                            ),

                                            tabPanel("Q4: How to query drug in Application and interpret the results?",
                                                     includeMarkdown("www/info_Q4.md")
                                                     # uiOutput(outputId = "display_Q4") %>% withSpinner()
                                            ),
                                            tabPanel("Q5: How to download data?",
                                                     includeMarkdown("www/info_Q5.md")
                                                     # uiOutput(outputId = "display_Q5") %>% withSpinner()
                                            ),
                                            tabPanel("Q6: How to get job result again?",
                                                     includeMarkdown("www/info_Q6.md")
                                                     # uiOutput(outputId = "display_Q6") %>% withSpinner()
                                            ),
                                            tabPanel("Q7: How to annotate drug?",
                                                     includeMarkdown("www/info_Q7.md")
                                                     # uiOutput(outputId = "display_Q7") %>% withSpinner()
                                            ),
                                            tabPanel("Q8: How to query drugs if I have other type signature?",
                                                     includeMarkdown("www/info_Q8.md")
                                                     # uiOutput(outputId = "display_Q8") %>% withSpinner()
                                            ),
                                            tabPanel("Q9: How to find the optimal topN and method?",
                                                     shiny::h3("How to find the optimal topN and method?"),
                                                     includeMarkdown("www/info_Q9_bm_ES.md"),
                                                     includeMarkdown("www/info_Q9_bm_AUC.md"),
                                                     # uiOutput(outputId = "display_Q9") %>% withSpinner()
                                            ),
                                            tabPanel("Q10: How to deployed SSP in my own computer or server?",
                                                     includeMarkdown("www/info_Q10.md")
                                                     # uiOutput(outputId = "display_Q10") %>% withSpinner()
                                            ),
                                            # tabPanel("Q11: Q&A collection from reviewers.",
                                            #          includeMarkdown("www/info_Q11.md")
                                            #          # uiOutput(outputId = "display_Q11") %>% withSpinner()
                                            # ),
                                            widths = c(4,8)
                                          ),
                                   ),
                                   column(1,
                                          # "sidebar2"
                                   )
                                 ),


                                 ),#Tab panel
                        tabPanel("Data", value = "data",
                                 
                                 fluidRow(
                                   column(3,
                                          # "sidebar1"
                                   ),
                                   column(7,
                                          # shiny::h3("Download manual of SSP"),
                                          # downloadButton("dl_manual_pdf", "Download manual", class = "btn-success"),
                                          shiny::h3("Download demo files to perform job"),
                                          downloadButton("dl_demo","Download Demo", class = "btn-success"),
                                          downloadButton("dl_script","Download Script", class = "btn-success"),
                                          shiny::br(),
                                          shiny::h3("Download curated pharmacotranscriptomic datasets"),
                                          pickerInput("sel_experiment_dl", label = "Select a specific pharmacotranscriptomic dataset", 
                                                      choices=drug_num_list1 , selected = "LINCS_HEPG2_10uM_6h.rdata"
                                          ),
                                          downloadButton("dl_drug_exp","Download pharmacotranscriptomic dataset", class = "btn-success"),
                                          downloadButton("dl_drug_ann","Download Drug and Experiment info", class = "btn-success"),
                                   ),
                                   column(2,
                                          # "sidebar2"
                                   )
                                 ),
                                 
                        ),#Tab panel
                        tabPanel("About", value = "about",

                                 fluidRow(
                                   column(3,
                                          # "sidebar1"
                                   ),
                                   column(6,
                                          uiOutput(outputId = "display_about") %>% withSpinner(),

                                   ),
                                   column(3,
                                          # "sidebar2"
                                   )
                                 ),

                        ),#Tab panel

                        ###############################################.

             ),# NavbarMenu bracket
  ), #Bracket  navbarPage

  div(style = "margin-bottom: 45px;"), # this adds breathing space between content and footer
  
  # CODE FOR STATISTICS
  # div(
  #   tags$script(src="//rf.revolvermaps.com/0/0/7.js?i=5jq3pohyu8j&amp;m=0&amp;c=ff0000&amp;cr1=ffffff&amp;sx=0",
  #               async="async"
  #   ),style = "width:0%;margin:0 auto;"
  # ),
  
  tags$head(
    tags$script(HTML("
      var _hmt = _hmt || [];
      (function() {
        var hm = document.createElement('script');
        hm.src = 'https://hm.baidu.com/hm.js?80bb4451d9bc4cbd2c38405dfa7de680';
        var s = document.getElementsByTagName('script')[0]; 
        s.parentNode.insertBefore(hm, s);
      })();
    "))
  ),
  
  

  # div(
  #   tags$script("
  #   var _hmt = _hmt || [];
  #   (function() {
  #     var hm = document.createElement('script');
  #     hm.src = 'https://hm.baidu.com/hm.js?c80c4665444bb409416f091b83b97f57';
  #     var s = document.getElementsByTagName('script')[0];
  #     s.parentNode.insertBefore(hm, s);
  #   })();
  # "),style = "width:0%;margin:0 auto;"
  # ),
  
  ###############################################.             
  ##############Footer----    
  ###############################################.
  # Copyright warning
  tags$footer(column(6, "This website is free and open to all users and there is no login requirement."),
              column(2, tags$a(href="mailto:jbzhangs@foxmail.com", tags$b("Contact us!"),
                               class="externallink", style = "color: white; text-decoration: none")),
              style = "
   position:fixed;
   text-align:center;
   left: 0;
   bottom:0;
   width:100%;
   z-index:1000;
   height:40px; /* Height of the footer */
   color: white;
   padding: 10px;
   font-weight: bold;
   background-color: #1995dc"
  )
  ################################################.
) #bracket tagList
###END




serverLoaded <- FALSE

###############################################.             
##############Server----    
###############################################.
server <- function(input, output, session) {

  ## 在启动时判断sever是否加载完全（主要是按钮能否有反应）
  if (!serverLoaded) {
    sendSweetAlert(
      session = session,
      title = "Welcome to SSP",
      text = "SSP is initializating. Please wait until the window closed." ,
      type = "info",
      btn_labels = NA,
      closeOnClickOutside = FALSE,
      showCloseButton = FALSE,
    )
  }

  session$onFlushed(once = TRUE, function() {
    closeSweetAlert()
    serverLoaded <<- TRUE
  })
  
  ###############################################.
  ## Sourcing tab code  ----
  ###############################################.
  # Sourcing file with server code
  source(file.path("tab_benchmark.R"),  local = TRUE)$value # benchmark tab
  source(file.path("tab_robustness.R"),  local = TRUE)$value # robustness tab
  source(file.path("tab_application.R"),  local = TRUE)$value # application tab
  source(file.path("tab_jobcenter.R"),  local = TRUE)$value # jobcenter tab
  # source(file.path("data_tab.R"),  local = TRUE)$value # data tab
  source(file.path("tab_info.R"),  local = TRUE)$value # info tab
  source(file.path("tab_converter.R"),  local = TRUE)$value # converter tab
  
  ### 2023年10月1日新增部分 ###
  source(file.path("tab_annotation.R"),  local = TRUE)$value # annotation tab
  ### 2023年10月1日新增部分 ###
  
  ### 2024年1月17日新增部分 ###
  source(file.path("tab_utils.R"),  local = TRUE)$value # annotation tab
  ### 2023年10月1日新增部分 ###
  
  ### 2023年12月19日新增部分 ###
  addResourcePath(prefix = "demo", directoryPath = "demo") # 添加下载路径，用于提供单独的demofile的下载！
  
    ### 2023年12月19日新增部分 ###
  

  observeEvent(input$jump_to_bm, {
    updateTabsetPanel(session, "intabset", selected = "benchmark")
  })
  
  observeEvent(input$jump_to_rb, {
    updateTabsetPanel(session, "intabset", selected = "robustness")
  })
  
  observeEvent(input$jump_to_sm, {
    updateTabsetPanel(session, "intabset", selected = "singlemethod")
  })

  observeEvent(input$jump_to_jc, {
    updateTabsetPanel(session, "intabset", selected = "jobcenter")
  })
  
  ### 2023年10月1日新增部分 ###
  observeEvent(input$jump_to_an, {
    updateTabsetPanel(session, "intabset", selected = "an_es")
  })
  ### 2023年10月1日新增部分end ###
  
  observeEvent(input$jump_to_ct, {
    updateTabsetPanel(session, "intabset", selected = "ct_gene")
  })
  
  # 重置
  observeEvent(input$btn_landing, {
    showModal(modalDialog(
      includeMarkdown("www/info_homepage.md"),
      title = "Guidence for New User",
      size = "l",
      easyClose = T
    ))
  })

  # 保存当前的sessioninfo用于部署包
  # sI <- (.packages())
  # save(sI,file = "sessioninfo.rdata")
  # Run JavaScript code to get the user's IP address

}







###############################################.             
##############Running Code----    
###############################################.
# Run the application 
shinyApp(ui = ui, server = server)
