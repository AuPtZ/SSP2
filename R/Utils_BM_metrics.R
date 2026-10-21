# =============================================================================
# 排序质量指标（2026-10-13 Benchmark 指标重构）
#
# ★ 指标选型原则（用户要求）：每个指标必须有已发表文献使用过的先例，否则不用。
#   已核定保留（出处见 tahoe_prep/ 文档与下方注释）：
#     AUROC / AUPRC / RecallAtK / EFpct / ES_rank
#   已核定弃用：
#     MRR     —— 文献集中在推荐系统/知识图谱链接预测，签名-药物检索基准未见使用
#     ES_abs  —— 即 gsea1 的 |score| 加权 ES（GSEA p=1）。算法有出处（Subramanian 2005），
#                但原版依赖"排序统计量同质 + NES 置换标准化"两个前提，本平台把未标准化的
#                裸 ES 用在尺度不均的药物分数上 → 零分布中心 +0.26（实测，09 脚本表 A）。
#                退役，由 ES_rank（= GSEA p=0 未加权 ES，即 KS 统计量）+ 置换 p 取代。
#
# 各指标文献出处：
#   AUROC      经典 ROC 分析（平台现有 pROC AUC 同口径），DTI/重定位论文通用
#   AUPRC      Davis & Goadrich, ICML 2006；药物重定位（如 AdaDR 2024）与 DTI 论文通用
#   RecallAtK  网络药物重定位基准的"已知药物检索率"（如 UCLA QCB gene-network 重定位工具，
#              用 retrieval rate of known drugs + 模拟签名加噪评测）；网络医学 top-k 命中
#   EFpct      虚拟筛选标准指标：DUD-E（Mysinger et al., JCIM 2012）；随机 = 1
#   ES_rank    GSEA 原文的未加权 ES（p=0）= Kolmogorov-Smirnov 统计量：
#              Mootha et al., Nat Genet 2003（KS 式 ES 原始版）；
#              Subramanian et al., PNAS 2005（同时定义 p=0 与 p=1，p=1 即退役的 ES_abs）
#              —— 与平台已有 CMap（KSScore）同族，非新发明
#
# 零分布：随机标签下真药在降序排名中的位置是均匀随机子集，与具体分数无关，
#        因此直接模拟位置子集 → 在 topN 扫描里是一条水平参考带（null 与 topN 无关）。
#
# 依赖：由 worker.R 在 source("R/Utils_BM.R") 之后加载（用到 gsea1 / local_cache_folder_BM）。
# =============================================================================

# 单条药物排名的 5 个指标
calc_rank_metrics <- function(s, truth, k = 20L, pct = 5) {
  truth <- intersect(truth, names(s))
  n <- length(s); n_t <- length(truth)
  na5 <- c(AUROC = NA_real_, AUPRC = NA_real_, RecallAtK = NA_real_,
           EFpct = NA_real_, ES_rank = NA_real_)
  if (n_t == 0 || n_t == n) return(na5)
  o <- order(-s); hit <- names(s)[o] %in% truth          # hit 已按分数降序排列
  auc <- (sum(rank(s)[truth]) - n_t * (n_t + 1) / 2) / (n_t * (n - n_t))
  ch <- cumsum(hit); idx <- which(hit)
  ap  <- mean(ch[idx] / seq_along(hit)[idx])
  kk  <- min(as.integer(k), n)
  rec <- sum(hit[1:kk]) / n_t
  m   <- max(1L, as.integer(floor(pct / 100 * n)))
  ef  <- (sum(hit[1:m]) / m) / (n_t / n)
  ins <- as.integer(hit)
  rs  <- cumsum(ins) / n_t - cumsum(1 - ins) / (n - n_t)
  es  <- ifelse(abs(max(rs)) > abs(min(rs)), max(rs), min(rs))
  c(AUROC = auc, AUPRC = ap, RecallAtK = rec, EFpct = ef, ES_rank = es)
}

