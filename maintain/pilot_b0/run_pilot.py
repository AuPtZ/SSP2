#!/usr/bin/env python3
# ============================================================
# SSP2 路线B pilot: 留一自检索基准 (leave-one-out self-retrieval)
#
# 两类扰动矩阵共用同一套打分内核 + 指标：
#   xpr (CRISPR-KO): query = 某基因的一个 guide 的签名；
#                    真值 = 同一基因(cmap_name)的其他 guide
#   cp  (化合物)   : query = 某药某 (dose,time) 条件的签名；
#                    真值 = 同一药物的其他 (dose,time) 条件
#
# 打分公式严格复刻 R/SS.R 的 *_i 函数（XSumScore_i / KSScore_i /
# GSEAweight1Score_i / ZhangScore_i / XCosScore_i），并已用 validate_py.py
# 与 R 原生实现逐值对拍（见 _review/pilot_results.md 的核对表）。
#   关键细节：ZhangScore 的 refRank = rank(|v|, ties="average") * sign(v)，
#   因 level5 z-score 存在大量并列 |z|，必须做 ties 平均，否则与 R 不符。
#
# 输出: 每个数据集一个 per-query CSV (长表)。
# 用法:
#   python3 run_pilot.py --kind xpr --cell A549 --n-queries 100 --n-perm 100
#   python3 run_pilot.py --kind cp  --cell MCF7 --n-queries 100 --n-perm 100
# ============================================================
import argparse, json, os, sys, time
import numpy as np
import pandas as pd

METHODS = ["XSum", "CMap", "GSEA", "Zhang", "XCos"]
TOPNS = [25, 50, 100, 200]
MAXN = max(TOPNS)


# ---------------- IO ----------------
def load_dataset(prefix):
    dims = {}
    with open(prefix + ".dims") as f:
        for line in f:
            k, v = line.split()
            dims[k] = int(v)
    G, N = dims["G"], dims["N"]
    t0 = time.time()
    M = np.fromfile(prefix + ".bin", dtype=np.float64).reshape((G, N), order="F")
    cols = pd.read_csv(prefix + "_cols.csv")
    assert M.shape == (G, N) and len(cols) == N, (M.shape, G, N, len(cols))
    print(f"[io] {prefix}: {G} x {N} loaded in {time.time()-t0:.1f}s", flush=True)
    return M, cols


def precompute_ranks(M):
    """返回 (Rank, SR, max_theo)
    Rank[i, j]   : 列 j 中第 i 行的降序名次 (1 = 值最大)
    SR[i, j]     : ZhangScore 的 refRank = rank(|v|, ties=average) * sign(v)
    max_theo[k]  : 每个列 k = 50/100/200/400 时的 maxTheoreticalScore
    """
    G, N = M.shape
    colidx = np.arange(N, dtype=np.int64)[None, :]
    t0 = time.time()

    # ---- Rank: descending rank (ties: stable, 与 R order(decreasing=TRUE) 一致) ----
    order_desc = np.argsort(-M, axis=0, kind="stable").astype(np.int32)
    Rank = np.empty_like(order_desc)
    pos = np.arange(1, G + 1, dtype=np.int32)[:, None]
    np.put_along_axis(Rank, order_desc, np.broadcast_to(pos, (G, N)), axis=0)
    del order_desc
    print(f"[prep] Rank {time.time()-t0:.1f}s", flush=True)

    # ---- SR: tie-averaged rank of |v| (1 = smallest |v|), 与 R rank() 一致 ----
    t0 = time.time()
    order_abs = np.argsort(-np.abs(M), axis=0, kind="stable").astype(np.int32)
    S = M[order_abs, colidx]            # |v| 降序排列 (G x N)
    np.abs(S, out=S)
    G0 = np.empty((G, N), dtype=bool)
    G0[0, :] = True
    G0[1:, :] = S[1:, :] != S[:-1, :]   # 并列组的起始行
    arangeG = np.arange(G, dtype=np.int32)[:, None]
    starts = np.maximum.accumulate(np.where(G0, arangeG, np.int32(0)), axis=0)
    idxmat = np.where(G0, arangeG, np.int32(G))            # 组起始行号, 其余=G
    revmin = np.minimum.accumulate(idxmat[::-1], axis=0)[::-1]  # 自 i 起最小起始行
    nxt = np.vstack([revmin[1:, :], np.full((1, N), G, dtype=np.int32)])
    ends_at_start = nxt - 1                                 # 每个组起始行 -> 组结束行
    e_i = np.take_along_axis(ends_at_start, starts, axis=0)
    # 降序位置 p(0-based) 对应的升序名次 = G - p；并列组取平均 -> G - (s+e)/2
    AR = (2.0 * G - starts.astype(np.float64) - e_i.astype(np.float64)) / 2.0
    del S, G0, idxmat, revmin, nxt, ends_at_start, e_i, starts
    max_theo = {k: AR[:k, :].sum(0).astype(np.float64) for k in [50, 100, 200, 400]}
    signed_sorted = AR * np.take_along_axis(np.sign(M), order_abs, axis=0)
    SR = np.empty((G, N), dtype=np.float32)
    np.put_along_axis(SR, order_abs, signed_sorted.astype(np.float32), axis=0)
    del AR, signed_sorted, order_abs
    print(f"[prep] SR + max_theo {time.time()-t0:.1f}s", flush=True)
    return Rank, SR, max_theo


