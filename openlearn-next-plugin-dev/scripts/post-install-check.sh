#!/usr/bin/env bash
# post-install-check.sh —— 安装后 60 秒自检
#
# 为什么需要它：插件"装上了"和"贡献点真的注册了"是两件事。宿主对下列三种失败
# **全部静默**（不报错、不写 500、日志无异常），只能靠页面肉眼等：
#   1. ZIP 里缺 frontend.js  → 宿主 fetch 404 抛错，registerManifestContributions 根本不执行
#   2. 安装期 schema 把 view strip 掉 → DB 里没有 view，渲染器直接 return null
#   3. view 文件没进 ZIP / 路径不是 storage/  → 面板空白或「非法的插件视图路径」
# 本脚本把这三种情况在"上传完就查"，而不是等用户反馈"页签不见了"。
#
# 用法：
#   bash scripts/post-install-check.sh @ext/lab-help
#   bash scripts/post-install-check.sh @ext/lab-help --zip dist/my-plugin-0.1.0.zip
#   bash scripts/post-install-check.sh 01a184a3-727e-722f-81f3-f16dcb3cd51d --port 0
#   PLATFORM_REPO=/path/to/openlearnv2 bash scripts/post-install-check.sh @ext/foo
#
# 退出码：0 全绿 / 1 有 ✖ / 2 环境或参数问题
set -uo pipefail

PLATFORM="${PLATFORM_REPO:-$HOME/Develop/openlearnv2}"
TARGET=""
ZIP=""
DB=""
PORT="9000"
JSON=0

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip)      ZIP="${2:-}"; shift 2 ;;
    --db)       DB="${2:-}"; shift 2 ;;
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --port)     PORT="${2:-}"; shift 2 ;;
    --json)     JSON=1; shift ;;
    -h|--help)  usage ;;
    -*)         echo "未知选项：$1"; usage ;;
    *)          TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || { echo "缺少插件标识（manifest.id 如 @ext/foo，或安装行 UUID）"; usage; }

[[ -d "$PLATFORM" ]] || { echo "找不到平台仓库：$PLATFORM（用 --platform 或 PLATFORM_REPO= 指定）"; exit 2; }

# DB 定位顺序：--db > $OPENLEARN_DB > 平台仓库默认位置 > 向上找
if [[ -z "$DB" ]]; then
  DB="${OPENLEARN_DB:-$PLATFORM/packages/core/db/educational_os.db}"
fi
[[ -f "$DB" ]] || { echo "找不到数据库：$DB（安装过一次插件后才有；用 --db 指定）"; exit 2; }

if [[ -n "$ZIP" && ! -f "$ZIP" ]]; then
  echo "找不到 ZIP：$ZIP"; exit 2
fi

python3 - "$DB" "$PLATFORM" "$TARGET" "$ZIP" "$PORT" "$JSON" <<'PY'
import json, os, sqlite3, sys, urllib.request, urllib.error

db_path, platform, target, zip_path, port, as_json = sys.argv[1:7]
port = int(port)
results = []   # (level, title, detail)  level: ok / warn / fail

def add(level, title, detail=""):
    results.append((level, title, detail))

# ---------- 1. 取 DB 行 ----------
con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
con.row_factory = sqlite3.Row
cols = {r[1] for r in con.execute("PRAGMA table_info(plugins)")}
need = {"id", "manifest", "status"}
if not need <= cols:
    print(f"✖ plugins 表结构与预期不符（缺 {need - cols}）；平台版本过旧？")
    sys.exit(2)

row = con.execute(
    "SELECT * FROM plugins WHERE id = ? OR json_extract(manifest,'$.id') = ? "
    "ORDER BY created_at DESC LIMIT 1", (target, target)
).fetchone()
if row is None:
    print(f"✖ 数据库里没有插件 {target}（还没安装成功？或装到了别的库）")
    print(f"  提示：库文件 {db_path}；用 sqlite3 '{db_path}' \"SELECT id,name FROM plugins\" 核对")
    sys.exit(1)

install_id = row["id"]
try:
    manifest = json.loads(row["manifest"] or "{}")
except json.JSONDecodeError as e:
    print(f"✖ plugins.manifest 不是合法 JSON：{e}")
    sys.exit(1)

