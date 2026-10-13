###############################################################################.
# 09 抓取 PubChem 药物信息 —— 以 LINCS2020_drug_info.Rdata 为基础补全
#
# 目的：给结果表里的每个药物准备一份"基本信息"，供点开弹窗展示，全程离线可用。
#
# 数据源（全部来自 PubChem PUG-REST / PUG-View，官方限速 5 req/s）：
#   A 名称反查   /compound/name/<name>/cids/TXT        给本地没有 CID 的药物补 CID
#   B 批量属性   /compound/cid/property/.../JSON        100 CID/批（分子式/分子量/
#                                                       IUPAC 名/通用名/理化性质）
#   C 批量同义词 /compound/cid/synonyms/JSON            50 CID/批（别名，最多 12 个）
#   D 作用机制   /pug_view/data/compound/<cid>/JSON     1 CID/次（最慢，可后台补跑）
#                 ?heading=Mechanism+of+Action
#
# 每个阶段都把结果落在 cache/pubchem/*.rds，中断后重跑自动续跑（已查过的跳过）。
#
# 用法：
#   Rscript maintain/09抓取PubChem药物信息.R              # 跑全部阶段
#   Rscript maintain/09抓取PubChem药物信息.R props        # 只跑 B+C（约 250 次请求，最划算）
#   Rscript maintain/09抓取PubChem药物信息.R moa          # 只补跑 D：已知药物（默认，约半小时）
#   Rscript maintain/09抓取PubChem药物信息.R moaall       # D 全量（约 3-4 小时，建议后台）
#   Rscript maintain/09抓取PubChem药物信息.R name         # A 名称反查补 CID（1 名字 1 请求，约 40 min）
#
# 限速提示：PubChem 对共享出口 IP 限流很严，超了会连续返回 503 ServerBusy 并持续
# 一段时间。脚本默认约 0.8 req/s，且被限流时自动长休眠；中断后重跑会从缓存续跑。
#
# 产物：data_preload/drugconvertor/drug_info_pubchem.Rdata（对象 drug_info_pubchem）
###############################################################################.

suppressPackageStartupMessages({
  library(data.table)
  library(httr2)
  library(jsonlite)
})

# ------------------------------------------------------------------ 配置 -----
BASE_FILE  <- "data_preload/drugconvertor/LINCS2020_drug_info.Rdata"   # LINCS2020 主表
EXTRA_FILE <- "data_preload/annotation/drug_GSE92742.Rdata"            # GSE92742 补充表
OUT_FILE   <- "data_preload/drugconvertor/drug_info_pubchem.Rdata"     # 最终产物
CACHE_DIR  <- "cache/pubchem"

BATCH_PROP <- 200L    # 属性：每批 CID 数（实测 200 个约 1.8s / 140 KB）
BATCH_SYN  <- 100L    # 同义词：每批 CID 数（100 个约 1.7s / 270 KB）
MAX_SYN    <- 12L     # 每个化合物最多保留的别名数
SLEEP       <- 1.2     # 每次请求后休眠 → 约 0.8 req/s。共享出口 IP 很容易被限流
                       # （超了返回 503 ServerBusy 并持续一段时间），宁慢勿快
BLOCK_SLEEP <- 300     # 连续多次被限流后的长休眠（秒）
MAX_MOA_CH <- 800L    # MoA 文本最长保留字符数

args <- commandArgs(trailingOnly = TRUE)
DO_NAME_LOOKUP <- TRUE   # A 名称反查（1 个名字 1 次请求，最费请求数）
DO_PROPS       <- TRUE   # B 批量属性
DO_SYNONYMS    <- TRUE   # C 批量同义词
DO_MOA         <- TRUE   # D 作用机制（1 个 CID 1 次请求）
MOA_SCOPE      <- "known"   # "known"=只抓已知药物（GSDC/GSDCIC50/DrugReHub 里出现过的 CID，
                            #          约 1 千来个，半小时跑完）；"all"=全部 CID（约 3-4 小时）
