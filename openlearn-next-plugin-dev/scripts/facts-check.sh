#!/usr/bin/env bash
# facts-check.sh —— 集成事实锚点校验（开发插件前 / 平台升级后跑一次）
#
# 用途：references/integration-facts.json 里的每条事实都绑定了平台源码锚点。
#       锚点存在（或按声明应消失）→ 事实仍成立，可直接按 skill 写代码；
#       锚点消失 / 文件改名 → 该条事实可能有变，先读 diff 再动手。
#
# 与 platform-drift-check.sh 的分工：
#   platform-drift-check.sh  维护本 skill 用：槽位数量、解压前缀、CLI 打包、白名单叙事
#   facts-check.sh           开发插件用：桥接返回形态、网关响应/超时/角色、SQL 守卫、渲染器隐藏
#
# 用法：
#   bash scripts/facts-check.sh
#   PLATFORM_REPO=/path/to/openlearnv2 bash scripts/facts-check.sh
#   bash scripts/facts-check.sh --json        # 机器可读
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${PLATFORM_REPO:-$HOME/Develop/openlearnv2}"
FACTS="${FACTS_FILE:-$SKILL_DIR/references/integration-facts.json}"

[[ -d "$PLATFORM" ]] || { echo "找不到平台仓库：$PLATFORM（用 PLATFORM_REPO=... 指定）"; exit 2; }
[[ -f "$FACTS" ]] || { echo "找不到 $FACTS"; exit 2; }

python3 - "$PLATFORM" "$FACTS" <<'PY'
import json, os, sys

root, facts_path = sys.argv[1], sys.argv[2]
meta = json.load(open(facts_path, encoding='utf-8'))
json_out = '--json' in sys.argv
facts = meta.get('facts', [])

def read(path):
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except OSError:
        return None

results = []
for fact in facts:
    problems = []
    for src in fact.get('sources', []):
        path = os.path.join(root, src['file'])
        text = read(path)
        if text is None:
            problems.append(f"{src['file']} 不存在（文件可能改名/移动）")
            continue
        found = src['anchor'] in text
        want = not src.get('absent', False)
        if found != want:
            problems.append(
                f"{src['file']} 中{'找不到' if want else '仍存在'}锚点 {src['anchor'][:70]!r}"
            )
            continue
        # 顺序断言：anchor 必须出现在 before 之前（用于「顺序反转」这类
        # 单纯查存在性检测不到的漂移，如 #350 把 register 移到 fetch 之前）
        if want and 'before' in src:
            a = text.find(src['anchor'])
            b = text.find(src['before'])
            if b < 0:
                problems.append(f"{src['file']} 中找不到顺序基准 {src['before'][:70]!r}")
            elif a > b:
                problems.append(
                    f"{src['file']} 顺序已反转：{src['anchor'][:40]!r} 出现在 "
                    f"{src['before'][:40]!r} 之后"
                )
    results.append({
        'id': fact['id'],
        'ok': not problems,
        'claim': fact['claim'],
        'impact': fact.get('impact', ''),
        'problems': problems,
    })

version = read(os.path.join(root, 'package.json'))
actual_version = json.loads(version)['version'] if version else None
version_ok = actual_version == meta.get('platformVersion')

# SDK 双版本信号：仓库（运行时真实行为）vs npm（脚手架模板来源）。
# 两者不一致是常态（发布有滞后），必须分别记录，否则会拿 npm 版本解释运行时行为。
sdk_pkg = read(os.path.join(root, 'packages/plugin-sdk/package.json'))
actual_sdk = json.loads(sdk_pkg)['version'] if sdk_pkg else None
sdk_recorded = meta.get('sdkVersionInRepo')

fail = [r for r in results if not r['ok']]

if json_out:
    print(json.dumps({
        'root': root,
        'expectedVersion': meta.get('platformVersion'),
        'actualVersion': actual_version,
        'versionOk': version_ok,
        'sdkInRepo': actual_sdk,
        'sdkOnNpm': meta.get('sdkVersion'),
        'sdkRecordedInRepo': sdk_recorded,
        'facts': results,
    }, ensure_ascii=False, indent=2))
else:
    print(f"\n【集成事实校验】{root}")
    print(f"  基线：平台 {meta.get('platformVersion')} / 核对于 {meta.get('verifiedAt')}"
          f" / 实际 {actual_version}{'' if version_ok else '  ← 版本已变，逐条看下列结果'}")
    if actual_sdk:
        tag = '' if actual_sdk == sdk_recorded else f'  ← 基线记的是 {sdk_recorded}，按实际为准并更新'
        print(f"  SDK：仓库 {actual_sdk}（运行时真实行为）/ npm {meta.get('sdkVersion')}（脚手架模板）{tag}")
    if not facts:
        print('  （facts 为空：确认 integration-facts.json 未被清空）')
    for r in results:
        mark = '\x1b[32m✔\x1b[0m' if r['ok'] else '\x1b[31m✖\x1b[0m'
        print(f"  {mark} [{r['id']}] {r['claim'][:60]}")
        if not r['ok']:
            for p in r['problems']:
                print(f"      · {p}")
            print(f"      影响：{r['impact']}")
    print(f"\n结果：{len(results) - len(fail)} 成立，{len(fail)} 需复核")
    if fail:
        print('锚点漂移 ≠ 事实一定变了：先 git log 看对应文件的 diff，确认是「实现改了」还是「只是重写」。')
        print('顺序类漂移（anchor 仍存在但先后关系变了）最容易被漏掉：不要只查关键词在不在。')
        print('确认无变化时，同步更新 references/integration-facts.json 的 anchor 与 verifiedAt。')
    print()

sys.exit(1 if fail or not version_ok else 0)
PY
