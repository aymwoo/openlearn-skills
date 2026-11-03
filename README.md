# OpenLearn Skills

面向 [OpenLearnV2](https://openlearn-next-v2.readthedocs.io/zh-cn/latest/) 教学平台的 AI Agent 可复用技能。

[![skills.sh](https://skills.sh/b/aymwoo/openlearn-skills)](https://skills.sh/aymwoo/openlearn-skills)

> **主仓**：[GitHub](https://github.com/aymwoo/openlearn-skills) ｜ **镜像**：[Gitee](https://gitee.com/aymwoo/openlearn-skills)
> issue / PR 优先在 GitHub 提交；GitHub 不可达时可到 Gitee 镜像提交，一个变更只在一个平台开 PR。

## 安装

```bash
# ① GitHub 主仓（skills.sh 注册表，registry 只索引 GitHub 仓库）
npx skills add aymwoo/openlearn-skills/openlearn-next-plugin-dev

# ② 国内网络访问 GitHub 受限时：直连 Gitee 镜像
#    skills CLI 会把非 GitHub 的完整 URL 当作 git 仓库克隆，
#    所以必须写全仓库地址，不能用 owner/repo 简写（简写会固定拼成 https://github.com/...）。
npx skills add https://gitee.com/aymwoo/openlearn-skills.git
```

> **镜像策略**：镜像由 GitHub → Gitee **单向同步**，与 `main` 保持一致，但 **CI 与 Release 只在 GitHub 侧运行**。
> 提 Issue / PR 请**只在一个平台开一份**；合并后把 `main` 快进到另一侧（绝不 force-push、不开自动双向镜像）。
>
> 完全离线也可以兜底：`git clone https://gitee.com/aymwoo/openlearn-skills.git` 后，把 `openlearn-next-plugin-dev/` 拷进 Agent 的 skills 目录
> （Claude Code `~/.claude/skills/`、pi `~/.pi/agent/skills/`，Codex / Antigravity 同理）。

## 已有技能

| 技能 | 说明 |
|------|------|
| [openlearn-next-plugin-dev](./openlearn-next-plugin-dev/SKILL.md) | OpenLearnV2 插件开发与仓库协作助手（基线：平台 v0.7.7 / SDK 3.7.4）：五套模板（server-only / full-stack / frontend-only / sandbox-view / inline-react）+ `new-plugin.sh` 一键生成、交互式需求梳理 Grilling 向导（`grill-requirements.sh`）、平台源码后台空闲同步与更新检查（`sync-platform-repo.sh`）、远程前端沙箱桥接范式、manifest 与能力权限规范、构建与安装验证；L0–L3 测试护栏（含 jsdom view 冒烟、process 隔离模式空能力门禁）+ 集成事实源码锚点校验；内置插件侧/系统侧故障归因与 Bug 报告；支持接手 GitHub / Gitee issue（assign + 占位评论）、独立 worktree 开发、PR 提交/审查/返工/合并，以及合并后 `main` 镜像同步（GitHub 优先，GitHub 不可达时回退 Gitee 镜像；一个变更只在一个平台开 PR） |

## 开发

```bash
cd openlearn-next-plugin-dev
bash scripts/check-templates.sh          # 模板与文档一致性自检（零依赖）
bash scripts/hydrate-contracts.sh        # 契约水合与对齐（直连 docs/agent/contracts/）
bash scripts/grill-requirements.sh -h   # 需求梳理 Grilling 决策向导
bash scripts/sync-platform-repo.sh check # 平台源码与更新状态检查（GitHub 优先，Gitee 回退）
bash scripts/platform-probe.sh --json   # GitHub / Gitee 连通性与权限探测
bash scripts/sync-mirror.sh status      # 双远端 main 一致性检查
bash scripts/verify-templates-build.sh   # 三套模板真实构建 + tsc 校验（需 SDK 与 typescript）
bash scripts/diff-official-scaffold.sh   # 与官方 CLI 脚手架比对（需平台仓库或 npm 安装的 SDK）
bash scripts/verify-test-harness.sh      # L0 护栏自检（零依赖）
bash scripts/facts-check.sh              # 集成事实的源码锚点校验（需平台仓库）
```

改动模板或 `SKILL.md` 后**必须**跑这几个脚本再提交。仓库已配置 CI（`.github/workflows/ci.yml`）：

| Job | 作用 | 是否阻塞 |
|-----|------|----------|
| `self-check` | 模板 / 文档一致性自检 | ✅ |
| `scaffold-diff` | 与 **npm 发布版 SDK** 的脚手架比对 | ✅ |
| `build-verify` | 三套模板真实构建 + `tsc --noEmit` | ✅ |
| `platform-head-diff` | 与**平台仓库 HEAD** 比对（提前预警下一次发版的变化） | ❌ 仅预警 |