if (length(args)) {
  DO_NAME_LOOKUP <- "name"  %in% args
  DO_PROPS       <- "props" %in% args
  DO_SYNONYMS    <- "props" %in% args   # 属性与同义词一起跑
  DO_MOA         <- "moa"   %in% args || "moaall" %in% args
  if ("moaall" %in% args) MOA_SCOPE <- "all"
}
TEST     <- "test" %in% args            # 冒烟测试：只抓一小撮
DEBUG    <- "debug" %in% args           # 打印非 200 响应的状态与返回体
N_TEST   <- 60L

dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)
f_prop <- file.path(CACHE_DIR, "props.rds")
f_syn  <- file.path(CACHE_DIR, "synonyms.rds")
f_moa  <- file.path(CACHE_DIR, "moa.rds")
f_name <- file.path(CACHE_DIR, "name2cid.rds")

load_cache <- function(f) if (file.exists(f)) readRDS(f) else NULL

# ------------------------------------------------------------ HTTP 工具 -----
LAST_STATUS <- NA_integer_     # 最近一次请求的 HTTP 状态（供调用方区分"真没有"与"请求失败"）
.http <- function(url, tries = 3L) {
  LAST_STATUS <<- NA_integer_
  for (k in seq_len(tries)) {
    resp <- tryCatch(
      req_perform(req_timeout(request(url), 60) |>
                    req_error(is_error = function(r) FALSE)),
      error = function(e) NULL)
    if (!is.null(resp)) {
      st <- resp_status(resp)
      LAST_STATUS <<- st
      Sys.sleep(SLEEP)
      if (DEBUG && st != 200L)
        cat(sprintf("    [debug] status=%s url=%.160s\n   body=%.200s\n", st, url,
                    gsub("\n", " ", resp_body_string(resp))))
      if (st == 200L) return(resp_body_string(resp))
      if (st %in% c(400L, 404L, 405L)) return(NA_character_)   # 明确没有/请求有问题，重试无意义
      Sys.sleep(c(20, 40, 60)[min(k, 3)])                      # 503/429/5xx：退避重试
    } else {
      Sys.sleep(c(20, 40, 60)[min(k, 3)])                      # 超时/网络错误
    }
  }
  NA_character_     # 彻底失败（多半是被限流），调用方按 LAST_STATUS 判断是否继续
}

# 连续失败到一定次数就长休眠一次，等限流过去，而不是硬撞
.throttle_guard <- function(fail_seq) {
  if (fail_seq >= 3L) {
    cat(sprintf("    [限流] 连续 %d 次失败，休眠 %d 秒后继续…（随时可中断，重跑续跑）\n",
                fail_seq, BLOCK_SLEEP))
    Sys.sleep(BLOCK_SLEEP)
    return(0L)      # 计数归零，继续跑
  }
  fail_seq
}

.now <- function() format(Sys.time(), "%H:%M:%S")

# =============================================================== 基础表 ======
# 以 CMAP_druginfo（LINCS2020）为骨架，用 drug_GSE92742 补本地就缺的 CID。
e <- new.env(); load(BASE_FILE, envir = e)
di <- as.data.table(get(ls(e)[1], e))
setnames(di, "canonical_smiles", "lincs_smiles")
di[, `:=`(name_key = tolower(pert_iname))]

e2 <- new.env(); load(EXTRA_FILE, envir = e2)
g9 <- as.data.table(get(ls(e2)[1], e2))[, .(pert_iname, pubchem_cid)]
g9[, name_key := tolower(pert_iname)]

# 一个 pert_iname 可能对应多行（不同 pert_id）：pert_id 合并，其它取第一条
base <- di[, .(pert_iname = pert_iname[1],
               pert_id    = paste(unique(pert_id_list[!is.na(pert_id_list)]), collapse = "; "),
               net_name   = net_drug_name[1],
               cid_lincs  = as.character(pubchem_cid[!is.na(pubchem_cid)][1]),
               lincs_smiles = lincs_smiles[!is.na(lincs_smiles)][1],
               inchi_key    = inchi_key[!is.na(inchi_key)][1]),
           by = name_key]

