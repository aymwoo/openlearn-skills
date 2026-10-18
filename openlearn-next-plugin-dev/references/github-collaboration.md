# GitHub Issue / PR 协作工作流

> 本文件是 `SKILL.md`「模式 B：GitHub Issue / PR 协作」的完整执行手册。
> 目标：**接手 issue 前先占位，开发在独立 worktree 完成，所有变更通过 PR 提交，公开动作先经用户确认。**

---

## 0. 适用仓库与本地路径

| 仓库 | 默认本地路径 | 当前账号权限 |
|------|-------------|-------------|
| `aymwoo/OpenLearn-Next-V2` | `~/Develop/openlearnv2` | owner |
| `openlearn-next/<plugin-repo>` | `~/Develop/openlearn-plugins/<plugin-repo>` | admin |
| `aymwoo/openlearn-skills` | `~/Develop/openlearn-skills` | owner |
| `openlearn-next/plugin-exam-bank` | 未克隆，按需询问 | admin |

**定位顺序（不要跳步）**

1. 用户给了 issue/PR URL → 从 URL 解析 `owner/repo` 与编号。
2. 当前目录是 git 仓库 → 用 `git remote get-url origin` 推断；必须与用户意图一致。
3. 只有仓库名 → 查上表；路径存在则校验 remote，不存在则**先询问是否 clone**，不自动克隆。
4. 仍无法确定 → 停下询问，绝不跨到无关仓库。
5. 当前目录仓库查不到该 issue/PR 编号 → **不要自动换仓库**；列出候选仓库让用户选。

```bash
# 校验本地仓库 remote（同时兼容 ssh / https）
git -C "$LOCAL" remote get-url origin

# 需要时克隆（先征得用户同意）
gh repo clone "$REPO" "$LOCAL"
```

**权限事实（每次会话可复核）**

```bash
gh auth status
# 预期 scopes: gist, read:org, repo
```

- 没有 `project` scope → **不要尝试更新 GitHub Projects 看板状态**，统一用 assignee + `in-progress` 标签表达“已分配 / 进行中”。
- 若确实需要 Projects 看板状态，先让用户执行 `gh auth refresh -s project` 并确认；本 skill 默认不做。
- assign、加标签、评论需要对该仓库有 push 权限；平台仓库为 owner，`openlearn-next/*` 为 admin。

**仓库文档优先**

定位到本地仓库后、创建 worktree 前，先读主 clone 的 `AGENTS.md`、`CLAUDE.md`、`README.md`、`package.json`；进入 worktree 后再复核。若仓库文档与本文件冲突，**以仓库文档为准**，并在汇报中说明差异。

---

## 1. 接管 Issue 前预检

### 1.1 读取 issue

```bash
REPO="aymwoo/OpenLearn-Next-V2"
N=133
LOCAL="$HOME/Develop/openlearnv2"

gh issue view "$N" -R "$REPO" \
  --json number,title,body,state,stateReason,author,assignees,labels,comments,url,createdAt,updatedAt
```

逐项检查：

- `state` 必须是 `OPEN`；已关闭 → 停止，说明关闭原因。
- `assignees` 含 `aymwoo`（或 `@me`）→ 视为自己已占位，跳过 assign。
- `assignees` 含其他 login → **停止**，询问是否仍要接手；不要抢别人的 issue。经确认后可 `--add-assignee @me`，是否移除原 assignee 必须由用户明确指示。
- `labels` 含 `in-progress` 但 assignee 为空 → 检查最近评论是否有人声明在做；有则停止。
- issue 正文缺少可验证的验收标准 → 见 1.4。

### 1.2 重复开发检查

先查是否已有开放 PR 引用该 issue：

```bash
gh pr list -R "$REPO" --state open --limit 100 \
  --json number,title,body,headRefName,author \
  | jq --arg n "$N" '
    [.[] | select(
      ((.title + " " + (.body // "") + " " + .headRefName)
       | test("(#" + $n + "([^0-9]|$))|(issue[-_/]" + $n + "([^0-9]|$))|(/issues/" + $n + "([^0-9]|$))"))
    )]
  '
```

> 只匹配 `#<n>`、`issue-<n>`、`/issues/<n>`，避免正文里的裸数字（行号、日期）造成误报。

> `--arg` 是 jq 的参数，不能直接传给 `gh --jq`；必须用管道交给系统 `jq`。

再查远程是否已有对应分支：

```bash
git -C "$LOCAL" fetch origin --prune
git -C "$LOCAL" ls-remote --heads origin "refs/heads/*issue-$N*"
```

