# SSP2 路线B pilot（B0）：cp vs xpr 留一自检索基准

结论与数字见 `_review/pilot_results.md`。脚本作用：

| 脚本 | 作用 |
|---|---|
| `prep_xpr.R` | 从 LINCS2020 xpr gctx 导出 4 个细胞系的 **guide 级**矩阵到 `/tmp/pilot/data/xpr_<cell>.bin`（列=guide sig_id，另存列注释 gene/pert_id） |
| `prep_cp.R` | 把现有 `data_preload/drugexp/LINCS_<cell>_<dose>_<time>.rdata` 按细胞系池化成 cp 矩阵（列=`<drug>@<dose>_<time>h`）到 `/tmp/pilot/data/cp_<cell>.bin` |
| `validate_r.R` / `validate_py.py` | 内核对拍：在 2,000 列小矩阵上用 R/SS.R 原生 `*_i` 函数与 Python 内核逐值比较（5 方法，topN 25/200） |
| `run_pilot.py` | 单数据集留一自检索：5 方法 × topN{25,50,100,200}，指标 AUC/Recall@10/20/Hit/MRR + 100 次置换 null；输出 `perquery_<kind>_<cell>.csv` |
| `aggregate_results.py` | 汇总 by-class / by-cell 表 + 跨类 Spearman |
| `analysis_extra.py`, `stats_queries.py` | 报告所需的附加表格（每类最优配置、每细胞最优、n_pos 分布等） |
| `sanity_xpr.R.py`, `sanity_cp.py` | 留一协议的合理性检查：同基因不同 guide / 同药不同条件的签名相关性 vs 随机配对 |

## 复现

```bash
mkdir -p /tmp/pilot/{data,logs,results,cache/SS} && cd /tmp/pilot
Rscript prep_xpr.R && Rscript prep_cp.R          # 约 3 + 2 min
Rscript validate_r.R && python3 validate_py.py   # 内核对拍（须先放好 2,000 列子矩阵的导出）
for d in "xpr U251MG" "xpr A549" "xpr PC3" "xpr MCF7" "cp A549" "cp PC3" "cp MCF7"; do
  set -- $d; nohup python3 run_pilot.py --kind $1 --cell $2 --n-queries 100 --n-perm 100 \
    --out-dir /tmp/pilot/results > logs/$1_$2.log 2>&1 &
done
python3 aggregate_results.py
```

注意：`validate_r.R` 会从 `data_preload/drugexp/LINCSxpr_U251MG_96h.rdata` 抽 2,000 列并导出 `/tmp/pilot/val/val_M.bin` 等文件；`validate_py.py` 依赖这些文件。运行 `run_pilot.py` 前需先跑 `prep_*.R`。
