# GitHub / Gitee Issue / PR 协作工作流

> 本文件是 `SKILL.md`「模式 B：仓库协作」的完整执行手册。
> 目标：**接手 issue 前先占位，开发在独立 worktree 完成，所有变更通过 PR 提交，公开动作先经用户确认。**
>
> 平台策略：**GitHub 优先；只有 GitHub 网络 / 鉴权不可用时才回退 Gitee 镜像。**
> 一个变更只在一个平台开 PR；合并后立即把 `main` 同步到另一个平台，绝不 force-push。

---

## 0. 平台选择与仓库定位

### 0.1 镜像登记表

Gitee 回退**只对登记过的仓库生效**。登记文件：`references/repo-mirrors.json`。

| 平台 | 仓库 | 本地默认路径 | 当前账号权限 |
|------|------|-------------|-------------|
| GitHub（主） | `aymwoo/OpenLearn-Next-V2` | `~/Develop/openlearnv2` | owner |
| Gitee（镜像） | `aymwoo/openlearn-next` | 同上（同一工作区，双远端） | owner |
| GitHub | `openlearn-next/<plugin-repo>` | `~/Develop/openlearn-plugins/<plugin-repo>` | admin |
| GitHub（主） | `aymwoo/openlearn-skills` | `~/Develop/openlearn-skills` | owner |
| Gitee（镜像） | `aymwoo/openlearn-skills` | 同上（同一工作区，双远端） | owner |
| GitHub | `openlearn-next/plugin-exam-bank` | 未克隆，按需询问 | admin |

> 插件仓库目前**没有**登记 Gitee 镜像 → 只走 GitHub，不尝试回退。
> 新增镜像必须先改 `repo-mirrors.json`，再使用 Gitee 命令。

### 0.2 每次协作前先探测

```bash
cd <skill-dir>
bash scripts/platform-probe.sh --repo aymwoo/OpenLearn-Next-V2 \
  --local "$HOME/Develop/openlearnv2" --json
```

机读字段：

| 字段 | 含义 | 用法 |
|------|------|------|
| `preferred.fetch` | 首选 fetch 平台 | worktree / fetch 用 |
| `preferred.issuePr` | 首选 issue / PR 平台 | 创建、查看、评论、合并用 |
| `preferred.push` | 首选 push 平台 | 推分支用 |
| `fallback` | 回退平台（`gitee` / `none`） | 仅当首选不可用时 |

判定规则：

1. `preferred.issuePr == github` → 全程 GitHub。
2. `preferred.issuePr == gitee` → 说明 GitHub CLI 不可用但 Gitee 可用；**只在 Gitee 开 issue/PR**，push 用 `sync-mirror.sh`。
3. `preferred.issuePr == none` → 停止，报告两个平台的鉴权/网络错误；不要手写 API 绕过。
4. 没有 `repo-mirrors.json` 登记 → 只允许 GitHub；探测结果里的 Gitee 字段一律忽略。

> 探测只回答「现在哪个平台能用」，不改变「GitHub 是主仓」这一事实。
> GitHub 恢复后，下一次操作应自动回到 GitHub，不需要手工切换配置。

### 0.3 两个平台的差异（先看再操作）

| 维度 | GitHub | Gitee |
|------|--------|-------|
| 仓库 | `aymwoo/OpenLearn-Next-V2` | `aymwoo/openlearn-next` |
| CLI | `gh` | `gitee` |
| issue 编号 | 整数 `#123` | 字符串 `#I...`（如 `#I9ABC1`） |
| PR 编号 | 整数 `#45` | 整数 `#45` |
| issue 正文传参 | `--body-file <file>` | **无 `--body-file`**，用 `-b "$(cat <file>)"` |
| issue 标签 | `--label bug --label needs-triage` | `--labels bug,needs-triage`（逗号分隔） |
| 标签集合 | 有 `in-progress` 等 | 只有 `bug` / `enhancement` / `question` 等；**没有 `in-progress` / `needs-triage`** |
| PR 关联 issue | `Closes #123` | `Closes #I...`（合并后自动关闭） |
| CI 查询 | `gh pr checks` | 无等价命令；用 `gitee pipeline build list` 或网页 |
| 评审 | approve / comment / request-changes | **只有 approve / comment**；请求修改用评论写明 |
| 合并 | `gh pr merge --squash --match-head-commit` | `gitee pr merge --method squash`（无 match-head-commit） |
| 合并后同步 | `sync-mirror.sh sync-main --from github` | `sync-mirror.sh sync-main --from gitee` |

### 0.4 本地远端约定

```bash
# 平台仓库：origin = GitHub，gitee = Gitee 镜像
git -C "$LOCAL" remote -v
# 预期：
# origin  git@github.com:aymwoo/OpenLearn-Next-V2.git (fetch/push)
# gitee   https://gitee.com/aymwoo/openlearn-next.git (fetch/push)
```

- 如果只有 `origin` 且指向 GitHub：用 `sync-mirror.sh status` 会自动补 `gitee` remote。
- 如果 `origin` 指向 Gitee（从镜像克隆）：先跑
  `bash scripts/sync-platform-repo.sh status` 或 `sync-mirror.sh status`，脚本会把远端统一成
  `origin`=GitHub、`gitee`=Gitee；不要手工把 `origin` 留在 Gitee。
- **不要**给 Gitee 仓库开启「自动双向镜像」：它会覆盖分支、标签和提交，可能把 GitHub 上的
  PR 合并结果冲掉。统一用 `scripts/sync-mirror.sh` 手动同步。

### 0.5 权限事实（每次会话可复核）

```bash
gh auth status
# 预期 scopes: gist, read:org, repo

gitee auth status
# 预期：Logged in to gitee.com as <login>
```

- GitHub 没有 `project` scope → **不要尝试更新 GitHub Projects 看板状态**，统一用 assignee + 标签表达。
- Gitee 没有 Projects 等价物；用 assignee + 评论表达「已分配 / 进行中」。
- assign、加标签、评论需要对该仓库有 push 权限；平台仓库两边都是 owner。

### 0.6 仓库文档优先

定位到本地仓库后、创建 worktree 前，先读主 clone 的 `AGENTS.md`、`CLAUDE.md`、`README.md`、`package.json`；
进入 worktree 后再复核。若仓库文档与本文件冲突，**以仓库文档为准**，并在汇报中说明差异。

### 0.7 定位顺序（不要跳步）

1. 用户给了 issue/PR URL → 从 URL 解析平台、`owner/repo` 与编号。
   - `github.com/.../issues/123` → GitHub，整数编号。
   - `gitee.com/.../issues/I...` → Gitee，字符串编号。
   - `gitee.com/.../pulls/45` → Gitee，整数 PR 编号。
2. 当前目录是 git 仓库 → 用 `git remote -v` 推断；必须与用户意图一致。
3. 只有仓库名 → 查 0.1 表；路径存在则校验 remote，不存在则**先询问是否 clone**，不自动克隆。
4. 仍无法确定 → 停下询问，绝不跨到无关仓库。
5. 当前仓库查不到该编号 → **不要自动换平台或换仓库**；列出候选让用户选。

