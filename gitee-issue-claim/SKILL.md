---
name: gitee-issue-claim
slug: gitee-issue-claim
displayName: Gitee Issue 定时筛选与认领
version: 1.0.0
description: 定时轮询 Gitee 仓库 open Issue，按规则筛选并认领最多 1 个可处理 Issue（评论占位 + 分配给自己 + 添加 bot-processing 标签），维护双重幂等与轻量 JSON 状态机。支持 --dry-run 只读评估与 MCP/CLI 双模式调用。
---

# Gitee Issue 筛选与认领（Skill A）

## 定位与职责

属于三层架构中的**第二层（Issue 轮询与认领）**：

- 定时高频运行（建议每 30 分钟一次），只负责筛选并认领 **最多 1 个** 符合条件的 Issue。
- 不拉取代码、不改文件、不开 PR，认领后将 `issue_number` 交给 Skill B（`gitee-implement-issue`）处理。

## 输入参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `owner` | 是 | Gitee 仓库所属命名空间 / 组织名 |
| `repo` | 是 | Gitee 仓库名称 |
| `--dry-run` | 否 | 只读预演模式：仅输出会认领哪个 Issue 及各 Issue 的筛选理由，禁止任何写操作 |

## 筛选规则（必须同时满足）

1. `state == "open"`
2. `assignee` 为空（无人认领）
3. 标签中不包含 `bot-processing`
4. 没有已关联的开放 PR（检查 Issue 关联 PR 及仓库 open PR 引用 `#N`）
5. 若本地状态文件存在该 Issue 记录，不能已处于 `claimed`、`working`、`pr_open`、`failed` 或 `skipped`

## 幂等与安全红线

- **先写远端标记，再写本地状态**：真实认领时，必须先执行 `comment_issue` 并通过 `update_issue` 分配给自己且保留原有标签追加 `bot-processing`，成功后再将本地状态（`GITEE_ISSUE_STATE_PATH`，默认 `./state/gitee_issue_state.json`）迁移为 `claimed`。
- **标签兜底**：即使本地状态文件丢失或被删除，下一轮轮询只要检测到 `bot-processing` 标签就必须直接跳过，绝不重复认领。
- **并发限制**：每轮最多认领 **1 个** Issue，命中即停止。
- **凭证安全**：`GITEE_TOKEN` 仅通过环境变量读取，禁止硬编码或写入日志。

## 执行模式一：Agent 会话内通过 Gitee MCP Server 工具

当在 Claude Code / OpenClaw 会话中直接调用本 Skill 时，按以下 MCP 工具顺序执行：

1. 调用 `list_repo_issues(owner, repo, state="open")` 获取待筛查 Issue 列表。
2. 如需核对详情或评论上下文，调用 `get_repo_issue_detail` 与 `list_issue_comments`。
3. 逐条执行上述筛选规则，记录跳过理由。
4. 若为 `--dry-run`：仅输出候选 Issue 编号、标题和筛选理由，立即结束（禁止调用 `comment_issue` 或 `update_issue`）。
5. 对首个命中的 Issue：
   - 调用 `comment_issue` 发表认领说明（标明“AI 起草 PR、人工审核合并”）。
   - 调用 `update_issue` 将 `assignee` 设为当前机器人账号，并在**保留原有标签**的前提下追加 `bot-processing`。
   - 更新本地状态文件为 `claimed`，输出认领的 `issue_number`（若无命中则输出空）。

## 执行模式二：无头脚本 / Crontab CLI

```bash
export GITEE_TOKEN="your_token_here"
export GITEE_ISSUE_STATE_PATH="./state/gitee_issue_state.json"

# 1. Dry-run 只读评估（不写远端、不写状态文件）
python3 gitee-issue-claim/scripts/claim_issue.py --owner <owner> --repo <repo> --dry-run

# 2. 真实认领（成功时 stdout 输出认领的 issue_number，无命中输出空行）
python3 gitee-issue-claim/scripts/claim_issue.py --owner <owner> --repo <repo>

# 3. 结构化 JSON 输出（便于流水线审计）
python3 gitee-issue-claim/scripts/claim_issue.py --owner <owner> --repo <repo> --json
```