- 命中开放 PR → **停止**，把 PR 号/分支/作者告诉用户。作者是自己 → 建议改为处理该 PR（审查/返工/合并）；作者是他人 → 询问是协作还是放弃。
- 只有远程分支、没有 PR → 查最近 commit 与作者；不是自己则停止询问。
- 自己已有的分支/worktree → 可继续，但要先确认状态干净。
- 只有已合并 PR 引用该 issue、但 issue 仍 open → 先确认是否漏关（缺 `Closes`），不要直接重做。

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

## 2. 占位三件套（assign + label + comment）

> **确认门 1**：先把 issue 摘要、验收标准、分支名、worktree 路径、评论草稿展示给用户，确认后才执行本节。所有公开可见动作不得跳过确认。

### 2.1 assign 给自己

```bash
gh issue edit "$N" -R "$REPO" --add-assignee @me
```

### 2.2 确保 `in-progress` 标签存在并添加

```bash
if ! gh label list -R "$REPO" --search "in-progress" --json name --jq '.[].name' \
  | grep -qx "in-progress"; then
  gh label create "in-progress" -R "$REPO" \
    --color "e36209" \
    --description "Currently being worked on"
fi

gh issue edit "$N" -R "$REPO" --add-label "in-progress"
```

- 只按需创建 `in-progress`；不要创建 `ready-for-agent` 等 triage 标签。
- 标签已存在时 `gh label create` 会报错；上面的判断用于避免噪音。

### 2.3 发布占位评论

```bash
LOGIN=$(gh api user --jq .login)
cat > "/tmp/opencode/issue-${N}-claim.md" <<EOF
开始处理本 issue。

- 负责人：@${LOGIN}
- 分支：\`<type>/issue-${N}-<slug>\`
- 开发方式：本地独立 worktree

如有重复工作或不同方案，请在本 issue 下告知，避免冲突。
EOF

gh issue comment "$N" -R "$REPO" --body-file "/tmp/opencode/issue-${N}-claim.md"
```

**幂等**：若已有自己发布的、含「开始处理本 issue」且分支一致的评论，跳过，不重复刷屏。

### 2.4 占位回滚

若占位后无法继续（worktree 创建失败、用户取消、发现重复开发），先汇报，确认后执行：

```bash
gh issue edit "$N" -R "$REPO" --remove-label "in-progress"
gh issue edit "$N" -R "$REPO" --remove-assignee @me
```

评论是否删除或更正，由用户决定；不要擅自删评论。

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

### 3.2 创建

```bash
BRANCH="<type>/issue-<n>-<slug>"
WT="$HOME/Develop/openlearn-issue-<n>"

git -C "$LOCAL" fetch origin --prune
git -C "$LOCAL" worktree add -b "$BRANCH" "$WT" origin/main

git -C "$WT" status -sb
git -C "$WT" log --oneline -1
```

- 始终从 `origin/main` 建分支；不要动主 clone 的工作区。
- 主 clone 有未提交改动不影响 worktree 创建，但**不要**在主 clone 里顺手改代码。
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
- 只 `git add` 本次相关文件；提交前看 `git status`，不要带入无关改动、构建产物或密钥。
- 不直接 push `main`，不在主 clone 提交。

---

## 5. 创建 PR

> **确认门 2**：展示 `git diff --stat`、提交列表、实际执行的测试命令与结果、PR 标题/正文，确认后才 push + 开 PR。

### 5.1 push 分支

```bash
git -C "$WT" push -u origin "$BRANCH"
```

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

### 5.3 创建

```bash
gh pr create -R "$REPO" \
  --base main \
  --head "$BRANCH" \
  --title "<type>(<scope>): <摘要>（Issue #<n>）" \
  --body-file "/tmp/opencode/pr-body-<repo>-<n>.md"
```

规则：

- 全中文；标题遵循 Conventional Commits；正文必须有 `Closes #<n>`。
- 测试计划写**真实执行的命令与结果**，不写“已测试”这类空话。
- UI 改动附截图；无法截图时说明原因。
- 默认创建 ready PR；代码未完成才用 `--draft`。
- 一个 issue 对应一个 PR；不要在一个 PR 里夹带无关重构。

---

## 6. CI 处理

```bash
timeout 600 gh pr checks <pr> -R "$REPO" --watch --interval 30
```

等待上限 10 分钟。**超时视为 pending，不要判失败**；汇报后由用户决定是否继续等待。非阻塞检查（如 `Windows platform probe`）失败不阻断合并，但必须汇报。

失败时：