```bash
# 校验本地仓库远端（同时兼容 ssh / https）
git -C "$LOCAL" remote -v

# 需要时克隆（先征得用户同意）
gh repo clone "$GH_REPO" "$LOCAL"
# GitHub 不可达且已登记镜像时：
git clone https://gitee.com/aymwoo/openlearn-next.git "$LOCAL"
```

---

## 1. 接管 Issue 前预检

### 1.1 读取 issue

**GitHub**

```bash
REPO="aymwoo/OpenLearn-Next-V2"
N=133
LOCAL="$HOME/Develop/openlearnv2"

gh issue view "$N" -R "$REPO" \
  --json number,title,body,state,stateReason,author,assignees,labels,comments,url,createdAt,updatedAt
```

**Gitee**

```bash
REPO="aymwoo/openlearn-next"
N="I9ABC1"          # Gitee issue 是字符串编号
LOCAL="$HOME/Develop/openlearnv2"

gitee issue view "$N" -R "$REPO" \
  --json=number,title,body,state,user.login,assignee.login,labels.name,html_url,created_at,updated_at
```

逐项检查：

- `state` 必须是 open；已关闭 → 停止，说明关闭原因。
- assignee 是自己（GitHub `aymwoo` / Gitee `aymwoo`）→ 视为已占位，跳过 assign。
- assignee 是其他人 → **停止**，询问是否仍要接手；不要抢别人的 issue。经确认后可 assign 给自己，
  是否移除原 assignee 必须由用户明确指示。
- 标签含「进行中」但 assignee 为空 → 检查最近评论是否有人声明在做；有则停止。
- issue 正文缺少可验证的验收标准 → 见 1.4。

### 1.2 重复开发检查（两个平台都要查）

同一变更可能在另一个平台已有 PR。先查 GitHub，再查 Gitee：

```bash
# GitHub：开放 PR 是否引用该 issue
gh pr list -R aymwoo/OpenLearn-Next-V2 --state open --limit 100 \
  --json number,title,body,headRefName,author \
  | jq --arg n "$N" '
    [.[] | select(
      ((.title + " " + (.body // "") + " " + .headRefName)
       | test("(#" + $n + "([^0-9]|$))|(issue[-_/]" + $n + "([^0-9]|$))|(/issues/" + $n + "([^0-9]|$))"))
    )]
  '

# Gitee：按分支名 / 标题 / 正文关键词查开放 PR
gitee pr list -R aymwoo/openlearn-next -s open -l 100 \
  --json=number,title,body,head.ref,user.login \
  | python3 -c '
import json, sys
needle = sys.argv[1]
rows = json.load(sys.stdin)
for p in rows:
    blob = " ".join(str(p.get(k, "")) for k in ("title", "body")) + " " + str((p.get("head") or {}).get("ref", ""))
    if needle in blob:
        print(p.get("number"), p.get("title"), (p.get("head") or {}).get("ref"), (p.get("user") or {}).get("login"))
' "$N"
```

再查远程是否已有对应分支（两边都查）：

```bash
git -C "$LOCAL" fetch origin --prune 2>/dev/null || true
git -C "$LOCAL" fetch gitee --prune 2>/dev/null || true
git -C "$LOCAL" ls-remote --heads origin "refs/heads/*issue-$N*"
git -C "$LOCAL" ls-remote --heads gitee  "refs/heads/*issue-$N*"
```

- 命中开放 PR → **停止**，把平台、PR 号/分支/作者告诉用户。
  - 作者是自己 → 建议改为处理该 PR（审查/返工/合并）。
  - 作者是他人 → 询问是协作还是放弃。
- 只有远程分支、没有 PR → 查最近 commit 与作者；不是自己则停止询问。
- 自己已有的分支/worktree → 可继续，但要先确认状态干净。
- 只有已合并 PR 引用该 issue、但 issue 仍 open → 先确认是否漏关（缺 `Closes`），不要直接重做。

> `--arg` 是 jq 的参数，不能直接传给 `gh --jq`；必须用管道交给系统 `jq`。
> Gitee 的 `--json` 字段选择不支持 `body` 全文搜索，所以用 Python 在本地过滤。

### 1.3 本地已有 worktree 检查

```bash
git -C "$LOCAL" worktree list --porcelain
```

- 目标 worktree 已存在且分支匹配 → 复用；若 `git -C "$WT" status --porcelain` 有输出，先汇报，不覆盖。
- 目标路径存在但不是该仓库的 worktree → **停止**，绝不覆盖。

### 1.4 验收标准检查

issue 至少应能回答：**要什么、怎么复现/验证、什么算完成**。

- 信息充分 → 进入第 2 节。
- 信息不足 → 停止开发，列出缺失项；可代拟一条澄清评论，**发布前必须经用户确认**。
- 不在本流程内凭空创建新 issue；如确实需要，先询问用户。

---

## 1A. 创建缺陷 Issue（系统侧缺陷上行）

> 与第 1 节相反方向：不是「接手已有 issue」，而是「把插件侧归因出的**平台缺陷**上报」。
> 入口：`SKILL.md`「第六步 B」。**只有归因结论为「系统侧」才能走本节。**
>
> 平台选择：先跑 0.2 的探测。GitHub 可用 → 提 GitHub；GitHub issue 能力不可用且
> `repo-mirrors.json` 登记了镜像 → 提 Gitee。**不要在两个平台各提一份。**

### 1A.1 上游门禁（缺一不提）

1. 已满足系统侧 4 条证据门槛（最小复现稳定复现 / 版本与堆栈齐全 / 报错点在宿主或 SDK / 已排除环境与插件冲突）。
2. 已去重（见 1A.2，两个平台都要查）。
3. 用户已审阅完整标题与正文并**明确同意**——Issue 对仓库可读者公开可见。
4. 已过脏数据脱敏（见 1A.5）。

### 1A.2 去重（含已关闭 issue，两个平台）

```bash
# GitHub
gh issue list -R aymwoo/OpenLearn-Next-V2 --state all --limit 50 \
  --search "<错误码 / 错误文案 / 模块名> in:title,body" \
  --json number,title,state,url,closedAt

# Gitee
gitee issue list -R aymwoo/openlearn-next -s all -l 50 \
  --query "<错误码 / 错误文案 / 模块名>" \
  --json=number,title,state,html_url

# 仓库内已知问题清单
rg -n "<关键词>" ~/Develop/openlearnv2/docs/beta/known-issues.md
```

| 命中 | 动作 |
|------|------|
| 开放 issue（同现象，任一平台） | 不新开；改为在该 issue 下补充评论（需确认） |
| 已关闭 issue 且修复版本 ≤ 当前版本 | 建议升级；升级后仍复现 → 新开并在正文注明「回归：原 #<编号>」 |
| 已关闭 issue 且修复版本 > 当前版本 | 同上，先升级 |
| `known-issues.md` 已列为已知限制 | 不提 Issue，转告用户官方口径与规避方案 |
| 无命中 | 继续 |

