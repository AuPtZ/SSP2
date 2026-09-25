# =============================================================================
# 作业队列工具（方案 C）
# 把"计算"与"Shiny 会话"解耦：Shiny 端只负责入队(enqueue)，独立的 worker.R
# 进程从队列取任务并计算、写库。用户可关闭页面，之后在 Job Center 取结果；
# 若不关页面，模块页会轮询 job_queue 状态并在完成后自动显示。
#
# 依赖：RSQLite。计算函数 get_benchmark / get_single_method 由 worker 侧
# source(R/*.R) 提供。build_df1 复用 global.R 里的 find_original_names 等。
# =============================================================================

QUEUE_DB  <- "results/resinfo.db"   # 与结果库同一个 SQLite 文件
QUEUE_DIR <- "cache/queue"          # 存放每个任务的参数 rds

# NULL -> NA 的小工具（构建元数据时防止 data.frame 报错）
.nz <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else x

# ---------------------------------------------------------------------------
# 自愈机制（方案 C）：提交任务时若没有存活的 worker，则自动拉起一个常驻
# worker。worker 本身是 repeat 循环，拉起后会一直处理后续所有任务，因此
# 只需保证"至少一个 worker 进程在跑"即可，无需手动启动，也不会因忘记
# 启动而让任务一直 queued。
# ---------------------------------------------------------------------------

# 返回当前存活的 worker.R 进程 PID 向量（排除自身）
.worker_pids_alive <- function() {
  out <- tryCatch(
    system2("pgrep", c("-f", "worker\\.R"), stdout = TRUE, stderr = FALSE),
    error = function(e) character(0)
  )
  pids <- as.integer(out[grepl("^[0-9]+$", out)])
  pids[pids > 0 & pids != Sys.getpid()]
}

# 若存活 worker 数 < target，则自动拉起一个（wait=FALSE 不阻塞 Shiny 会话）。
# 调用方无需关心 worker 是否已在运行：本函数保证最终至少有一个。
ensure_worker_running <- function(target = 1) {
  alive <- .worker_pids_alive()
  if (length(alive) >= target) return(invisible(alive))
  logf <- file.path("log", sprintf("worker_auto_%d.log", Sys.getpid()))
  if (!dir.exists("log")) dir.create("log", showWarnings = FALSE)
  suppressWarnings(
    system(sprintf("Rscript worker.R > %s 2>&1", shQuote(logf)), wait = FALSE)
  )
  message(sprintf("[queue] no live worker found, auto-spawned worker.R (target=%d)", target))
  invisible(.worker_pids_alive())
}

