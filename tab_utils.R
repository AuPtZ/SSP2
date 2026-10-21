# benchmark和application的结果保存
# 这个页面提供的是需要在不同页面使用的，超过2次以上的功能

# Quick Tip 弹窗。res_plot 已把 actionButton 的 id 按 prefix+jobid 唯一化
# （bm_ / sm_ / jc_ 前缀），避免同会话两处渲染同一结果导致的
# 「IDs were used for more than one input」警告。
# 检测点击用「逐键记录已见点击数」：只有当某按钮的点击计数较上次
# 增大时才弹窗；结果重渲染（按钮 id 变化、新按钮初始为 0）不会误触发。
if (!exists("tip_seen", mode = "environment") || is.null(tip_seen)) {
  tip_seen <- new.env(hash = TRUE, parent = emptyenv())
}

# ---- plotly widget 会话级缓存（2026-10-15 性能：图惰性构建）----
# 键 = paste0(prefix, "_", jobid, "_", tab)：切 tab 命中缓存秒出，未构建过的才现场画。
# 上限 80 条（约 25 MB）后整体清空，避免长时间会话无限增长。
if (!exists("pic_cache", mode = "environment") || is.null(pic_cache)) {
  pic_cache <- new.env(hash = TRUE, parent = emptyenv())
}

.observe_tip <- function(pattern, md_file, title) {
  observe({
    ks <- grep(pattern, names(input), value = TRUE)
    for (k in ks) {
      v <- input[[k]]
      seen <- if (exists(k, envir = tip_seen, inherits = FALSE)) tip_seen[[k]] else 0
      if (!is.null(v) && v > seen) {
        tip_seen[[k]] <- v
        showModal(modalDialog(
          includeMarkdown(md_file),
          title = title, size = "l", easyClose = TRUE
        ))
      }
    }
  })
}

.observe_tip("intro_res_bm_AUC_",   "www/info_Q9_bm_AUC.md",
            "How to find optimal method and topN in Benchmark? (AUC)")
.observe_tip("intro_res_bm_ES_",    "www/info_Q9_bm_ES.md",
            "How to find optimal method and topN in Benchmark? (ES)")
.observe_tip("intro_res_bm_METRIC_", "www/info_Q9_bm_METRIC.md",
            "How to read the ranking-quality metrics?")
.observe_tip("intro_res_bm_SUMMARY_", "www/info_Q9_bm_SUMMARY.md",
            "How to read the Benchmark overview?")
.observe_tip("intro_res_sm_sm_",    "www/info_Q9_sm_sm.md",    "Quick Tip")
.observe_tip("intro_res_sm_cross_", "www/info_Q9_sm_cross.md", "Quick Tip")
.observe_tip("intro_res_sm_all_",  "www/info_Q9_sm_all.md",  "Quick Tip")

# ---------------------------------------------------------------------------
# 药物详情弹窗：结果表（singlemethod / SS_all / SS_cross，行 = 药物）点任意一行，
# 弹出该药物在 PubChem 上的基本信息。数据来自 drug_info_pubchem（见 R/global.R，
# 由 maintain/09抓取PubChem药物信息.R 离线抓取）。
#
# 两个坑，和 Quick Tip 一样绕开：
#  1) 表 id 必须显式指定。原来写成 DT::renderDataTable(...) 内联形式，Shiny 自动
#     分配的 output id 拿不到，也就没法监听行点击。这里改成 output[[id]] +
#     DTOutput(id)，id 仍走 res_plot 的 tid()（prefix + jobid），保证
#     Benchmark / Application / Job Center 三处同时渲染时不重名。
#  2) 观察器不能按 id 逐个 observeEvent——id 是动态生成的。沿用 .observe_tip 的
#     「扫 input 名 + 逐键记录已见时间戳」写法：结果重渲染不会重复弹窗，而同一行
#     点第二次（时间戳变了）仍会弹。
# ---------------------------------------------------------------------------
drug_tbl_reg    <- new.env(parent = emptyenv())            # dt_id -> 该表的药物名向量
drug_click_seen <- new.env(hash = TRUE, parent = emptyenv())
DRUG_ROW_SFX    <- "_drugrow"      # 被点击的行号（1-based，R 侧下标）
DRUG_CLICK_SFX  <- "_drugclick"    # 点击时间戳（区分"又点了一次"）

# 点击行的 JS：把行号 + 时间戳送回 R。时间戳保证点同一行也能再次触发。
.drug_click_js <- function(id) {
  DT::JS(paste0(
    "table.on('click.dt', 'tbody tr', function() {",
    "  var i = table.row(this).index();",
    "  if (i === undefined || i === null) return;",
    "  Shiny.setInputValue('", id, DRUG_ROW_SFX,   "', i + 1);",
    "  Shiny.setInputValue('", id, DRUG_CLICK_SFX, "', Date.now());",
    "});"))
}

.drug_has <- function(x)
  !is.null(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(as.character(x)))

# 值单元格：长串自动换行；SMILES / InChIKey 也和其他行一样用普通字体，不用等宽
.drug_val <- function(v, mono = FALSE) {
  shiny::tags$td(as.character(v),
                 style = "word-break:break-word;overflow-wrap:anywhere;")
}

# 一行「字段名 / 值」，值缺失就整行不显示
.drug_kv <- function(k, v, mono = FALSE) {
  if (!.drug_has(v)) return(NULL)
  shiny::tags$tr(
    shiny::tags$td(k, style = "width:30%;font-weight:600;opacity:0.8;"),
    .drug_val(v, mono))
}