# drug_GSE92742 里能补上的 CID（同名、主表缺 CID 时用它补）
fill <- g9[!is.na(pubchem_cid), .(cid = as.character(pubchem_cid[1])), by = name_key]
base[fill, cid_lincs := ifelse(is.na(cid_lincs), i.cid, cid_lincs), on = "name_key"]
base[, cid_source := ifelse(is.na(cid_lincs), NA_character_, "lincs")]

cat(sprintf("[%s] 基础表：%d 个药物名 | 本地已有 CID %d 个 | 缺 CID %d 个\n",
            .now(), nrow(base), sum(!is.na(base$cid_lincs)), sum(is.na(base$cid_lincs))))

# LINCS 里有一批 CID 是 -666 这类哨兵值（等于"没有 CID"，但字段非 NA）。必须**先**把它
# 们清成 NA，否则 A 阶段的"待查名单"会漏掉这些名字（vorinostat 就是这样被漏掉的）。
# 批量请求里只要夹一个坏 ID，PubChem 就整批返回 400，所以也顺手保证 cid_all 全合法。
v <- base$cid_lincs
valid <- !is.na(v) & grepl("^[0-9]+$", v)
valid[valid] <- suppressWarnings(as.numeric(v[valid])) > 0
bad_rows <- which(!is.na(v) & !valid)
if (length(bad_rows))
  base[bad_rows, `:=`(cid_lincs = NA_character_, cid_source = "invalid_lincs_id")]
cat(sprintf("[%s] 剔除无效 CID（如 -666 哨兵值）：%d 个\n", .now(), length(bad_rows)))

# =============================================== A 名称反查（补 CID）=========
if (DO_NAME_LOOKUP) {
  nm_cid <- load_cache(f_name)
  if (is.null(nm_cid))
    nm_cid <- data.table(name_key = character(), cid = character(), resolved = logical())

  todo <- base[is.na(cid_lincs) & !(name_key %in% nm_cid$name_key) & !grepl("^brd-", name_key),
               name_key]
  cat(sprintf("[%s] A 名称反查：待查 %d 个非 BRD- 名字（BRD- 编号 PubChem 查不到，跳过）\n",
              .now(), length(todo)))
  if (TEST) todo <- head(todo, N_TEST)

  fail_seq <- 0L
  for (i in seq_along(todo)) {
    nm <- todo[i]
    url <- paste0("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/",
                  URLencode(nm, reserved = TRUE), "/cids/TXT")
    body <- .http(url)
    definitive <- LAST_STATUS %in% c(200L, 404L)   # 只有明确返回才记账，请求失败的下轮重查
    cid <- if (is.na(body)) NA_character_ else {
      v <- trimws(unlist(strsplit(body, "\\s+")))
      v <- v[nzchar(v)]
      if (length(v)) v[1] else NA_character_
    }
    if (definitive) {
      nm_cid <- rbindlist(list(nm_cid,
                               data.table(name_key = nm, cid = cid, resolved = !is.na(cid))))
      fail_seq <- 0L
    } else {
      fail_seq <- .throttle_guard(fail_seq + 1L)   # 被限流就等一会儿再继续
    }
    if (i %% 100 == 0 || i == length(todo)) {
      saveRDS(nm_cid, f_name)
      cat(sprintf("    %d/%d  命中 %d\n", i, length(todo), nm_cid[, sum(resolved)]))
    }
  }
  saveRDS(nm_cid, f_name)

  cat(sprintf("[%s] A 完成：本轮补上 CID %d 个\n", .now(), sum(nm_cid$resolved)))
}

# 无论本轮跑没跑 A，都要把缓存里的名称反查结果并进基础表
# （否则只跑 props/moa 时会把之前补的 CID 弄丢）
nm_cid <- load_cache(f_name)
if (!is.null(nm_cid) && nrow(nm_cid)) {
  ok <- nm_cid[resolved & !is.na(cid)]
  # 只补"本来没有 CID"的行，绝不覆盖 LINCS 自带的 CID
  ok <- ok[name_key %in% base[is.na(cid_lincs), name_key]]
  if (nrow(ok))
    base[ok, `:=`(cid_lincs = i.cid, cid_source = "name_lookup"), on = "name_key"]
  cat(sprintf("[%s] 名称反查累计补全 CID：%d 个\n", .now(), nrow(ok)))
}

