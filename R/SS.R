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
      queryUp <- as.character(queryDown)
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
      queryUp <- as.character(queryDown)
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
      queryUp <- as.character(queryDown)
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
      queryUp <- as.character(queryDown)
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
  
  XSumScore <- memoise::memoise(XSumScore_i,cache = local_cache_folder)
  KSScore <- memoise::memoise(KSScore_i,cache = local_cache_folder)
  GSEAweight1Score <- memoise::memoise(GSEAweight1Score_i,cache = local_cache_folder)
  ZhangScore <- memoise::memoise(ZhangScore_i,cache = local_cache_folder)
  XCosScore <- memoise::memoise(XCosScore_i,cache = local_cache_folder)
  

  
  
  
  
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
      queryUp <- as.character(queryDown)
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
      queryUp <- as.character(queryDown)
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
      queryUp <- as.character(queryDown)
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
      queryUp <- as.character(queryDown)
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







