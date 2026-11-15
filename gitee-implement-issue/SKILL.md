---
name: gitee-implement-issue
slug: gitee-implement-issue
displayName: Gitee Issue 编码实现与草稿 PR 提交
version: 1.0.0
description: 读取已认领 Gitee Issue 详情与评论，创建 fix/issue-{number}-{slug} 分支，在“Issue 直接相关有限文件”约束下起草修复、运行项目 lint/test 验证，通过后提交包含 closes #N 的 PR 并回写 Issue；失败时评论原因、清理分支并标记 skipped。严禁调用 merge_pull，支持 --dry-run 与自动选取最早 claimed Issue。
---

# Gitee Issue 编码实现与提 PR（Skill B）

## 定位与职责

属于三层架构中的**第三层（编码 Agent）+ 状态闭环回写**：

- 定位为“**AI 起草 PR，人来审核合并**”。
- 建议低频运行（例如每天 1 次），每次最多处理 **1 个** Issue。
- 未传入 `--issue-number` 时，自动从本地状态文件（`GITEE_ISSUE_STATE_PATH`）中选取 **1 个最早处于 `claimed` 状态**的 Issue。

## 输入参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `owner` | 是 | Gitee 仓库所属命名空间 / 组织名 |
| `repo` | 是 | Gitee 仓库名称 |
| `issue_number` | 否 | 目标 Issue 编号；省略时自动从状态文件选取最早 `claimed` 的 1 个 Issue |
| `--dry-run` | 否 | 只读预演模式：仅分析并输出预计修改的文件与大概实现方案，不建分支、不改文件、不提 PR |

## 安全闸门与硬性约束

1. **严禁自动合并**：**绝对禁止调用 `merge_pull`**，PR 必须由人工审核合并。
2. **分支命名规范**：`fix/issue-{number}-{slug}`（`slug` 从标题提取 ASCII 关键词或短哈希并限制长度，上限 40 字符）。
3. **有限相关文件约束**：只修改与该 Issue 直接相关的有限文件（默认上限 `GITEE_MAX_CHANGED_FILES=5`），禁止无关重构或大面积改写。
4. **轮次与超时上限**：编码 Agent 限制 `max-turns`（默认 `25`）与执行超时（默认 `1200s` / 20 分钟）。
5. **验证门禁**：提交 PR 前必须运行仓库既有的 `lint`/`test` 命令（若存在）；**任何验证不通过都禁止创建 PR**。
6. **PR 自动关单语法**：PR 正文必须包含 `closes #{number}`。
7. **失败回滚闭环**：无法理解 Issue、超出文件范围或验证不通过时，不提交 PR；调用 `comment_issue` 说明失败原因，清理本地与远端临时分支，状态经 `failed` 迁至 `skipped`。

## 执行模式一：Agent 会话内通过 Gitee MCP Server 工具

当在 Claude Code / OpenClaw 会话中直接执行本 Skill 时：

1. 若未指定 `issue_number`，读取 `GITEE_ISSUE_STATE_PATH` 挑选最早 `claimed` 的 1 条 Issue。
2. 调用 `get_repo_issue_detail` 与 `list_issue_comments` 获取完整上下文，确认尚未被关闭且无关联开放 PR。
3. 若为 `--dry-run`：仅输出预计修改的文件路径、修改方案与验证命令，立即结束，不执行任何写操作。
4. 调用 `create_branch` 基于默认分支创建 `fix/issue-{number}-{slug}`，本地检出并将状态迁至 `working`。
5. 在本地克隆仓库中仅修改与 Issue 直接相关的有限文件（若无法理解则中止并走失败处理）。
6. 运行项目既有 lint/test；不通过则回滚分支、`comment_issue` 说明原因并标记 `failed` → `skipped`。
7. 验证通过后 commit 并 push，调用 `create_pull` 创建 PR（正文含 `closes #{number}`），再调用 `comment_issue` 回写 PR 链接，并将状态更新为 `pr_open`。
8. **再次确认**：全程绝不调用 `merge_pull`。

## 执行模式二：无头脚本 / Crontab CLI

```bash
export GITEE_TOKEN="your_token_here"
export GITEE_REPO_DIR="/path/to/local-repo"
export GITEE_ISSUE_STATE_PATH="./state/gitee_issue_state.json"

# 1. Dry-run 只读方案预览
python3 gitee-implement-issue/scripts/implement_issue.py --owner <owner> --repo <repo> --issue-number 12 --dry-run

# 2. 显式指定 Issue 执行
python3 gitee-implement-issue/scripts/implement_issue.py --owner <owner> --repo <repo> --issue-number 12

# 3. 省略 --issue-number：自动挑选最早 claimed 的 1 个 Issue
python3 gitee-implement-issue/scripts/implement_issue.py --owner <owner> --repo <repo>
```