# 零分布标定：返回 summary（均值/分位数）与 draws（原始抽样，供算置换 p 值）
null_rank_metrics <- function(n, n_hits, k = 20L, pct = 5, nperm = 1000, seed = 1) {
  stopifnot(n_hits > 0, n_hits < n)
  set.seed(seed)
  pos <- replicate(nperm, sort(sample.int(n, n_hits)), simplify = FALSE)
  f <- function(p) {
    n_t <- length(p)
    auc <- (n_t * (n + 1) - sum(p) - n_t * (n_t + 1) / 2) / (n_t * (n - n_t))
    hit <- rep(FALSE, n); hit[p] <- TRUE
    ch <- cumsum(hit); idx <- which(hit)
    ap  <- mean(ch[idx] / seq_along(hit)[idx])
    kk  <- min(as.integer(k), n)
    rec <- sum(p <= kk) / n_t
    m   <- max(1L, as.integer(floor(pct / 100 * n)))
    ef  <- (sum(p <= m) / m) / (n_t / n)
    ins <- as.integer(hit)
    rs  <- cumsum(ins) / n_t - cumsum(1 - ins) / (n - n_t)
    es  <- ifelse(abs(max(rs)) > abs(min(rs)), max(rs), min(rs))
    c(AUROC = auc, AUPRC = ap, RecallAtK = rec, EFpct = ef, ES_rank = es)
  }
  draws <- t(vapply(pos, f, numeric(5)))
  list(
    summary = data.frame(metric = colnames(draws),
                         null_mean = colMeans(draws),
                         null_q025 = apply(draws, 2, quantile, 0.025),
                         null_q975 = apply(draws, 2, quantile, 0.975),
                         row.names = NULL),
    draws = draws
  )
}

# 单个 SSM 在给定 topn 下的药物分数（调用方式与 get_es_all_i 逐字一致）
.ssm_score_by_name <- function(fn, refMatrix, sig_input, topn) {
  sig1_up <- sig_input %>% dplyr::filter(log2FC > 0) %>%
    dplyr::arrange(dplyr::desc(log2FC)) %>% dplyr::pull(Gene)
  sig1_dn <- sig_input %>% dplyr::filter(log2FC < 0) %>%
    dplyr::arrange(log2FC) %>% dplyr::pull(Gene)
  raw <- switch(fn,
    "SS_Xsum"  = XSumScore(refMatrix, queryUp = na.omit(sig1_up[1:topn]),
                           queryDown = na.omit(sig1_dn[1:topn]), topN = nrow(refMatrix) / 2),
    "SS_CMap"  = KSScore(refMatrix, queryUp = na.omit(sig1_up[1:topn]),
                         queryDown = na.omit(sig1_dn[1:topn])),
    "SS_GSEA"  = GSEAweight1Score(refMatrix, queryUp = na.omit(sig1_up[1:topn]),
                                  queryDown = na.omit(sig1_dn[1:topn])),
    "SS_ZhangScore" = ZhangScore(refMatrix, queryUp = na.omit(sig1_up[1:topn]),
                                 queryDown = na.omit(sig1_dn[1:topn])),
    "SS_XCos"  = {
      s1 <- sig_input %>% dplyr::filter(log2FC < 0) %>% dplyr::slice_min(log2FC, n = topn)
      s2 <- sig_input %>% dplyr::filter(log2FC > 0) %>% dplyr::slice_max(log2FC, n = topn)
      s4 <- rbind(s2, s1)
      XCosScore(refMatrix, query = setNames(s4$log2FC, s4$Gene), topN = nrow(refMatrix) / 2)
    },
    "SS_PLAGE" = PLAGEScore(refMatrix, queryUp = na.omit(sig1_up[1:topn]),
                            queryDown = na.omit(sig1_dn[1:topn])),
    "SS_QuSAGE" = QuSAGEScore(refMatrix, queryUp = na.omit(sig1_up[1:topn]),
                              queryDown = na.omit(sig1_dn[1:topn])),
    stop("未知 SSM: ", fn)
  )
  setNames(raw[, 1], rownames(raw))
}

# 单个 topN：全部 SSM × 全部指标（返回 tidy 一块）
metrics_all_i <- function(topn, refMatrix, sig_input, drug_sig, get_ss,
                          k = 20L, pct = 5, es_abs = TRUE) {
  out <- do.call(rbind, lapply(get_ss, function(fn) {
    s <- .ssm_score_by_name(fn, refMatrix, sig_input, topn)
    v <- calc_rank_metrics(s, drug_sig, k = k, pct = pct)
    if (es_abs) v <- c(v, ES_abs = as.numeric(gsea1(reflist = sort(s, decreasing = TRUE),
                                                    set = drug_sig))[1])
    data.frame(topn = topn, method = fn, t(v), row.names = NULL)
  }))
  out
}
metrics_all <- memoise::memoise(metrics_all_i, cache = local_cache_folder_BM)