# 长文本（IUPAC 名、Synonyms）：换行显示；max_h 非空时才限高滚动，防弹窗被撑爆
.drug_kv_long <- function(k, v, max_h = NULL) {
  if (!.drug_has(v)) return(NULL)
  st <- "word-break:break-word;overflow-wrap:anywhere;"
  if (!is.null(max_h))
    st <- paste0(st, sprintf("max-height:%s;overflow-y:auto;", max_h))
  shiny::tags$tr(
    shiny::tags$td(k, style = "width:30%;font-weight:600;opacity:0.8;vertical-align:top;"),
    shiny::tags$td(shiny::tags$div(as.character(v), style = st)))
}

.drug_modal_ui <- function(nm) {
  nm  <- as.character(nm)[1]
  key <- tolower(trimws(nm))
  di  <- if (exists("drug_info_pubchem", inherits = TRUE)) drug_info_pubchem else NULL

  # 先按药物名精确匹配；结果表里有些药物直接写成 LINCS 的 BRD- 编号，再去 pert_id 里找
  rec <- NULL
  if (!is.null(di) && nrow(di) && nzchar(key)) {
    i <- which(di$name_key == key)[1]
    # 只有 BRD- 编号才值得再扫一遍 pert_id 列（3 万行 strsplit，别在每次点击都做）
    if (is.na(i) && grepl("^brd[- ]", key)) {
      hit <- vapply(strsplit(as.character(di$pert_id), "|", fixed = TRUE),
                    function(x) key %in% tolower(trimws(x)), logical(1))
      i <- which(hit)[1]
    }
    if (!is.na(i)) rec <- di[i, , drop = FALSE]
  }
  gv <- function(col) if (is.null(rec)) NULL else rec[[col]][1]

  tbl <- function(...)
    shiny::tags$table(class = "table", style = "margin-bottom:6px;",
                      shiny::tags$tbody(...))

  cid_src <- gv("cid_source")
  cid_src_txt <- if (.drug_has(cid_src)) switch(
    as.character(cid_src),
    lincs           = "LINCS 2020 (original record)",
    name_lookup     = "PubChem name search (inferred)",
    invalid_lincs_id = "LINCS id invalid, re-searched by name",
    as.character(cid_src))

  ident <- tbl(
    .drug_kv("Drug name", nm),
    .drug_kv("Common name", gv("pc_title")),
    .drug_kv("LINCS ID", gv("pert_id")),
    .drug_kv("PubChem CID", gv("pubchem_cid")),
    .drug_kv("Record source", cid_src_txt),
    .drug_kv_long("IUPAC name", gv("pc_iupac")))

  chem <- tbl(
    .drug_kv("Molecular formula", gv("pc_formula")),
    .drug_kv("Molecular weight", if (.drug_has(gv("pc_mw")))
      paste0(gv("pc_mw"), " g/mol")),
    .drug_kv("Monoisotopic mass", gv("pc_mono")),
    .drug_kv("XLogP", gv("pc_xlogp")),
    .drug_kv("Topological polar surface area", if (.drug_has(gv("pc_tpsa")))
      paste0(gv("pc_tpsa"), " Å²")),
    .drug_kv("Complexity", gv("pc_complexity")),
    .drug_kv("H-bond donors / acceptors",
             if (.drug_has(gv("pc_hbd")) || .drug_has(gv("pc_hba")))
               paste0(gv("pc_hbd"), " / ", gv("pc_hba"))),
    .drug_kv("Rotatable bonds", gv("pc_rotb")),
    .drug_kv("Charge", gv("pc_charge")))

  # PubChem 没抓到 SMILES 时退回 LINCS 自带的（字段名叫 canonical_smiles）
  sm <- gv("pc_smiles"); sm_lab <- "SMILES (PubChem)"
  if (!.drug_has(sm)) { sm <- gv("lincs_smiles"); sm_lab <- "SMILES (LINCS)" }
  ik <- gv("pc_inchikey"); ik_lab <- "InChIKey (PubChem)"
  if (!.drug_has(ik)) { ik <- gv("inchi_key"); ik_lab <- "InChIKey (LINCS)" }
  # 与其它字段完全相同的行样式（不再是输入框），仅结构串用等宽字体
  struct <- tbl(.drug_kv(sm_lab, sm, mono = TRUE),
                .drug_kv(ik_lab, ik, mono = TRUE))

  syn <- if (.drug_has(gv("pc_synonyms")))
    tbl(.drug_kv_long("Synonyms", gv("pc_synonyms"), max_h = "110px"))
  moa <- if (.drug_has(gv("pc_moa")))
    shiny::tagList(
      shiny::tags$h5("Mechanism of action", style = "margin:10px 0 4px 0;"),
      shiny::tags$div(as.character(gv("pc_moa")),
                      style = "max-height:180px;overflow-y:auto;"))

  # 外链：有 CID 就精确定位，没有就按名称搜索兜底
  en <- utils::URLencode(as.character(nm), reserved = TRUE)
  u_pub <- if (.drug_has(gv("pubchem_cid")))
    sprintf("https://pubchem.ncbi.nlm.nih.gov/compound/%s", gv("pubchem_cid"))
  else sprintf("https://pubchem.ncbi.nlm.nih.gov/#query=%s", en)
  links <- shiny::tags$p(
    shiny::tags$a("PubChem", href = u_pub, target = "_blank", rel = "noopener"), " · ",
    shiny::tags$a("ChEMBL",
                  href = sprintf("https://www.ebi.ac.uk/chembl/g/#search_results/all/query=%s", en),
                  target = "_blank", rel = "noopener"),
    style = "margin-top:10px;")

  body <- if (is.null(rec)) {
    shiny::tagList(
      shiny::tags$p(shiny::strong(nm), style = "margin-bottom:6px;"),
      shiny::tags$p(
        if (is.null(di) || !nrow(di))
          "The local drug annotation database is not available (data_preload/drugconvertor/drug_info_pubchem.Rdata missing)."
        else
          paste("No PubChem record for this compound in the local database.",
                "It is probably a research compound that has no PubChem entry;",
                "try the links below."),
        style = "opacity:0.75;"),
      ident, links)
  } else {
    shiny::tagList(ident,
                   shiny::tags$h5("Chemical properties", style = "margin:10px 0 4px 0;"),
                   chem,
                   shiny::tags$h5("Structure identifiers", style = "margin:10px 0 4px 0;"),
                   struct, syn, moa, links)
  }

  # 强制弹窗内所有正文与网页基础字体一致（1rem），不再额外缩小
  body <- shiny::tags$div(body, style = "font-size:1rem;line-height:1.5;")

  modalDialog(body, title = paste0("Drug details — ", nm),
              size = "l", easyClose = TRUE,
              footer = shiny::modalButton("Close"))
}