# ---------------- scoring kernels (faithful to R/SS.R) ----------------
def score_all(M, Rank, SR, max_theo, order_desc_query, qcol, topns=TOPNS):
    """Return dict[(method, topN)] = score vector over all N reference columns."""
    G, N = M.shape
    out = {}
    for topN in topns:
        up = order_desc_query[:topN]                     # topN up genes of query signature
        dn = order_desc_query[G - 1:G - 1 - topN:-1]     # topN down genes (最负在前)
        k = topN

        # ---- XSum (XSumScore_i): refList = topN + bottomN values; 只累加落在极值集的查询基因 ----
        ext_up = Rank[up]
        ext_dn = Rank[dn]
        mask_up = (ext_up <= topN) | (ext_up > G - topN)
        mask_dn = (ext_dn <= topN) | (ext_dn > G - topN)
        s_up = np.where(mask_up, M[up], 0.0).sum(0)
        s_dn = np.where(mask_dn, M[dn], 0.0).sum(0)
        out[("XSum", topN)] = s_up - s_dn

        # ---- CMap / KS (KSScore_i) ----
        def ks_one(q):
            kk = len(q)
            p = np.sort(Rank[q], axis=0).astype(np.float64)
            d = (np.arange(1, kk + 1, dtype=np.float64)[:, None] / kk) - p / G
            a = d.max(0)
            b = -d.min(0) + 1.0 / kk
            return np.where(a > b, a, -b)
        su = ks_one(up)
        sd = ks_one(dn)
        out[("CMap", topN)] = np.where(su * sd <= 0, su - sd, 0.0)

        # ---- GSEA weight1 (GSEAweight1Score_i) ----
        def es_one(q):
            kk = len(q)
            r = Rank[q].astype(np.float64)
            w = np.abs(M[q])
            o = np.argsort(r, axis=0, kind="stable")
            rs = np.take_along_axis(r, o, axis=0)
            ws = np.take_along_axis(w, o, axis=0)
            W = ws.sum(0)
            Nm = G - kk
            cumW = np.cumsum(ws, axis=0)
            t = np.arange(1, kk + 1, dtype=np.float64)[:, None]
            res_max = (cumW / W - (rs - t) / Nm).max(0)
            rs_next = np.vstack([rs[1:], np.full((1, N), float(G + 1))])
            cand_next = (cumW / W - (rs_next - 1.0 - t) / Nm).min(0)
            cand_end = 1.0 - (G - kk) / Nm
            cand_before_first = np.where(rs[0] > 1.0, -(rs[0] - 1.0) / Nm, np.inf)
            res_min = np.minimum(cand_next, np.minimum(cand_before_first, cand_end))
            return np.where(res_max > -res_min, res_max, res_min)
        eu = es_one(up)
        ed = es_one(dn)
        out[("GSEA", topN)] = np.where(eu * ed <= 0, eu - ed, 0.0)

        # ---- Zhang (ZhangScore_i; maxTheoreticalScore 用逐列 ties 平均名次和) ----
        kk = 2 * topN
        out[("Zhang", topN)] = (SR[up].sum(0, dtype=np.float64) -
                                SR[dn].sum(0, dtype=np.float64)) / max_theo[kk]

        # ---- XCos (XCosScore_i, ref topN = nrow/2 => 全部基因; 查询向量 = up∪dn 的签名值) ----
        Q = np.concatenate([up, dn])
        qv = M[Q, qcol].astype(np.float64)
        V = M[Q].astype(np.float64)
        num = qv @ V
        den = np.sqrt((V * V).sum(0) * float(qv @ qv))
        out[("XCos", topN)] = num / den
    return out