> GitHub 与 Gitee 的 issue **不会自动互相同步**。只查一个平台可能漏掉另一个平台的重复单。

### 1A.3 标题与正文

- 标题：`[缺陷] <模块/组件>：<一句话现象>`（仓库缺陷表单用 `[缺陷] ` 前缀）
- 正文：`assets/platform-issue-template.md` 渲染到 `/tmp/openlearn-issue-<slug>.md`
- **三段必备**：`## 问题原因`（具体包/文件/机制 + 触发链 + 版本口径 + 关键堆栈帧）、
  `## 影响`（受影响对象 + 阻塞程度 + 版本区间 + 触发概率 + 连带影响 + 临时规避）、
  `## 建议解决方式`（改动点 + 方案权衡 + 验收标准）
- 另必附：环境信息（含表单要求项：报告人角色=开发者 / 对上课的影响 / 版本）、复现步骤、期望 vs 实际、完整堆栈、
  最小复现插件、归因证据与对照实验、已排除项

### 1A.4 执行

> **确认门**：先展示 `TITLE` 与 `BODY` 全文，确认后才执行。

**GitHub**

```bash
REPO="aymwoo/OpenLearn-Next-V2"
TITLE="[缺陷] <模块/组件>：<一句话现象>"
BODY=/tmp/openlearn-issue-<slug>.md

gh auth status || { echo "未登录 gh，改用手动提交"; }
gh issue create -R "$REPO" --title "$TITLE" --body-file "$BODY" \
  --label bug --label needs-triage
```

**Gitee**

```bash
REPO="aymwoo/openlearn-next"
TITLE="[缺陷] <模块/组件>：<一句话现象>"
BODY=/tmp/openlearn-issue-<slug>.md

gitee auth status || { echo "未登录 gitee，改用手动提交"; }
# Gitee CLI 没有 --body-file，必须把正文作为参数传入
gitee issue create -R "$REPO" -t "$TITLE" -b "$(cat "$BODY")" --labels bug
```

- 只用仓库已有标签；**不自创标签、不 assign 他人、不在正文 @ 维护者**。
  - GitHub：`bug` / `needs-triage`。
  - Gitee：仓库只有 `bug` / `enhancement` / `question` 等，**没有 `needs-triage`**；用 `bug` 即可。
- 提交后回读确认，并输出平台、编号、标题、URL、标签。
  - GitHub：`gh issue view <n> -R "$REPO" --json number,title,url,state`
  - Gitee：`gitee issue view "<I...>" -R "$REPO" --json=number,title,html_url,state`
- 最小复现插件体积小 → 源码贴正文；否则写「可提供 zip」。

### 1A.5 脱敏（公开可见）

删除：学生全名册 / 作业试卷原文 / 成绩导出 · 密码、班级临时口令、Cookie、`edu_os_token` ·
AI API Key（**含首尾掩码**）· `.env` / `ENCRYPTION_KEY` / `bootstrap-credentials.txt` · 身份证 / 住址 / 电话 / 健康信息。
只留 `x-request-id` 与「3 班第 2 次作业」这类去标识描述。

### 1A.6 失败回退

| 情况 | 动作 |
|------|------|
| `gh` 未登录 / 无该仓库权限 | 不重试；保留正文文件，给 `https://github.com/aymwoo/OpenLearn-Next-V2/issues/new` 手动提交 |
| `gitee` 未登录 / 无该仓库权限 | 不重试；保留正文文件，给 `https://gitee.com/aymwoo/openlearn-next/issues/new` 手动提交 |
| 首选平台失败但另一个平台可用 | 先报告失败原因，**经用户确认**后才换平台；不要静默改投 |
| 网络失败 / 429 | 报告错误原文，保留正文文件路径，不自动循环 |
| 创建后才发现信息不足 | 用评论补充（需确认），不删重建 |
| 用户事后反悔 | 不擅自关闭/删除；询问后按用户指令操作 |

---

## 2. 占位三件套（assign + label + comment）

> **确认门 1**：先把 issue 摘要、验收标准、分支名、worktree 路径、评论草稿展示给用户，确认后才执行本节。
> 所有公开可见动作不得跳过确认。

### 2.1 assign 给自己

```bash
# GitHub
gh issue edit "$N" -R aymwoo/OpenLearn-Next-V2 --add-assignee @me

# Gitee（assignee 用登录名，不是显示名）
gitee issue assign "$N" aymwoo -R aymwoo/openlearn-next
```

### 2.2 标签

**GitHub**

```bash
if ! gh label list -R "$REPO" --search "in-progress" --json name --jq '.[].name' \
  | grep -qx "in-progress"; then
  gh label create "in-progress" -R "$REPO" \
    --color "e36209" \
    --description "Currently being worked on"
fi

gh issue edit "$N" -R "$REPO" --add-label "in-progress"
```

**Gitee**

```bash
# Gitee 仓库没有 in-progress / needs-triage；不要为了流程自创标签。
# 用 assignee + 占位评论表达「已分配 / 进行中」。
# 如需打已有标签，--labels 会替换全部标签，先看清当前标签再执行：
gitee issue edit "$N" -R aymwoo/openlearn-next --labels bug
```

- 只按需创建 GitHub 的 `in-progress`；不要创建 `ready-for-agent` 等 triage 标签。
- 标签已存在时 `gh label create` 会报错；上面的判断用于避免噪音。
- Gitee 的 `--labels` 是**覆盖**不是追加；移除标签时把剩余标签一起列上。

### 2.3 发布占位评论

```bash
LOGIN_GH="$(gh api user --jq .login 2>/dev/null || echo aymwoo)"
LOGIN_GT="$(gitee api /user 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("login","aymwoo"))' 2>/dev/null || echo aymwoo)"

cat > "/tmp/opencode/issue-${N}-claim.md" <<EOF
开始处理本 issue。

- 负责人：@${LOGIN_GH}
- 分支：\`<type>/issue-${N}-<slug>\`
- 开发方式：本地独立 worktree

如有重复工作或不同方案，请在本 issue 下告知，避免冲突。
EOF
```

```bash
# GitHub
gh issue comment "$N" -R aymwoo/OpenLearn-Next-V2 --body-file "/tmp/opencode/issue-${N}-claim.md"

# Gitee
gitee issue comment "$N" -R aymwoo/openlearn-next -b "$(cat "/tmp/opencode/issue-${N}-claim.md")"
```

**幂等**：若已有自己发布的、含「开始处理本 issue」且分支一致的评论，跳过，不重复刷屏。

### 2.4 占位回滚

若占位后无法继续（worktree 创建失败、用户取消、发现重复开发），先汇报，确认后执行：

```bash
# GitHub
gh issue edit "$N" -R "$REPO" --remove-label "in-progress"
gh issue edit "$N" -R "$REPO" --remove-assignee @me

# Gitee（没有 in-progress 标签时只撤销 assignee）
gitee issue edit "$N" -R aymwoo/openlearn-next -a "" 2>/dev/null || true
```