.drug_modal <- function(nm) showModal(.drug_modal_ui(nm))

# 药物结果表：显式 output id + 登记药物名，供弹窗取用
.drug_dt_ui <- function(tb, id) {
  tb <- as.data.frame(tb, stringsAsFactors = FALSE) %>%
    dplyr::rename(dplyr::any_of(rename_col_rules))
  nmcol <- if ("name" %in% names(tb)) "name" else names(tb)[1]
  drug_tbl_reg[[id]] <- as.character(tb[[nmcol]])
  output[[id]] <- DT::renderDataTable(
    DT::datatable(tb, selection = "single", callback = .drug_click_js(id)),
    server = FALSE)
  shiny::tagList(
    shiny::tags$p("Tip: click any row to see the drug's details.",
                  style = "color:#666;margin:2px 0 6px 0;"),
    DT::DTOutput(id))
}

.observe_drug_click <- function() {
  observe({
    ks <- grep(paste0(DRUG_CLICK_SFX, "$"), names(input), value = TRUE)
    for (k in ks) {
      ts <- input[[k]]
      seen <- if (exists(k, envir = drug_click_seen, inherits = FALSE)) drug_click_seen[[k]] else 0
      if (is.null(ts) || is.na(ts) || ts <= seen) next
      drug_click_seen[[k]] <- ts
      base <- sub(paste0(DRUG_CLICK_SFX, "$"), "", k)
      row  <- input[[paste0(base, DRUG_ROW_SFX)]]
      nms  <- if (exists(base, envir = drug_tbl_reg, inherits = FALSE)) drug_tbl_reg[[base]] else NULL
      idx  <- suppressWarnings(as.integer(row))
      nm   <- if (!is.null(nms) && !is.na(idx) && idx >= 1L && idx <= length(nms))
        nms[idx] else NA_character_
      .drug_modal(if (is.na(nm)) "(unknown)" else nm)
    }
  })
}
.observe_drug_click()

# Job info：原来是「2 列 × 11~14 行」的表，纵向太长，把结果表和图挤到很下面。
# 改成自适应卡片网格：每个字段一小块（字段名小字 + 值），宽屏一行 3~4 块、
# 窄屏自动折行，高度压到原来的 1/3 左右。
.job_info_ui <- function(x) {
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  if (is.null(x) || ncol(x) < 2L || !nrow(x)) return(NULL)
  # 列名不固定：demo 里是 V2(字段名) + V1(值)，别的 job 文件也可能反过来，
  # 用 "Job id" 落在哪一列来判定字段名列（判不出来就按位置：第 1 列是字段名）。
  lcol <- if ("V2" %in% names(x)) "V2" else names(x)[1]
  vcol <- if ("V1" %in% names(x)) "V1" else names(x)[2]
  if (!any(x[[lcol]] == "Job id", na.rm = TRUE)) { lcol <- names(x)[1]; vcol <- names(x)[2] }
  labs <- trimws(as.character(x[[lcol]]))
  vals <- trimws(as.character(x[[vcol]]))
  # 提交时间原本带微秒（2026-09-29 16:14:46.83041），截到秒就够看
  fix <- grepl("submission time", labs, ignore.case = TRUE)
  vals[fix] <- substr(vals[fix], 1L, 19L)
  keep <- !is.na(labs) & nzchar(labs)
  labs <- labs[keep]; vals <- vals[keep]
  items <- lapply(seq_along(labs), function(i) {
    v <- vals[i]
    if (is.na(v) || !nzchar(v)) v <- "—"
    shiny::tags$div(
      style = paste0("flex:1 1 200px;min-width:0;padding:5px 10px;margin:2px;",
                     "border:1px solid rgba(127,127,127,.25);border-radius:6px;",
                     "background:rgba(127,127,127,.06);"),
      shiny::tags$div(labs[i], style = "font-size:.8rem;opacity:.72;line-height:1.25;"),
      shiny::tags$div(v, title = v,
                      style = "word-break:break-word;overflow-wrap:anywhere;line-height:1.35;"))
  })
  shiny::tags$div(style = "display:flex;flex-wrap:wrap;margin:2px 0 6px 0;", items)
}