plugin_id = manifest.get("id") or install_id

# file_path 列存的是入口文件（plugins/{uuid}/index.js），不是目录；两种形态都要兼容
raw_path = row["file_path"] if "file_path" in cols and row["file_path"] else ""
if raw_path and raw_path.endswith(".js"):
    plugin_dir = os.path.dirname(raw_path)
elif raw_path:
    plugin_dir = raw_path
else:
    plugin_dir = os.path.join(platform, "plugins", install_id)
status = row["status"] if "status" in cols else "?"
mode = row["execution_mode"] if "execution_mode" in cols else "?"
version = row["version"] if "version" in cols else ""

add("ok", f"找到安装行 {install_id}", f"{plugin_id} v{version} status={status} mode={mode}")

# ---------- 2. 状态 ----------
if status.lower() != "active":
    add("fail", f"插件未处于 active（当前 {status}）", "先启用；ERROR 状态看日志 [Plugin:%s] 前缀" % install_id)
else:
    add("ok", "状态 active", "")

if mode != "process":
    add("warn", f"executionMode={mode}（第三方插件应为 process）", "v0.7.0+ 强制子进程；若为 inline 说明是老记录或被白名单放行")

# ---------- 3. 收集 manifest 里的全部 view ----------
def walk(node, path=""):
    """递归找出所有带 view 的条目，返回 [(槽位路径, 条目dict)]"""
    out = []
    if isinstance(node, dict):
        if isinstance(node.get("view"), str):
            out.append((path, node))
        for k, v in node.items():
            if k == "view":
                continue
            out.extend(walk(v, f"{path}.{k}" if path else k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            out.extend(walk(v, f"{path}[{i}]"))
    return out

declared = walk(manifest.get("contributes") or {})
if not declared:
    add("warn", "manifest 里没有任何 view", "若插件本就走 React 组件/命令面板，可忽略；否则确认 contributes 写对了")
else:
    add("ok", f"DB 中的 manifest 声明了 {len(declared)} 个 view",
        ", ".join(p for p, _ in declared))

# ---------- 4. view 路径与落盘文件 ----------
for slot, entry in declared:
    view = entry["view"]
    if not view.startswith("storage/"):
        add("fail", f"{slot}.view 不在 storage/ 下：{view}",
            "安装器只解压 ZIP 的 storage/**，其他前缀不会落盘 → 运行时「非法的插件视图路径」")
        continue
    if ".." in view.split("/"):
        add("fail", f"{slot}.view 含 ..：{view}", "路径穿越会被渲染器拒绝")
        continue
    fpath = os.path.join(plugin_dir, view)
    if os.path.isfile(fpath):
        size = os.path.getsize(fpath)
        add("ok", f"{slot}.view 已落盘", f"{view} ({size} B)")
    else:
        add("fail", f"{slot}.view 文件不存在", f"期望 {fpath}")
        # 给一个"目录里到底有什么"的线索，省一轮 ls
        if os.path.isdir(os.path.join(plugin_dir, "storage")):
            got = sorted(os.listdir(os.path.join(plugin_dir, "storage")))
            add("warn", "  storage/ 实际内容", ", ".join(got) or "（空）")
        else:
            add("warn", "  插件目录里没有 storage/", "说明 ZIP 根本没带静态文件")

# ---------- 5. frontend.js（最容易被忽略的激活门槛） ----------
fe = os.path.join(plugin_dir, "frontend.js")
if os.path.isfile(fe):
    add("ok", "frontend.js 存在", f"{os.path.getsize(fe)} B")
else:
    add("fail", "缺少 frontend.js",
        "宿主激活时先 fetch /plugins/{id}/frontend.js，404 会抛错，registerManifestContributions 永不执行"
        " → 所有声明式入口同时消失且日志静默。补一个空 src/frontend.tsx 并确保打包包含它")

# ---------- 6. 与 ZIP 对比：检出被 strip 的字段 ----------
if zip_path:
    import zipfile
    try:
        zf = zipfile.ZipFile(zip_path)
    except zipfile.BadZipFile as e:
        add("fail", f"ZIP 无法解析：{e}", "")
        zf = None
    if zf:
        names = set(zf.namelist())
        add("ok", f"ZIP 共 {len(names)} 个条目", "")

        if "frontend.js" not in names:
            add("fail", "ZIP 内缺 frontend.js", "官方 CLI 只打 3 个文件；自定义打包务必显式加入（见 pack.mjs）")
        else:
            add("ok", "ZIP 内含 frontend.js", "")

        if "manifest.json" in names:
            try:
                zip_manifest = json.loads(zf.read("manifest.json").decode("utf-8"))
            except Exception as e:
                zip_manifest = None
                add("fail", f"ZIP 内 manifest.json 解析失败：{e}", "")
            if zip_manifest:
                zip_views = walk(zip_manifest.get("contributes") or {})
                db_view_slots = {p for p, _ in declared}
                stripped = [(p, e["view"]) for p, e in zip_views if p not in db_view_slots]
                if stripped:
                    add("fail", f"{len(stripped)} 个 view 在安装时被 schema strip 掉了",
                        "；".join(f"{p} → {v}" for p, v in stripped))
                    add("warn", "  修复方式",
                        "① 确认平台已包含该槽位的 view 声明（manifest-schema.ts），改完必须重启 dev；"
                        "② 重新上传安装（激活只 JSON.parse 旧值，升级不回填）")
                elif zip_views:
                    add("ok", "ZIP 声明的 view 全部落进了 DB", "")

                # 静态文件是否进包
                missing = [v for _, e in zip_views for v in [e["view"]]
                           if v.startswith("storage/") and v not in names]
                if missing:
                    add("fail", f"{len(missing)} 个 view 文件没打进 ZIP", ", ".join(missing))
                elif zip_views:
                    add("ok", "ZIP 内 view 文件齐全", "")

# ---------- 7. HTTP 抽查（可选） ----------
if port > 0:
    base = f"http://localhost:{port}"
    try:
        with urllib.request.urlopen(f"{base}/api/plugins", timeout=5) as r:
            add("ok", f"平台可达（{base}/api/plugins）", f"HTTP {r.status}")
            api_ok = True
    except urllib.error.HTTPError as e:
        add("warn", f"/api/plugins 返回 {e.code}", "需要登录态，跳过接口核对；静态资源仍可单独验")
        api_ok = False
    except Exception as e:
        add("warn", f"连不上 {base}", f"{type(e).__name__}；端口不对就用 --port 指定，或 --port 0 跳过（{e}）")
        api_ok = False

    if api_ok:
        for slot, entry in declared:
            url = f"{base}/plugins/{install_id}/{entry['view']}"
            try:
                req = urllib.request.Request(url, method="HEAD")
                with urllib.request.urlopen(req, timeout=5) as r:
                    add("ok", f"静态资源可达 {slot}", f"HTTP {r.status} {entry['view']}")
            except urllib.error.HTTPError as e:
                add("fail", f"静态资源 {e.code}：{entry['view']}", url)
            except Exception as e:
                add("warn", f"静态资源检查失败：{entry['view']}", f"{type(e).__name__}")

# ---------- 输出 ----------
fails = [r for r in results if r[0] == "fail"]
warns = [r for r in results if r[0] == "warn"]

if as_json == "1":
    print(json.dumps({"target": plugin_id, "installId": install_id, "db": db_path,
                      "results": [{"level": l, "title": t, "detail": d} for l, t, d in results]},
                     ensure_ascii=False, indent=2))
else:
    icon = {"ok": "✔", "warn": "▲", "fail": "✖"}
    for level, title, detail in results:
        line = f"{icon[level]} {title}"
        print(line)
        if detail:
            print(f"   {detail}")
    print()
    print(f"—— {len(results) - len(fails) - len(warns)} 通过 / {len(warns)} 提醒 / {len(fails)} 失败")
    if fails:
        print("结论：安装不完整，先修 ✖ 再谈「页面上为什么看不到」。")
    elif warns:
        print("结论：结构完整。剩余 ▲ 多为环境提示，按 detail 处理。")
    else:
        print("结论：结构完整，可以开始肉眼验收入口了。")

sys.exit(1 if fails else 0)
PY