> Gitee CLI 的 `issue edit -a ""` 是否支持清空 assignee 取决于版本；不支持就说明「Gitee 端保留 assignee」，
> 由用户在网页上取消，不要反复试错。评论是否删除或更正，由用户决定；不要擅自删评论。

---

## 3. 创建 worktree

### 3.1 路径与分支命名

| 场景 | worktree 路径 |
|------|--------------|
| 平台 issue | `~/Develop/openlearn-issue-<n>` |
| 插件 issue | `~/Develop/openlearn-plugins/<repo>-issue-<n>` |
| PR 审查（临时） | `~/Develop/openlearn-pr-<n>` / `~/Develop/openlearn-plugins/<repo>-pr-<n>` |

分支：`<type>/issue-<n>-<slug>`

**type 推断**（标题前缀优先，其次标签）：

| 信号 | type |
|------|------|
| 标题 `fix(...)` / 标签 `bug` | `fix` |
| 标题 `feat(...)` / 标签 `enhancement` | `feat` |
| 标题 `docs(...)` / 标签 `documentation` | `docs` |
| 标题 `refactor(...)` | `refactor` |
| 标题 `test(...)` | `test` |
| 标题 `chore(...)` / 其他 | `chore` |

**slug 规则**：3-6 个英文小写单词，连字符分隔，表达变更语义；避免拼音堆砌。

示例：

- `#133 security(presence): presence-update 全局广播…` → `fix/issue-133-presence-broadcast-scope`
- `#122 [P0c] 测评子系统 · 学生端作答 UI` → `feat/issue-122-student-assessment-ui`
- Gitee `#I9ABC1` → 分支仍可用 `fix/issue-I9ABC1-<slug>`（编号原样保留，便于检索）。

### 3.2 创建

```bash
BRANCH="<type>/issue-<n>-<slug>"
WT="$HOME/Develop/openlearn-issue-<n>"

# GitHub 优先
git -C "$LOCAL" fetch origin --prune
git -C "$LOCAL" worktree add -b "$BRANCH" "$WT" origin/main

# GitHub 不可达、且已登记 Gitee 镜像时
# git -C "$LOCAL" fetch gitee --prune
# git -C "$LOCAL" worktree add -b "$BRANCH" "$WT" gitee/main

git -C "$WT" status -sb
git -C "$WT" log --oneline -1
```

- 始终从主平台的 `main` 建分支；GitHub 可用时用 `origin/main`，不可用时用 `gitee/main`。
- 不要动主 clone 的工作区。主 clone 有未提交改动不影响 worktree 创建，但**不要**在主 clone 里顺手改代码。
- 若 `git worktree add` 因分支已存在失败：确认分支是否属于自己、是否已合并；不要直接 `-B` 覆盖。

---

## 4. 开发与本地验证

### 4.1 先读仓库约定

- 平台：`AGENTS.md`、`CLAUDE.md`、`README.md`、`package.json`、`.github/workflows/ci.yml`。
- 插件：`README.md`、`package.json`、`build.js`、`test/`。

### 4.2 平台仓库（`aymwoo/OpenLearn-Next-V2`）

worktree 是全新 checkout，**没有 `node_modules`**，首次需安装：

```bash
cd "$WT"
pnpm install --frozen-lockfile
```

开发中跑定向测试（按改动文件选择）：

```bash
pnpm vitest run <test-file-or-dir>
```

开 PR 前至少跑类型检查（CI 会跑全量测试）：

```bash
pnpm lint
pnpm lint:strict
```

- 用户已确认「定向测试 + 由 CI 跑全量」，因此**不强制**本地跑完整 `pnpm test`；但涉及核心链路时建议主动补跑。
- 若改动前端/构建配置，可加跑 `pnpm build`（耗时较长，先说明）。

### 4.3 插件仓库（`openlearn-next/*`）

按其 `package.json` 里**实际存在**的脚本执行，不臆造命令：

| 仓库 | 可用脚本（示例） | 注意 |
|------|-----------------|------|
| `class_manager` | `build`, `typecheck` | 无 test |
| `lab-seat` | `build`, `test` | `test` 会先构建测试 bundle |
| `interactive-courseware` | `build`（内含 `bump-version.js`） | **构建会改版本号**，非必要不跑；跑了要检查并还原无关版本变更 |
| `attendance-record` | `build` | 无 test |
| `lianyun-course` | `build`, `test` | `test` 为 `vitest run` |

- 按 lockfile 选择包管理器（`pnpm-lock.yaml` → pnpm，`package-lock.json` → npm，`yarn.lock` → yarn）。
- 没有 test 脚本就如实说明「该仓库无自动化测试」，用构建 + 手工验证补足。

### 4.4 提交

- 1-3 个逻辑提交；最终 PR 以 squash 合并。
- 提交信息：`<type>(<scope>): <中文摘要>（Issue #<n>）`
  - 示例：`fix(security): 修复 presence 全局广播泄露（Issue #133）`
  - Gitee：`fix(security): 修复 presence 全局广播泄露（Issue #I9ABC1）`
- 只 `git add` 本次相关文件；提交前看 `git status`，不要带入无关改动、构建产物或密钥。
- 不直接 push `main`，不在主 clone 提交。

---

## 5. 创建 PR

> **确认门 2**：展示 `git diff --stat`、提交列表、实际执行的测试命令与结果、PR 标题/正文、目标平台，确认后才 push + 开 PR。

### 5.1 push 分支（GitHub 优先，Gitee 镜像）

```bash
cd <skill-dir>
bash scripts/sync-mirror.sh push "$BRANCH" \
  --repo aymwoo/OpenLearn-Next-V2 --local "$LOCAL"
```

行为：

- GitHub 可用 → 推 `origin`，成功后自动镜像推 `gitee`。
- GitHub 网络/鉴权失败 → 只推 `gitee`，并提示「GitHub 待同步」。
- GitHub 返回 `rejected`（非 fast-forward / 保护分支）→ **不回退 Gitee**，避免把分叉带到另一边。
- 查看结果：`bash scripts/sync-mirror.sh status --local "$LOCAL"`。

> 不要用裸 `git push -u origin "$BRANCH"` 代替：它不会镜像到 Gitee，也不会区分可回退/不可回退的失败。

### 5.2 PR 正文模板

写入 `/tmp/opencode/pr-body-<repo>-<n>.md`：

```markdown
## 变更内容

- ...

## 关联 Issue

Closes #<n>

## 测试计划

- [x] `<command>` — 通过
- [x] `<command>` — 通过

## 截图

（仅 UI 改动；无 UI 改动请删除本节）

## 风险与回滚

- 风险：...
- 回滚：revert 本 PR 即可。
```

> Gitee 的关联写法是 `Closes #I...`（issue 字符串编号）；GitHub 是 `Closes #123`。
> 不确定编号格式时，先 `gitee issue view` / `gh issue view` 回读，不要猜。

### 5.3 创建

**GitHub**

```bash
gh pr create -R aymwoo/OpenLearn-Next-V2 \
  --base main \
  --head "$BRANCH" \
  --title "<type>(<scope>): <摘要>（Issue #<n>）" \
  --body-file "/tmp/opencode/pr-body-<repo>-<n>.md"
```