.job_info_block <- function(job_info)
  shiny::tagList(shiny::h3("Job info"), .job_info_ui(job_info$yourjob))

# 读取 demo 结果 rdata：不硬依赖文件里的对象名。
# 历史教训（2026-09-30）：生成脚本曾把对象存成 ji，而页面 load() 之后按
# job_info 取，8 个 demo 按钮全部报 "object 'job_info' not found"。这里先看
# 有没有 job_info，没有就用文件里唯一的对象，让两侧彻底解耦。
.load_demo <- function(f) {
  e <- new.env(parent = emptyenv())
  load(f, envir = e)
  if (exists("job_info", envir = e, inherits = FALSE)) return(get("job_info", envir = e))
  nms <- ls(e)
  if (length(nms) == 1L) return(get(nms, envir = e))
  stop("demo 文件 ", f, " 里的对象名无法识别：", paste(nms, collapse = ", "))
}

# ---- 视口居中的全屏加载指示（2026-10-16）----
# withSpinner() 的 loader 是 position:absolute，**相对结果区**居中；而结果区在长表单下方，
# 首屏根本看不到 → 用户以为"点了没反应"，要下滑才找得到那个转圈。
# 这里改用 shinycssloaders 自带的**全屏** spinner（#shinycssloaders-global-spinner：
# position:fixed + z-index 1e8 → 固定在视口正中，与滚动位置无关）。
show_page_spinner <- function(caption = "Loading results ...", timeout_ms = 60000L) {
  shinycssloaders::showPageSpinner(caption = caption)
  # 兜底：全屏 spinner 是 position:fixed + z-index 1e8，一旦"显示后永不隐藏"会盖住整页。
  # 正常路径由 renderUI 的 on.exit(hide_page_spinner()) 收起；但若渲染出错
  # （sanitize.errors 下输出不送达客户端，on.exit 不触发），只能靠这个超时兜底。
  # 直接移除 DOM 元素，不依赖包内部 API。
  shinyjs::runjs(sprintf(
    "setTimeout(function(){ var e = document.getElementById('shinycssloaders-global-spinner'); if (e) e.remove(); }, %d);",
    as.integer(timeout_ms)))
}
hide_page_spinner <- function() {
  shinycssloaders::hidePageSpinner()
}

# FOR EACH PAGE
observeEvent(input$runBENdemo,{
  job_info <- .load_demo("demo/BEN1790672381JTV.rdata")
  show_page_spinner()
  output$display_bm <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "bm") })
})
observeEvent(input$runBENdemo2,{
  job_info <- .load_demo("demo/BEN_Tahoe_demo2.rdata")
  show_page_spinner()
  output$display_bm <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "bm") })
})
observeEvent(input$runAPPdemo1,{
  job_info <- .load_demo("demo/APP1790669686URX.rdata")
  show_page_spinner()
  output$display_sm <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "sm") })
})
observeEvent(input$runAPPdemo2,{
  job_info <- .load_demo("demo/APP1790669691LXK.rdata")
  show_page_spinner()
  output$display_sm <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "sm") })
})
observeEvent(input$runAPPdemo3,{
  job_info <- .load_demo("demo/APP1790735151KID.rdata")
  show_page_spinner()
  output$display_sm <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "sm") })
})
# FOR JOB PAGE
observeEvent(input$runjcBENdemo,{
  job_info <- .load_demo("demo/BEN1790672381JTV.rdata")
  show_page_spinner()
  output$display_jc <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "jc") })
})
observeEvent(input$runjcBENdemo2,{
  job_info <- .load_demo("demo/BEN_Tahoe_demo2.rdata")
  show_page_spinner()
  output$display_jc <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "jc") })
})
observeEvent(input$runjcAPPdemo1,{
  job_info <- .load_demo("demo/APP1790669686URX.rdata")
  show_page_spinner()
  output$display_jc <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "jc") })
})
observeEvent(input$runjcAPPdemo2,{
  job_info <- .load_demo("demo/APP1790669691LXK.rdata")
  show_page_spinner()
  output$display_jc <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "jc") })
})
observeEvent(input$runjcAPPdemo3,{
  job_info <- .load_demo("demo/APP1790735151KID.rdata")
  show_page_spinner()
  output$display_jc <- renderUI({ on.exit(hide_page_spinner(), add = TRUE); res_plot(job_info, prefix = "jc") })
})



# ---------------------------------------------------------------------------
# Benchmark 新指标曲线（2026-10-13 指标重构）。五个指标均有文献先例，出处见
# R/Utils_BM_metrics.R 头注；零分布 = 标签置换，与 topN/logFC 无关 → 水平参考带。
# ---------------------------------------------------------------------------
BM_METRIC_TABS <- c("ES_rank", "AUPRC", "RecallAtK", "EFpct", "AUROC")


# 跨扫描的每方法汇总（median / max / 零分布 / 置换显著性）。
# ★ 当前 UI 的指标 tab 用的是与 AUC/ES 同构的**宽表**（见 res_plot 的 DT_metric）；
#   本函数保留给将来的 API / 论文批量汇总用。
metrics_summary_table <- function(curve) {
  curve %>% dplyr::group_by(Method, Metric) %>%
    dplyr::summarise(median = median(Value, na.rm = TRUE),
              max    = max(Value, na.rm = TRUE),
              null_mean = unique(NullMean)[1],
              null_q975 = unique(NullQ975)[1], .groups = "drop") %>%
    dplyr::mutate(sig = median > null_q975) %>%
    dplyr::select(Method, Metric, median, max, null_mean, null_q975, sig) %>%
    dplyr::arrange(Metric, dplyr::desc(median)) %>% as.data.frame()
}