# topN 扫描驱动（与 get_dr_es_i 同构：按 topn 并行），返回 曲线 + 零分布
get_dr_metrics <- function(topn_seq, refMatrix, sig_input, drug_sig, get_ss,
                           cores = 1L, k = 20L, pct = 5, nperm = 1000) {
  patch <- parallel::mclapply(topn_seq, function(tn)
    metrics_all(tn, refMatrix = refMatrix, sig_input = sig_input,
                drug_sig = drug_sig, get_ss = get_ss, k = k, pct = pct),
    mc.cores = cores)
  curve <- do.call(rbind, patch)
  nul <- null_rank_metrics(n = ncol(refMatrix),
                           n_hits = length(intersect(drug_sig, colnames(refMatrix))),
                           k = k, pct = pct, nperm = nperm)
  list(curve = curve, null = nul)
}

# 置换 p 值（单侧：优于随机；+1 平滑避免 p=0）
# 单侧置换 p 值：P(null >= obs)，并列计入，+1 平滑避免 p=0（下限 1/(nperm+1)）。
# calc_benchmark_metrics 里的 p_null 列就是逐点调用它（向量化实现）。
metric_pvalue <- function(obs, draws) {
  if (is.na(obs)) return(NA_real_)
  (1 + sum(draws >= obs)) / (length(draws) + 1)
}

# -----------------------------------------------------------------------------
# 显式基因集版本（logFC 模式用，或被 topN 版本复用）。
# 返回 tidy 长表：Metric × Method × Value
# -----------------------------------------------------------------------------
metrics_sets_i <- function(sel_exp, sig_input, queryUp, queryDown, drug_sig,
                           get_ss, k = 20L, pct = 5, es_abs = TRUE,
                           anno_type = "effective") {
  e <- new.env(); load(paste0("data_preload/drugexp/", sel_exp), envir = e)
  refMatrix <- get("exp_LINCS2020", envir = e)
  out <- do.call(rbind, lapply(get_ss, function(fn) {
    raw <- switch(fn,
      "SS_Xsum"  = XSumScore(refMatrix, queryUp = na.omit(queryUp),
                             queryDown = na.omit(queryDown), topN = nrow(refMatrix) / 2),
      "SS_CMap"  = KSScore(refMatrix, queryUp = na.omit(queryUp),
                           queryDown = na.omit(queryDown)),
      "SS_GSEA"  = GSEAweight1Score(refMatrix, queryUp = na.omit(queryUp),
                                    queryDown = na.omit(queryDown)),
      "SS_ZhangScore" = ZhangScore(refMatrix, queryUp = na.omit(queryUp),
                                   queryDown = na.omit(queryDown)),
      "SS_XCos"  = {
        s4 <- sig_input %>% dplyr::filter(Gene %in% union(queryUp, queryDown)) %>%
          dplyr::arrange(dplyr::desc(log2FC))
        XCosScore(refMatrix, query = setNames(s4$log2FC, s4$Gene), topN = nrow(refMatrix) / 2)
      },
      "SS_PLAGE" = PLAGEScore(refMatrix, queryUp = na.omit(queryUp),
                              queryDown = na.omit(queryDown)),
      "SS_QuSAGE" = QuSAGEScore(refMatrix, queryUp = na.omit(queryUp),
                                queryDown = na.omit(queryDown)),
      stop("未知 SSM: ", fn)
    )
    s <- setNames(raw[, 1], rownames(raw))
    # ★ 毒性模式（用户 2026-10-17 拍板"方向相反"）：毒性场景下签名应当【不】匹配
    #   毒性药 → 把分数取反后走同一套指标，5 个指标统一按"毒性药沉底 = 好"解读。
    #   零分布不受影响（随机放置与分数无关，且 AP 的零分布对取反后的观测仍然有效）。
    if (identical(anno_type, "toxic")) s <- -s
    v <- calc_rank_metrics(s, drug_sig, k = k, pct = pct)
    if (es_abs) v <- c(v, ES_abs = as.numeric(gsea1(reflist = sort(s, decreasing = TRUE),
                                                    set = drug_sig))[1])
    data.frame(Metric = names(v), Method = fn, Value = as.numeric(v), row.names = NULL)
  }))
  out
}
metrics_sets <- memoise::memoise(metrics_sets_i, cache = local_cache_folder_BM)

