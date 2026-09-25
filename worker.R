#!/usr/bin/env Rscript
# =============================================================================
# 后台作业 worker（方案 C）
# 从 job_queue 取 pending 任务 -> 计算 -> 写库 -> 标记 done/error。
# 与 Shiny 进程完全独立：用户可关闭页面，服务器重启后 worker 继续处理未完成任务。
#
# 用法（从项目根目录）：
#   Rscript worker.R
# 并发 = 起多个进程：
#   for i in 1 2 3 4; do nohup Rscript worker.R > log/worker_$i.log 2>&1 & done
# 生产环境推荐用 systemd 托管（Restart=always，开机自启）。
# =============================================================================

# --- 定位到项目根目录（worker.R 与 app.R 同级）-------------------------------
local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f) == 1 && nzchar(f)) setwd(dirname(normalizePath(f)))
})

# --- 保证 memoise / 队列所需目录存在（等价 beforerun.R 里的 dir.create）------
for (d in c("cache", "cache/BM", "cache/SM", "cache/SS", "cache/queue", "log")) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# --- 加载全部业务代码（global.R 先行：包 + 数据 + 辅助函数）------------------
suppressPackageStartupMessages({
  source("R/global.R")                       # 包、预加载数据、find_original_names 等
  source("R/SS.R")                           # 签名搜索算法
  source("R/Utils_BM.R")                     # get_benchmark ...
  source("R/Utils_SM.R")                     # get_single_method ...
  source("R/db_utils.R")
  source("R/queue_utils.R")                  # 队列 + 写库助手（本方案核心）
})

message(sprintf("[%s] worker %d started, polling job_queue ...",
                format(Sys.time()), Sys.getpid()))

# --- 主循环 -----------------------------------------------------------------
repeat {
  job <- tryCatch(claim_next_job(), error = function(e) {
    message("claim error: ", conditionMessage(e)); NULL
  })

  if (is.null(job)) { Sys.sleep(3); next }   # 空闲轮询

  message(sprintf("[%s] running %s (%s / %s)",
                  format(Sys.time()), job$jobid, job$module, job$sub_module))

  ok <- tryCatch({
    run_job(job)
    TRUE
  }, error = function(e) {
    mark_job(job$jobid, "error", conditionMessage(e))
    message(sprintf("[%s] ERROR %s: %s",
                    format(Sys.time()), job$jobid, conditionMessage(e)))
    FALSE
  })

  if (ok) {
    mark_job(job$jobid, "done")
    message(sprintf("[%s] done %s", format(Sys.time()), job$jobid))
  }
}