# ---------------------------------------------------------------------------
# 建表：job_queue（若不存在）
# ---------------------------------------------------------------------------
ensure_job_queue_table <- function(con) {
  RSQLite::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS job_queue (
      jobid          TEXT PRIMARY KEY,
      module         TEXT,
      sub_module     TEXT,
      status         TEXT DEFAULT 'pending',
      submitted_time TEXT,
      started_time   TEXT,
      finished_time  TEXT,
      error_msg      TEXT,
      worker_pid     INTEGER
    )")
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# 入队（Shiny 会话内调用）
#   params : 计算函数的入参列表（已解析好的数据对象，不是临时文件路径）
#   meta   : 构建 res 元数据所需的、来自 input 的值（worker 无法访问 input）
# ---------------------------------------------------------------------------
enqueue_job <- function(jobid, module, sub_module, params, meta,
                        submitted_time = as.character(Sys.time())) {
  # 自愈：确保至少有一个 worker 在运行，否则自动拉起（方案 C）
  ensure_worker_running()

  if (!dir.exists(QUEUE_DIR)) dir.create(QUEUE_DIR, recursive = TRUE, showWarnings = FALSE)
  saveRDS(
    list(jobid = jobid, module = module, sub_module = sub_module,
         submitted_time = submitted_time, params = params, meta = meta),
    file.path(QUEUE_DIR, paste0(jobid, ".rds"))
  )

  con <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
  on.exit(RSQLite::dbDisconnect(con))
  RSQLite::dbExecute(con, "PRAGMA busy_timeout=8000;")
  ensure_job_queue_table(con)
  RSQLite::dbExecute(con,
    "INSERT OR REPLACE INTO job_queue (jobid, module, sub_module, status, submitted_time)
     VALUES (?, ?, ?, 'pending', ?)",
    params = list(jobid, module, sub_module, submitted_time))
  invisible(jobid)
}

# ---------------------------------------------------------------------------
# 查询任务状态（Shiny 轮询用）。返回含 status/error_msg 的 data.frame（0 或 1 行）
# ---------------------------------------------------------------------------
get_job_status <- function(jobid) {
  con <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
  on.exit(RSQLite::dbDisconnect(con))
  RSQLite::dbExecute(con, "PRAGMA busy_timeout=8000;")
  if (!RSQLite::dbExistsTable(con, "job_queue")) return(data.frame())
  RSQLite::dbGetQuery(con,
    "SELECT status, error_msg FROM job_queue WHERE jobid = ?",
    params = list(jobid))
}

# ---------------------------------------------------------------------------
# worker 侧：原子抢占一条 pending 任务（BEGIN IMMEDIATE 防止多 worker 抢同一条）
# ---------------------------------------------------------------------------
claim_next_job <- function() {
  con <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
  on.exit(RSQLite::dbDisconnect(con))
  RSQLite::dbExecute(con, "PRAGMA busy_timeout=8000;")
  ensure_job_queue_table(con)
  RSQLite::dbExecute(con, "BEGIN IMMEDIATE;")
  job <- tryCatch(
    RSQLite::dbGetQuery(con,
      "SELECT * FROM job_queue WHERE status='pending' ORDER BY submitted_time LIMIT 1"),
    error = function(e) { RSQLite::dbExecute(con, "ROLLBACK;"); stop(e) }
  )
  if (nrow(job) == 1) {
    RSQLite::dbExecute(con,
      "UPDATE job_queue SET status='running', started_time=?, worker_pid=? WHERE jobid=?",
      params = list(as.character(Sys.time()), Sys.getpid(), job$jobid))
  }
  RSQLite::dbExecute(con, "COMMIT;")
  if (nrow(job) == 1) job else NULL
}

# ---------------------------------------------------------------------------
# worker 侧：更新任务终态
# ---------------------------------------------------------------------------
mark_job <- function(jobid, status, error_msg = NA_character_) {
  con <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
  on.exit(RSQLite::dbDisconnect(con))
  RSQLite::dbExecute(con, "PRAGMA busy_timeout=8000;")
  RSQLite::dbExecute(con,
    "UPDATE job_queue SET status=?, finished_time=?, error_msg=? WHERE jobid=?",
    params = list(status, as.character(Sys.time()), error_msg, jobid))
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# 由 meta 构建 res 元数据 df1（与 tab_utils.R::write_in_db 的字段完全一致，
# 只是数据来源从 input 换成入队时捕获的 meta）
# ---------------------------------------------------------------------------
build_df1 <- function(jobid, submitted_time, module, sub_module, table_num, meta) {
  fm <- meta$filter_mode
  fv <- meta$filter_value
  base <- function(...) data.frame(
    Jobid = jobid, Submitted_time = submitted_time,
    main_module = module, table_num = table_num, ...,
    stringsAsFactors = FALSE
  )

  if (module == "Benchmark") {
    if (grepl("^AUC", sub_module)) {
      base(drug_profile = meta$sel_experiment, method_bm = meta$sel_ss_names,
           signature_file1 = meta$file_sig_name, ic50_file = meta$file_IC50_name,
           sub_module = sub_module, filter_mode = fm, filter_value = fv)
    } else if (grepl("^ES", sub_module)) {
      base(drug_profile = meta$sel_experiment, method_bm = meta$sel_ss_names,
           signature_file1 = meta$file_sig_name, fda_file = meta$file_FDA_name,
           sub_module = sub_module, filter_mode = fm, filter_value = fv)
    } else { # ALL (ES and AUC)
      base(drug_profile = meta$sel_experiment, method_bm = meta$sel_ss_names,
           signature_file1 = meta$file_sig_name, fda_file = meta$file_FDA_name,
           ic50_file = meta$file_IC50_name, sub_module = sub_module,
           filter_mode = fm, filter_value = fv)
    }
  } else { # Application
    if (sub_module == "singlemethod") {
      base(drug_profile = meta$sel_experiment_sm, sub_module = meta$sel_model_sm,
           method_sm2 = meta$method_sm2, signature_file2 = meta$file_sig_sm_name,
           sel_num_gene = meta$sel_topn_sm, filter_mode = fm, filter_value = fv)
    } else if (sub_module == "SS_cross") {
      base(drug_profile = meta$sel_experiment_sm, sub_module = meta$sel_model_sm,
           method_sm2 = meta$method_sm2, signature_file3 = meta$file_sig_sm1_name,
           signature_file4 = meta$file_sig_sm2_name, signature_name1 = meta$file_name1,
           signature_name2 = meta$file_name2, sel_num_gene = meta$sel_topn_sm,
           filter_mode = fm, filter_value = fv)
    } else { # SS_all
      base(drug_profile = meta$sel_experiment_sm, sub_module = meta$sel_model_sm,
           method_sm1 = meta$method_sm1_all, direction_sm = meta$direction_sm,
           signature_file2 = meta$file_sig_sm_name, sel_num_gene = meta$sel_topn_sm,
           filter_mode = fm, filter_value = fv)
    }
  }
}

# 确保 res 表存在并按需扩列；返回 TRUE 表示本次是新建（新建时 df1 已作为首行写入）
.ensure_res_cols <- function(con, df1) {
  if (!RSQLite::dbExistsTable(con, "res")) {
    RSQLite::dbWriteTable(con, "res", df1)
    return(TRUE)
  }
  existing <- RSQLite::dbListFields(con, "res")
  for (col in setdiff(names(df1), existing)) {
    RSQLite::dbExecute(con, sprintf('ALTER TABLE res ADD COLUMN "%s"', col))
  }
  FALSE
}

# ---------------------------------------------------------------------------
# worker 侧：写结果表 + 追加 res 元数据（等价于 write_in_db，但不依赖 input）
# ---------------------------------------------------------------------------
write_result_from_meta <- function(jobid, submitted_time, module, sub_module,
                                   table_num, table_res, meta) {
  df1 <- build_df1(jobid, submitted_time, module, sub_module, table_num, meta)
  con <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
  on.exit(RSQLite::dbDisconnect(con))
  RSQLite::dbExecute(con, "PRAGMA busy_timeout=8000;")
  created <- .ensure_res_cols(con, df1)
  if (table_num == 2) {
    RSQLite::dbWriteTable(con, paste0(jobid, "_AUC"), table_res[["AUC"]])
    RSQLite::dbWriteTable(con, paste0(jobid, "_ES"),  table_res[["ES"]])
  } else {
    RSQLite::dbWriteTable(con, jobid, table_res)
  }
  if (!created) RSQLite::dbAppendTable(con, "res", df1)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# worker 侧：执行单个任务（计算 + 写库）
# ---------------------------------------------------------------------------
run_job <- function(job) {
  j    <- readRDS(file.path(QUEUE_DIR, paste0(job$jobid, ".rds")))
  p    <- j$params
  meta <- j$meta

  if (j$module == "Benchmark") {
    res_bm <- get_benchmark(
      IC50_drug    = p$IC50_drug,
      FDA_drug     = p$FDA_drug,
      i.need.logfc = p$i.need.logfc,
      sel_exp      = p$sel_exp,
      sel_ss       = p$sel_ss,
      filter_mode  = p$filter_mode
    )
    if (length(res_bm) == 3) {
      write_result_from_meta(j$jobid, j$submitted_time, "Benchmark",
        "ALL (ES and AUC)", 2, list(AUC = res_bm[[1]], ES = res_bm[[2]]), meta)
    } else if (length(res_bm) == 2) {
      write_result_from_meta(j$jobid, j$submitted_time, "Benchmark",
        res_bm[[2]], 1, res_bm[[1]], meta)
    } else {
      stop("Benchmark returned unexpected result length: ", length(res_bm))
    }

  } else if (j$module == "Application") {
    res_sm <- get_single_method(
      drug_profile  = p$drug_profile,
      topn          = p$topn,
      filter_mode   = p$filter_mode,
      fc_threshold  = p$fc_threshold,
      sel_model_sm1 = p$sel_model_sm1,
      i.need.logfc  = p$i.need.logfc,
      funcname      = p$funcname,
      funcname_mul  = p$funcname_mul,
      direct        = p$direct,
      bioname1      = p$bioname1,
      bioname2      = p$bioname2
    )
    write_result_from_meta(j$jobid, j$submitted_time, "Application",
      j$sub_module, 1, res_sm[[1]], meta)

  } else {
    stop("Unknown module: ", j$module)
  }

  # 计算完成后清理参数文件
  try(file.remove(file.path(QUEUE_DIR, paste0(job$jobid, ".rds"))), silent = TRUE)
  invisible(NULL)
}
