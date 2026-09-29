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

# 若存活 worker 数 < target，则自动拉起一个（不阻塞 Shiny 会话）。
# 调用方无需关心 worker 是否已在运行：本函数保证最终至少有一个。
#
# 用 processx 而不是 system()：system() 拉起后立刻返回、再也拿不到任何反馈，
# worker 若因缺包等原因启动即崩，任务会静默卡在 pending，前端只显示 "Loading..."
# 而毫无提示（2026-09-28 踩过：worker 在 library(shinyBS) 处 Execution halted，
# 用户干等 22 分钟）。processx 能拿到进程句柄，启动后短等一下即可判断是否存活，
# 失败直接 stop() 并附上日志尾部，让错误在提交的那一刻就暴露。
#
# 另：显式用 file.path(R.home("bin"), "Rscript") 而不是 PATH 里的 "Rscript"，
# 确保 worker 与当前 Shiny 会话跑的是同一个 R，库路径一致，避免因 .libPaths()
# 指向另一个 R 环境而缺包。
ensure_worker_running <- function(target = 1) {
  alive <- .worker_pids_alive()
  if (length(alive) >= target) return(invisible(alive))
  logf <- file.path("log", sprintf("worker_auto_%d.log", Sys.getpid()))
  if (!dir.exists("log")) dir.create("log", showWarnings = FALSE, recursive = TRUE)

  p <- processx::process$new(
    command = file.path(R.home("bin"), "Rscript"),
    args    = "worker.R",
    wd      = getwd(),
    stdout  = logf, stderr = logf,
    cleanup = FALSE    # 常驻进程：进程对象被回收 / Shiny 重启都不要杀掉它
  )
  # 给 worker 一点时间启动；缺包导致的失败通常在 source(R/*.R) 阶段就已退出
  Sys.sleep(2)
  if (!p$is_alive()) {
    st   <- tryCatch(p$get_exit_status(), error = function(e) NA_integer_)
    tail <- tryCatch(paste(tail(readLines(logf, warn = FALSE), 10), collapse = "\n"),
                     error = function(e) "")
    stop(sprintf(
      "worker.R 启动后立刻退出（exit=%s），任务不会被执行。详见 %s ：\n%s",
      st, logf, tail), call. = FALSE)
  }
  message(sprintf("[queue] no live worker found, auto-spawned worker.R (pid=%s, target=%d)",
                  p$get_pid(), target))
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
      worker_pid     INTEGER,
      progress_total INTEGER,
      progress_msg   TEXT
    )")
  # 兼容旧库：表已存在时补齐进度列
  cols <- RSQLite::dbListFields(con, "job_queue")
  if (!"progress_total" %in% cols)
    RSQLite::dbExecute(con, "ALTER TABLE job_queue ADD COLUMN progress_total INTEGER")
  if (!"progress_msg" %in% cols)
    RSQLite::dbExecute(con, "ALTER TABLE job_queue ADD COLUMN progress_msg TEXT")

  # 进度打点表：每完成一步追加一行，前端用 COUNT(*) 取已完成数。
  # 之所以用「追加 + 计数」而不是 UPDATE 同一行，是因为 Benchmark 的扫描跑在
  # mclapply 的 fork 子进程里，多个子进程并发 UPDATE 同一行会互相覆盖/锁等待。
  RSQLite::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS job_progress (
      jobid   TEXT,
      tick_at TEXT
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
# 进度上报（给前端轮询渲染真实进度条）
#
# 约束：Benchmark 的 topN/FC 扫描跑在 parallel::mclapply 的 fork 子进程里，
# 所以进度不能靠"函数返回值"传递，必须由计算侧主动写库。fork 会继承父进程
# 内存，因此子进程同样能读到这里的 job 上下文，并各自建连接写打点。
# ---------------------------------------------------------------------------
.ssp_job_ctx <- new.env(parent = emptyenv())

# worker 开始执行某任务时绑定；任务结束置 NULL
set_job_context <- function(jobid) { .ssp_job_ctx$jobid <- jobid; invisible(jobid) }
get_job_context <- function() .ssp_job_ctx$jobid

# 任务开始时调用：写入总步数，并清空上一轮遗留的打点
init_job_progress <- function(jobid, total, msg = "") {
  if (is.null(jobid) || is.na(jobid)) return(invisible(NULL))
  con <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
  on.exit(RSQLite::dbDisconnect(con))
  RSQLite::dbExecute(con, "PRAGMA busy_timeout=8000;")
  ensure_job_queue_table(con)
  RSQLite::dbExecute(con, "DELETE FROM job_progress WHERE jobid=?", params = list(jobid))
  RSQLite::dbExecute(con,
    "UPDATE job_queue SET progress_total=?, progress_msg=? WHERE jobid=?",
    params = list(as.integer(total), as.character(msg), jobid))
  invisible(NULL)
}

# 完成一步：追加一行打点。静默失败——进度上报绝不能拖垮/中断计算。
tick_job_progress <- function(jobid = get_job_context()) {
  if (is.null(jobid) || is.na(jobid)) return(invisible(NULL))
  con <- tryCatch({
    cc <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
    RSQLite::dbExecute(cc, "PRAGMA busy_timeout=8000;")
    cc
  }, error = function(e) NULL)
  if (is.null(con)) return(invisible(NULL))
  on.exit(RSQLite::dbDisconnect(con), add = TRUE)
  tryCatch({
    RSQLite::dbExecute(con,
      "INSERT INTO job_progress (jobid, tick_at) VALUES (?, ?)",
      params = list(jobid, as.character(Sys.time())))
  }, error = function(e) NULL)
  invisible(NULL)
}

# 前端轮询：返回 list(done, total, msg)；total=0 表示任务尚未开始计算
get_job_progress <- function(jobid) {
  con <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
  on.exit(RSQLite::dbDisconnect(con))
  RSQLite::dbExecute(con, "PRAGMA busy_timeout=8000;")
  if (!RSQLite::dbExistsTable(con, "job_queue"))
    return(list(done = 0L, total = 0L, msg = ""))
  q <- RSQLite::dbGetQuery(con,
    "SELECT progress_total, progress_msg FROM job_queue WHERE jobid=?",
    params = list(jobid))
  total <- if (nrow(q) && !is.na(q$progress_total[1])) as.integer(q$progress_total[1]) else 0L
  msg   <- if (nrow(q) && !is.na(q$progress_msg[1])) as.character(q$progress_msg[1]) else ""
  done <- 0L
  if (RSQLite::dbExistsTable(con, "job_progress")) {
    done <- as.integer(RSQLite::dbGetQuery(con,
      "SELECT COUNT(*) AS n FROM job_progress WHERE jobid=?",
      params = list(jobid))$n)
  }
  list(done = done, total = total, msg = msg)
}

# 任务结束后清理打点，避免表无限增长
clear_job_progress <- function(jobid) {
  con <- tryCatch({
    cc <- RSQLite::dbConnect(RSQLite::SQLite(), QUEUE_DB)
    RSQLite::dbExecute(cc, "PRAGMA busy_timeout=8000;")
    cc
  }, error = function(e) NULL)
  if (is.null(con)) return(invisible(NULL))
  on.exit(RSQLite::dbDisconnect(con), add = TRUE)
  tryCatch({
    if (RSQLite::dbExistsTable(con, "job_progress"))
      RSQLite::dbExecute(con, "DELETE FROM job_progress WHERE jobid=?", params = list(jobid))
    # 同时复位 job_queue 上的进度显示字段。只删打点表的话，任务结束后
    # progress_total/progress_msg 仍停留在最后一次扫描的读数（如 "Benchmark
    # scanning" / 102），任谁查库都会误以为任务还没跑完。置 NULL 即等于
    # "无进度可读"，前端 req(total > 0) 也就不再渲染进度条，正是结束态应有表现。
    RSQLite::dbExecute(con,
      "UPDATE job_queue SET progress_total=NULL, progress_msg=NULL WHERE jobid=?",
      params = list(jobid))
  }, error = function(e) NULL)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# 由 meta 构建 res 元数据 df1。字段布局的**唯一权威定义**在此；
# 旧的同义副本 write_in_db / db_write_result 已删除，勿再复制一份。
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
# worker 侧：写结果表 + 追加 res 元数据（全项目唯一的写结果入口）
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

  # 绑定 job 上下文：计算函数内的 tick_job_progress() 由此知道写哪个任务。
  # 总步数先置 0（表示"尚未进入扫描循环"），由各模块计算函数再 init 真实值。
  set_job_context(j$jobid)
  init_job_progress(j$jobid, 0L, "starting")
  on.exit({ clear_job_progress(j$jobid); set_job_context(NULL) }, add = TRUE)

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
