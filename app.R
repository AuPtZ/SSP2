library(shiny)
library(shinyjs)
library(bslib)
library(bsicons)
library(shinyWidgets)
library(shinycssloaders)
library(htmltools)

# 方案C：重型计算由独立 worker.R 进程处理，Shiny 端不再需要 future/plan(multisession)，
# 因此启动不再花费在预热后台 worker 上。

shinyOptions(cache = cachem::cache_mem(max_size = 1000e6))
options(shiny.sanitize.errors = TRUE)


# --------------------------------------------------------------------------
# UI -----------------------------------------------------------------------
# --------------------------------------------------------------------------
ui <- page_navbar(
  id = "intabset",
  title = bs_icon("stars"),
  window_title = "SSP2",
  lang = "en",
  theme = bs_theme(
    version = 5,
    preset = "journal" ,
    # heading_font = font_google("News Cycle"),
    base_font = font_google("Roboto Condensed")
  ),
  navbar_options = navbar_options(
    collapsible = TRUE # ,
    # class = "bg-primary" # ,
    # bg = "#eb6864",
    # fg = "white",
    # theme = "light"
    
  ),
  header = tagList(
    useShinyjs(),
    useSweetAlert(),
    # introjsUI(),
    tags$head(
      tags$title("Signature Search Polestar 2"),
      tags$link(rel = "shortcut icon", href = "favicon.ico"),
      tags$base(target = "_blank"),
      tags$script(HTML(
        "
        var _hmt = _hmt || [];
        (function() {
          var hm = document.createElement('script');
          hm.src = 'https://hm.baidu.com/hm.js?80bb4451d9bc4cbd2c38405dfa7de680';
          var s = document.getElementsByTagName('script')[0];
          s.parentNode.insertBefore(hm, s);
        })();
      "
      ))
    )
  ),
  ###############################################.
  ## Landing page ----
  ###############################################.
  nav_panel(
    title = "Home",
    icon = bs_icon("house"),
    value = "home",
    page_fillable(
      div(
        class = "px-3 py-4",
        # Hero / intro section
        card(
          class = "border-0",
          card_body(
            class = "mt-0 mb-0",
            h1("Signature Search Polestar 2 (SSP2)", class = "fw-bold"),
            h5(
              # class = "lead",
              "A free, open-access web platform for ",
              strong("pharmacotranscriptomic signature search"),
              " — benchmark drug-repositioning methods, query promising drugs, and explore LINCS2020 perturbation data across cancer cell lines."
            ),
            h5(
              "SSP2 integrates",
              strong(" 9 tumor cell lines"),
              ", multiple perturbation concentrations and treatment times, and",
              strong(" 12,328 genes"),
              " from the LINCS2020 beta dataset. It offers rigorously benchmarked Signature Search Methods (SSMs)",
              " and reproducible drug-repurposing workflows for cancer researchers."
            ),
            # div(
            #   class = "d-flex flex-wrap gap-2 mt-2",
            #   span(class = "badge bg-primary", "LINCS2020"),
            #   span(class = "badge bg-secondary", "12,328 genes"),
            #   span(class = "badge bg-info text-dark", "9 cell lines"),
            #   span(class = "badge bg-success", "Real-time p-values"),
            #   span(class = "badge bg-warning text-dark", "topN / |log2FC|")
            # )
            # Module cards
            h3("Get started", class = "mt-0 mb-0"),
            layout_column_wrap(
              width = 1 / 3,
              fill = FALSE,
              card(
                card_header(bs_icon("graph-up"), " Benchmark"),
                card_body(
                  p(
                    "Evaluation of Signature Search methods based on annotation"
                  ),
                  actionButton(
                    "jump_to_bm",
                    "Open",
                    class = "btn-primary w-100"
                  )
                )
              ),
              card(
                card_header(bs_icon("capsule"), " Application (Query Drugs)"),
                card_body(
                  p("Drugs repurposing using Signature Search methods"),
                  actionButton(
                    "jump_to_sm",
                    "Open",
                    class = "btn-primary w-100"
                  )
                )
              ),
              card(
                card_header(bs_icon("tags"), " Annotation"),
                card_body(
                  p("Obtain preliminary annotation of Drugs from GSDC and DRH"),
                  actionButton(
                    "jump_to_an",
                    "Open",
                    class = "btn-primary w-100"
                  )
                )
              ),
              card(
                card_header(bs_icon("inbox"), " Job Center"),
                card_body(
                  p("Retrieve your query results"),
                  actionButton(
                    "jump_to_jc",
                    "Open",
                    class = "btn-primary w-100"
                  )
                )
              ),
              card(
                card_header(bs_icon("arrow-left-right"), " Converter"),
                card_body(
                  p("Easily convert gene and drug identifiers"),
                  actionButton(
                    "jump_to_ct",
                    "Open",
                    class = "btn-primary w-100"
                  )
                )
              )
            ),
            # How it works
            h3("How it works", class = "mt-0 mb-0"),
            layout_column_wrap(
              width = 1 / 4,
              fill = FALSE,
              card(
                card_header(bs_icon("upload"), "1. Provide a signature"),
                card_body(p(
                  "Upload an oncogenic gene signature (gene symbol + log2FC) from cell lines or patient cohorts."
                ))
              ),
              card(
                card_header(bs_icon("search"), "2. Choose a method"),
                card_body(p(
                  "Select one or more Signature Search Methods, or integrate them via SS_all / SS_cross."
                ))
              ),
              card(
                card_header(bs_icon("capsule"), "3. Query drugs"),
                card_body(p(
                  "Rank candidate drugs by enrichment, with real-time null distributions for p-values."
                ))
              ),
              card(
                card_header(bs_icon("bar-chart"), "4. Evaluate"),
                card_body(p(
                  "Benchmark module helps you pick the best method for your context."
                ))
              )
            )
          )
        ),

        # Footer info (moved from global footer)
        hr(class = "mt-0"),
        div(
          class = "d-flex justify-content-between align-items-center flex-wrap gap-2 text-muted",
          span(
            "This website is free and open to all users and there is no login requirement."
          ),
          tags$a(
            href = "mailto:jbzhangs@foxmail.com",
            tags$b("Contact us!"),
            class = "link-secondary"
          )
        )
      )
    )
  ),

  ###############################################.
  ## Benchmark ----
  ###############################################.
  nav_panel(
    title = "Benchmark",
    icon = bs_icon("graph-up"),
    value = "benchmark",
    layout_sidebar(
      sidebar = sidebar(
        id = "bm_input",
        width = 380,
        title = NULL,
        tagList(
          div(
            class = "mb-0",
            div(
              class = "fw-bold mb-0",
              step_pop(
                " Step 1. Select a pharmacotranscriptomic dataset",
                paste(
                  "SSP contains datasets of nine tumor cell lines at ",
                  as.character(strong(
                    "different concentration and treat time."
                  )),
                  "<br>In general, we recommend user to select a dataset with more drugs and highly related to cancer of interest.",
                  "<br> The blank annotation can be obtained by clicking the button provided below. Once filled out, the annotation file could be used in step 4."
                )
              )
            ),
            pickerInput(
              "sel_experiment",
              label = NULL,
              choices = drug_num_list1,
              selected = "LINCS_U2OS_10uM_6h.rdata"
            ),
            downloadButton(
              "dl_drug_ann_bm",
              "Download Blank Annotation",
              class = "btn-success"
            )
          ),
          div(
            class = "mb-0",
            div(
              class = "fw-bold mb-0",
              step_pop(
                " Step 2. Select Signature Search methods",
                paste(
                  "Please select ",
                  as.character(strong("at least TWO")),
                  "methods for benchmark. More methods mean more time.",
                  as.character(strong(
                    "The time for a full-seleted job is 15~30 mins"
                  ))
                )
              )
            ),
            awesomeCheckboxGroup(
              "sel_ss",
              label = NULL,
              choices = ss_list,
              selected = list("SS_Xsum", "SS_CMap")
            )
          ),
          div(
            class = "mb-0",
            div(
              class = "fw-bold mb-0",
              step_pop(
                " Step 3. Upload oncogenic signature",
                paste(
                  "oncogenic signature is a gene list (gene symbol) with log2FC, derived from gene expression profile from cell lines or patient cohorts. A",
                  a(href = "demo/signature.txt", "demo signature file"),
                  "is provided.<br>If you have other identifier (e.g. EntrezID), please go to",
                  as.character(strong(" converter page")),
                  " to convert your signature."
                )
              )
            ),
            fileInput(
              inputId = "file_sig",
              label = NULL,
              buttonLabel = "Browse...",
              placeholder = "No file selected",
              accept = c(".csv", ".txt")
            )
          ),
          div(
            class = "mb-0",
            div(
              class = "fw-bold mb-0",
              step_pop(
                " Step 4a. Upload drug annotations (for AUC)",
                paste(
                  "At least upload one type annotation in 4a or 4b, also you can upload both of them. For AUC, we recommend upload a list of experimentally evaluated drugs (for example, IC50 < 10uM or IC50 > 10uM). A",
                  a(
                    href = "demo/drug_annotation_AUC.txt",
                    "demo drug annotation for AUC"
                  ),
                  "is provided.",
                  "<br>SSP accept drug name as input, if you have other identifier (e.g. PubchemCID), please go to",
                  as.character(strong(" converter page")),
                  " to convert your annotation."
                )
              )
            ),
            fileInput(
              inputId = "file_IC50",
              label = NULL,
              buttonLabel = "Browse...",
              placeholder = "No file selected",
              accept = c(".csv", ".txt")
            )
          ),
          div(
            class = "mb-0",
            div(
              class = "fw-bold mb-0",
              step_pop(
                " Step 4b. Upload drug annotations (for ES)",
                paste(
                  "At least upload one drug annotation in 4a or 4b, also you can upload both of them. For ES, we recommend upload a list of clinically effective drugs (for example, FDA-approved drugs). A",
                  a(
                    href = "demo/drug_annotation_ES.txt",
                    "demo drug annotation for ES"
                  ),
                  "is provided.",
                  "<br>SSP accept drug name as input, if you have other identifier (e.g. PubchemCID), please go to",
                  as.character(strong(" converter page")),
                  " to convert your annotation."
                )
              )
            ),
            fileInput(
              inputId = "file_FDA",
              label = NULL,
              buttonLabel = "Browse...",
              placeholder = "No file selected",
              accept = c(".csv", ".txt")
            )
          ),
          div(
            class = "mb-0",
            div(class = "fw-bold mb-0", " Step 5. Select gene filter mode"),
            radioButtons(
              "filter_mode_bm",
              label = NULL,
              choices = c("topN" = "topN", "|log2FC| threshold" = "logFC"),
              selected = "topN",
              inline = TRUE
            )
          )
        ),
        div(
          class = "d-grid gap-2 mt-0",
          actionButton("runBM", "Run", class = "btn-success"),
          actionButton("reset", "Reset", class = "btn-outline-secondary"),
          actionButton(
            "runBENdemo",
            "demo(Benchmark)",
            class = "btn-outline-primary"
          )
        )
      ),
      card(
        full_screen = TRUE,
        # card_header("Benchmark results"),
        uiOutput(outputId = "display_bm") %>% withSpinner()
      )
    )
  ),

  ## Application ----
  ###############################################.
  nav_panel(
    title = "Application (Query Drugs)",
    icon = bs_icon("capsule"),
    value = "singlemethod",
    layout_sidebar(
      sidebar = sidebar(
        id = "sm_input",
        width = 380,
        title = NULL,
        tagList(
          div(
            class = "mb-0",
            div(
              class = "fw-bold mb-0",
              step_pop(
                " Step 1. Select module",
                paste(
                  as.character(strong("Single Search")),
                  " is the traditional method to query promising drugs, just like GSEA.<br>",
                  as.character(strong("SS_all")),
                  "query promising drugs integrating the results of all SSMs.<br>",
                  as.character(strong("SS_corss")),
                  " use two oncogenic signatures to query promising drugs with consensus."
                )
              )
            ),
            pickerInput(
              inputId = "sel_model_sm",
              label = NULL,
              choices = list(
                "Single method" = "singlemethod",
                "SS cross" = "SS_cross",
                "SS all" = "SS_all"
              ),
              selected = "singlemethod"
            )
          ),
          div(
            class = "mb-0",
              div(
                class = "fw-bold mb-0",
                step_pop(
                  " Step 2. Select Signature Search method(s)",
                  paste(
                    "<strong>singlemethod / SS_cross:</strong> Just select one method of your interest.<br>",
                    "<strong>SS_all:</strong> Please select at least two methods of your interest. More methods mean more time. ",
                    as.character(strong("The time for a full-selected job is 20~40 mins.")), "<br>",
                    "<strong>Direction (SS_all):</strong> SS_all only compares drugs in the same direction (scores both > 0 or < 0). Down is default for oncogenic signature; other signature types are not recommended."
                  )
                )
              ),
              conditionalPanel(
                condition = "input.sel_model_sm == 'singlemethod' | input.sel_model_sm == 'SS_cross'",
                awesomeRadio(
                  "sel_ss_sm",
                  label = NULL,
                  choices = ss_list,
                  selected = list("SS_GSEA")
                )
              ),
              conditionalPanel(
                condition = "input.sel_model_sm == 'SS_all'",
                awesomeCheckboxGroup(
                  "sel_all_sm",
                  label = NULL,
                  choices = ss_list,
                  selected = list("SS_Xsum", "SS_CMap")
                ),
                awesomeRadio(
                  "sel_direct_sm",
                  label = NULL,
                  choices = sm_direct,
                  inline = TRUE,
                  selected = list("Down")
                )
              )
            ),
          div(
            class = "mb-0",
            div(
              class = "fw-bold mb-0",
              step_pop(
                " Step 3. Select a pharmacotranscriptomic dataset",
                paste(
                  "SSP contains datasets of nine tumor cell lines at ",
                  as.character(strong(
                    "different concentration and treat time."
                  )),
                  "<br>In general, we recommend user to select a dataset with more drugs and highly related to cancer of interest"
                )
              )
            ),
            pickerInput(
              "sel_experiment_sm",
              label = NULL,
              choices = drug_num_list1,
              selected = "LINCS_MCF7_10uM_6h.rdata"
            )
          ),
          div(
            class = "mb-0",
            div(
              class = "fw-bold mb-0",
              step_pop(
                " Step 4. Upload oncogenic signature(s)",
                HTML(paste(
                  "Oncogenic signature is a gene list (gene symbol) with log2FC, derived from gene expression profile from cell lines or patient cohorts.",
                  "For single method / SS_all, upload one signature (a",
                  a(href = "demo/signature.txt", "demo signature file"),
                  "is provided). For SS_cross, upload two signatures (signature 2",
                  a(href = "demo/signature2.txt", "demo signature file 2"),
                  "is provided).",
                  "<br>If you have other identifier (e.g. EntrezID), please go to",
                  as.character(strong(" converter page")),
                  " to convert your signature."
                ))
              )
            ),
            conditionalPanel(
              condition = "input.sel_model_sm == 'SS_all' | input.sel_model_sm == 'singlemethod'",
              fileInput(
                inputId = "file_sig_sm",
                label = NULL,
                buttonLabel = "Browse...",
                placeholder = "No file selected",
                accept = c(".csv", ".txt")
              )
            ),
            conditionalPanel(
              condition = "input.sel_model_sm == 'SS_cross'",
              textInput("file_name1", label = NULL, value = "Signature1"),
              fileInput(
                inputId = "file_sig_sm1",
                label = NULL,
                buttonLabel = "Browse...",
                placeholder = "No file selected",
                accept = c(".csv", ".txt")
              ),
              textInput("file_name2", label = NULL, value = "Signature2"),
              fileInput(
                inputId = "file_sig_sm2",
                label = NULL,
                buttonLabel = "Browse...",
                placeholder = "No file selected",
                accept = c(".csv", ".txt")
              )
            )
          ),
          div(
            class = "mb-0",
            div(class = "fw-bold mb-0", " Step 5. Set gene filter"),
            radioButtons(
              "filter_mode_sm",
              label = NULL,
              choices = c("topN" = "topN", "|log2FC| threshold" = "logFC"),
              selected = "topN",
              inline = TRUE
            ),
            conditionalPanel(
              condition = "input.filter_mode_sm == 'topN'",
              numericInput(
                "sel_topn_sm",
                label = NULL,
                value = 150,
                min = 10,
                max = 1000
              )
            ),
            conditionalPanel(
              condition = "input.filter_mode_sm == 'logFC'",
              numericInput(
                "sel_fc_sm",
                label = NULL,
                value = 0.5,
                min = 0.05,
                max = 5,
                step = 0.05
              )
            )
          )
        ),
        div(
          class = "d-grid gap-2 mt-0",
          actionButton("runSM", "Run", class = "btn-success"),
          actionButton("reset_sm", "Reset", class = "btn-outline-secondary"),
          actionButton(
            "runAPPdemo1",
            "demo(Single method)",
            class = "btn-outline-primary"
          ),
          actionButton(
            "runAPPdemo2",
            "demo(SS_all)",
            class = "btn-outline-primary"
          ),
          actionButton(
            "runAPPdemo3",
            "demo(SS_cross)",
            class = "btn-outline-primary"
          )
        )
      ),
      card(
        full_screen = TRUE,
        # card_header("Application results"),
        uiOutput(outputId = "display_sm") %>% withSpinner()
      )
    )
  ),

  ###############################################.
  ## Job Center ----
  ###############################################.
  nav_panel(
    title = "Job Center",
    icon = bs_icon("inbox"),
    value = "jobcenter",
    layout_sidebar(
      sidebar = sidebar(
        id = "job_page",
        width = 380,
        title = NULL,
        textInput(
          "jobid_input",
          label = "Input Jobid",
          value = "BEN1783750343BUH"
        ),
        div(
          class = "d-grid gap-2 mt-0",
          actionButton("jobid_get", "Retrieve", class = "btn-success"),
          actionButton("reset_jc", "Reset", class = "btn-outline-secondary"),
          actionButton(
            "runjcBENdemo",
            "demo(Benchmark)",
            class = "btn-outline-primary"
          ),
          actionButton(
            "runjcAPPdemo1",
            "demo(Single method)",
            class = "btn-outline-primary"
          ),
          actionButton(
            "runjcAPPdemo2",
            "demo(SS_all)",
            class = "btn-outline-primary"
          ),
          actionButton(
            "runjcAPPdemo3",
            "demo(SS_cross)",
            class = "btn-outline-primary"
          )
        ),
        shiny::p(
          br(),
          strong(
            "Please be aware that the \"Quick Tip\" button may become unresponsive when you're viewing identical result types across two different modules, such as seeing AUC in both the Job Center and Benchmark, or SS_all in both the Job Center and Application."
          ),
          strong(
            "In such cases, kindly use the \"Reset\" button within the respective module to reactivate the \"Quick Tip\" functionality in the other module."
          )
        )
      ),
      card(
        full_screen = TRUE,
        # card_header("Job results"),
        tableOutput("display_jc_info"),
        uiOutput(outputId = "display_jc") %>% withSpinner()
      )
    )
  ),

  ###############################################.
  ## Annotation ----
  ###############################################.
  nav_menu(
    title = "Annotation",
    icon = bs_icon("tags"),
    value = "annotation",
    nav_panel(
      title = "For AUC",
      value = "an_auc",
      layout_sidebar(
        sidebar = sidebar(
          width = 350,
          title = NULL,
          shiny::p(
            br(),
            "Select a cancer and download annotations.",
            br(),
            "The drug annotation are display on the right table.",
            br(),
            "Here are two types of annotation files for different methods.",
            br()
          ),
          pickerInput(
            "an_auc_input",
            "Please select cancer",
            choices = disinfo_vector,
            selected = "PRAD"
          ),
          shiny::br(),
          downloadButton(
            "run_an_auc",
            "Download annotations",
            class = "btn-success"
          )
        ),
        card(
          full_screen = TRUE,
          # card_header("AUC annotations"),
          uiOutput(outputId = "display_an_auc") %>% withSpinner(),
          dataTableOutput("display_an_auc_tb")
        )
      )
    ),
    nav_panel(
      title = "For ES",
      value = "an_es",
      layout_sidebar(
        sidebar = sidebar(
          width = 350,
          title = NULL,
          shiny::p(
            br(),
            "Select a cancer and download annotations.",
            br(),
            "The drug annotation are display on the right table.",
            br(),
            "Here are two types of annotation files for different methods.",
            br()
          ),
          pickerInput(
            "an_es_input",
            "Please select cancer",
            choices = disinfo_vector2,
            selected = "BRCA"
          ),
          shiny::br(),
          downloadButton(
            "run_an_es",
            "Download annotations",
            class = "btn-success"
          )
        ),
        card(
          full_screen = TRUE,
          # card_header("ES annotations"),
          uiOutput(outputId = "display_an_es") %>% withSpinner(),
          dataTableOutput("display_an_es_tb")
        )
      )
    )
  ),

  ###############################################.
  ## Converter ----
  ###############################################.
  nav_menu(
    title = "Converter",
    icon = bs_icon("arrow-left-right"),
    value = "converter",
    nav_panel(
      title = "Gene",
      value = "ct_gene",
      layout_sidebar(
        sidebar = sidebar(
          width = 350,
          title = NULL,
          textAreaInput(
            "text_ctg",
            "Step 1. Input your signature",
            height = "200px"
          ),
          actionButton("runCTGdemo", "demo", class = "btn-outline-primary"),
          shiny::p(),
          radioButtons(
            "format_ctg",
            "Step 2. Select the \"From\" ID",
            inline = TRUE,
            choices = c("ENTREZID", "ENSEMBL", "UNIPROT", "GENENAME")
          ),
          checkboxInput(
            "header_check_ctg",
            label = strong("Step 3. Header or non-header?"),
            value = TRUE
          ),
          actionButton("runCTG", "Convert", class = "btn-success")
        ),
        card(
          full_screen = TRUE,
          # card_header("Gene conversion results"),
          uiOutput(outputId = "display_ctg") %>% withSpinner()
        )
      )
    ),
    nav_panel(
      title = "Drug",
      value = "ct_drug",
      layout_sidebar(
        sidebar = sidebar(
          width = 350,
          title = NULL,
          textAreaInput(
            "text_ctd",
            "Step 1. Input your drug ID",
            height = "200px"
          ),
          actionButton("runCTDdemo1", "demo1", class = "btn-outline-primary"),
          actionButton("runCTDdemo2", "demo2", class = "btn-outline-primary"),
          actionButton("runCTDdemo3", "demo3", class = "btn-outline-primary"),
          shiny::p(),
          radioButtons(
            "format_ctd",
            "Step 2. Select the \"From\" ID",
            inline = TRUE,
            choices = c(
              "Drug Name" = "net_drug_name",
              "SMILES(Canonical)" = "canonical_smiles",
              "PubChem Cid" = "pubchem_cid",
              "InChIKeys" = "inchi_key",
              "CMAP ID(BRD-)" = "pert_id"
            )
          ),
          checkboxInput(
            "header_check_ctd",
            label = strong("Step 3. Header or non-header?"),
            value = TRUE
          ),
          actionButton("runCTD", "Convert", class = "btn-success")
        ),
        card(
          full_screen = TRUE,
          # card_header("Drug conversion results"),
          uiOutput(outputId = "display_ctd") %>% withSpinner()
        )
      )
    )
  ),

  ###############################################.
  ## Info ----
  ###############################################.
  nav_menu(
    title = "Info",
    icon = bs_icon("info-circle"),
    value = "info",
    nav_panel(
      title = "Help",
      value = "help",
    navset_pill_list(
      widths = c(3, 9),
      well = FALSE,
      # 左侧竖排导航切换帮助主题（替代 radio 按钮）
      nav_panel(
        "Q1: Why we built SSP?", value = "q1",
        card(title = NULL, full_screen = TRUE, includeMarkdown("www/info_Q1.md"))
      ),
      nav_panel(
        "Q2: Benchmark", value = "q2",
        card(title = NULL, full_screen = TRUE, includeMarkdown("www/info_Q2.md"))
      ),
      nav_panel(
        "Q4: Application", value = "q4",
        card(title = NULL, full_screen = TRUE, includeMarkdown("www/info_Q4.md"))
      ),
      nav_panel(
        "Q5: Download data", value = "q5",
        card(title = NULL, full_screen = TRUE, includeMarkdown("www/info_Q5.md"))
      ),
      nav_panel(
        "Q6: Retrieve job", value = "q6",
        card(title = NULL, full_screen = TRUE, includeMarkdown("www/info_Q6.md"))
      ),
      nav_panel(
        "Q7: Annotate drug", value = "q7",
        card(title = NULL, full_screen = TRUE, includeMarkdown("www/info_Q7.md"))
      ),
      nav_panel(
        "Q8: Other signature types", value = "q8",
        card(title = NULL, full_screen = TRUE, includeMarkdown("www/info_Q8.md"))
      ),
      nav_panel(
        "Q9: Optimal topN/method", value = "q9",
        card(
          title = NULL, full_screen = TRUE,
          tagList(
            shiny::h3("How to find the optimal topN and method?"),
            includeMarkdown("www/info_Q9_bm_ES.md"),
            includeMarkdown("www/info_Q9_bm_AUC.md")
          )
        )
      ),
      nav_panel(
        "Q10: Deploy SSP", value = "q10",
        card(title = NULL, full_screen = TRUE, includeMarkdown("www/info_Q10.md"))
      )
    )
    ),
    nav_panel(
      title = "Data",
      value = "data",
      page_fluid(
        div(
          style = "max-width: 900px; margin: 0 auto;",
          h3("Download demo files to perform job"),
          downloadButton("dl_demo", "Download Demo", class = "btn-success"),
          downloadButton("dl_script", "Download Script", class = "btn-success"),
          br(),
          br(),
          h3("Download curated pharmacotranscriptomic datasets"),
          pickerInput(
            "sel_tissue_dl",
            label = "Select tissue",
            choices = names(drug_num_list_by_tissue),
            selected = names(drug_num_list_by_tissue)[1]
          ),
          pickerInput(
            "sel_experiment_dl",
            label = "Select a specific dataset",
            choices = drug_num_list_by_tissue[[names(drug_num_list_by_tissue)[1]]],
            selected = unname(drug_num_list_by_tissue[[names(drug_num_list_by_tissue)[1]]][1])
          ),
          downloadButton(
            "dl_drug_exp",
            "Download pharmacotranscriptomic dataset",
            class = "btn-success"
          ),
          downloadButton(
            "dl_drug_ann",
            "Download Drug and Experiment info",
            class = "btn-success"
          )
        )
      )
    ),
    nav_panel(
      title = "About",
      value = "about",
      page_fluid(
        div(
          style = "max-width: 900px; margin: 0 auto;",
          uiOutput(outputId = "display_about") %>% withSpinner()
        )
      )
    )
  ),
  nav_item(input_dark_mode(), class = "ms-auto")
)
# --------------------------------------------------------------------------
# Server --------------------------------------------------------------------
# --------------------------------------------------------------------------
serverLoaded <- FALSE

