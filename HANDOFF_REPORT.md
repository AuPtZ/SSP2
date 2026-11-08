# SSP2 第四轮整改交付报告（2026-11-08）

基线：`56785c8`（路线 B 已 revert 的旧版站点）。备份见文末。
本轮共 6 个 commit，工作树干净。路线 B 按用户选项 A 从备份恢复后**重新审查/测试过**，未直接当作最终版。

---

## 阶段 0：改前备份

| 路径 | 内容 |
|---|---|
| `/home/data/auptz/ssp2_backup_20261108_round4/pre_round4.bundle` | 全分支 git 历史（15 MB） |
| `…/uncommitted.patch` | 改前的 9 个未提交文档改动 |
| `…/gitignore.before` | 改前 `.gitignore` |
| `/home/data/auptz/ssp2_rollback_20261108/` | **上一轮备份，原样未动**（bundle / routeB_data / routeB_scripts / patch） |

---

## 阶段 1 — `f7e1faa` 保留上一轮遗留改动

- 提交 8 个文档改动（含 **删除 limitations**，符合用户 2026-11-08 禁令，未被 checkout 掉）。
- `.gitignore` 按用户决策 q-2 丢弃其改动，恢复 `mcp` / `tahoe_prep/` / `R/mcp_utils.R` 三条忽略。

验收：`git show --stat f7e1faa` → 8 files, 23 insertions(+), 37 deletions(-)。

## 阶段 2 — `91e938c` 恢复路线 B

- 5 个路线 B 提交（`5411523`…`2d4b551`）本就在本地历史里，用 `git revert 56785c8` 恢复树，
  **未从 bundle fetch、未改写历史**；bundle 仅作保险。
- 验收：`git diff --stat 2d4b551 HEAD` 仅 8 文件（正是阶段 1 保留的清理）；工作树 clean。

## 阶段 3 — 数据回拷（不入 git）

- 从 `routeB_data/` 用 `cp -n` 拷回 **19 个 `LINCSxpr_*.rdata`**（约 3.0 GB）到
  `data_preload/drugexp/`，`dataset_registry.rdata` + `calibration_pilot.rdata` 到 `data_preload/others/`。
- 脚本（`maintain/13,14,15`、`pilot_b0/`）已随 git 恢复回来，md5 与备份一致，无需重复拷贝，未重跑 `maintain/02`。

验收：

```
drugexp LINCSxpr 数量: 19
化合物数据集数量（应仍为 831）: 831
registry: OK / calibration: OK
抽查 A549/MCF7/registry 源与目标字节数一致
registry 行数: 850   (cp 831 / xpr 19)
```

## 阶段 4 — `9158823` 按用户 4 个决策对齐恢复后的树

| 决策 | 处置 |
|---|---|
| q-0 删除 Q10 部署页 | 路线 B 的 `2d4b551` 本就已删（Q1–Q9），无需再动；孤儿 `www/info_Q10.md` 在阶段 6b 移出 |
| q-1 归档放项目外 | 恢复带回来的项目内 `archive/` 移到 `ssp2-admin/archive/`，与既有归档合并 |
| q-2 不要根 README | 恢复带回来的路线 B 版 `README.md` 移到 `ssp2-admin/README_routeB_2d4b551.md`；mcp/tahoe_prep 保持不入库 |
| q-3 路线 B 选 A | 见阶段 2/3 |

- **恢复带回来的 limitations 检查**：未出现（阶段 1 的删除在 revert 中保留），复核 `grep` 为 CLEAN。

## 阶段 5 — 恢复后重新审查/测试（未直接当最终版）

静态：

- 15 个 `.R` 文件 `parse()` 全通过；`beforerun.R` 可执行（R 4.4.1，31 个依赖，缺失 0）。
- `registry` 850 行 = 831 cp + 19 xpr；831 个化合物数据集文件未被修改。
- 任务 A 随 `5411523` 自动完成：Q8 挂 `info_Q9_bm_METRIC.md` + `_SUMMARY.md`、
  Q3 挂三份 `info_Q9_sm_*.md`、`tab_utils.R` 旧 `intro_res_bm_AUC_/ES_` Quick Tip 已清、
  `www/` 下无退役 ES/AUC 文档。

本地渲染（`127.0.0.1:3939`，`log/verify_routeb.js`）：

```
首页: HTTP 200, HTML 190 KB, title 正确, 含 LINCS-CRISPR / 校准面板, 无百度统计
Application: sel_source_sm 下拉 = LINCS | Tahoe-100M | LINCS-CRISPR
Help: Q1–Q9 连续, fiveMethods=false, aucIsMetric=false
图片: 28/28 加载, 28/28 带 alt, 0 个 4xx, 0 JS error
```

## 阶段 6a — `3e209dc` 任务 B：反向代理下的可收藏链接

`R/global.R::bookmarkable_job_url()` 改为三级回退，**未改任何 frp/nginx/Shiny Server 配置**：

1. `SSP2_PUBLIC_BASE` 环境变量（例 `https://web.biotcm.net/SSP2`）；
2. `session$request` 的 `HTTP_X_FORWARDED_HOST` / `HTTP_X_FORWARDED_PROTO`（逗号链取第一项，缺 proto 按 https）；
3. `clientData` 直连回退（本机开发正确）。

单元验证：