# ---------------- metrics ----------------
def rank_desc_average(x):
    """1-based rank, largest value -> 1, ties averaged (numpy only)."""
    n = len(x)
    order = np.argsort(x, kind="stable")          # ascending
    xs = x[order]
    uniq, inv, counts = np.unique(xs, return_inverse=True, return_counts=True)
    start = np.concatenate(([0.0], np.cumsum(counts)[:-1]))
    avg_asc = start + (counts + 1) / 2.0           # asc rank (1 = smallest)
    ra = np.empty(n, dtype=np.float64)
    ra[order] = avg_asc[inv]
    return (n + 1.0) - ra                          # desc rank (1 = largest)


def null_metrics(n_valid, n_pos, n_perm, rng):
    """置换 null: 随机正例标签 (只依赖 n_valid/n_pos, 与打分方法无关)."""
    aucs = np.empty(n_perm); rec10 = np.empty(n_perm); rec20 = np.empty(n_perm)
    hit10 = np.empty(n_perm); hit20 = np.empty(n_perm); mrr = np.empty(n_perm)
    n_neg = n_valid - n_pos
    for i in range(n_perm):
        rp = rng.choice(n_valid, size=n_pos, replace=False) + 1.0   # desc rank
        aucs[i] = (n_pos * (n_valid + 1) - rp.sum()
                   - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)
        rec10[i] = (rp <= 10).sum() / n_pos
        rec20[i] = (rp <= 20).sum() / n_pos
        hit10[i] = 1.0 if (rp <= 10).any() else 0.0
        hit20[i] = 1.0 if (rp <= 20).any() else 0.0
        mrr[i] = 1.0 / rp.min()
    return dict(auc=aucs, recall10=rec10, recall20=rec20,
                hit10=hit10, hit20=hit20, mrr=mrr)


def obs_metrics(scores, pos_idx, self_col, null):
    N = len(scores)
    keep = np.ones(N, dtype=bool)
    keep[self_col] = False
    s = scores[keep]
    n_valid = len(s)
    pos_mask = np.zeros(N, dtype=bool)
    pos_mask[pos_idx] = True
    pos_mask[self_col] = False
    pos = pos_mask[keep]
    n_pos = int(pos.sum()); n_neg = n_valid - n_pos
    r = rank_desc_average(s)
    rp = r[pos]
    # standard AUC under descending ranks (rp = 1 is the highest score)
    auc = (n_pos * (n_valid + 1) - rp.sum() - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)
    mrr = 1.0 / rp.min()
    res = dict(n_pos=n_pos, n_neg=n_neg, auc=float(auc), mrr=float(mrr),
               recall10=float((rp <= 10).sum() / n_pos),
               recall20=float((rp <= 20).sum() / n_pos),
               hit10=float((rp <= 10).any()), hit20=float((rp <= 20).any()))
    for key, val in (("auc", auc), ("recall10", res["recall10"]),
                     ("recall20", res["recall20"]), ("hit10", res["hit10"]),
                     ("hit20", res["hit20"]), ("mrr", mrr)):
        res["p_" + key] = float((1.0 + (null[key] >= val - 1e-12).sum()) / (1.0 + len(null[key])))
    res["null_auc_mean"] = float(null["auc"].mean())
    res["null_auc_q95"] = float(np.quantile(null["auc"], 0.95))
    res["null_recall10_mean"] = float(null["recall10"].mean())
    res["null_hit10_mean"] = float(null["hit10"].mean())
    res["null_mrr_mean"] = float(null["mrr"].mean())
    return res