server <- function(input, output, session) {

  ## 在启动时判断sever是否加载完全（主要是按钮能否有反应）
  if (!serverLoaded) {
    sendSweetAlert(
      session = session,
      title = "Welcome to SSP",
      text = "SSP is initializating. Please wait until the window closed.",
      type = "info",
      btn_labels = NA,
      closeOnClickOutside = FALSE,
      showCloseButton = FALSE
    )
  }

  session$onFlushed(once = TRUE, function() {
    closeSweetAlert()
    serverLoaded <<- TRUE
  })

  # 下载页两级联动：切换 tissue 时，更新 dataset 下拉的可选项与默认值
  observeEvent(input$sel_tissue_dl, {
    new_choices <- drug_num_list_by_tissue[[input$sel_tissue_dl]]
    updatePickerInput(
      session,
      "sel_experiment_dl",
      choices = new_choices,
      selected = unname(new_choices[1])
    )
  })

  ###############################################.
  ## Sourcing tab code  ----
  ###############################################.
  source(file.path("tab_benchmark.R"),  local = TRUE)$value
  # Robustness module removed - data generation failed
  source(file.path("tab_application.R"),  local = TRUE)$value
  source(file.path("tab_jobcenter.R"),  local = TRUE)$value
  # source(file.path("data_tab.R"),  local = TRUE)$value
  source(file.path("tab_info.R"),  local = TRUE)$value
  source(file.path("tab_converter.R"),  local = TRUE)$value
  source(file.path("tab_annotation.R"),  local = TRUE)$value
  source(file.path("tab_utils.R"),  local = TRUE)$value

  addResourcePath(prefix = "demo", directoryPath = "demo")

  observeEvent(input$jump_to_bm, {
    nav_select(id = "intabset", selected = "benchmark", session = session)
  })

  observeEvent(input$jump_to_rb, {
  })

  observeEvent(input$jump_to_sm, {
    nav_select(id = "intabset", selected = "singlemethod", session = session)
  })

  observeEvent(input$jump_to_jc, {
    nav_select(id = "intabset", selected = "jobcenter", session = session)
  })

  observeEvent(input$jump_to_an, {
    nav_select(id = "intabset", selected = "an_es", session = session)
  })

  observeEvent(input$jump_to_ct, {
    nav_select(id = "intabset", selected = "ct_gene", session = session)
  })

  # 重置
  observeEvent(input$btn_landing, {
    showModal(modalDialog(
      includeMarkdown("www/info_homepage.md"),
      title = "Guidence for New User",
      size = "l",
      easyClose = TRUE
    ))
  })

  # 保存当前的sessioninfo用于部署包
  # sI <- (.packages())
  # save(sI, file = "sessioninfo.rdata")
  # Run JavaScript code to get the user's IP address

}

# Run the application
shinyApp(ui = ui, server = server)
