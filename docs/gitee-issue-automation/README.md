# Gitee Issue 自动化处理指南（Skill A + Skill B）

本方案实现了定位为「**AI 起草 PR，人来审核合并**」的两段式 Gitee Issue 自动化处理 Skill，遵循三层分离架构、状态机 + `bot-processing` 标签双重幂等，以及严格的安全闸门。

## 目录与职责

| 组件 | 职责 | 对应文件 |
|---|---|---|
| **Skill A（`gitee-issue-claim`）** | 第二层：定时轮询 open Issue，筛选并认领最多 1 个 Issue（评论 + 分配给自己 + 打 `bot-processing` 标签） | [SKILL.md](../../gitee-issue-claim/SKILL.md) / [claim_issue.py](../../gitee-issue-claim/scripts/claim_issue.py) |
| **Skill B（`gitee-implement-issue`）** | 第三层：读取 Issue 详情与评论，建分支 `fix/issue-{number}-{slug}`，在有限相关文件范围内修改并运行 lint/test，通过后提交含 `closes #N` 的 PR 并回写 Issue | [SKILL.md](../../gitee-implement-issue/SKILL.md) / [implement_issue.py](../../gitee-implement-issue/scripts/implement_issue.py) |
| **共享核心（`gitee-issue-shared`）** | 配置加载、Token 脱敏日志、原子 JSON 状态机、Gitee API v5 客户端（禁用 `merge_pull`）、筛选规则与 Slug 生成 | [state_machine.py](../../gitee-issue-shared/state_machine.py) / [gitee_client.py](../../gitee-issue-shared/gitee_client.py) |
| **定时触发示例** | 第一层：系统 crontab 与 Gitee Go `schedule` 流水线配置 | [crontab.example](./crontab.example) / [gitee-go-schedule.yml](./gitee-go-schedule.yml) |

## 安装与环境要求

- **Python**：3.10+（核心完全使用 Python 标准库，零强制第三方依赖）。
- **Git**：需在本地克隆目标仓库，并已配置推拉权限（用于 Skill B）。
- **编码 Agent CLI**：Skill B 默认通过 `GITEE_CODING_AGENT_CMD`（默认 `claude`）以 `--max-turns` 和超时限制运行；也可在 Claude Code / OpenClaw 会话内直接加载 `SKILL.md` 并配合 Gitee MCP Server 工具运行。

安装到 Claude Code / OpenClaw 本地目录（如需独立拷贝）：

```bash
# 方式一：直接使用本仓库路径或 npx skills add
npx skills add aymwoo/openlearn-skills/gitee-issue-claim
npx skills add aymwoo/openlearn-skills/gitee-implement-issue

# 方式二：离线拷贝时需一并拷贝共享核心 gitee-issue-shared/ 到同级目录
cp -r gitee-issue-claim gitee-implement-issue gitee-issue-shared ~/.claude/skills/
```

## 环境变量配置

| 变量 | 必填 | 默认值 | 说明 |
|---|---|---|---|
| `GITEE_TOKEN` | 实跑必填 | 无 | Gitee Token；仅从环境变量读取，日志自动脱敏 |
| `GITEE_API_BASE` | 否 | `https://gitee.com/api/v5` | Gitee API v5 基地址 |
| `GITEE_BOT_USERNAME` | 否 | 自动调用 `/user` 获取 | 认领 Issue 时设置的 `assignee` |
| `GITEE_ISSUE_STATE_PATH` | 否 | `./state/gitee_issue_state.json` | 状态机 JSON 文件路径 |
| `GITEE_REPO_DIR` | 否 | `.` | Skill B 操作的本地 Git 仓库目录 |
| `GITEE_BASE_BRANCH` | 否 | 仓库默认分支 | 目标基准分支（如 `main` / `master`） |
| `GITEE_CODING_AGENT_CMD` | 否 | `claude` | 无头编码 Agent 命令（支持 `{prompt}` / `{max_turns}` 占位符） |
| `GITEE_AGENT_MAX_TURNS` | 否 | `25` | 编码 Agent 最大轮次 |
| `GITEE_AGENT_TIMEOUT_SEC` | 否 | `1200` | 编码 Agent 超时秒数（20 分钟） |
| `GITEE_VERIFY_CMD` | 否 | 自动探测 | 覆盖默认探测的 lint/test 命令 |
| `GITEE_MAX_CHANGED_FILES` | 否 | `5` | “Issue 直接相关有限文件”护栏上限 |

## 运行与 Dry-run 用法

```bash
# 1. Dry-run 演示（本地 Mock Server + 示例仓库，零外部影响）
bash docs/gitee-issue-automation/demo_dry_run.sh

# 2. Skill A Dry-run：只输出会认领哪个 Issue 及各 Issue 筛选理由
python3 gitee-issue-claim/scripts/claim_issue.py --owner <owner> --repo <repo> --dry-run

# 3. Skill A 真实认领（输出认领的 issue_number 或空）
python3 gitee-issue-claim/scripts/claim_issue.py --owner <owner> --repo <repo>

# 4. Skill B Dry-run：只输出预计修改的文件与变更方案
python3 gitee-implement-issue/scripts/implement_issue.py --owner <owner> --repo <repo> --issue-number 12 --dry-run

# 5. Skill B 真实执行（省略 --issue-number 时自动选取最早 claimed 的 1 个 Issue）
python3 gitee-implement-issue/scripts/implement_issue.py --owner <owner> --repo <repo>
```

## 状态机与双重幂等

状态流转：`new → claimed → working → pr_open`；异常或被排除则落入 `failed → skipped` 或 `skipped`。

1. **标签兜底幂等**：Skill A 在写本地状态之前，先调用 `comment_issue` 并 `update_issue` 追加 `bot-processing` 标签；后续即使 `gitee_issue_state.json` 丢失，轮询只要看到 `bot-processing` 就会跳过。
2. **文件锁 + 原子写入**：`StateStore` 通过 `fcntl.flock` + 临时文件 `os.replace` 保证并发定时任务不会损坏 JSON。

## 安全闸门与已知限制

- **禁止自动合并**：`GiteeClient` 与 `GiteeRestClient` 未实现 `merge_pull`，`SKILL.md` 亦明确禁用，PR 必须人工审核合并。
- **单轮并发上限**：Skill A 与 Skill B 每轮均严格最多处理 1 个 Issue。
- **已知限制**：
  - 自动关联 PR 检查除调用 `/issues/{number}/pull_requests` 外，还通过扫描 open PR 标题/正文是否引用 `#N` 判断；若人工开启 PR 未关联 Issue 或未写 `#N`，可能无法识别。
  - 若目标仓库无任何可探测的 lint/test 配置且未设置 `GITEE_VERIFY_CMD`，Skill B 会记录“未检测到自动测试”并继续提交草稿 PR，此时完全依赖人工 Review 兜底。
  - 编码质量与多文件边界依赖所配置的编码 Agent CLI 能力及 `GITEE_MAX_CHANGED_FILES` 上限控制。