# ---------------- queries ----------------
def make_queries(cols, kind, n_queries, seed):
    grp_col = "gene" if kind == "xpr" else "drug"
    g = cols.groupby(grp_col, sort=True)
    sizes = g.size()
    eligible = sizes[sizes >= 2]
    if len(eligible) == 0:
        raise SystemExit(f"[{kind}] 没有 >=2 个条件的组")
    rng = np.random.default_rng(seed)
    take = min(n_queries, len(eligible))
    chosen = rng.choice(eligible.index.to_numpy(), size=take, replace=False)
    qs = []
    for grp in chosen:
        idx = g.get_group(grp).index.to_numpy()
        q = int(rng.choice(idx, size=1)[0])
        pos = idx[idx != q]
        label = str(cols.iloc[q]["col"]) if "col" in cols.columns else str(q)
        qs.append(dict(query_col=q, pos_cols=pos.tolist(), group=str(grp),
                       query_label=label))
    return qs


# ---------------- driver ----------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", required=True, choices=["xpr", "cp"])
    ap.add_argument("--cell", required=True)
    ap.add_argument("--n-queries", type=int, default=100)
    ap.add_argument("--n-perm", type=int, default=100)
    ap.add_argument("--seed", type=int, default=20261108)
    ap.add_argument("--data-dir", default="/tmp/pilot/data")
    ap.add_argument("--out-dir", default="/tmp/pilot/results")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    t_all = time.time()
    prefix = os.path.join(args.data_dir, f"{args.kind}_{args.cell}")
    M, cols = load_dataset(prefix)
    G, N = M.shape
    Rank, SR, max_theo = precompute_ranks(M)

    qlist = make_queries(cols, args.kind, args.n_queries, args.seed)
    print(f"[query] {args.kind} {args.cell}: {len(qlist)} queries; "
          f"n_pos median {np.median([len(q['pos_cols']) for q in qlist]):.0f}", flush=True)

    rows = []
    t0 = time.time()
    for qi, q in enumerate(qlist):
        qcol = q["query_col"]
        order = np.argsort(-M[:, qcol], kind="stable")
        score = score_all(M, Rank, SR, max_theo, order, qcol, TOPNS)
        null = null_metrics(N - 1, len(q["pos_cols"]), args.n_perm,
                            np.random.default_rng(args.seed + qi))
        for (method, topN), sc in score.items():
            mt = obs_metrics(sc, q["pos_cols"], qcol, null)
            mt.update(dict(kind=args.kind, cell=args.cell, query=q["group"],
                           query_col=q["query_label"], method=method, topn=topN))
            rows.append(mt)
        if (qi + 1) % 10 == 0:
            el = time.time() - t0
            print(f"  [{qi+1}/{len(qlist)}] {el:.0f}s "
                  f"(eta {el/(qi+1)*(len(qlist)-qi-1):.0f}s)", flush=True)

    df = pd.DataFrame(rows)
    out = os.path.join(args.out_dir, f"perquery_{args.kind}_{args.cell}.csv")
    df.to_csv(out, index=False)
    print(f"[done] {args.kind} {args.cell}: {len(df)} rows -> {out} "
          f"({time.time()-t_all:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