**Gitee**

```bash
gitee pr create -R aymwoo/openlearn-next \
  --base main \
  --head "$BRANCH" \
  -t "<type>(<scope>): <摘要>（Issue #I...）" \
  -b "$(cat "/tmp/opencode/pr-body-<repo>-<n>.md")"
```

规则：

- 全中文；标题遵循 Conventional Commits；正文必须有 `Closes #<编号>`。
- 测试计划写**真实执行的命令与结果**，不写“已测试”这类空话。
- UI 改动附截图；无法截图时说明原因。
- 默认创建 ready PR；代码未完成才用 `--draft`（Gitee 也支持 `--draft`）。
- 一个 issue 对应一个 PR；不要在一个 PR 里夹带无关重构。
- **同一个变更不要在两个平台各开一个 PR**。若已误开，保留主平台 PR，另一个关闭并评论指向主 PR（需确认）。

---

## 6. CI 处理

**GitHub**

```bash
timeout 600 gh pr checks <pr> -R aymwoo/OpenLearn-Next-V2 --watch --interval 30
```

**Gitee**

```bash
# 若仓库已接 Gitee Go：
gitee pipeline build list -R aymwoo/openlearn-next \
  --ref "$BRANCH" --json=id,buildNumber,status,startTime,endTime,fileName

# 若未接 Gitee Go：以 PR 页面的人工验证/评论为准，不要伪造 CI 结论。
```

等待上限 10 分钟。**超时视为 pending，不要判失败**；汇报后由用户决定是否继续等待。
非阻塞检查（如 GitHub 的 `Windows platform probe`）失败不阻断合并，但必须汇报。

失败时：

```bash
# GitHub
gh run list -R "$REPO" --branch "$BRANCH" --limit 5 \
  --json databaseId,workflowName,conclusion,createdAt,url
gh run view <run-id> -R "$REPO" --log-failed

# Gitee
gitee pipeline build list -R aymwoo/openlearn-next --ref "$BRANCH" \
  --json=id,buildNumber,status,message,startTime,endTime
```

分类处理：

| 类型 | 动作 |
|------|------|
| 明显由本次改动导致 | 自动修 **1 轮**，补提交、push、重新等待 |
| 环境/网络/缓存/flaky | 停止，汇报失败任务与关键日志，不反复重跑 |
| 与本次改动无关的既有失败 | 停止，说明基线问题，询问是否继续 |

- 最多自动修一轮，避免无限循环。
- **CI 未绿不合并，不提供绕过选项**。Gitee 没有 checks 命令时，用「PR 页面状态 + 本地测试结果」作为证据，
  并在合并确认卡里写明「Gitee CI 未接入 / 已人工验证」。

---

## 7. 审查 PR

### 7.1 状态卡片

**GitHub**

```bash
gh pr view <pr> -R aymwoo/OpenLearn-Next-V2 \
  --json number,title,author,isDraft,state,baseRefName,headRefName,mergeable,mergeStateStatus,reviewDecision,additions,deletions,changedFiles,closingIssuesReferences,url
gh pr checks <pr> -R aymwoo/OpenLearn-Next-V2
gh pr view <pr> -R aymwoo/OpenLearn-Next-V2 --comments
```

**Gitee**

```bash
gitee pr view <pr> -R aymwoo/openlearn-next \
  --json=number,title,state,draft,mergeable,head.ref,base.ref,user.login,html_url,created_at,updated_at
gitee pr diff <pr> -R aymwoo/openlearn-next --json=filename,status,additions,deletions
gitee pr comment <pr> -R aymwoo/openlearn-next -b "..."   # 仅评论；查看评论用网页或 API
```

先输出只读状态卡片，再问用户要执行哪种动作：**审查 / 修评论 / 合并 / 仅解释**。不要自动审查或自动合并。

### 7.2 读 diff

```bash
# GitHub
gh pr diff <pr> -R aymwoo/OpenLearn-Next-V2 --name-only
gh pr diff <pr> -R aymwoo/OpenLearn-Next-V2

# Gitee
gitee pr diff <pr> -R aymwoo/openlearn-next --json=filename,status,additions,deletions
gitee pr diff <pr> -R aymwoo/openlearn-next
```

大 PR 先按文件列表拆分，再逐文件看；重点关注：行为变更、边界条件、错误处理、权限/数据范围、测试覆盖、与关联 issue 的一致性。

### 7.3 需要本地验证时

创建临时 review worktree（不污染主 clone）：

```bash
REVIEW_WT="$HOME/Develop/openlearn-pr-<pr>"

# GitHub
git -C "$LOCAL" fetch origin "$HEAD_BRANCH"
git -C "$LOCAL" worktree add --detach "$REVIEW_WT" "origin/$HEAD_BRANCH"

# Gitee（分支已镜像到 gitee 时）
# git -C "$LOCAL" fetch gitee "$HEAD_BRANCH"
# git -C "$LOCAL" worktree add --detach "$REVIEW_WT" "gitee/$HEAD_BRANCH"
```

fork PR 的 head 分支不在 origin 时（仅 GitHub）：

```bash
git -C "$LOCAL" fetch origin "pull/<pr>/head:refs/remotes/origin/pr-<pr>"
git -C "$LOCAL" worktree add --detach "$REVIEW_WT" "origin/pr-<pr>"
```

> 插件仓库把 `REVIEW_WT` 换成 `$HOME/Develop/openlearn-plugins/<repo>-pr-<pr>`。

在 review worktree 里跑定向测试；评审结束确认无未提交改动后再询问是否删除。

### 7.4 评审意见的发布

先在对话里给出草稿：

- 结论建议：`comment` / `request-changes` / `approve`
- 阻塞项：`file:line` + 问题 + 建议
- 非阻塞项：同上
- 与 issue 的一致性判断

用户确认后才发布：

**GitHub**

```bash
gh pr review <pr> -R "$REPO" --comment --body-file "/tmp/opencode/review-<pr>.md"
# 有阻塞项：
gh pr review <pr> -R "$REPO" --request-changes --body-file "/tmp/opencode/review-<pr>.md"
# 无阻塞项且用户明确同意：
gh pr review <pr> -R "$REPO" --approve --body-file "/tmp/opencode/review-<pr>.md"
```

**Gitee**

```bash
# 只有 approve / comment，没有 request-changes。
# 有阻塞项时：用评论明确写「请求修改」+ 阻塞项，不要点 approve。
gitee pr comment <pr> -R aymwoo/openlearn-next -b "$(cat "/tmp/opencode/review-<pr>.md")"

# 无阻塞项且用户明确同意：
gitee pr review <pr> -R aymwoo/openlearn-next -b "已审查，无阻塞项。"
```

规则：

- **自己的 PR 不能 approve**（GitHub 限制），只能 `--comment`；Gitee 同样不要给自己的 PR 点 approve。
- 有阻塞项不得 approve。
- 所有公开评审动作先经用户确认。
- 不替别人 resolve 讨论串。

---