# =============================================================================
# plotly widget 的**进程级**构建缓存（2026-10-16 性能）
#
# 背景：demo/作业的图每次点开都要"现场构建"（AUC 那张 991x7 + loess 实测 ~1.0-1.6 s），
#   而数据在进程生命周期内是不变的 → 用 memoise 按**数据内容哈希**缓存构建结果，
#   第二个会话/第二次点击直接命中（哈希一个 41k 行 data.frame 约 20 ms，远快于重建）。
#   实测：点 demo 首次 ~1.6 s，之后 ~0 s。
#   注意：不要把 widget 存进 demo rdata —— R 读深层嵌套 list 极慢
#   （7 个 widget 的 10.8 MB 文件 load 要 2.8 s，而重建只要 1.1 s）。
# =============================================================================
# ★ 不用 memoise：它会对**每个参数**做 digest 哈希，41k 行的 METRICS 表哈希一次要
#   ~0.3 s，抵消缓存收益。改为自建 env + 预先算好的廉价内容指纹（只哈希 topN 列与
#   Value 的分布摘要，约 1000 个数 → ~1 ms），env 查找是 O(1)。
.bm_widget_cache <- new.env(hash = TRUE, parent = emptyenv())

# 廉价但敏感的内容指纹：维度 + 扫描列 + Value/p 的分布摘要
bm_data_key <- function(auc_tab, mtab) {
  v <- if (is.null(mtab)) numeric(0) else
         c(as.numeric(mtab[[1]]), nrow(mtab), mean(mtab$Value, na.rm = TRUE),
           stats::sd(mtab$Value, na.rm = TRUE), max(mtab$Value, na.rm = TRUE),
           min(mtab$Value, na.rm = TRUE),
           if ("p_null" %in% names(mtab)) sum(mtab$p_null, na.rm = TRUE) else NA_real_)
  a <- if (is.null(auc_tab)) numeric(0) else c(as.numeric(auc_tab[[1]]), ncol(auc_tab))
  paste0(nrow(auc_tab), "x", ncol(auc_tab), "|",
         digest::digest(c(v, a), algo = "xxhash64"))
}

bm_get_widget <- function(nm, key, auc_tab, mtab, is_fc) {
  k <- paste0(nm, "|", key)
  hit <- .bm_widget_cache[[k]]
  if (!is.null(hit)) return(hit)
  w <- bm_build_widget(nm, auc_tab, mtab, is_fc)
  if (!is.null(w)) {
    if (length(ls(.bm_widget_cache)) > 32)
      rm(list = ls(.bm_widget_cache), envir = .bm_widget_cache)
    assign(k, w, envir = .bm_widget_cache)
  }
  w
}

# ★ toWebGL() 在 R 侧不改 trace 类型，是 **plotly.js 在客户端**把 scatter 转成
#   scattergl；而 scattergl 的校验器不接受 hoveron（scatter 专有属性），会报
#   "'scattergl' objects don't have these attributes: 'hoveron'" 导致图渲染失败。
#   ggplotly 会给带 hover 文本的 trace 加 hoveron="points"，这里统一剥掉
#   （scatter 默认就会在点上显示 hover，去掉不影响交互）。
.bm_strip_hoveron <- function(w) {
  d <- w$x$data
  if (is.null(d) || !is.list(d)) return(w)
  for (i in seq_along(d)) {
    if (!is.null(d[[i]]$hoveron)) d[[i]]$hoveron <- NULL
    # ggplotly 会给 legend trace 名加 ",N" 后缀（如 "CMap,1"），这里清掉
    if (!is.null(d[[i]]$name) && grepl(",[0-9]+$", d[[i]]$name))
      d[[i]]$name <- sub(",[0-9]+$", "", d[[i]]$name)
  }
  w$x$data <- d
  w
}

