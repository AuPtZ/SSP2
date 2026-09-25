# =============================================================================
# 一键清空 cache/ 下所有文件（保留文件夹结构，仅删除文件）
# 用法：从项目根目录运行  Rscript maintain/05清空cache缓存.R
# =============================================================================

cache_dir <- "cache"

if (!dir.exists(cache_dir)) {
  cat("目录不存在，无需清理：", cache_dir, "\n")
} else {
  # 递归列出所有文件（include.dirs = FALSE 只取文件，不含目录本身）
  files <- list.files(cache_dir, recursive = TRUE, full.names = TRUE,
                      all.files = TRUE, include.dirs = FALSE, no.. = TRUE)

  if (length(files) == 0) {
    cat("cache/ 下没有文件，无需清理。\n")
  } else {
    ok <- file.remove(files)
    cat(sprintf("已删除 %d/%d 个文件（文件夹已保留）。\n", sum(ok), length(files)))
    failed <- files[!ok]
    if (length(failed) > 0) {
      cat("以下文件删除失败：\n")
      cat(paste0("  ", failed), sep = "\n")
    }
  }
}