## 8. PR 返工

> 本节默认是**自己（或已获授权）的 PR**。对他人 PR 的 review 意见，只做审查与回复建议；未经作者/用户明确授权，不要 push 到对方分支。
> 需要改代码时，另开分支 + 新 PR，并在原 PR 下说明。

### 8.1 拉取未解决讨论串

**GitHub**

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 50) {
            nodes { author { login } body createdAt url }
          }
        }
      }
    }
  }
}' -F owner="<owner>" -F repo="<repo>" -F number=<pr>
```

**Gitee**

```bash
# Gitee CLI 没有 review thread 查询；用 PR 评论 + 网页查看行内评论。
gitee pr view <pr> -R aymwoo/openlearn-next --json=number,title,body,html_url
# 行内评论在网页的「文件变更」页查看；需要逐条回复时用：
gitee pr comment <pr> -R aymwoo/openlearn-next -b "回复：<意见摘要> → 已修复 <commit>"
```

### 8.2 逐条处理

- 可执行意见 → 在 worktree 修改、补提交、push。
- 需要解释的意见 → 准备回复，不强行改。
- 与 issue 范围冲突的意见 → 先汇报，问用户是否扩大范围。

### 8.3 回复讨论串

**GitHub**

```bash
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $threadId,
    body: $body
  }) { comment { url } }
}' -F threadId="<thread-id>" -f body="已修复：<commit-hash>。"
```

**Gitee**

```bash
gitee pr comment <pr> -R aymwoo/openlearn-next \
  -b "已修复：<commit-hash>。<对应意见摘要>"
```

规则：

- 回复里带 commit hash 与简短说明。
- **不替别人 resolve 讨论串**；是否 resolve 由 reviewer 决定。
- 普通 `push` 优先；确需重写自己 PR 分支历史时才用 `--force-with-lease`，且执行前确认。
- 返工 push 同样走 `sync-mirror.sh push "$BRANCH"`，保持两边分支一致。
- 永不 force-push `main` 或共享分支。

---

## 9. 合并 PR

> 仅在用户**明确说“合并”**时执行。仓库 `main` 没有分支保护，本流程是唯一防线。
> 合并只能在**开 PR 的那个平台**执行；另一个平台只做 `main` 同步，不再重复合并。

### 9.1 前置条件

- [ ] PR 为 open 且非 draft
- [ ] 所有阻断性 CI 检查全绿（明确标注 non-blocking 的失败需汇报，不阻断；Gitee 未接 CI 时需人工验证并注明）
- [ ] `mergeable` 为 true / GitHub `MERGEABLE`，且不是 `DIRTY` / `BLOCKED`
- [ ] 无未处理的「请求修改」意见
- [ ] 所有 review thread 已处理或已得到用户豁免
- [ ] 用户已再次确认最终 squash commit message
- [ ] 已记录合并前头指针（防止确认后 PR 又追加提交）

### 9.2 执行（GitHub）

```bash
HEAD_SHA=$(gh pr view <pr> -R aymwoo/OpenLearn-Next-V2 --json headRefOid --jq .headRefOid)
gh pr merge <pr> -R aymwoo/OpenLearn-Next-V2 \
  --squash \
  --match-head-commit "$HEAD_SHA" \
  --subject "<PR 标题>" \
  --body "<简要总结 + Closes #<n>>"
```

- 默认 squash。
- `--match-head-commit` 防止确认后 PR 又追加提交；被拒绝说明头指针已变，重新审查后再合并。
- **不要用 `--delete-branch`**：PR 分支正被 worktree 占用时，gh 删除本地分支会失败。合并成功后再显式清理（见 10.1）。
- 不加 `--admin`；不加 `--auto`（自动合并会绕过最终确认）。
- 不合并自己的 PR，除非用户明确要求（平台 `AGENTS.md` 的要求）。

### 9.3 执行（Gitee）

```bash
# 合并前记录头指针；确认后、合并前再核一次
HEAD_SHA=$(git -C "$LOCAL" ls-remote --heads gitee "refs/heads/$BRANCH" | awk '{print $1}')
gitee pr view <pr> -R aymwoo/openlearn-next --json=number,state,draft,mergeable,head.ref

gitee pr merge <pr> -R aymwoo/openlearn-next --method squash
```

- Gitee CLI **没有** `--match-head-commit`；用上面的 `ls-remote` + `pr view` 人工核对。
- 不要加 `--delete-branch`（原因同 GitHub：worktree 占用）。
- 合并后回读 `gitee pr view <pr> --json=state,merged_at` 确认状态。
- Gitee 的 `--method squash` 会生成一个合并提交；随后必须同步 `main` 到 GitHub。

### 9.4 合并后同步 main（必做）

```bash
cd <skill-dir>

# 在 GitHub 合并：
bash scripts/sync-mirror.sh sync-main --from github \
  --repo aymwoo/OpenLearn-Next-V2 --local "$LOCAL"

# 在 Gitee 合并：
bash scripts/sync-mirror.sh sync-main --from gitee \
  --repo aymwoo/OpenLearn-Next-V2 --local "$LOCAL"
```

- 脚本只做 fast-forward；两边分叉时停止并提示人工处理，**绝不 force-push**。
- 同步后用 `bash scripts/sync-mirror.sh status --local "$LOCAL"` 确认两边 `main` 一致。

### 9.5 合并后校验

```bash
# GitHub
gh pr view <pr> -R aymwoo/OpenLearn-Next-V2 --json state,mergedAt,mergeCommit
gh issue view "$N" -R aymwoo/OpenLearn-Next-V2 --json state,stateReason

# Gitee
gitee pr view <pr> -R aymwoo/openlearn-next --json=number,state,merged_at
gitee issue view "$N" -R aymwoo/openlearn-next --json=number,state
```

- issue 因 `Closes #<编号>` 自动关闭 → 正常。
- issue 仍 open → 汇报，询问是否补关闭；不要擅自关闭。
- 若合并平台与 issue 所在平台不同（例如 Gitee PR 关联 GitHub issue），不会自动关闭；需在 issue 下评论说明并询问是否关闭。

---

## 10. 清理与陈旧 worktree

### 10.1 PR 合并后

```bash
# 1) 有未提交改动则停止
git -C "$WT" status --porcelain

# 2) 删除远程分支（两边都查；只删存在的）
if git -C "$LOCAL" ls-remote --heads origin "$BRANCH" | grep -q .; then
  git -C "$LOCAL" push origin --delete "$BRANCH"
fi
if git -C "$LOCAL" ls-remote --heads gitee "$BRANCH" | grep -q .; then
  git -C "$LOCAL" push gitee --delete "$BRANCH"
fi

# 3) 移除 worktree
git -C "$LOCAL" worktree remove "$WT"

# 4) 删除本地分支：squash 合并后分支不是 main 的祖先，`-d` 通常会拒绝；
#    先确认 PR state == MERGED，再在用户确认后用 -D
gh pr view <pr> -R "$REPO" --json state,mergedAt
git -C "$LOCAL" branch -D "$BRANCH"

git -C "$LOCAL" fetch origin --prune 2>/dev/null || true
git -C "$LOCAL" fetch gitee --prune 2>/dev/null || true
```

