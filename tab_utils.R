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

# FOR EACH PAGE
observeEvent(input$runBENdemo,{
  job_info <- .load_demo("demo/BEN1790672381JTV.rdata")
  output$display_bm <- renderUI({res_plot(job_info, prefix = "bm")})
})
observeEvent(input$runAPPdemo1,{
  job_info <- .load_demo("demo/APP1790669686URX.rdata")
  output$display_sm <- renderUI({res_plot(job_info, prefix = "sm")})
})
observeEvent(input$runAPPdemo2,{
  job_info <- .load_demo("demo/APP1790669691LXK.rdata")
  output$display_sm <- renderUI({res_plot(job_info, prefix = "sm")})
})
observeEvent(input$runAPPdemo3,{
  job_info <- .load_demo("demo/APP1790735151KID.rdata")
  output$display_sm <- renderUI({res_plot(job_info, prefix = "sm")})
})
# FOR JOB PAGE
observeEvent(input$runjcBENdemo,{
  job_info <- .load_demo("demo/BEN1790672381JTV.rdata")
  output$display_jc <- renderUI({res_plot(job_info, prefix = "jc")})
})
observeEvent(input$runjcAPPdemo1,{
  job_info <- .load_demo("demo/APP1790669686URX.rdata")
  output$display_jc <- renderUI({res_plot(job_info, prefix = "jc")})
})
observeEvent(input$runjcAPPdemo2,{
  job_info <- .load_demo("demo/APP1790669691LXK.rdata")
  output$display_jc <- renderUI({res_plot(job_info, prefix = "jc")})
})
observeEvent(input$runjcAPPdemo3,{
  job_info <- .load_demo("demo/APP1790735151KID.rdata")
  output$display_jc <- renderUI({res_plot(job_info, prefix = "jc")})
})



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

  if(job_info$yourmodule == "ALL (ES and AUC)" || 
     grepl("^ALL_FC$", job_info$yourmodule)) {
    
    res_bm1 <- job_info$yourtable$`AUC` %>% as_tibble()
    res_bm2 <- job_info$yourtable$`ES` %>% as_tibble()
    
    if (is_fc_mode(res_bm1)) {
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
    
    tagList(
      .job_info_block(job_info),
      shiny::h3("Results of AUC",actionButton(tid("intro_res_bm_AUC"),"Quick Tip",class = "btn-success")),
      renderPlotly(pic_out1),
      DT::renderDataTable(DT_res_bm1),
      shiny::br(),
      shiny::h3("Results of ES",actionButton(tid("intro_res_bm_ES"),"Quick Tip",class = "btn-success")),
      renderPlotly(pic_out2),
      DT::renderDataTable(DT_res_bm2),
    )
    
  } else if(job_info$yourmodule == "AUC" || job_info$yourmodule == "AUC_FC") {
    
    res_bm = job_info$yourtable %>% as_tibble()
    res_title = job_info$yourmodule
    tip_id <- if (res_title == "AUC_FC") "AUC" else res_title

    pic_out <- if (is_fc_mode(res_bm))
      ggplotly(draw_dr_auc_fc(res_bm)) else ggplotly(draw_dr_auc(res_bm))

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
      ggplotly(draw_dr_es_fc(res_bm)) else ggplotly(draw_dr_es(res_bm))

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