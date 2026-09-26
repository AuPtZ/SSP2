library(memoise)
local_cache_folder <- cache_filesystem("cache/SS/")

if(T){
  XSumScore_i <- function(refMatrix, queryUp, queryDown,topN = 500, pval = F){
    
    # print("XSumScore is using")
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    if (!is.character(queryUp)) {
      queryUp <- as.character(queryUp)
    }
    if (!is.character(queryDown)) {
      queryDown <- as.character(queryDown)
    }
    if (topN > nrow(refMatrix)/2) {
      stop("Warning: topN is lager than half\n
         the length of gene list!")
    }
    matrixToRankedList <- function(refMatrix, topN) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refList[[i]] <- c(head(refMatrix[order(refMatrix[,i],
                                               decreasing = TRUE), i], 
                               n = topN), 
                          tail(refMatrix[order(refMatrix[,i], 
                                               decreasing = TRUE), i], 
                               n = topN))
      }
      return(refList)
    }
    
    XSum <- function(refList, queryUp, queryDown) {
      scoreUp <- sum(refList[match(queryUp, names(refList))], 
                     na.rm = T)
      scoreDown <- sum(refList[match(queryDown, names(refList))], 
                       na.rm = T)
      return(scoreUp - scoreDown)
    }
    
    refList <- matrixToRankedList(refMatrix, topN = topN)
    score <- lapply(refList, XSum, queryUp = queryUp, queryDown = queryDown)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  
  KSScore_i <- function(refMatrix, queryUp, queryDown, pval = F){
    # print("KSScore is using")
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    if (!is.character(queryUp)) {
      queryUp <- as.character(queryUp)
    }
    if (!is.character(queryDown)) {
      queryDown <- as.character(queryDown)
    }
    matrixToRankedList <- function(refMatrix) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refList[[i]] <- names(refMatrix[order(refMatrix[, 
                                                        i], decreasing = TRUE), i])
      }
      return(refList)
    }
    ksScore <- function(refList, query) {
      lenRef <- length(refList)
      queryRank <- match(query, refList)
      queryRank <- sort(queryRank[!is.na(queryRank)])
      lenQuery <- length(queryRank)
      if (lenQuery == 0) {
        return(0)
      }
      else {
        d <- (1:lenQuery)/lenQuery - queryRank/lenRef
        a <- max(d)
        b <- -min(d) + 1/lenQuery
        ifelse(a > b, a, -b)
      }
    }
    ks <- function(refList, queryUp, queryDown) {
      scoreUp <- ksScore(refList, queryUp)
      scoreDown <- ksScore(refList, queryDown)
      ifelse(scoreUp * scoreDown <= 0, scoreUp - scoreDown, 
             0)
    }
    refList <- matrixToRankedList(refMatrix)
    queryUp <- intersect(queryUp, rownames(refMatrix))
    queryDown <- intersect(queryDown, rownames(refMatrix))
    score <- lapply(refList, ks, queryUp = queryUp, queryDown = queryDown)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  
  GSEAweight1Score_i <- function(refMatrix, queryUp, queryDown, pval = F){
    # print("GSEAweight1Score is using")
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    if (!is.character(queryUp)) {
      queryUp <- as.character(queryUp)
    }
    if (!is.character(queryDown)) {
      queryDown <- as.character(queryDown)
    }
    matrixToRankedList <- function(refMatrix) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refList[[i]] <- refMatrix[order(refMatrix[, i], decreasing = TRUE), 
                                  i]
      }
      return(refList)
    }
    weight1EnrichmentScore <- function(refList, query) {
      tagIndicator <- sign(match(names(refList), query, nomatch = 0))
      noTagIndicator <- 1 - tagIndicator
      N <- length(refList)
      Nh <- length(query)
      Nm <- N - Nh
      correlVector <- abs(refList)
      sumCorrelTag <- sum(correlVector[tagIndicator == 1])
      normTag <- 1/sumCorrelTag
      normNoTag <- 1/Nm
      RES <- cumsum(tagIndicator * correlVector * normTag - 
                      noTagIndicator * normNoTag)
      maxES <- max(RES)
      minES <- min(RES)
      maxES <- ifelse(is.na(maxES), 0, maxES)
      minES <- ifelse(is.na(minES), 0, minES)
      ifelse(maxES > -minES, maxES, minES)
    }
    weight1 <- function(refList, queryUp, queryDown) {
      scoreUp <- weight1EnrichmentScore(refList, queryUp)
      scoreDown <- weight1EnrichmentScore(refList, queryDown)
      ifelse(scoreUp * scoreDown <= 0, scoreUp - scoreDown, 
             0)
    }
    refList <- matrixToRankedList(refMatrix)
    queryUp <- intersect(queryUp, rownames(refMatrix))
    queryDown <- intersect(queryDown, rownames(refMatrix))
    score <- lapply(refList, weight1, queryUp = queryUp, queryDown = queryDown)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  ZhangScore_i <- function(refMatrix, queryUp, queryDown, pval = F){
    # print("ZhangScore is using")
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    if (is.null(queryUp)) {
      queryUp <- character(0)
    }
    if (is.null(queryDown)) {
      queryDown <- character(0)
    }
    if (!is.character(queryUp)) {
      queryUp <- as.character(queryUp)
    }
    if (!is.character(queryDown)) {
      queryDown <- as.character(queryDown)
    }
    matrixToRankedList <- function(refMatrix) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refSort <- refMatrix[order(abs(refMatrix[, i]), decreasing = TRUE), 
                             i]
        refRank <- rank(abs(refSort)) * sign(refSort)
        refList[[i]] <- refRank
      }
      return(refList)
    }
    computeScore <- function(refRank, queryRank) {
      if (length(intersect(names(refRank), names(queryRank))) > 
          0) {
        maxTheoreticalScore <- sum(abs(refRank)[1:length(queryRank)] * 
                                     abs(queryRank))
        score <- sum(queryRank * refRank[names(queryRank)], 
                     na.rm = TRUE)/maxTheoreticalScore
      }
      else {
        score <- NA
      }
      return(score)
    }
    refList <- matrixToRankedList(refMatrix)
    queryVector <- c(rep(1, length(queryUp)), rep(-1, length(queryDown)))
    names(queryVector) <- c(queryUp, queryDown)
    score <- lapply(refList, computeScore, queryRank = queryVector)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  XCosScore_i <- function (refMatrix, query, topN = 500, pval = F){
    # print("XCosScore is using")
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix must have both rownames and colnames!")
    }
    if (!is.numeric(query)) {
      stop("Warning: query must be a numeric vector!")
    }
    if (is.null(names(query))) {
      stop("Warning: query must have names!")
    }
    if (topN > nrow(refMatrix)/2) {
      stop("Warning: topN is lager than half\n
         the length of gene list!")
    }
    matrixToRankedList <- function(refMatrix, topN) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refList[[i]] <- c(head(refMatrix[order(refMatrix[, i], decreasing = TRUE), i], n = topN), 
                          tail(refMatrix[order(refMatrix[, i], decreasing = TRUE), i], n = topN))
      }
      return(refList)
    }
    XCos <- function(refList, query) {
      reservedRef <- refList[match(intersect(names(refList), 
                                             names(query)), names(refList))]
      reservedRef[order(names(reservedRef))]
      reservedQuery <- query[match(intersect(names(refList), 
                                             names(query)), names(query))]
      reservedQuery[order(names(reservedQuery))]
      if (length(reservedRef) == 0) {
        return(NA)
      }
      else {
        return((crossprod(reservedRef, reservedQuery)/sqrt(crossprod(reservedRef) * 
                                                             crossprod(reservedQuery)))[1, 1])
      }
    }
    refList <- matrixToRankedList(refMatrix, topN = topN)
    score <- lapply(refList, XCos, query = query)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  # ---- PLAGE 内部辅助 ----
  # 基因（行）在样本/药物（列）间做 z-score 标准化
  .zscore_rows <- function(x) {
    mu <- rowMeans(x)
    xc <- x - mu
    sd <- sqrt(rowSums(xc * xc) / max(1, ncol(x) - 1))
    sd[!is.finite(sd) | sd == 0] <- 1
    xc / sd
  }
  
  # 第一主成分活性：x 为 genes × drugs 子矩阵，返回长度 = ncol(x) 的活性向量
  # 等价于 svd(x) 的 d[1] * v[, 1]；因 k << n，改用 k×k Gram 矩阵特征分解更快
  .plage_activity <- function(x) {
    z  <- .zscore_rows(x)
    g  <- tcrossprod(z)                       # k × k
    u1 <- eigen(g, symmetric = TRUE)$vectors[, 1]
    activity <- as.vector(crossprod(z, u1))   # = t(z) %*% u1
    # SVD 的符号是任意的：统一取向，使活性与基因集的平均表达正相关
    if (sum(u1) < 0) activity <- -activity
    return(activity)
  }
  
  # ===============================================================
  # SS_PLAGE —— Pathway level analysis of gene expression
  # 出处：Tomfohr J, Lu J, Kepler TB (2005) "Pathway level analysis of
  #   gene expression using singular value decomposition"
  #   BMC Bioinformatics 6:225. DOI: 10.1186/1471-2105-6-225
  # 统计量：基因在样本（药物）间做 z-score 标准化后，对基因集子矩阵做 SVD，
  #   取第一主成分在各样本上的投影作为该基因集的"活性"；
  #   Score = activity(up 基因集) - activity(down 基因集)。
  # ===============================================================
  PLAGEScore_i <- function(refMatrix, queryUp, queryDown, pval = F){
    
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    queryUp   <- intersect(as.character(queryUp),   rownames(refMatrix))
    queryDown <- intersect(as.character(queryDown), rownames(refMatrix))
    
    zero <- rep(0, ncol(refMatrix))
    a_up <- if (length(queryUp)   >= 2) .plage_activity(refMatrix[queryUp,   , drop = FALSE]) else zero
    a_dn <- if (length(queryDown) >= 2) .plage_activity(refMatrix[queryDown, , drop = FALSE]) else zero
    
    score <- a_up - a_dn
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  # ===============================================================
  # SS_QuSAGE —— Quantitative set analysis for gene expression
  # 出处：Yaari G, Bolen CR, Thakar J, Kleinstein SH (2013) "Quantitative
  #   set analysis for gene expression: a method to quantify gene set
  #   differential expression including gene-gene correlations"
  #   Nucleic Acids Res 41(18):e170. DOI: 10.1093/nar/gkt660
  # 统计量：基因集均值经方差膨胀因子 VIF = 1 + (|S| - 1) * rho_bar 校正
  #   （rho_bar = 基因集内基因两两相关的均值，用于扣除基因间相关带来的
  #   伪重复信息），得到 t 样集合统计量；Score = stat(up) - stat(down)，
  #   并已标准化为 null 下近似标准正态，p 值在 get_pval() 中解析求出。
  # ===============================================================
  QUSAGE_MAX_COLS <- 2000L  # 估计 rho_bar 时最多使用的药物数（控制开销）
  
  QuSAGEScore_i <- function(refMatrix, queryUp, queryDown, pval = F){
    
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    queryUp   <- intersect(as.character(queryUp),   rownames(refMatrix))
    queryDown <- intersect(as.character(queryDown), rownames(refMatrix))
    
    n_genes <- nrow(refMatrix)
    # 每个药物：全部基因的均值与方差，作为 null 分布的中心与尺度
    mu_all  <- colMeans(refMatrix)
    var_all <- vapply(seq_len(ncol(refMatrix)), function(j) {
      v <- refMatrix[, j]
      sum((v - mean(v))^2) / (n_genes - 1)
    }, numeric(1))
    var_all[!is.finite(var_all) | var_all <= 0] <- NA_real_
    
    # rho_bar：基因集内两两相关均值（在药物子集上估计，确定性抽样、不涉及 RNG）
    .rho_bar <- function(genes) {
      k <- length(genes)
      if (k < 2) return(0)
      x <- refMatrix[genes, , drop = FALSE]
      if (ncol(x) > QUSAGE_MAX_COLS) {
        x <- x[, seq(1, ncol(x), length.out = QUSAGE_MAX_COLS), drop = FALSE]
      }
      sds <- sqrt(rowSums((x - rowMeans(x))^2) / max(1, ncol(x) - 1))
      keep <- is.finite(sds) & sds > 0
      if (sum(keep) < 2) return(0)
      cm  <- stats::cor(t(x[keep, , drop = FALSE]))
      rho <- mean(cm[upper.tri(cm)], na.rm = TRUE)
      if (!is.finite(rho)) rho <- 0
      return(rho)
    }
    
    .set_stat <- function(genes) {
      k <- length(genes)
      if (k < 1) return(rep(0, ncol(refMatrix)))
      vif <- max(1 + (k - 1) * .rho_bar(genes), 1e-6)
      m   <- colMeans(refMatrix[genes, , drop = FALSE])
      z   <- (m - mu_all) / sqrt(vif * var_all / k)
      z[!is.finite(z)] <- 0
      return(z)
    }
    
    z_up <- .set_stat(queryUp)
    z_dn <- .set_stat(queryDown)
    # 两个基因集近似独立，差值的 null 方差约为 2，除以 sqrt(2) 标准化
    score <- (z_up - z_dn) / sqrt(2)
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  XSumScore <- memoise::memoise(XSumScore_i,cache = local_cache_folder)
  KSScore <- memoise::memoise(KSScore_i,cache = local_cache_folder)
  GSEAweight1Score <- memoise::memoise(GSEAweight1Score_i,cache = local_cache_folder)
  ZhangScore <- memoise::memoise(ZhangScore_i,cache = local_cache_folder)
  XCosScore <- memoise::memoise(XCosScore_i,cache = local_cache_folder)
  PLAGEScore <- memoise::memoise(PLAGEScore_i,cache = local_cache_folder)
  QuSAGEScore <- memoise::memoise(QuSAGEScore_i,cache = local_cache_folder)
  

  
  
  
  
}else{
  ## 原始程序
  XSumScore <- function(refMatrix, queryUp, queryDown,topN = 500, pval = F){
    
    # print("XSumScore is using")
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    if (!is.character(queryUp)) {
      queryUp <- as.character(queryUp)
    }
    if (!is.character(queryDown)) {
      queryDown <- as.character(queryDown)
    }
    if (topN > nrow(refMatrix)/2) {
      stop("Warning: topN is lager than half\n
         the length of gene list!")
    }
    matrixToRankedList <- function(refMatrix, topN) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refList[[i]] <- c(head(refMatrix[order(refMatrix[,i],
                                               decreasing = TRUE), i], 
                               n = topN), 
                          tail(refMatrix[order(refMatrix[,i], 
                                               decreasing = TRUE), i], 
                               n = topN))
      }
      return(refList)
    }
    
    XSum <- function(refList, queryUp, queryDown) {
      scoreUp <- sum(refList[match(queryUp, names(refList))], 
                     na.rm = T)
      scoreDown <- sum(refList[match(queryDown, names(refList))], 
                       na.rm = T)
      return(scoreUp - scoreDown)
    }
    
    refList <- matrixToRankedList(refMatrix, topN = topN)
    score <- lapply(refList, XSum, queryUp = queryUp, queryDown = queryDown)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  
  KSScore <- function(refMatrix, queryUp, queryDown, pval = F){
    # print("KSScore is using")
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    if (!is.character(queryUp)) {
      queryUp <- as.character(queryUp)
    }
    if (!is.character(queryDown)) {
      queryDown <- as.character(queryDown)
    }
    matrixToRankedList <- function(refMatrix) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refList[[i]] <- names(refMatrix[order(refMatrix[, 
                                                        i], decreasing = TRUE), i])
      }
      return(refList)
    }
    ksScore <- function(refList, query) {
      lenRef <- length(refList)
      queryRank <- match(query, refList)
      queryRank <- sort(queryRank[!is.na(queryRank)])
      lenQuery <- length(queryRank)
      if (lenQuery == 0) {
        return(0)
      }
      else {
        d <- (1:lenQuery)/lenQuery - queryRank/lenRef
        a <- max(d)
        b <- -min(d) + 1/lenQuery
        ifelse(a > b, a, -b)
      }
    }
    ks <- function(refList, queryUp, queryDown) {
      scoreUp <- ksScore(refList, queryUp)
      scoreDown <- ksScore(refList, queryDown)
      ifelse(scoreUp * scoreDown <= 0, scoreUp - scoreDown, 
             0)
    }
    refList <- matrixToRankedList(refMatrix)
    queryUp <- intersect(queryUp, rownames(refMatrix))
    queryDown <- intersect(queryDown, rownames(refMatrix))
    score <- lapply(refList, ks, queryUp = queryUp, queryDown = queryDown)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  
  GSEAweight1Score <- function(refMatrix, queryUp, queryDown, pval = F){
    # print("GSEAweight1Score is using")
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    if (!is.character(queryUp)) {
      queryUp <- as.character(queryUp)
    }
    if (!is.character(queryDown)) {
      queryDown <- as.character(queryDown)
    }
    matrixToRankedList <- function(refMatrix) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refList[[i]] <- refMatrix[order(refMatrix[, i], decreasing = TRUE), 
                                  i]
      }
      return(refList)
    }
    weight1EnrichmentScore <- function(refList, query) {
      tagIndicator <- sign(match(names(refList), query, nomatch = 0))
      noTagIndicator <- 1 - tagIndicator
      N <- length(refList)
      Nh <- length(query)
      Nm <- N - Nh
      correlVector <- abs(refList)
      sumCorrelTag <- sum(correlVector[tagIndicator == 1])
      normTag <- 1/sumCorrelTag
      normNoTag <- 1/Nm
      RES <- cumsum(tagIndicator * correlVector * normTag - 
                      noTagIndicator * normNoTag)
      maxES <- max(RES)
      minES <- min(RES)
      maxES <- ifelse(is.na(maxES), 0, maxES)
      minES <- ifelse(is.na(minES), 0, minES)
      ifelse(maxES > -minES, maxES, minES)
    }
    weight1 <- function(refList, queryUp, queryDown) {
      scoreUp <- weight1EnrichmentScore(refList, queryUp)
      scoreDown <- weight1EnrichmentScore(refList, queryDown)
      ifelse(scoreUp * scoreDown <= 0, scoreUp - scoreDown, 
             0)
    }
    refList <- matrixToRankedList(refMatrix)
    queryUp <- intersect(queryUp, rownames(refMatrix))
    queryDown <- intersect(queryDown, rownames(refMatrix))
    score <- lapply(refList, weight1, queryUp = queryUp, queryDown = queryDown)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  ZhangScore <- function(refMatrix, queryUp, queryDown, pval = F){
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix should have both rownames and colnames!")
    }
    if (is.null(queryUp)) {
      queryUp <- character(0)
    }
    if (is.null(queryDown)) {
      queryDown <- character(0)
    }
    if (!is.character(queryUp)) {
      queryUp <- as.character(queryUp)
    }
    if (!is.character(queryDown)) {
      queryDown <- as.character(queryDown)
    }
    matrixToRankedList <- function(refMatrix) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refSort <- refMatrix[order(abs(refMatrix[, i]), decreasing = TRUE), 
                             i]
        refRank <- rank(abs(refSort)) * sign(refSort)
        refList[[i]] <- refRank
      }
      return(refList)
    }
    computeScore <- function(refRank, queryRank) {
      if (length(intersect(names(refRank), names(queryRank))) > 
          0) {
        maxTheoreticalScore <- sum(abs(refRank)[1:length(queryRank)] * 
                                     abs(queryRank))
        score <- sum(queryRank * refRank[names(queryRank)], 
                     na.rm = TRUE)/maxTheoreticalScore
      }
      else {
        score <- NA
      }
      return(score)
    }
    refList <- matrixToRankedList(refMatrix)
    queryVector <- c(rep(1, length(queryUp)), rep(-1, length(queryDown)))
    names(queryVector) <- c(queryUp, queryDown)
    score <- lapply(refList, computeScore, queryRank = queryVector)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
  
  XCosScore <- function (refMatrix, query, topN = 500, pval = F){
    if (is.data.frame(refMatrix)) {
      refMatrix <- as.matrix(refMatrix)
    }
    if (is.null(colnames(refMatrix)) || is.null(rownames(refMatrix))) {
      stop("Warning: refMatrix must have both rownames and colnames!")
    }
    if (!is.numeric(query)) {
      stop("Warning: query must be a numeric vector!")
    }
    if (is.null(names(query))) {
      stop("Warning: query must have names!")
    }
    if (topN > nrow(refMatrix)/2) {
      stop("Warning: topN is lager than half\n
         the length of gene list!")
    }
    matrixToRankedList <- function(refMatrix, topN) {
      refList <- vector("list", ncol(refMatrix))
      for (i in 1:ncol(refMatrix)) {
        refList[[i]] <- c(head(refMatrix[order(refMatrix[, i], decreasing = TRUE), i], n = topN), 
                          tail(refMatrix[order(refMatrix[, i], decreasing = TRUE), i], n = topN))
      }
      return(refList)
    }
    XCos <- function(refList, query) {
      reservedRef <- refList[match(intersect(names(refList), 
                                             names(query)), names(refList))]
      reservedRef[order(names(reservedRef))]
      reservedQuery <- query[match(intersect(names(refList), 
                                             names(query)), names(query))]
      reservedQuery[order(names(reservedQuery))]
      if (length(reservedRef) == 0) {
        return(NA)
      }
      else {
        return((crossprod(reservedRef, reservedQuery)/sqrt(crossprod(reservedRef) * 
                                                             crossprod(reservedQuery)))[1, 1])
      }
    }
    refList <- matrixToRankedList(refMatrix, topN = topN)
    score <- lapply(refList, XCos, query = query)
    score <- as.vector(do.call(rbind, score))
    
    if(pval){
      scoreResult <- data.frame(Score = score,pValue=1,pAdjValue = 1)
    }else(
      scoreResult <- data.frame(Score = score)
    )
    
    
    rownames(scoreResult) <- colnames(refMatrix)
    return(scoreResult)
  }
}