- **每一步清理前都必须确认**；有未提交改动时停止并列出改动。
- 不要用 `gh pr merge --delete-branch` / `gitee pr merge --delete-branch` 代替上述步骤（worktree 占用会导致本地分支删除失败）。
- `-D` 是强制删除，只在 `gh pr view` / `gitee pr view` 确认 `state == MERGED` 后使用；PR 未合并时保留分支。

### 10.2 PR 关闭但未合并

- 保留 worktree 与分支，汇报关闭原因。
- GitHub 移除 `in-progress` 标签；Gitee 没有该标签，改用评论说明。
- 是否在 issue/PR 下留言说明，先问用户。

### 10.3 陈旧 worktree 巡检

```bash
git -C "$LOCAL" worktree list --porcelain
git -C "$LOCAL" fetch origin --prune 2>/dev/null || true
git -C "$LOCAL" fetch gitee --prune 2>/dev/null || true
git -C "$LOCAL" branch --merged origin/main

gh pr list -R "$REPO" --state all --head "<branch>" \
  --json number,state,title,mergedAt
gitee pr list -R aymwoo/openlearn-next -s all --head "<branch>" \
  --json=number,state,title,merged_at
```

- 只列出“已合并 / PR 已关闭 / 分支已删除”的目录及建议动作。
- **绝不自动删除**；每次清理都要用户确认。
- 有未提交改动 → 永不删除。

---

## 11. 异常处理表

| 场景 | 动作 |
|------|------|
| issue/PR 编号在目标平台不存在 | 停止，确认平台与编号；不自动换平台/仓库 |
| 用户给的编号是 Gitee `I...` 但当前在 GitHub 操作 | 停止，说明编号格式不兼容；切到 Gitee 或让用户给 GitHub 编号 |
| issue 已关闭 | 停止，说明关闭原因与关联 PR |
| issue 已 assign 给他人 | 停止，询问是否仍要接手；不抢单 |
| issue 已 assign 给自己 | 幂等继续，跳过 assign |
| 已有开放 PR 引用该 issue（任一平台） | 停止，汇报平台、PR 号/分支/作者；自己的 PR 建议转为处理该 PR |
| 已有远程分支但无 PR | 查作者与提交；非自己则停止询问 |
| issue 信息不足 | 列出缺失的验收标准；可代拟澄清评论，发布前确认 |
| 本地仓库不存在 | 询问后再 clone，不自动克隆 |
| 占位后无法继续（worktree 失败/用户取消） | 汇报并询问是否回滚 assign + 标签；不擅自删评论 |
| 目标 worktree 路径已存在 | 同分支且干净 → 复用；否则停止，绝不覆盖 |
| 分支已存在 | 确认归属与合并状态；不直接 `-B` 覆盖 |
| 主 clone 工作区有未提交改动 | 不影响 worktree；但不要在主 clone 改动或提交 |
| GitHub `in-progress` 标签不存在 | 按 2.2 创建；不创建其他 triage 标签 |
| Gitee 无 `in-progress` / `needs-triage` | 不自创标签；用 assignee + 评论表达状态 |
| GitHub 无 project scope | 不更新 Projects 看板，用标签 + assignee 表达状态 |
| 首选平台 issue/PR 能力不可用 | 按 0.2 回退 Gitee（仅限登记镜像）；先报告再执行 |
| 两个平台都不可用 | 停止；保留本地报告与正文，给出手动入口 |
| 上报系统侧缺陷时 CLI 未登录/无权限 | 不作静默失败；保留正文文件并给手动 `issues/new` 入口 |
| 上报前命中已有开放 issue | 不开新单，建议在原 issue 补充评论（需确认） |
| 上报前命中已修复版本记录 | 建议升级复测；仍复现则标「回归」并引原 issue 号 |
| 用户要求把插件侧问题也提 issue | 拒绝，说明会污染缺陷库；改为给修复指引 |
| push 失败（权限/网络） | 报告错误原文；`sync-mirror.sh` 只在网络/鉴权失败时回退，`rejected` 不回退 |
| GitHub push 成功、Gitee 镜像失败 | 不阻塞；记录「Gitee 待同步」，稍后重跑 `sync-mirror.sh push` |
| CI 红且属于本次改动 | 自动修 1 轮并重推；仍红则停止汇报 |
| CI 红且属于环境/flaky | 停止汇报，不反复重跑 |
| Gitee 未接 CI | 用本地测试 + 人工验证；合并确认卡注明，不伪造「CI 全绿」 |
| 合并冲突 | 先汇报；确认后再 rebase/merge 主平台 `main`，解决后重跑定向测试 |
| 两边 `main` 分叉 | 停止自动同步；人工合并后重跑 `sync-mirror.sh sync-main`，绝不 force-push |
| PR 被关闭未合并 | 保留 worktree；移除可移除的标签；留言需确认 |
| 审查意见要求扩大范围 | 先汇报范围变化与成本，等用户决定 |
| 用户要求直接推 main | 拒绝并说明仓库规范；改为分支 + PR |
| 用户要求开启 Gitee 自动镜像 | 拒绝并解释会覆盖分支/标签/提交；改用 `sync-mirror.sh` |

---

## 12. 命令速查