```bash
gh run list -R "$REPO" --branch "$BRANCH" --limit 5 \
  --json databaseId,workflowName,conclusion,createdAt,url

gh run view <run-id> -R "$REPO" --log-failed
```

分类处理：

| 类型 | 动作 |
|------|------|
| 明显由本次改动导致 | 自动修 **1 轮**，补提交、push、重新等待 |
| 环境/网络/缓存/flaky | 停止，汇报失败任务与关键日志，不反复重跑 |
| 与本次改动无关的既有失败 | 停止，说明基线问题，询问是否继续 |

- 最多自动修一轮，避免无限循环。
- **CI 未绿不合并，不提供绕过选项**。

---

## 7. 审查 PR

### 7.1 状态卡片

```bash
gh pr view <pr> -R "$REPO" \
  --json number,title,author,isDraft,state,baseRefName,headRefName,mergeable,mergeStateStatus,reviewDecision,additions,deletions,changedFiles,closingIssuesReferences,url

gh pr checks <pr> -R "$REPO"
gh pr view <pr> -R "$REPO" --comments
```

先输出只读状态卡片，再问用户要执行哪种动作：**审查 / 修评论 / 合并 / 仅解释**。不要自动审查或自动合并。

### 7.2 读 diff

```bash
gh pr diff <pr> -R "$REPO" --name-only
gh pr diff <pr> -R "$REPO"
```

大 PR 先按文件列表拆分，再逐文件看；重点关注：行为变更、边界条件、错误处理、权限/数据范围、测试覆盖、与关联 issue 的一致性。

### 7.3 需要本地验证时

创建临时 review worktree（不污染主 clone）：

```bash
REVIEW_WT="$HOME/Develop/openlearn-pr-<pr>"

git -C "$LOCAL" fetch origin "$HEAD_BRANCH"
git -C "$LOCAL" worktree add --detach "$REVIEW_WT" "origin/$HEAD_BRANCH"
```

fork PR 的 head 分支不在 origin 时：

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

```bash
gh pr review <pr> -R "$REPO" --comment --body-file "/tmp/opencode/review-<pr>.md"
# 有阻塞项：
gh pr review <pr> -R "$REPO" --request-changes --body-file "/tmp/opencode/review-<pr>.md"
# 无阻塞项且用户明确同意：
gh pr review <pr> -R "$REPO" --approve --body-file "/tmp/opencode/review-<pr>.md"
```

规则：

- **自己的 PR 不能 approve**（GitHub 限制），只能 `--comment`。
- 有阻塞项不得 approve。
- 所有公开评审动作先经用户确认。
- 不替别人 resolve 讨论串。

---

## 8. PR 返工

> 本节默认是**自己（或已获授权）的 PR**。对他人 PR 的 review 意见，只做审查与回复建议；未经作者/用户明确授权，不要 push 到对方分支。需要改代码时，另开分支 + 新 PR，并在原 PR 下说明。

### 8.1 拉取未解决讨论串

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

### 8.2 逐条处理

- 可执行意见 → 在 worktree 修改、补提交、push。
- 需要解释的意见 → 准备回复，不强行改。
- 与 issue 范围冲突的意见 → 先汇报，问用户是否扩大范围。

### 8.3 回复讨论串

```bash
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $threadId,
    body: $body
  }) { comment { url } }
}' -F threadId="<thread-id>" -f body="已修复：<commit-hash>。"
```

规则：

- 回复里带 commit hash 与简短说明。
- **不替别人 resolve 讨论串**；是否 resolve 由 reviewer 决定。
- 普通 `push` 优先；确需重写自己 PR 分支历史时才用 `--force-with-lease`，且执行前确认。
- 永不 force-push `main` 或共享分支。

---

## 9. 合并 PR

> 仅在用户**明确说“合并”**时执行。仓库 `main` 没有分支保护，本流程是唯一防线。

### 9.1 前置条件

- [ ] PR 为 open 且非 draft
- [ ] 所有阻断性 CI 检查全绿（明确标注 non-blocking 的失败需汇报，不阻断）
- [ ] `mergeable == MERGEABLE`，且不是 `DIRTY` / `BLOCKED`
- [ ] 无 `changes requested`
- [ ] 所有 review thread 已处理或已得到用户豁免
- [ ] 用户已再次确认最终 squash commit message

### 9.2 执行