bm_build_widget <- function(nm, auc_tab, mtab, is_fc) {
  # ★ 默认不再用 toWebGL（2026-10-16 决定）：实测收益为零（headless 1.46 vs 1.48 s），
  #   却连踩三个坑——① scattergl 不支持 mode="text"（热图数值全丢）；
  #   ② 校验器不接受 hoveron（整图报错）；③ 不支持空心符号 shape=21（峰值环变实心黑团）。
  #   散点已抽稀到 ~150 点/方法（约 1 千点/图），SVG 完全够用。
  mk <- function(gp, use_gl = FALSE) {
    w <- ggplotly(gp, tooltip = c("x", "y"))
    w <- .bm_strip_hoveron(w)               # 防御性：即便将来有人改回 WebGL 也不会再报 hoveron
    if (use_gl) w <- plotly::toWebGL(w)
    plotly::config(w, displayModeBar = FALSE)
  }
  if (nm == "Summary")
    return(if (is.null(mtab)) NULL else mk(draw_dr_summary(mtab), use_gl = FALSE))
  if (nm == "AUC")
    return(if (is_fc) mk(draw_dr_auc_fc(auc_tab, max_points = 150))
                  else mk(draw_dr_auc(auc_tab, max_points = 150)))
  if (!is.null(mtab) && nm %in% BM_METRIC_TABS)
    return(mk(draw_dr_metrics(mtab, nm, max_points = 150)))
  NULL
}
res_plot <- function(job_info, prefix = "res"){
  # 每个调用上下文（Benchmark / Job Center / Application）传不同 prefix，
  # 使 actionButton 的 id 在会话内唯一，避免 "IDs were used for more than one input"。
  jid <- job_info$yourjob$V1[job_info$yourjob$V2 == "Job id"]
  jid <- if (length(jid) && nzchar(jid[1])) jid[1] else "x"
  tid <- function(base) paste0(prefix, "_", base, "_", jid)

  # 模式判定：**以结果表首列名为准**（topN 模式首列 "TopN"，|log2FC| 模式首列 "logFC"）。
  # 不能靠 filter_mode 元数据判定：yourjob 是 V1/V2 键值表，$filter_mode 恒为 NULL；
  # 且 logFC 任务的 sub_module 仍写作 "ALL (ES and AUC)"（_FC 后缀只出现在 label_output），
  # 于是 grepl("FC", module) 也判不出来。2026-09-29 实测：两条依据同时失效，
  # logFC 任务被送进 topN 分支，崩在 draw_dr_auc 的 pivot_longer(cols = -TopN)。
  is_fc_mode <- function(df) !identical(tolower(names(df)[1]), "topn")

if (!is.null(job_info$yourtable$METRICS)) {   # 有 METRICS 表 → 指标视图（新旧作业统一）

# 新契约（2026-10-17）：结果只有 METRICS 表；旧 ALL 结果的 AUC/ES 表仍在但不显示
# （AUC tab 已退役、旧 ES 已退役）。res_bm1 保留给 bm_data_key 做内容指纹。
res_bm1 <- if (!is.null(job_info$yourtable$`AUC`)) job_info$yourtable$`AUC` %>% as_tibble() else NULL
res_bm2 <- if (!is.null(job_info$yourtable$`ES`))  job_info$yourtable$`ES`  %>% as_tibble() else NULL
is_fc  <- if (!is.null(res_bm1)) is_fc_mode(res_bm1) else FALSE
# ---- 指标数据只解析一次（很便宜，eager）----
mtab <- NULL; mets <- character(0); metric_err <- NULL
if (!is.null(job_info$yourtable$METRICS)) {
mr <- tryCatch({
mt <- job_info$yourtable$METRICS %>% tibble::as_tibble()
mt <- mt[mt$Metric != "ES_abs", , drop = FALSE]     # 退役对照无零分布，不进图/表
list(mtab = mt, mets = intersect(BM_METRIC_TABS, unique(mt$Metric)))
}, error = function(e) { metric_err <<- conditionMessage(e); NULL })
if (!is.null(mr)) { mtab <- mr$mtab; mets <- mr$mets }
}
# Summary 放在最前；旧 ES（gsea1 的 |score| 加权版，零分布偏正 +0.26）已退役，
# 只保留 ES_rank（= GSEA 原文未加权 ES，零分布 0）——两者同族，保留一个即可。
# ★ AUC tab 已退役（2026-10-16）：它与 AUROC 是同一个统计量，而 legacy AUC 的
#   direction 是反的（实测报告 1 - AUROC，表里黄色"最佳 topN"实际最差），三重验证见
#   R/Utils_BM.R 的 process_raw1 注释。AUROC 已正确覆盖该信息且带置换 p 值。
#   注：AUC-only 单模块提交仍走 draw_dr_auc（direction 已修），此处只去掉 ALL 分支的重复 tab。
tab_ids <- if (!is.null(mtab) && length(mets) > 0) c("Summary", mets) else c("AUC")
# ---- 方案②：demo 文件预存了构建好的 widget（PICS）→ 灌缓存，跳过构建，秒开 ----
if (!is.null(job_info$yourtable$PICS)) {
for (nm in intersect(names(job_info$yourtable$PICS), tab_ids))
pic_cache[[paste0(prefix, "_", jid, "_", nm)]] <- job_info$yourtable$PICS[[nm]]
}
# ---- 方案①：图惰性构建 + 会话缓存（2026-10-15）----
build_pic <- function(nm) bm_get_widget(nm, bm_data_key(res_bm1, mtab), res_bm1, mtab, is_fc)
get_pic <- function(nm) {
key <- paste0(prefix, "_", jid, "_", nm)
hit <- pic_cache[[key]]
if (!is.null(hit)) return(hit)        # 缓存命中：切回已看过的 tab 秒出
w <- build_pic(nm)                     # 未构建过：现场画（1-2 s，spinner 覆盖）
if (!is.null(w)) {
pic_cache[[key]] <- w
if (length(ls(pic_cache)) > 80) rm(list = ls(pic_cache), envir = pic_cache)  # 防无限增长
}
w
}
# ---- 数据表（eager，很便宜）：指标宽表 + Summary 总览表 ----
DT_overview <- NULL      # Summary 页的跨方法总览表
if (!is.null(mtab) && length(mets) > 0) {
  DT_overview <- tryCatch({
    ov <- metrics_overview(mtab)
    if (is.null(ov)) NULL else {
      # 数值列统一 4 位小数（与指标宽表一致；否则总览表会出现 16 位小数）
      num <- vapply(ov, is.numeric, logical(1))
      ov[num] <- lapply(ov[num], function(x) round(x, 4))
      DT::datatable(ov)
    }
  }, error = function(e) { metric_err <<- conditionMessage(e); message("[res_plot] Summary 表构建失败: ", conditionMessage(e)); NULL })
}
DT_metric <- list()      # 名字 = 指标名；每个都是与 AUC/ES 表同构的宽表
if (!is.null(mtab) && length(mets) > 0) {
DT_metric <- tryCatch({
  # 显示名与列序都跟 AUC/ES 表一致（XSum 表是 rename_col_rules 改出来的同名）
  disp <- c(SS_CMap = "CMap", SS_GSEA = "GSEA", SS_XCos = "XCos", SS_Xsum = "XSum",
            SS_ZhangScore = "ZhangScore", SS_PLAGE = "PLAGE", SS_QuSAGE = "QuSAGE")
  swp <- names(mtab)[1]                                    # TopN 或 logFC
  out <- list()
  for (mm in mets) {
    d <- mtab[mtab$Metric == mm, c(swp, "Method", "Value", "NullMean", "NullQ975")]
    w <- tidyr::pivot_wider(d, names_from = Method, values_from = Value)
    ssm_cols <- intersect(names(disp), names(w))              # 原始 SS_ 方法列
    w <- w[, c(swp, ssm_cols), drop = FALSE]
    names(w) <- c(swp, unname(disp[ssm_cols]))                # 换成与 AUC/ES 表一致的显示名
    # 列序直接沿用 AUC 表（AUC/ES 表的列序是平台里方法顺序的唯一事实源）
    # 列序 = 平台约定的方法顺序（与 AUC/ES 表一致；不再依赖 res_bm1，新格式作业没有该表）
    w <- w[, c(swp, intersect(c('XSum','CMap','GSEA','ZhangScore','XCos','PLAGE','QuSAGE'), names(w))), drop = FALSE]
    mcols <- names(w)[-1]                                     # ★ 之后一律用新列名索引
    # 保留 4 位小数：AUC/ES 表在页面上就是这个精度（pROC 输出本身位数就少）
    for (cc in mcols) w[[cc]] <- round(as.numeric(w[[cc]]), 4)
    # 尾部两列：置换零分布（该指标下是常量，随表一起给出，便于和数值直接比）
    w[["null_mean"]] <- round(unique(d$NullMean)[1], 4)
    w[["null_q975"]] <- round(unique(d$NullQ975)[1], 4)
    # 排序 + 高亮：与 AUC/ES 表同一套规则（按"最大值所在列"降序，首行最大值黄色）
    top_col <- mcols[which.max(vapply(mcols, function(cc) max(w[[cc]], na.rm = TRUE), numeric(1)))]
    w <- w[order(-w[[top_col]], na.last = TRUE), , drop = FALSE]
    out[[mm]] <- DT::datatable(w) %>%
      # 注意：w 是 tibble，w[1, col] 返回 1x1 tibble 会让 styleEqual 报错，必须取标量
      DT::formatStyle(top_col, backgroundColor = DT::styleEqual(w[[top_col]][1], c("yellow")))
  }
  out
}, error = function(e) { metric_err <<- conditionMessage(e); message("[res_plot] 指标表构建失败: ", conditionMessage(e)); NULL })
}
# ---- Quick Tip 按钮放进各 tab（激活项才可见；id 唯一，无重复 id 警告）----
# 每个 tab 一个**唯一**按钮 id：所有 tabPanel 同时存在于 DOM（CSS 隐藏），
# 共用 id 会触发 Shiny "Duplicate input ID"（5 个指标 tab 曾全用 METRICS 一个 id）
tip_of <- function(nm) {
  if (nm == "AUC") "intro_res_bm_AUC"
  else if (nm == "Summary") "intro_res_bm_SUMMARY"
  else paste0("intro_res_bm_METRIC_", nm)
}
# tab 标题用显示名（ES_rank -> ES），但 value 保持**内部指标键**：
# bslib 的 tabsetPanel 把 value 发给 input$res_tabs，联动查表/查图全靠它，
# 若把标题当 value（即不显式指定），改名后 cur_tab() 会拿到 "ES" 而查不到 "ES_rank"。
tabs <- lapply(tab_ids, function(nm) {
  lab <- .bm_metric_label(nm)
  shiny::tabPanel(title = lab, value = nm,
    shiny::div(style = "display:flex; justify-content:space-between; align-items:center;",
      shiny::tags$span(lab, style = "font-weight:600;"),
      actionButton(tid(tip_of(nm)), "Quick Tip", class = "btn-outline-success btn-sm")))
})
# ---- anno_type：有效药 / 毒性药（决定区块标题与解释文案；计算在 worker 里已按
#      "toxic → 分数取反"处理，这里只负责展示语义）----
atype_raw <- job_info$yourjob$V1[job_info$yourjob$V2 == "Annotation type"]
anno_type  <- if (length(atype_raw) && nzchar(atype_raw[1])) atype_raw[1] else "effective"
anno_head  <- if (identical(anno_type, "toxic"))
  "Toxicity screening (toxic drugs sink to the bottom = your signature is safe)"
else
  "Efficacy benchmark (effective drugs enriched at the top)"

# ---- 联动数据区：标题与表都随 tab 切换 ----
# ---- 三个输出统一用**匿名 render 函数**（与优化前同一模式）----
# 试过显式 output[[id]] <- ... 在 renderUI 内动态注册，testServer 实测 promise 解析报错；
# 匿名形式在本项目已多次验证可用（图/标题/表各一个，页面内不重复）。
#
# ★ 不能用 req(input$res_tabs)：bslib 的 tabsetPanel **只在用户点击时**才把选中值发到
#   服务端，初始化不主动上报 → 默认激活的那个 tab 的值服务端永远拿不到 →
#   req() 永久挂起 → 图和表全空白（也不报错）。故改为缺省回落到 tab_ids[1]。
# tabset 的 input 名就是它的 DOM id —— tid("res_tabs") = "<prefix>_res_tabs_<jobid>"。
# ★ 之前误写成 input$res_tabs（漏了 prefix+jobid）→ 服务端永远读到 NULL：
#   表现一：req() 永久挂起 → 图和表全空白；改用回退后又表现二：切 tab 永不联动。
tab_inp  <- tid("res_tabs")
cur_tab <- function() { v <- input[[tab_inp]]; if (is.null(v)) tab_ids[1] else v }
tagList(
.job_info_block(job_info),
shiny::h3(anno_head),
do.call(shiny::tabsetPanel, c(list(id = tid("res_tabs"), selected = tab_ids[1], type = "pills"), tabs)),
renderPlotly({ get_pic(cur_tab()) }),   # 惰性：图在渲染时才构建（写成 eager 会退化回 3.5 s 阻塞）
shiny::br(),
DT::renderDataTable({
  tb <- cur_tab()
  if (tb == "Summary") DT_overview
  else if (!is.null(DT_metric[[tb]])) DT_metric[[tb]]
  else DT::datatable(data.frame(note = "table unavailable")) }),
if (!is.null(metric_err))
shiny::tags$pre(paste0("Ranking-quality metrics failed: ", metric_err),
style = "color:#b02a37;white-space:pre-wrap;")
)
    
  } else if(job_info$yourmodule == "AUC" || job_info$yourmodule == "AUC_FC") {
    
    res_bm = job_info$yourtable %>% as_tibble()
    res_title = job_info$yourmodule
    tip_id <- if (res_title == "AUC_FC") "AUC" else res_title

    pic_out <- if (is_fc_mode(res_bm))
      ggplotly(draw_dr_auc_fc(res_bm), tooltip = c("x", "y")) else ggplotly(draw_dr_auc(res_bm), tooltip = c("x", "y"))

    DT_res_bm <- datatable(res_bm) %>% 
      formatStyle(names(res_bm)[which.max(res_bm[1,-1]) + 1],
                  backgroundColor = styleEqual(res_bm[1, which.max(res_bm[1,-1])+ 1], c('yellow')))

    tagList(
      .job_info_block(job_info),
      shiny::h3(paste0("Plot summary of ",res_title),
                actionButton(tid(paste0("intro_res_bm_",tip_id)),"Quick Tip",class = "btn-success")),
      renderPlotly(pic_out),
      shiny::br(),
      shiny::h3(paste0("Results of "),res_title),
      DT::renderDataTable(DT_res_bm)
    )
  } else if(job_info$yourmodule == "ES" || job_info$yourmodule == "ES_FC") {
    
    res_bm = job_info$yourtable %>% as_tibble()
    res_title = job_info$yourmodule

    pic_out <- if (is_fc_mode(res_bm))
      ggplotly(draw_dr_es_fc(res_bm), tooltip = c("x", "y")) else ggplotly(draw_dr_es(res_bm), tooltip = c("x", "y"))

    DT_res_bm <- datatable(res_bm) %>% 
      formatStyle(names(res_bm)[which.min(res_bm[1,-1]) + 1],
                  backgroundColor = styleEqual(res_bm[1, which.min(res_bm[1,-1])+ 1], c('yellow')))

    tagList(
      .job_info_block(job_info),
      shiny::h3(paste0("Plot summary of ",res_title),
                actionButton(tid(paste0("intro_res_bm_",tip_id)),"Quick Tip",class = "btn-success")),
      renderPlotly(pic_out),
      shiny::br(),
      shiny::h3(paste0("Results of "),res_title),
      DT::renderDataTable(DT_res_bm)
    )
    
  } else if(job_info$yourmodule == "singlemethod") {
    
    tagList(
      .job_info_block(job_info),
      shiny::h3("Plot summary",actionButton(tid("intro_res_sm_sm"),"Quick Tip",class = "btn-success")),
      renderPlotly(ggplotly(draw_single(job_info$yourtable))),
      shiny::h3("Results"),
      .drug_dt_ui(job_info$yourtable, tid("dt_drug")),
    )
    
  } else if(job_info$yourmodule == "SS_cross"){
    tagList(
      .job_info_block(job_info),
      shiny::h3("Plot summary",actionButton(tid("intro_res_sm_cross"),"Quick Tip",class = "btn-success")),
      renderPlotly(ggplotly(draw_cross(job_info$yourtable, 
                                       bioname1=job_info$signame1,bioname2=job_info$signame2))),
      shiny::br(),
      shiny::h3("Results"),
      .drug_dt_ui(job_info$yourtable, tid("dt_drug")),
    )
  } else if(job_info$yourmodule == "SS_all"){
    tagList(
      .job_info_block(job_info),
      shiny::h3("Plot summary",actionButton(tid("intro_res_sm_all"),"Quick Tip",class = "btn-success")),
      renderPlotly(ggplotly(draw_all(job_info$yourtable))),
      shiny::br(),
      shiny::h3("Results"),
      .drug_dt_ui(job_info$yourtable, tid("dt_drug")),
    )
  }
}