```bash
# ---- 平台探测 ----
bash scripts/platform-probe.sh --repo aymwoo/OpenLearn-Next-V2 --local "$LOCAL" --json

# ---- issue（GitHub）----
gh issue view <n> -R "$REPO" --json number,title,body,state,assignees,labels,comments,url
gh issue edit <n> -R "$REPO" --add-assignee @me --add-label in-progress
gh issue comment <n> -R "$REPO" --body-file <file>
gh issue edit <n> -R "$REPO" --remove-label in-progress
gh issue view <n> -R "$REPO" --json state,stateReason

# ---- issue（Gitee）----
gitee issue view "<I...>" -R aymwoo/openlearn-next --json=number,title,state,body,user.login,assignee.login,labels.name,html_url
gitee issue assign "<I...>" aymwoo -R aymwoo/openlearn-next
gitee issue comment "<I...>" -R aymwoo/openlearn-next -b "<正文>"
gitee issue edit "<I...>" -R aymwoo/openlearn-next --labels bug
gitee issue view "<I...>" -R aymwoo/openlearn-next --json=number,state

# ---- 缺陷上报 ----
# GitHub
gh issue list -R "$REPO" --state all --limit 50 --search "<关键词> in:title,body" \
  --json number,title,state,url,closedAt
gh issue create -R "$REPO" --title "[缺陷] <模块>：<现象>" --body-file <file> \
  --label bug --label needs-triage
# Gitee
gitee issue list -R aymwoo/openlearn-next -s all -l 50 --query "<关键词>" \
  --json=number,title,state,html_url
gitee issue create -R aymwoo/openlearn-next -t "[缺陷] <模块>：<现象>" \
  -b "$(cat <file>)" --labels bug

# ---- 重复开发 ----
git -C "$LOCAL" fetch origin --prune 2>/dev/null || true
git -C "$LOCAL" fetch gitee --prune 2>/dev/null || true
git -C "$LOCAL" ls-remote --heads origin "refs/heads/*issue-<n>*"
git -C "$LOCAL" ls-remote --heads gitee  "refs/heads/*issue-<n>*"
gh pr list -R "$REPO" --state open --json number,title,body,headRefName,author
gitee pr list -R aymwoo/openlearn-next -s open --json=number,title,body,head.ref,user.login

# ---- worktree ----
git -C "$LOCAL" worktree list --porcelain
git -C "$LOCAL" worktree add -b "$BRANCH" "$WT" origin/main
git -C "$LOCAL" worktree remove "$WT"
git -C "$LOCAL" branch -D "$BRANCH"   # 确认 PR 已合并后再强制删除

# ---- push（GitHub 优先 + Gitee 镜像）----
bash scripts/sync-mirror.sh push "$BRANCH" --repo aymwoo/OpenLearn-Next-V2 --local "$LOCAL"

# ---- PR ----
gh pr create -R "$REPO" --base main --head "$BRANCH" --title "<title>" --body-file <file>
gitee pr create -R aymwoo/openlearn-next --base main --head "$BRANCH" -t "<title>" -b "$(cat <file>)"
gh pr checks <pr> -R "$REPO" --watch --interval 30
gitee pipeline build list -R aymwoo/openlearn-next --ref "$BRANCH" --json=id,buildNumber,status
gh pr view <pr> -R "$REPO" --json state,mergeable,mergeStateStatus,reviewDecision
gitee pr view <pr> -R aymwoo/openlearn-next --json=number,state,draft,mergeable,head.ref
gh pr diff <pr> -R "$REPO" --name-only
gitee pr diff <pr> -R aymwoo/openlearn-next --json=filename,status,additions,deletions
gh pr view <pr> -R "$REPO" --comments
gh pr review <pr> -R "$REPO" --comment --body-file <file>
gitee pr review <pr> -R aymwoo/openlearn-next -b "<审查意见>"
gitee pr comment <pr> -R aymwoo/openlearn-next -b "请求修改：<阻塞项>"

# ---- 合并 ----
HEAD_SHA=$(gh pr view <pr> -R "$REPO" --json headRefOid --jq .headRefOid)
gh pr merge <pr> -R "$REPO" --squash --match-head-commit "$HEAD_SHA" --subject "<title>" --body "<body>"
gitee pr merge <pr> -R aymwoo/openlearn-next --method squash
bash scripts/sync-mirror.sh sync-main --from github --repo aymwoo/OpenLearn-Next-V2 --local "$LOCAL"
bash scripts/sync-mirror.sh sync-main --from gitee  --repo aymwoo/OpenLearn-Next-V2 --local "$LOCAL"
git -C "$LOCAL" push origin --delete "$BRANCH"   # 合并成功后，确认后再删远程分支
git -C "$LOCAL" push gitee  --delete "$BRANCH"

# ---- CI 日志 ----
gh run list -R "$REPO" --branch "$BRANCH" --limit 5 --json databaseId,workflowName,conclusion
gh run view <run-id> -R "$REPO" --log-failed
gitee pipeline build list -R aymwoo/openlearn-next --ref "$BRANCH" --json=id,buildNumber,status,message
```

---

## 13. 输出模板

### 13.1 接管 issue 前的确认卡

```
【接管 Issue】<平台> <repo>#<n> <title>
类型：<bug/feat/...> | 优先级：<P0/P1/...>
当前状态：OPEN | assignee: <...> | labels: <...>
验收标准：
  1. ...
计划：
  - 平台：GitHub / Gitee
  - 分支：<type>/issue-<n>-<slug>
  - worktree：<path>
  - 测试：<commands>
  - 占位评论：<一句话>
确认后我会：assign @me → 加标签/评论 → 创建 worktree。
```

### 13.2 PR 状态卡

```
【PR 状态】<平台> <repo>#<pr> <title>
作者：<login> | 状态：<OPEN/DRAFT/MERGED/CLOSED> | 分支：<head> → <base>
CI：<pass/fail/pending/未接入> | 评审：<approved/changes requested/none> | 可合并：<yes/no>
改动：<files> files, +<add>/-<del>
关联 issue：<#...>
未解决评论：<n>
可选动作：审查 / 修评论 / 合并 / 仅解释
```

### 13.3 审查草稿

```
【审查草稿】<平台> <repo>#<pr>
结论建议：comment / request-changes / approve
阻塞项：
  - <file:line> <问题> → <建议>
非阻塞项：
  - ...
确认后发布到 <GitHub/Gitee>。
```

### 13.4 完成汇报

```
【完成】<平台> <repo>#<n> → PR #<pr>
分支：<branch>
worktree：<path>
测试：<commands + results>
CI：<status>
合并：<未合并 / squash merged>
main 同步：<GitHub/Gitee 已一致 / 待同步 / 分叉待处理>
清理：<保留 / 已移除>
```

---

## 14. 红线

1. **GitHub 优先**：只有 GitHub 网络/鉴权不可用时才回退 Gitee；回退仅限 `repo-mirrors.json` 登记的仓库。
2. **绝不直接 push `main` / `master`**，所有变更走分支 + PR。
3. **绝不未经明确指令合并 PR**；不 `--admin`、不 `--auto`。
4. **绝不 force-push `main` 或共享分支**；`--force-with-lease` 仅限自己的 PR 分支且需确认。
5. **绝不开启 Gitee 自动双向镜像**：会覆盖分支、标签、提交；统一用 `sync-mirror.sh`。
6. **同一个变更不在两个平台各开一个 PR**；一个 issue 对应一个 PR。
7. **合并后必须 `sync-main`**：在哪个平台合并，就把该平台 `main` 快进到另一个平台；分叉时停止，不 force。
8. **绝不自动删除** worktree、本地分支、远程分支；清理必须确认，有未提交改动时永不删除。
9. **绝不覆盖已存在的目录或分支**。
10. **绝不未经确认发布公开内容**：assign、评论、review、approve、合并。
11. **绝不替别人 resolve 讨论串**，不关闭他人的 issue/PR。
12. **绝不把无关改动、构建产物、密钥带进 PR**。
13. **阻断性 CI 未绿不合并**，不提供绕过选项；非阻塞检查失败也必须汇报；Gitee 未接 CI 时注明人工验证，不伪造结论。
14. **issue/PR 编号不跨平台复用**：GitHub 整数、Gitee `I...`；不确定就回读，不猜。
15. **不确定就停**：平台、仓库、权限、issue 归属、验收标准任何一项不清楚，都先问用户。
16. **只提「系统侧」缺陷**：插件侧问题、产品边界（设计行为）、环境与配置问题绝不提 Issue；
    提 Issue 前必须完成去重（两个平台）+ 脏数据脱敏 + 用户确认标题与正文。
17. **不伪造证据**：缺版本号 / 完整堆栈 / 最小复现时，不拿猜测填进 Issue。