```bash
HEAD_SHA=$(gh pr view <pr> -R "$REPO" --json headRefOid --jq .headRefOid)
gh pr merge <pr> -R "$REPO" \
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

### 9.3 合并后校验

```bash
gh pr view <pr> -R "$REPO" --json state,mergedAt,mergeCommit
gh issue view "$N" -R "$REPO" --json state,stateReason
```

- issue 因 `Closes #N` 自动关闭 → 正常。
- issue 仍 open → 汇报，询问是否补关闭；不要擅自关闭。

---

## 10. 清理与陈旧 worktree

### 10.1 PR 合并后

```bash
# 1) 有未提交改动则停止
git -C "$WT" status --porcelain

# 2) 删除远程分支（若仍存在；仓库可能已开启自动删除）
if git -C "$LOCAL" ls-remote --heads origin "$BRANCH" | grep -q .; then
  git -C "$LOCAL" push origin --delete "$BRANCH"
fi

# 3) 移除 worktree
git -C "$LOCAL" worktree remove "$WT"

# 4) 删除本地分支：squash 合并后分支不是 main 的祖先，`-d` 通常会拒绝；
#    先确认 PR state == MERGED，再在用户确认后用 -D
gh pr view <pr> -R "$REPO" --json state,mergedAt
git -C "$LOCAL" branch -D "$BRANCH"

git -C "$LOCAL" fetch origin --prune
```

- **每一步清理前都必须确认**；有未提交改动时停止并列出改动。
- 不要用 `gh pr merge --delete-branch` 代替上述步骤（worktree 占用会导致本地分支删除失败）。
- `-D` 是强制删除，只在 `gh pr view` 确认 `state == MERGED` 后使用；PR 未合并时保留分支。

### 10.2 PR 关闭但未合并

- 保留 worktree 与分支，汇报关闭原因。
- 移除 `in-progress` 标签：

```bash
gh issue edit "$N" -R "$REPO" --remove-label "in-progress"
```

- 是否在 issue/PR 下留言说明，先问用户。

### 10.3 陈旧 worktree 巡检

```bash
git -C "$LOCAL" worktree list --porcelain
git -C "$LOCAL" fetch origin --prune
git -C "$LOCAL" branch --merged origin/main

gh pr list -R "$REPO" --state all --head "<branch>" \
  --json number,state,title,mergedAt
```

- 只列出“已合并 / PR 已关闭 / 分支已删除”的目录及建议动作。
- **绝不自动删除**；每次清理都要用户确认。
- 有未提交改动 → 永不删除。

---

## 11. 异常处理表

| 场景 | 动作 |
|------|------|
| issue/PR 编号在目标仓库不存在 | 停止，确认仓库与编号；不自动换仓库 |
| issue 已关闭 | 停止，说明关闭原因与关联 PR |
| issue 已 assign 给他人 | 停止，询问是否仍要接手；不抢单 |
| issue 已 assign 给自己 | 幂等继续，跳过 assign |
| 已有开放 PR 引用该 issue | 停止，汇报 PR 号/分支/作者；自己的 PR 建议转为处理该 PR |
| 已有远程分支但无 PR | 查作者与提交；非自己则停止询问 |
| issue 信息不足 | 列出缺失的验收标准；可代拟澄清评论，发布前确认 |
| 本地仓库不存在 | 询问后再 `gh repo clone`，不自动克隆 |
| 占位后无法继续（worktree 失败/用户取消） | 汇报并询问是否回滚 assign + `in-progress`；不擅自删评论 |
| 目标 worktree 路径已存在 | 同分支且干净 → 复用；否则停止，绝不覆盖 |
| 分支已存在 | 确认归属与合并状态；不直接 `-B` 覆盖 |
| 主 clone 工作区有未提交改动 | 不影响 worktree；但不要在主 clone 改动或提交 |
| `in-progress` 标签不存在 | 按 2.2 创建；不创建其他 triage 标签 |
| 无 project scope | 不更新 Projects 看板，用标签 + assignee 表达状态 |
| push 失败（权限/网络） | 报告错误原文；不盲目重试 |
| CI 红且属于本次改动 | 自动修 1 轮并重推；仍红则停止汇报 |
| CI 红且属于环境/flaky | 停止汇报，不反复重跑 |
| 合并冲突 | 先汇报；确认后再 rebase/merge `origin/main`，解决后重跑定向测试 |
| PR 被关闭未合并 | 保留 worktree；移除 `in-progress`；留言需确认 |
| 审查意见要求扩大范围 | 先汇报范围变化与成本，等用户决定 |
| 用户要求直接推 main | 拒绝并说明仓库规范；改为分支 + PR |

---

## 12. 命令速查

