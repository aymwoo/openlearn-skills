# OpenLearn Skills

面向 [OpenLearnV2](https://openlearn-next-v2.readthedocs.io/zh-cn/latest/) 教学平台的 AI Agent 可复用技能。

[![skills.sh](https://skills.sh/b/aymwoo/openlearn-skills)](https://skills.sh/aymwoo/openlearn-skills)

## 安装

```bash
npx skills add aymwoo/openlearn-skills/openlearn-next-plugin-dev
```

## 已有技能

| 技能 | 说明 |
|------|------|
| [openlearn-next-plugin-dev](./openlearn-next-plugin-dev/SKILL.md) | OpenLearnV2 插件开发与仓库协作助手（基线：平台 v0.7.7 / SDK 3.7.4）：五套模板（server-only / full-stack / frontend-only / sandbox-view / inline-react）+ `new-plugin.sh` 一键生成、远程前端沙箱桥接范式、manifest 与能力权限规范、构建与安装验证；L0–L3 测试护栏（含 jsdom view 冒烟、process 隔离模式空能力门禁）+ 集成事实源码锚点校验；内置插件侧/系统侧故障归因与 Bug 报告；支持接手 GitHub issue（assign + in-progress 占位）、独立 worktree 开发、PR 提交/审查/返工/合并 |

## 开发

```bash
cd openlearn-next-plugin-dev
bash scripts/check-templates.sh          # 模板与文档一致性自检（零依赖）
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