cid_all <- unique(base$cid_lincs[!is.na(base$cid_lincs)])
if (TEST) cid_all <- head(cid_all, N_TEST)
cat(sprintf("[%s] 待抓 CID 总数：%d\n", .now(), length(cid_all)))

# ================================================ B 批量属性（100 CID/批）====
PROPS <- paste("MolecularFormula,MolecularWeight,IUPACName,Title,ConnectivitySMILES,",
               "InChIKey,XLogP,TPSA,Complexity,Charge,HBondDonorCount,HBondAcceptorCount,",
               "RotatableBondCount,MonoisotopicMass", sep = "")

prop_url <- function(ids)
  paste0("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/property/",
         PROPS, "/JSON?cid=", paste(ids, collapse = ","))
syn_url <- function(ids)
  paste0("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/synonyms/JSON?cid=",
         paste(ids, collapse = ","))

parse_props <- function(body) {
  j <- tryCatch(fromJSON(body)$PropertyTable$Properties, error = function(e) NULL)
  if (is.null(j) || !nrow(j)) return(NULL)
  j <- as.data.table(j)
  # 2025 年起 CanonicalSMILES 改叫 ConnectivitySMILES，两种都兼容
  sm <- if ("ConnectivitySMILES" %in% names(j)) j$ConnectivitySMILES else
    if ("CanonicalSMILES" %in% names(j)) j$CanonicalSMILES else NA_character_
  data.table(cid = as.character(j$CID),
             pc_formula    = as.character(j$MolecularFormula),
             pc_mw         = as.character(j$MolecularWeight),
             pc_iupac      = as.character(j$IUPACName),
             pc_title      = as.character(j$Title),
             pc_smiles     = as.character(sm),
             pc_inchikey   = as.character(j$InChIKey),
             pc_xlogp      = as.character(j$XLogP),
             pc_tpsa       = as.character(j$TPSA),
             pc_complexity = as.character(j$Complexity),
             pc_charge     = as.character(j$Charge),
             pc_hbd        = as.character(j$HBondDonorCount),
             pc_hba        = as.character(j$HBondAcceptorCount),
             pc_rotb       = as.character(j$RotatableBondCount),
             pc_mono       = as.character(j$MonoisotopicMass))
}

parse_syns <- function(body) {
  items <- tryCatch(fromJSON(body, simplifyVector = FALSE)$InformationList$Information,
                    error = function(e) NULL)
  if (is.null(items) || !length(items)) return(NULL)
  rbindlist(lapply(items, function(it) {
    s <- unique(unlist(it$Synonym))
    s <- s[!is.na(s) & nzchar(s)]
    data.table(cid = as.character(it$CID),
               pc_synonyms = paste(head(s, MAX_SYN), collapse = "; "))
  }))
}

# 整批失败时，只有当坏 ID（400/405）才退回逐条请求；被限流(503)或超时就不拆，
# 否则一批会炸成 200 次请求，反而加重限流
fetch_batch <- function(ids, url_fn, parse_fn) {
  body <- .http(url_fn(ids))
  if (!is.na(body)) return(parse_fn(body))
  if (!(LAST_STATUS %in% c(400L, 405L))) return(NULL)
  out <- lapply(ids, function(id) {
    b <- .http(url_fn(id))
    if (is.na(b)) NULL else parse_fn(b)
  })
  out <- out[!vapply(out, is.null, logical(1))]
  if (length(out)) rbindlist(out) else NULL
}