```bash
# ---- issue ----
gh issue view <n> -R "$REPO" --json number,title,body,state,assignees,labels,comments,url
gh issue edit <n> -R "$REPO" --add-assignee @me --add-label in-progress
gh issue comment <n> -R "$REPO" --body-file <file>
gh issue edit <n> -R "$REPO" --remove-label in-progress
gh issue view <n> -R "$REPO" --json state,stateReason

# ---- 重复开发 ----
git -C "$LOCAL" fetch origin --prune
git -C "$LOCAL" ls-remote --heads origin "refs/heads/*issue-<n>*"
gh pr list -R "$REPO" --state open --json number,title,body,headRefName,author

# ---- worktree ----
git -C "$LOCAL" worktree list --porcelain
git -C "$LOCAL" worktree add -b "$BRANCH" "$WT" origin/main
git -C "$LOCAL" worktree remove "$WT"
git -C "$LOCAL" branch -D "$BRANCH"   # 确认 PR 已合并后再强制删除

# ---- PR ----
git -C "$WT" push -u origin "$BRANCH"
gh pr create -R "$REPO" --base main --head "$BRANCH" --title "<title>" --body-file <file>
gh pr checks <pr> -R "$REPO" --watch --interval 30
gh pr view <pr> -R "$REPO" --json state,mergeable,mergeStateStatus,reviewDecision
gh pr diff <pr> -R "$REPO" --name-only
gh pr view <pr> -R "$REPO" --comments
gh pr review <pr> -R "$REPO" --comment --body-file <file>
HEAD_SHA=$(gh pr view <pr> -R "$REPO" --json headRefOid --jq .headRefOid)
gh pr merge <pr> -R "$REPO" --squash --match-head-commit "$HEAD_SHA" --subject "<title>" --body "<body>"
git -C "$LOCAL" push origin --delete "$BRANCH"   # 合并成功后，确认后再删远程分支

# ---- CI 日志 ----
gh run list -R "$REPO" --branch "$BRANCH" --limit 5 --json databaseId,workflowName,conclusion
gh run view <run-id> -R "$REPO" --log-failed
```

---

## 13. 输出模板

### 13.1 接管 issue 前的确认卡

```
【接管 Issue】<repo>#<n> <title>
类型：<bug/feat/...> | 优先级：<P0/P1/...>
当前状态：OPEN | assignee: <...> | labels: <...>
验收标准：
  1. ...
计划：
  - 分支：<type>/issue-<n>-<slug>
  - worktree：<path>
  - 测试：<commands>
  - 占位评论：<一句话>
确认后我会：assign @me → 加 in-progress → 发布评论 → 创建 worktree。
```

### 13.2 PR 状态卡

```
【PR 状态】<repo>#<pr> <title>
作者：<login> | 状态：<OPEN/DRAFT/MERGED/CLOSED> | 分支：<head> → <base>
CI：<pass/fail/pending> | 评审：<approved/changes requested/none> | 可合并：<yes/no>
改动：<files> files, +<add>/-<del>
关联 issue：<#...>
未解决评论：<n>
可选动作：审查 / 修评论 / 合并 / 仅解释
```

### 13.3 审查草稿

```
【审查草稿】<repo>#<pr>
结论建议：comment / request-changes / approve
阻塞项：
  - <file:line> <问题> → <建议>
非阻塞项：
  - ...
确认后发布到 GitHub。
```

### 13.4 完成汇报

```
【完成】<repo>#<n> → PR #<pr>
分支：<branch>
worktree：<path>
测试：<commands + results>
CI：<status>
合并：<未合并 / squash merged>
清理：<保留 / 已移除>
```

---

## 14. 红线

1. **绝不直接 push `main` / `master`**，所有变更走分支 + PR。
2. **绝不未经明确指令合并 PR**；不 `--admin`、不 `--auto`。
3. **绝不 force-push `main` 或共享分支**；`--force-with-lease` 仅限自己的 PR 分支且需确认。
4. **绝不自动删除** worktree、本地分支、远程分支；清理必须确认，有未提交改动时永不删除。
5. **绝不覆盖已存在的目录或分支**。
6. **绝不未经确认发布公开内容**：assign、评论、review、approve、合并。
7. **绝不替别人 resolve 讨论串**，不关闭他人的 issue/PR。
8. **绝不把无关改动、构建产物、密钥带进 PR**。
9. **阻断性 CI 未绿不合并**，不提供绕过选项；非阻塞检查失败也必须汇报。
10. **不确定就停**：仓库、权限、issue 归属、验收标准任何一项不清楚，都先问用户。