```
A 直连回退:          http://127.0.0.1:81/SSP2/?job=APP1
B forwarded(https):  https://web.biotcm.net/SSP2/?job=APP1
C forwarded(仅host): https://web.biotcm.net/SSP2/?job=APP1
D PUBLIC_BASE:       https://web.biotcm.net/SSP2/?job=APP1
```

真实 Shiny 会话（带 env）与**线上**实测均为：
`https://web.biotcm.net/SSP2/?job=APP1790669686URX`，Job Center 自动打开并显示结果/状态。

## 阶段 6b — `cd45903` P1 收口

- 数据溯源：`tab_info.R` / `info_Q1.md` 去掉不可核实的 "final L1000 release"，改为
  "SSP2 uses the CMap LINCS 2020 (Phase 2) Level-5 release"；`ChEMBL/DrugBank/ClinicalTrials.gov`
  明确写成**外部可参考资源、不是内置数据**（`tab_info.R`、`info_Q7.md`）；移除指向已不存在的根 README 的悬空引用。
- 删除重复的 `tags$title`（现仅 `window_title` 一个 `<title>`）。
- 孤儿 `info_Q10.md` 与过期 `sessioninfo.rdata` 移到项目外；`beforerun.R` **修好保留**为
  只读依赖检查脚本（不自动安装包）。
- 隐私措辞保持 `at least 90 days; there is no automatic deletion`（与实现一致，未加清理机制）。
- 拼写/品牌（`initializing`、`cancer-drug`、"upgraded version of the SSP webserver"）在路线 B 版本中已修好，复核 CLEAN。
- **未添加/恢复 limitations**（`info_Q9_bm_METRIC.md` / `_SUMMARY.md` 结尾未改）。

验收：

```
无 alt 图片=0  总 img=41  <title> 数=1  README 引用=0  limitations=CLEAN
About 渲染 10214 字符: 品牌/外部资源/隐私/无 final 断言 全部 true
```

## 阶段 6c — 任务 D：线上回归（2026-11-08）

线上已自动 reload 到路线 B（无需重启 worker 或改启动参数）：

| 检查 | 命令 / 结果 |
|---|---|
| 首页 | `curl -w` → `HTTP 200  TTFB 5.60s  size 179258`；`LINCS-CRISPR` ×9、`five methods` ×0 |
| 冷启动（空闲 65 s 后） | `curl -w` → `TTFB 5.63s`（启动参数按规则未改） |
| 文档图片 | 5 张抽测全部 `HTTP 200`；无头浏览器 28/28 加载、28/28 带 alt、0 个 4xx |
| Help | Q1–Q9 连续，`fiveMethods=false`、`aucIsMetric=false` |
| 深链 | `https://web.biotcm.net/SSP2/?job=APP1790669686URX` → Job Center 自动打开、显示链接与结果面板 |
| 模块切换 | `benchmark` / `singlemethod` / `jobcenter` / `ct_gene` / `ct_drug` 全部 clicked 且 active 正确 |
| Converter demo | `runCTGdemo`、`runCTDdemo1-3` 全部 clicked，输出表格存在，0 pageerror |
| 256px 移动端 | `scrollWidth=256 == innerWidth=256`（无横向溢出），60 个按钮，0 error |
| console | 全程 `pageerrors: []` |

> 说明：任务单称「8 个 demo 按钮」，实际代码中有 **12 个**（BEN 1、APP 3、JC 4、Converter 4）。
> 为避免触发 15–30 分钟的长计算与写入生产库，只点击了 4 个不产生计算任务的 Converter demo；
> 其余 8 个仅做存在性与模块切换核对，未实际提交计算任务。Benchmark/Application/Job Center 的
> 取回能力由 `?job=` 深链（已有结果）验证。

---

## git 状态

```
工作树: clean
git ls-files results/         → 0（生产 DB 未入库）
git ls-files mcp/ tahoe_prep/ R/mcp_utils.R → 0 / 0 / 0（q-2 不入库）
git rev-list --count origin/master..HEAD → 30
```

本轮 commit：

```
cd45903 docs(nar): fix provenance wording, single title, image alt; refresh dependency check script
3e209dc fix(job): build bookmarkable URLs from public base / forwarded headers behind reverse proxy
9158823 chore: align restored tree with user decisions (no root README, archives outside project)
91e938c Revert "revert(routeB/P0-2): restore site to pre-modification state ..."
f7e1faa docs: keep previous-round help, retired-doc and converter cleanups
```

---

## 剩余风险与待办

1. **`git tag v2.0.0` 与 `push` 尚未执行**（公开仓库操作，按约定先由用户确认）。
   `master` 领先 `origin/master` 30 个提交，push 会把路线 B 的 5 个提交连同 revert 历史一并公开。
2. `SSP2_PUBLIC_BASE` 目前**未设为常驻环境变量**：线上现靠 forwarded header / clientData 回退已能生成正确链接，
   但为长期稳妥建议在部署环境显式设置该变量（需改部署侧，本轮按规则未动）。
3. 路线 B 代码是**上一版实现**，本轮已重新通过静态与线上回归，但未做 CRISPR KO 全流程真实计算任务的端到端验证；
   如需上线为正式功能，建议再跑一次 `LINCS-CRISPR` 真实查询（会写入生产库）。
4. `data_preload/` 中 3 个历史入库的小元数据（274 B / 12 KB / 1.1 MB，Converter 必需）按「不删数据」原则保留。
5. 归档、备份、路线 B 版 README 均在项目外的 `/home/data/auptz/rprojects/ssp2-admin/`，不在 webserver 项目根。