if (DO_PROPS && length(cid_all)) {
  props <- load_cache(f_prop)
  if (is.null(props))
    props <- data.table(cid = character(), pc_formula = character(), pc_mw = character(),
                        pc_iupac = character(), pc_title = character(), pc_smiles = character(),
                        pc_inchikey = character(), pc_xlogp = character(), pc_tpsa = character(),
                        pc_complexity = character(), pc_charge = character(),
                        pc_hbd = character(), pc_hba = character(), pc_rotb = character(),
                        pc_mono = character())
  done <- props$cid
  todo <- setdiff(cid_all, done)
  batches <- split(todo, ceiling(seq_along(todo) / BATCH_PROP))
  cat(sprintf("[%s] B 批量属性：%d 个 CID / %d 批\n", .now(), length(todo), length(batches)))

  fail_seq <- 0L
  for (b in seq_along(batches)) {
    add <- fetch_batch(batches[[b]], prop_url, parse_props)
    if (is.null(add)) {
      cat(sprintf("    第 %d 批失败（status=%s），下一轮重跑会重试\n", b, LAST_STATUS))
      fail_seq <- .throttle_guard(fail_seq + 1L)
    } else {
      props <- rbindlist(list(props, add), fill = TRUE)
      fail_seq <- 0L
    }
    if (b %% 20 == 0 || b == length(batches)) {
      saveRDS(props, f_prop)
      cat(sprintf("    %d/%d 批，已取到 %d 个 CID 的属性\n", b, length(batches), nrow(props)))
    }
  }
  saveRDS(props, f_prop)
}

# =============================================== C 批量同义词（50 CID/批）====
if (DO_SYNONYMS && length(cid_all)) {
  syn <- load_cache(f_syn)
  if (is.null(syn)) syn <- data.table(cid = character(), pc_synonyms = character())
  todo <- setdiff(cid_all, syn$cid)
  batches <- split(todo, ceiling(seq_along(todo) / BATCH_SYN))
  cat(sprintf("[%s] C 批量同义词：%d 个 CID / %d 批\n", .now(), length(todo), length(batches)))

  fail_seq <- 0L
  for (b in seq_along(batches)) {
    add <- fetch_batch(batches[[b]], syn_url, parse_syns)
    if (is.null(add)) {
      cat(sprintf("    第 %d 批失败（status=%s），下一轮重跑会重试\n", b, LAST_STATUS))
      fail_seq <- .throttle_guard(fail_seq + 1L)
    } else {
      syn <- rbindlist(list(syn, add), fill = TRUE)
      fail_seq <- 0L
    }
    if (b %% 20 == 0 || b == length(batches)) {
      saveRDS(syn, f_syn)
      cat(sprintf("    %d/%d 批，已取到 %d 个 CID 的别名\n", b, length(batches), nrow(syn)))
    }
  }
  saveRDS(syn, f_syn)
}

# ============================================ D 作用机制 MoA（逐 CID，慢）====
.find_heading <- function(secs, heading) {
  for (s in secs) {
    if (!is.null(s$TOCHeading) && identical(s$TOCHeading, heading)) return(s)
    if (!is.null(s$Section)) {
      r <- .find_heading(s$Section, heading)
      if (!is.null(r)) return(r)
    }
  }
  NULL
}
.flat_str <- function(x) {
  out <- character(0)
  rec <- function(n) {
    if (!is.list(n)) return(invisible(NULL))
    nms <- names(n)
    for (i in seq_along(n)) {
      v  <- n[[i]]
      nm <- if (is.null(nms)) "" else nms[i]
      # 文本藏在 Value$StringWithMarkup[[i]]$String 里，而 StringWithMarkup 是
      # 无名数组，所以必须按元素递归，不能只按名字遍历
      if (nm %in% c("String", "Str") && is.character(v)) { out <<- c(out, v); next }
      if (is.list(v)) rec(v)
    }
    invisible(NULL)
  }
  rec(x); unique(unlist(out))
}

.unescape <- function(x) {
  x <- gsub("&lt;",   "<", x, fixed = TRUE)
  x <- gsub("&gt;",   ">", x, fixed = TRUE)
  x <- gsub("&quot;", '"', x, fixed = TRUE)
  x <- gsub("&apos;", "'", x, fixed = TRUE)
  x <- gsub("&#39;",  "'", x, fixed = TRUE)
  gsub("&amp;",       "&", x, fixed = TRUE)
}