# -----------------------------------------------------------------------------
# Benchmark 入口：沿 topN（或 logFC 阈值）扫描，产出 5 个指标的长表（含零分布列）。
# 在 run_job 的 ALL 分支调用；真值 = ES 注释的 Compound_name（与 get_dr_es_i 同源）。
# topn_seq / thr_seq 可显式传入（测试用），缺省与 get_dr_es_i 完全同参。
# 返回 data.frame：首列 TopN 或 logFC（与 AUC/ES 表的判别约定一致），后接
#   Metric, Method, Value, NullMean, NullQ025, NullQ975
# -----------------------------------------------------------------------------
calc_benchmark_metrics <- function(sel_exp, sig_input, drug_sig, get_ss,
                                   filter_mode = "topN", cores = 1L,
                                   k = 20L, pct = 5, nperm = 1000,
                                   topn_seq = NULL, thr_seq = NULL,
                                   anno_type = "effective") {
  e <- new.env(); load(paste0("data_preload/drugexp/", sel_exp), envir = e)
  refMatrix <- get("exp_LINCS2020", envir = e)
  drug_sig <- intersect(unique(as.character(drug_sig)), colnames(refMatrix))
  if (length(drug_sig) < 3) {
    message("[metrics] 真值药不足 3 个，跳过")
    return(NULL)
  }
  if (length(drug_sig) >= ncol(refMatrix)) {
    message("[metrics] 真值药覆盖了全部药物（ES 注释应只列真药），指标无意义，跳过")
    return(NULL)
  }
  stopifnot(anno_type %in% c("effective", "toxic"))

  if (filter_mode == "logFC") {
    thr <- if (is.null(thr_seq)) seq(0.5, min(get_fcth(sig_input), 3.0), by = 0.05) else thr_seq
    parts <- parallel::mclapply(thr, function(th) {
      up <- sig_input %>% dplyr::filter(log2FC >  th) %>% dplyr::pull(Gene)
      dn <- sig_input %>% dplyr::filter(log2FC < -th) %>% dplyr::pull(Gene)
      if (length(up) < 2 || length(dn) < 2) return(NULL)
      metrics_sets(sel_exp, sig_input, up, dn, drug_sig, get_ss, k = k, pct = pct,
                   anno_type = anno_type) %>%
        dplyr::mutate(logFC = th)
    }, mc.cores = cores)
    sweep_col <- "logFC"
  } else {
    tseq <- if (is.null(topn_seq)) seq(10, max(10L, min(get_topn(sig_input), 1000L)), by = 1) else topn_seq
    parts <- parallel::mclapply(tseq, function(tn) {
      up <- sig_input %>% dplyr::filter(log2FC > 0) %>% dplyr::arrange(dplyr::desc(log2FC)) %>%
        dplyr::slice_head(n = tn) %>% dplyr::pull(Gene)
      dn <- sig_input %>% dplyr::filter(log2FC < 0) %>% dplyr::arrange(log2FC) %>%
        dplyr::slice_head(n = tn) %>% dplyr::pull(Gene)
      if (length(up) < 2 || length(dn) < 2) return(NULL)
      metrics_sets(sel_exp, sig_input, up, dn, drug_sig, get_ss, k = k, pct = pct,
                   anno_type = anno_type) %>%
        dplyr::mutate(TopN = tn)
    }, mc.cores = cores)
    sweep_col <- "TopN"
  }

  curve <- dplyr::bind_rows(parts)
  if (is.null(curve) || nrow(curve) == 0) return(NULL)
  nul <- null_rank_metrics(n = ncol(refMatrix), n_hits = length(drug_sig),
                           k = k, pct = pct, nperm = nperm)
  out <- curve %>%
    dplyr::left_join(nul$summary %>% dplyr::select(metric, NullMean = null_mean,
                                                   NullQ025 = null_q025, NullQ975 = null_q975),
                     by = c("Metric" = "metric")) %>%
    dplyr::select(dplyr::all_of(c(sweep_col, "Metric", "Method", "Value",
                                  "NullMean", "NullQ025", "NullQ975"))) %>%
    as.data.frame()
  # ---- 逐点置换 p 值（零分布抽样就在此处，直接算；ES_abs 无抽样 → NA）----
  # 为什么必须存 p 而不用"是否超过 NullQ975"：Recall@K / EF 这类离散指标的 95% 分位
  # 恰好落在某个可达取值上（如 7 个真值药时 Q975 = 2/7），此时"刚好达标"会被严格
  # 大于号判成不显著。p 值按 P(null >= obs) 计入并列，是正确的单侧检验。
  nd <- nul$draws
  out$p_null <- vapply(seq_len(nrow(out)), function(i) {
    mt <- out$Metric[i]
    if (!mt %in% colnames(nd) || is.na(out$Value[i])) return(NA_real_)
    d <- nd[, mt]
    (1 + sum(d >= out$Value[i])) / (length(d) + 1)
  }, numeric(1))
  out
}
