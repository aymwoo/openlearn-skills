#!/usr/bin/env python3
"""
scaffold-fingerprint.py —— 提取插件模板的「契约指纹」

用于比对本 skill 的 assets/<template>/ 与官方 CLI 脚手架
（<platform-repo>/packages/plugin-sdk/scaffold/templates/<template>/）之间的**语义差异**，
而不是逐行 diff —— 我们在官方模板基础上加了中文注释与 guardrail，逐行 diff 只会全是噪声。

指纹包含：
  files            模板包含的文件
  manifest_keys    manifest 的字段名集合
  manifest_values  关键字段的字面值（main / engines.openlearn）
  placeholders     模板中用到的 {{占位符}}
  exports          具名导出
  default_export   default export 的形状（activate / deactivate）
  command_types    actionRegistry 登记的 commandType 与 registerHandler 的 type
  frontend_react   前端产物是否依赖 React / DOM
  sdk_dep          package.json 中 @openlearn/plugin-sdk 的依赖写法

用法：
  python3 scaffold-fingerprint.py <template-dir> [<template-name>]
输出：一行 JSON
"""
import json
import re
import sys
from pathlib import Path


def read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8")
    except Exception:
        return ""


def manifest_keys(src: str) -> list:
    m = re.search(r"manifest:\s*\{(.*?)\n  \},", src, re.S)
    if not m:
        return []
    return re.findall(r"^\s{4}(\w+):", m.group(1), re.M)


def manifest_values(src: str) -> dict:
    out = {}
    m = re.search(r"^\s{4}main:\s*(.+?),?\s*$", src, re.M)
    if m:
        out["main"] = m.group(1).rstrip(",").strip()
    m = re.search(r"engines:\s*\{\s*openlearn:\s*(.+?)\s*\}", src)
    if m:
        out["engines.openlearn"] = m.group(1).strip()
    return out


def command_types(src: str) -> dict:
    actions = re.findall(r"commandType:\s*'([^']+)'", src)
    handlers = re.findall(r"registerHandler\(\s*'([^']+)'", src)
    return {
        "actions": sorted(set(actions)),
        "handlers": sorted(set(handlers)),
    }


def frontend_react(fe: Path) -> bool:
    if not fe.exists():
        return False
    src = read(fe)
    # 注释里的 React 提及不算依赖
    code = "\n".join(
        line for line in src.splitlines()
        if not line.strip().startswith(("*", "//", "/*"))
    )
    return bool(re.search(r"from\s+['\"]react|ReactDOM|document\.|window\.", code))


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: scaffold-fingerprint.py <template-dir> [name]", file=sys.stderr)
        return 2

    tdir = Path(sys.argv[1]).resolve()
    name = sys.argv[2] if len(sys.argv) > 2 else tdir.name

    idx = tdir / "src" / "index.ts"
    fe = tdir / "src" / "frontend.tsx"
    pkg = tdir / "package.json"

    src = read(idx)
    fe_src = read(fe)

    default_export = []
    m_def = re.search(r"export\s+default\s*\{([^}]*)\}", fe_src, re.S)
    if m_def:
        default_export = sorted(set(re.findall(r"\b(activate|deactivate)\b", m_def.group(1))))

    sdk_dep = ""
    pkg_text = read(pkg)
    m = re.search(r'"@openlearn/plugin-sdk":\s*"([^"]+)"', pkg_text)
    if m:
        sdk_dep = m.group(1)

    fp = {
        "template": name,
        "files": sorted(str(p.relative_to(tdir)) for p in tdir.rglob("*")
                        if p.is_file() and "node_modules" not in p.parts),
        "manifest_keys": manifest_keys(src),
        "manifest_values": manifest_values(src),
        "placeholders": sorted(set(re.findall(r"\{\{([a-zA-Z]+)\}\}",
                                              "\n".join(read(p) for p in tdir.rglob("*")
                                                        if p.is_file() and p.suffix in {".ts", ".tsx", ".json"})))),
        "exports": sorted(set(re.findall(r"export\s+(?:async\s+)?function\s+(\w+)", fe_src))),
        "default_export": default_export,
        "command_types": command_types(src),
        "frontend_react": frontend_react(fe),
        "sdk_dep": sdk_dep,
    }
    print(json.dumps(fp, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