if (DO_MOA && length(cid_all)) {
  moa <- load_cache(f_moa)
  if (is.null(moa)) moa <- data.table(cid = character(), pc_moa = character())

  # MoA 是 1 个 CID 1 次请求，而多数研究化合物在 PubChem 根本没有药理数据（返回 404）。
  # 默认只抓"已知药物"：GSDC（700 个带靶点的抗癌药）+ GSDCIC50 + DrugReHub 里出现过的 CID。
  # 想全量跑就加参数 moaall。
  if (MOA_SCOPE == "known") {
    known <- character()
    for (f in c("data_preload/annotation/GSDC_drug_info_full.Rdata",
                "data_preload/annotation/GSDCIC50_update.Rdata",
                "data_preload/annotation/DrugReHub.Rdata")) {
      if (!file.exists(f)) next
      ee <- new.env(); load(f, envir = ee)
      for (obj in ls(ee)) {
        o <- get(obj, envir = ee)
        for (cn in c("PubCHEM", "PubChem_Cid", "PubChem_Cid", "pubchem_cid")) {
          if (cn %in% names(o))
            known <- c(known, as.character(na.omit(o[[cn]])))
        }
      }
    }
    known <- unique(known[grepl("^[0-9]+$", known)])
    pool <- intersect(cid_all, known)
    cat(sprintf("[%s] D 作用机制：范围=已知药物，%d 个 CID（全部 CID 共 %d 个，用 moaall 可全量跑）\n",
                .now(), length(pool), length(cid_all)))
  } else {
    pool <- cid_all
  }

  todo <- setdiff(pool, moa$cid)
  cat(sprintf("[%s] D 作用机制：%d 个 CID 待抓（约 %.0f 分钟，可中断后重跑续跑）\n",
              .now(), length(todo), length(todo) * (SLEEP + 0.5) / 60))

  fail_seq <- 0L
  for (i in seq_along(todo)) {
    cid <- todo[i]
    body <- .http(paste0("https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/",
                         cid, "/JSON?heading=Mechanism+of+Action"))
    txt <- NA_character_
    if (!is.na(body)) {
      rec <- tryCatch(fromJSON(body, simplifyVector = FALSE)$Record$Section,
                      error = function(e) NULL)
      if (!is.null(rec)) {
        sec <- .find_heading(rec, "Mechanism of Action")
        if (!is.null(sec)) {
          t <- .flat_str(sec)
          t <- t[!is.na(t) & nzchar(t)]
          t <- t[!grepl("^In medicine, the term", t)]          # 去掉栏目通用说明
          # PubChem 把 <sub> 之类标记转义成 &lt;sub&gt;：先还原实体，再剥标签
          t <- .unescape(t)
          t <- gsub("<[^>]+>", "", t)
          if (length(t)) txt <- substr(paste(unique(t), collapse = " "), 1, MAX_MOA_CH)
        }
      }
    }
    # 404 = PubChem 确实没有药理数据；请求失败则不记账，下次重跑补
    if (LAST_STATUS %in% c(200L, 404L)) {
      moa <- rbindlist(list(moa, data.table(cid = cid, pc_moa = txt)))
      fail_seq <- 0L
    } else {
      fail_seq <- .throttle_guard(fail_seq + 1L)
    }
    if (i %% 200 == 0 || i == length(todo)) {
      saveRDS(moa, f_moa)
      cat(sprintf("    %d/%d  有 MoA 描述 %d 个\n", i, length(todo), moa[, sum(!is.na(pc_moa))]))
    }
  }
  saveRDS(moa, f_moa)
}

# =============================================================== 汇总输出 =====
props <- load_cache(f_prop); syn <- load_cache(f_syn)
moa   <- load_cache(f_moa);  nm_cid <- load_cache(f_name)

out <- base[, .(name_key, pert_iname, pert_id, net_name,
                pubchem_cid = cid_lincs, cid_source,
                lincs_smiles, inchi_key)]

