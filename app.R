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
  title = tagList(bs_icon("stars"), "SSP2"),
  window_title = "SSP2: Signature Search Polestar 2",
  lang = "en",
  theme = bs_theme(
    version = 5,
    preset = "flatly" ,
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
      tags$meta(name = "description",
                content = "Signature Search Polestar 2 (SSP2) - a webserver for signature-based drug and perturbation search: evaluate signature search methods, query promising compounds, and rank CRISPR knockout target genes for a customized query signature."),
      tags$meta(property = "og:title", content = "SSP2: Signature Search Polestar 2"),
      tags$meta(property = "og:description",
                content = "A webserver for signature-based drug and perturbation search and signature search method evaluation."),
      tags$meta(property = "og:type", content = "website"),
      tags$link(rel = "shortcut icon", href = "favicon.ico"),
      tags$base(target = "_blank"),
      tags$style(HTML("
        /* bootstrap-select 搜索框在 Bootstrap 5 下的可见性修复 */
        .bootstrap-select .bs-searchbox { padding: 4px 8px; }
        .bootstrap-select .bs-searchbox input.form-control {
          width: 100%;
          box-sizing: border-box;
        }
      "))
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
              " — benchmark signature-search methods, query promising compounds, and now also rank ",
              strong("CRISPR knockout target genes"), " with the same query signature."
            ),
            h5(
              "SSP2 integrates",
              strong(" 155 tumor cell lines"),
              ", multiple compound concentrations and treatment times, and",
              strong(" 12,328 genes"),
              " from the LINCS2020 beta dataset alone (scope: LINCS only; the Tahoe-100M datasets are additional). ",
              "It offers rigorously benchmarked Signature Search Methods (SSMs),",
              " an additional ",
              strong("LINCS-CRISPR"),
              " data source (19 cell lines, 96 h, ~5,000 target genes each), and reproducible ",
              "drug-/perturbation-search workflows for cancer researchers."
            ),
            # div(
            #   class = "d-flex flex-wrap gap-2 mt-2",
            #   span(class = "badge bg-primary", "LINCS2020"),
            #   span(class = "badge bg-secondary", "12,328 genes"),
            #   span(class = "badge bg-info text-dark", "155 cell lines"),
            #   span(class = "badge bg-success", "Real-time p-values"),
            #   span(class = "badge bg-warning text-dark", "topN / |log2FC|")
            # )
            # 数据库规模统计卡片（置于 Get started 上方）
            layout_column_wrap(
              width = 1 / 4,
              fill = FALSE,
              value_box(
                title = "Tissues (all sources)",
                value = n_tissue # ,
                # showcase = bs_icon("heart-pulse"),
                # theme = "info"
              ),
              value_box(
                title = "Cell lines (all sources)",
                value = n_cellline # ,
                # showcase = bs_icon("bug"),
                # theme = "secondary"
              ),
              value_box(
                title = "Signature Search Methods",
                value = n_method # ,
                # showcase = bs_icon("search"),
                # theme = "primary"
              ),
              value_box(
                title = "Genes (largest dataset)",
                value = format(n_gene, big.mark = ",") # ,
                # showcase = bs_icon("virus"),
                # theme = "primary"
              )
            ),
            p(class = "text-muted small mt-1 mb-0",
              "Statistics above cover all data sources: 155 LINCS tumor cell lines and ",
              "48 Tahoe-100M entries (47 cell lines plus one pan-cell-line aggregate); ",
              "A549 appears in both sources, giving 202 unique cell lines in total. ",
              "The largest single dataset has 62,710 genes (Tahoe-100M) versus 12,328 ",
              "landmark genes in LINCS2020 beta. The numbers in the introduction above ",
              "refer to LINCS2020 beta only."),
            # Module cards
            h3("Get started", class = "mt-0 mb-0"),
            layout_column_wrap(
              width = 1 / 4,
              fill = FALSE,
              card(
                card_header(bs_icon("graph-up"), " Benchmark"),
                card_body(
                  p("Evaluation of Signature Search methods based on annotation (compound datasets)"),
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
                  p("Compound and CRISPR KO perturbation queries using signature search methods"),
                  actionButton(
                    "jump_to_sm",
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
          )
        ),

        # Footer info (moved from global footer)
        hr(class = "mt-0"),
        div(
          class = "d-flex justify-content-between align-items-center flex-wrap gap-2 text-muted",
          span(
            "This website is free and open to all users and there is no login requirement. ",
            tags$a("License: Mulan Permissive Software License v2 (MulanPSL-2.0)",
                   href = "https://license.coscl.org.cn/MulanPSL2",
                   class = "link-secondary"),
            "."
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
        open = "always",
        card(
          card_header(class = "bg-transparent pb-0", div(class = "fw-bold",
            step_pop(
              " \u2460 Select a dataset",
              paste(
                "SSP2 contains datasets of 155 tumor cell lines at ",
                as.character(strong("different concentration and treat time.")),
                "<br>In general, we recommend user to select a dataset with more drugs and highly related to cancer of interest.",
                "<br> The blank annotation can be obtained by clicking the button provided below. Once filled out, the annotation file could be used in step 3."
              )
            )
          )),
          card_body(
            pickerInput(
              "sel_source",
              label = "Select data source",
              choices = names(drug_num_list_by_source_tissue),
              selected = DEFAULT_SOURCE,
              options = list()
            ),
            pickerInput(
              "sel_tissue",
              label = "Select tissue",
              choices = names(drug_num_list_by_tissue),
              selected = DEFAULT_TISSUE_BM,
              options = list()
            ),
            pickerInput(
              "sel_experiment",
              label = "Select a specific dataset",
              choices = drug_num_list_by_tissue[[DEFAULT_TISSUE_BM]],
              selected = DEFAULT_DS_BM,
              options = list()
            ),
            downloadButton(
              "dl_drug_ann_bm",
              "Download Blank Annotation",
              class = "btn-success w-100"
            )
          )
        ),
        card(
          card_header(class = "bg-transparent pb-0", div(class = "fw-bold",
            step_pop(
              " \u2461 Signature & compound annotation",
              paste(
                "Step 2: upload a query signature (Gene + log2FC). A",
                a(href = "demo/signature.txt", "demo signature file"),
                "is provided.",
                "<br>Step 3: upload a one-column drug list (header: Compound_name) - the drugs you want the signature search to retrieve. A",
                a(href = "demo/drug_annotation_ES.txt", "demo compound annotation"),
                "is provided. Then choose what these drugs represent.",
                "<br>If you have other identifiers (e.g. EntrezID), please go to the",
                as.character(strong(" converter page")), " to convert."
              )
            )
          )),
          card_body(
            div(class = "fw-bold small mb-1", "Step 2 \u00b7 Query signature"),
            fileInput(
              inputId = "file_sig",
              label = NULL,
              buttonLabel = "Browse...",
              placeholder = "No file selected",
              accept = c(".csv", ".txt")
            ),
            div(class = "fw-bold small mb-1 mt-2", "Step 3 \u00b7 Compound annotation & what it means"),
            fileInput(
              inputId = "file_anno",
              label = NULL,
              buttonLabel = "Browse...",
              placeholder = "No file selected",
              accept = c(".csv", ".txt")
            ),
            radioButtons(
              "anno_type",
              label = NULL,
              choices = c("Effective drugs (efficacy benchmark)" = "effective",
                          "Toxic drugs (toxicity screening)" = "toxic"),
              selected = "effective",
              inline = FALSE
            )
          )
        ),
        card(
          card_header(class = "bg-transparent pb-0", div(class = "fw-bold",
            step_pop(
              " \u2462 Methods & gene filter",
              paste(
                "Step 4: please select ",
                as.character(strong("at least TWO")),
                " methods for benchmark. More methods mean more time.",
                as.character(strong("The time for a full-selected job is 15~30 mins"))
              )
            )
          )),
          card_body(
            checkboxGroupInput(
              "sel_ss",
              label = NULL,
              choices = ss_list,
              selected = c("SS_Xsum", "SS_CMap")
            ),
            div(class = "fw-bold small mb-1 mt-2", "Step 5 \u00b7 Gene filter mode"),
            radioButtons(
              "filter_mode_bm",
              label = NULL,
              choices = c("topN" = "topN", "|log2FC| threshold" = "logFC"),
              selected = "topN",
              inline = TRUE
            )
          )
        ),
        card(
          card_footer(class = "bg-transparent d-grid gap-2",
            actionButton("runBM", "Run", class = "btn-success"),
            actionButton("reset", "Reset", class = "btn-outline-secondary"),
            actionButton("runBENdemo2", "demo2(Tahoe)", class = "btn-outline-primary")
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
        open = "always",
        card(
          card_header(class = "bg-transparent pb-0", div(class = "fw-bold", "① Query mode & methods")),
          card_body(
            div(class = "fw-bold small mb-1",
              step_pop(
                " Step 1. Select module",
                paste(
                  as.character(strong("Single Search")),
                  " is the traditional method to query promising drugs, just like GSEA.<br>",
                  as.character(strong("SS_all")),
                  "query promising drugs integrating the results of all SSMs.<br>",
                  as.character(strong("SS_corss")),
                  " use two query signatures to query promising drugs with consensus."
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
              selected = "singlemethod",
              options = list()
            ),
            div(class = "fw-bold small mb-1 mt-3",
              step_pop(
                " Step 2. Select Signature Search method(s)",
                paste(
                  "<strong>singlemethod / SS_cross:</strong> Just select one method of your interest.<br>",
                  "<strong>SS_all:</strong> Please select at least two methods of your interest. More methods mean more time. ",
                  as.character(strong("The time for a full-selected job is 20~40 mins.")), "<br>",
                  "<strong>Direction (SS_all):</strong> SS_all only compares drugs in the same direction (scores both > 0 or < 0). Down is default for query signature; other signature types are not recommended."
                )
              )
            ),
            conditionalPanel(
              condition = "input.sel_model_sm == 'singlemethod' | input.sel_model_sm == 'SS_cross'",
              radioButtons(
                "sel_ss_sm",
                label = NULL,
                choices = ss_list,
                selected = "SS_GSEA"
              )
            ),
            conditionalPanel(
              condition = "input.sel_model_sm == 'SS_all'",
              checkboxGroupInput(
                "sel_all_sm",
                label = NULL,
                choices = ss_list,
                selected = c("SS_Xsum", "SS_CMap")
              ),
              radioButtons(
                "sel_direct_sm",
                label = NULL,
                choices = sm_direct,
                inline = TRUE,
                selected = "Down"
              )
            )
          )
        ),
        card(
          card_header(class = "bg-transparent pb-0", div(class = "fw-bold", "② Dataset & signature")),
          card_body(
            div(class = "fw-bold small mb-1",
              step_pop(
                " Step 3. Select a pharmacotranscriptomic dataset",
                paste(
                  "Select the perturbation class via ", as.character(strong("data source")),
                  ": <br>",
                  as.character(strong("LINCS / Tahoe-100M")), " are compound (drug) datasets at ",
                  as.character(strong("different concentrations and treatment times")),
                  " (155 LINCS tumor cell lines or 47 Tahoe cell lines, 24 h).<br>",
                  as.character(strong("LINCS-CRISPR")), " are CRISPR knockout datasets (19 cell lines, 96 h): ",
                  "the ranked entities are ", as.character(strong("target genes")), ", not drugs, and drug-detail popups are disabled for them.",
                  "<br>In general, we recommend selecting a dataset with many perturbations and a cell line related to the cancer of interest."
                )
              )
            ),
            pickerInput(
              "sel_source_sm",
              label = "Select data source",
              choices = PERT_DATA_SOURCES,
              selected = DEFAULT_PERT_SOURCE,
              options = list()
            ),
            pickerInput(
              "sel_tissue_sm",
              label = "Select tissue",
              choices = names(pert_by_tissue),
              selected = PERT_DEFAULT_TISSUE_SM,
              options = list()
            ),
            pickerInput(
              "sel_experiment_sm",
              label = "Select a specific dataset",
              choices = pert_by_tissue[[PERT_DEFAULT_TISSUE_SM]],
              selected = PERT_DEFAULT_DS_SM,
              options = list()
            ),
            shiny::uiOutput("sm_dataset_class_hint"),
            shiny::uiOutput("sm_calibration_hint"),
            div(class = "fw-bold small mb-1 mt-3",
              step_pop(
                " Step 4. Upload query signature(s)",
                HTML(paste(
                  "A query signature is a gene list (gene symbol) with log2FC, derived from a gene expression profile of cell lines or patient cohorts (e.g. a query signature from TCGA).",
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
          )
        ),
        card(
          card_header(class = "bg-transparent pb-0", div(class = "fw-bold", "③ Gene filter")),
          card_body(
            div(class = "fw-bold small mb-1", " Step 5. Set gene filter"),
            radioButtons(
              "filter_mode_sm",
              label = NULL,
              choices = c("topN" = "topN", "|log2FC| threshold" = "logFC"),
              selected = "topN",
              inline = TRUE
            ),
            conditionalPanel(
              condition = "input.filter_mode_sm == 'topN'",
              numericInput("sel_topn_sm", label = NULL, value = 150, min = 10, max = 1000)
            ),
            conditionalPanel(
              condition = "input.filter_mode_sm == 'logFC'",
              numericInput("sel_fc_sm", label = NULL, value = 0.5, min = 0.05, max = 5, step = 0.05)
            )
          )
        ),
        card(
          card_footer(class = "bg-transparent d-grid gap-2",
            actionButton("runSM", "Run", class = "btn-success"),
            actionButton("reset_sm", "Reset", class = "btn-outline-secondary"),
            actionButton("runAPPdemo1", "demo(Single method)", class = "btn-outline-primary"),
            actionButton("runAPPdemo2", "demo(SS_all)", class = "btn-outline-primary"),
            actionButton("runAPPdemo3", "demo(SS_cross)", class = "btn-outline-primary")
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
        open = "always",
        card(
          card_header(class = "bg-transparent pb-0", div(class = "fw-bold",
            bs_icon("search"), " Retrieve a result by Job ID")),
          card_body(
            textInput(
              "jobid_input",
              label = "Input Jobid",
              value = "APP1790735151KID"
            ),
            shiny::p(
              class = "text-muted small mt-2 mb-0",
              "Please be aware that the \"Quick Tip\" button may become unresponsive when you're viewing identical result types across two different modules (e.g. Benchmark results in both Benchmark and Job Center). Use the \"Reset\" button in the respective module to reactivate it."
            ),
            shiny::uiOutput("jc_bookmark_hint")
          ),
          card_footer(class = "bg-transparent d-grid gap-2",
            actionButton("jobid_get", "Retrieve", class = "btn-success"),
            actionButton("reset_jc", "Reset", class = "btn-outline-secondary"),
            actionButton("runjcBENdemo2", "demo2(Tahoe)", class = "btn-outline-primary"),
            actionButton("runjcAPPdemo1", "demo(Single method)", class = "btn-outline-primary"),
            actionButton("runjcAPPdemo2", "demo(SS_all)", class = "btn-outline-primary"),
            actionButton("runjcAPPdemo3", "demo(SS_cross)", class = "btn-outline-primary")
          )
        ),
        card(
          card_header(class = "bg-transparent pb-0", div(class = "fw-bold",
            bs_icon("clock-history"), " Recent jobs (this session)")),
          card_body(
            uiOutput("jc_recent_jobs")
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
          open = "always",
          card(
            card_header(class = "bg-transparent pb-0", div(class = "fw-bold", "① Input your IDs")),
            card_body(
              textAreaInput("text_ctg", label = NULL, height = "200px"),
              actionButton("runCTGdemo", "demo", class = "btn-outline-primary")
            )
          ),
          card(
            card_header(class = "bg-transparent pb-0", div(class = "fw-bold", "② ID type & header")),
            card_body(
              radioButtons(
                "format_ctg",
                "Convert from",
                inline = TRUE,
                choices = c("ENTREZID", "ENSEMBL", "UNIPROT", "GENENAME")
              ),
              checkboxInput(
                "header_check_ctg",
                label = strong("The first row is a header"),
                value = TRUE
              )
            ),
            card_footer(class = "bg-transparent",
              actionButton("runCTG", "Convert", class = "btn-success w-100")
            )
          )
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
          open = "always",
          card(
            card_header(class = "bg-transparent pb-0", div(class = "fw-bold", "① Input your drug IDs")),
            card_body(
              textAreaInput("text_ctd", label = NULL, height = "200px"),
              div(class = "d-flex flex-wrap gap-2",
                actionButton("runCTDdemo1", "demo1", class = "btn-outline-primary"),
                actionButton("runCTDdemo2", "demo2", class = "btn-outline-primary"),
                actionButton("runCTDdemo3", "demo3", class = "btn-outline-primary")
              )
            )
          ),
          card(
            card_header(class = "bg-transparent pb-0", div(class = "fw-bold", "② ID type & header")),
            card_body(
              radioButtons(
                "format_ctd",
                "Convert from",
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
                label = strong("The first row is a header"),
                value = TRUE
              )
            ),
            card_footer(class = "bg-transparent",
              actionButton("runCTD", "Convert", class = "btn-success w-100")
            )
          )
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
        "Q1: Why we built SSP2?", value = "q1",
        card(title = NULL, full_screen = TRUE, includeMarkdownExternal("www/info_Q1.md"))
      ),
      nav_panel(
        "Q2: Benchmark", value = "q2",
        card(title = NULL, full_screen = TRUE, includeMarkdownExternal("www/info_Q2.md"))
      ),
      nav_panel(
        "Q3: Application", value = "q4",
        navset_card_tab(
          nav_panel(
            "Application guide",
            includeMarkdownExternal("www/info_Q4.md")
          ),
          nav_panel(
            "Single method",
            includeMarkdownExternal("www/info_Q9_sm_sm.md")
          ),
          nav_panel(
            "SS_cross",
            includeMarkdownExternal("www/info_Q9_sm_cross.md")
          ),
          nav_panel(
            "SS_all",
            includeMarkdownExternal("www/info_Q9_sm_all.md")
          )
        )
      ),
      nav_panel(
        "Q4: Download data", value = "q5",
        card(title = NULL, full_screen = TRUE, includeMarkdownExternal("www/info_Q5.md"))
      ),
      nav_panel(
        "Q5: Retrieve job", value = "q6",
        card(title = NULL, full_screen = TRUE, includeMarkdownExternal("www/info_Q6.md"))
      ),
      nav_panel(
        "Q6: Annotate drug", value = "q7",
        card(title = NULL, full_screen = TRUE, includeMarkdownExternal("www/info_Q7.md"))
      ),
      nav_panel(
        "Q7: Other signature types", value = "q8",
        card(title = NULL, full_screen = TRUE, includeMarkdownExternal("www/info_Q8.md"))
      ),
      nav_panel(
        "Q8: Optimal topN/method", value = "q9",
        card(
          title = NULL, full_screen = TRUE,
          tagList(
            shiny::h3("How to find the optimal topN and method?"),
            includeMarkdownExternal("www/info_Q9_bm_METRIC.md"),
            includeMarkdownExternal("www/info_Q9_bm_SUMMARY.md")
          )
        )
      ),
      nav_panel(
        "Q9: Frequently asked questions", value = "q11",
        card(title = NULL, full_screen = TRUE, includeMarkdownExternal("www/info_Q11.md"))
      )
    )
    ),
    nav_panel(
      title = "Data",
      value = "data",
      page_fluid(
        div(
          style = "max-width: 900px; margin: 0 auto;",
          h3("Download"),
          card(
            card_header(class = "bg-transparent pb-0",
              div(class = "fw-bold", bs_icon("download"), " Demo files & scripts")),
            card_body(
              p(class = "text-muted small mb-2",
                "Signature / compound annotation templates and the demo bundle used in the tutorials."),
              div(class = "d-flex flex-wrap gap-2",
                downloadButton("dl_demo", "Download Demo", class = "btn-success"),
                downloadButton("dl_script", "Download Script", class = "btn-success")
              )
            )
          ),
          card(
            card_header(class = "bg-transparent pb-0",
              div(class = "fw-bold", bs_icon("database"), " Curated pharmacotranscriptomic datasets")),
            card_body(
              pickerInput(
                "sel_source_dl",
                label = "Select data source",
                choices = names(drug_num_list_by_source_tissue),
                selected = DEFAULT_SOURCE,
                options = list()
              ),
              pickerInput(
                "sel_tissue_dl",
                label = "Select tissue",
                choices = names(drug_num_list_by_tissue),
                selected = names(drug_num_list_by_tissue)[1],
                options = list()
              ),
              pickerInput(
                "sel_experiment_dl",
                label = "Select a specific dataset",
                choices = drug_num_list_by_tissue[[names(drug_num_list_by_tissue)[1]]],
                selected = unname(drug_num_list_by_tissue[[names(drug_num_list_by_tissue)[1]]][1]),
                options = list()
              ),
              div(class = "d-flex flex-wrap gap-2",
                downloadButton("dl_drug_exp", "Download dataset", class = "btn-success"),
                downloadButton("dl_drug_ann", "Download Drug / Experiment info", class = "btn-success")
              )
            )
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
  )
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
      title = "Welcome to SSP2",
      text = "SSP2 is initializing. Please wait until this window closes.",
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

  # ---- 三级联动：数据源 -> 组织 -> 数据集 ----
  # 切换数据源时同时刷新 tissue 与 dataset；切换 tissue 时只刷新 dataset。
  # ignoreInit = TRUE：不在启动时覆盖 UI 里写死的默认值（Bone / Breast 等）。
  # by_source：选择数据源->组织->数据集映射；默认用化合物列表，
  # Application 页传入 pert_num_list_by_source_tissue（含 LINCS-CRISPR）。
  make_source_obs <- function(src_id, tis_id, dst_id,
                              by_source = drug_num_list_by_source_tissue) {
    observeEvent(input[[src_id]], {
      tt <- names(by_source[[input[[src_id]]]])
      updatePickerInput(session, tis_id, choices = tt, selected = tt[1])
      nc <- by_source[[input[[src_id]]]][[tt[1]]]
      updatePickerInput(session, dst_id, choices = nc, selected = unname(nc[1]))
    }, ignoreInit = TRUE)
    observeEvent(input[[tis_id]], {
      nc <- by_source[[input[[src_id]]]][[input[[tis_id]]]]
      updatePickerInput(session, dst_id, choices = nc, selected = unname(nc[1]))
    }, ignoreInit = TRUE)
  }
  make_source_obs("sel_source_dl", "sel_tissue_dl", "sel_experiment_dl")  # 下载页
  make_source_obs("sel_source",    "sel_tissue",    "sel_experiment")     # Benchmark
  make_source_obs("sel_source_sm", "sel_tissue_sm", "sel_experiment_sm",
                  by_source = pert_num_list_by_source_tissue)            # Application（含 CRISPR KO）

  # 会话内最近任务（P2：Job Center 展示本会话提交的 jobid）
  recent_jobs <- reactiveValues(ids = character(0))
  register_recent_job <- function(jobid) {
    recent_jobs$ids <- unique(c(jobid, recent_jobs$ids))
  }

  ###############################################.
  ## Sourcing tab code  ----
  ###############################################.
  source(file.path("tab_benchmark.R"),  local = TRUE)$value
  source(file.path("tab_application.R"),  local = TRUE)$value
  source(file.path("tab_jobcenter.R"),  local = TRUE)$value
  # source(file.path("data_tab.R"),  local = TRUE)$value
  source(file.path("tab_info.R"),  local = TRUE)$value
  source(file.path("tab_converter.R"),  local = TRUE)$value
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


  observeEvent(input$jump_to_ct, {
    nav_select(id = "intabset", selected = "ct_gene", session = session)
  })

  # 重置
  observeEvent(input$btn_landing, {
    showModal(modalDialog(
      includeMarkdownExternal("www/info_homepage.md"),
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
