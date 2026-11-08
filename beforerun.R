# SSP2 依赖检查（可选，部署前手动运行一次即可）
#
# 用法：Rscript beforerun.R
# 只做检查与报告，不会自动安装任何包；缺什么请自行用 install.packages() /
# BiocManager::install() 安装，避免旧版脚本在无人值守时改动生产 R 环境。
# 应用本身（app.R / worker.R）不依赖本脚本；缓存目录由 worker.R 自行创建。

required <- c(
  "shiny", "bslib", "bsicons", "shinyjs", "shinyWidgets", "shinycssloaders",
  "shinyBS", "dplyr", "tidyr", "tibble", "data.table", "ggplot2", "ggrepel",
  "DT", "plotly", "rio", "zip", "stringr", "memoise", "digest", "jsonlite",
  "RSQLite", "DBI", "pROC", "clusterProfiler", "org.Hs.eg.db", "markdown",
  "htmltools", "arrow", "sessioninfo", "BiocManager"
)

installed <- rownames(utils::installed.packages())
missing <- setdiff(required, installed)

cat(sprintf("R %s | 已检查 %d 个依赖，缺失 %d 个\n",
            getRversion(), length(required), length(missing)))
if (length(missing)) {
  cat("缺失包:\n")
  cat(paste0("  - ", missing, collapse = "\n"), "\n")
  cat("\n请手动安装，例如：\n")
  cat(sprintf("  install.packages(c(%s))\n",
              paste(shQuote(missing), collapse = ", ")))
  cat("Bioconductor 包（clusterProfiler / org.Hs.eg.db）请用：\n")
  cat("  BiocManager::install(c(\"clusterProfiler\", \"org.Hs.eg.db\"))\n")
} else {
  cat("所有依赖均已安装。\n")
}

invisible(missing)