# A 阶段按名字反查来的 CID：别名里找不到原名 → 降级为未验证（UI 可标注"推断"）
if (!is.null(syn) && nrow(syn) && !is.null(nm_cid) && nrow(nm_cid)) {
  chk <- nm_cid[resolved & !is.na(cid)]
  chk[, hit := FALSE]
  # 只比字母数字：A-443654 / "A 443654" / "A443654" 都算同一个名字
  norm <- function(x) gsub("[^a-z0-9]", "", tolower(x))
  s <- syn[!is.na(pc_synonyms) & nchar(pc_synonyms) > 0]
  for (k in seq_len(nrow(s))) {
    ids <- norm(unlist(strsplit(s$pc_synonyms[k], "; ")))
    chk[norm(name_key) %in% ids & cid == s$cid[k], hit := TRUE]
  }
  bad <- chk[hit == FALSE, name_key]
  out[name_key %in% bad & cid_source == "name_lookup", cid_source := "name_lookup_unverified"]
  cat(sprintf("[%s] 名称反查校验：%d 个无法在 PubChem 别名中核实，已标记为 inferred\n",
              .now(), length(bad)))
}

if (!is.null(props) && nrow(props))
  out[props, `:=`(pc_formula = i.pc_formula, pc_mw = i.pc_mw, pc_iupac = i.pc_iupac,
                  pc_title = i.pc_title, pc_smiles = i.pc_smiles, pc_inchikey = i.pc_inchikey,
                  pc_xlogp = i.pc_xlogp, pc_tpsa = i.pc_tpsa, pc_complexity = i.pc_complexity,
                  pc_charge = i.pc_charge, pc_hbd = i.pc_hbd, pc_hba = i.pc_hba,
                  pc_rotb = i.pc_rotb, pc_mono = i.pc_mono), on = c(pubchem_cid = "cid")]
if (!is.null(syn) && nrow(syn))
  out[syn, pc_synonyms := i.pc_synonyms, on = c(pubchem_cid = "cid")]
if (!is.null(moa) && nrow(moa))
  out[moa, pc_moa := i.pc_moa, on = c(pubchem_cid = "cid")]

out[, fetch_date := Sys.Date()]
# 某个阶段还没跑（缓存为空）时对应列不存在，用 intersect 兜住，保证随时可中途输出
setcolorder(out, intersect(c("name_key", "pert_iname", "pert_id", "net_name", "pubchem_cid",
                             "cid_source", "pc_title", "pc_iupac", "pc_formula", "pc_mw",
                             "pc_mono", "pc_smiles", "pc_inchikey", "pc_xlogp", "pc_tpsa",
                             "pc_complexity", "pc_charge", "pc_hbd", "pc_hba", "pc_rotb",
                             "pc_synonyms", "pc_moa", "lincs_smiles", "inchi_key",
                             "fetch_date"), names(out)))
setkey(out, name_key)

dir.create(dirname(OUT_FILE), showWarnings = FALSE, recursive = TRUE)
drug_info_pubchem <- out          # 存成这个名字，global.R 直接 load 即可用
save(drug_info_pubchem, file = OUT_FILE, compress = "xz")

# ------------------------------------------------------------------ 报告 -----
cat("\n================ 抓取结果 ================\n")
cat(sprintf("药物名总数        : %d\n", nrow(out)))
cat(sprintf("有 PubChem CID    : %d (%.1f%%)\n", sum(!is.na(out$pubchem_cid)),
            100 * mean(!is.na(out$pubchem_cid))))
cat(sprintf("  其中来自 LINCS  : %d\n", sum(out$cid_source == "lincs", na.rm = TRUE)))
cat(sprintf("  名称反查补全    : %d（未核实 %d）\n",
            sum(out$cid_source == "name_lookup", na.rm = TRUE),
            sum(out$cid_source == "name_lookup_unverified", na.rm = TRUE)))
cat(sprintf("有属性(分子式等)  : %d\n", sum(!is.na(out$pc_formula))))
cat(sprintf("有通用名 Title    : %d\n", sum(!is.na(out$pc_title))))
cat(sprintf("有别名字段        : %d\n", sum(!is.na(out$pc_synonyms))))
cat(sprintf("有作用机制 MoA    : %d\n", sum(!is.na(out$pc_moa))))
cat(sprintf("文件              : %s（%.1f MB）\n", OUT_FILE,
            file.info(OUT_FILE)$size / 1024^2))
t0 <- system.time(load(OUT_FILE))
cat(sprintf("启动加载耗时      : %.2f s\n", t0[["elapsed"]]))
cat("==========================================\n")
