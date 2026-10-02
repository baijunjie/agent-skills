"""校验 plugin manifest 与两个 marketplace 的一致性，以及「版本只升一次」。

用法：python3 -B check.py <仓库根>

规则原文在 docs/authoring.md「新增 plugin」与 docs/release.md「发布」，这里只做机械检查：

- manifest：plugins/ 下每个 plugin 都有 plugin.json、.codex-plugin/plugin.json、.claude-plugin/plugin.json，
  都能解析，三份的 version 相同、description 相同。
- marketplace：.claude-plugin/marketplace.json 与 .agents/plugins/marketplace.json 的 plugins 数组各登记了
  plugins/ 下的全部 plugin（不多、不漏、不重复，source 指向 ./plugins/<名>）；
  .claude-plugin/marketplace.json 里的 description 与 manifest 的 description 一字不差。
- interface：.codex-plugin/plugin.json 有 interface，其 displayName、shortDescription、longDescription 是非空字符串。
- 版本：以 origin/main 为已发布版本。相对它内容有变化的 plugin（git diff --name-only origin/main 非空，
  或有未跟踪的新文件；只改了 manifest 的 version 不算内容变化），version 必须恰好升一级
  （patch+1；或 minor+1 且 patch 归零；或 major+1 且 minor、patch 归零）；内容没变的 version 必须不变。
  origin/main 上没有的 plugin 不比。本地没有 origin/main（无远程、CI 浅克隆没取到）时整项 SKIP。

不校验、靠复核：
- interface 文案（shortDescription、longDescription 等）与 description 意思是否一致——
  两者本来就是不同长度的转述，没有可机械比对的原文。
- 升 patch 还是 minor 是否与改动性质相符（破坏性变更或新增能力升 minor）。
- 三份 manifest 中 version、description 以外的字段。
- README 的安装、更新命令与「可用 Skills」是否补了新 plugin。
- interface 三个字段非空只是「文案与 description 保持一致」的最低机械近似。

只对仓库做只读的 git 查询（rev-parse、show、diff --name-only、ls-files）。
输出：每项一行 `ok <项>`、`FAIL <项>: <原因>` 或 `SKIP <项>: <原因>`；有 FAIL 时退出码 1。
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PROG = "check.py"
MANIFESTS = ("plugin.json", ".codex-plugin/plugin.json", ".claude-plugin/plugin.json")
CLAUDE_MP = ".claude-plugin/marketplace.json"
CODEX_MP = ".agents/plugins/marketplace.json"
BASE = "origin/main"
VERSION_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")

failures = []


def report(kind, item, msg=""):
    if kind == "FAIL":
        failures.append(item)
    print(f"{kind} {item}" + (f": {msg}" if msg else ""))


def git(root, *args):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, env=env)


def load(path):
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except (OSError, ValueError) as e:
        return None, f"{path.name} 无法解析：{e}"


def check_manifests(root, plugins):
    """返回 {plugin: {manifest 路径: 数据}}，解析失败的不收。"""
    data = {}
    for p in plugins:
        item = f"manifest {p}"
        got = {}
        errs = []
        for m in MANIFESTS:
            f = root / "plugins" / p / m
            if not f.is_file():
                errs.append(f"缺 {m}")
                continue
            d, err = load(f)
            if err:
                errs.append(f"{m} 无法解析")
            elif not isinstance(d, dict):
                errs.append(f"{m} 不是 JSON 对象")
            else:
                got[m] = d
        data[p] = got
        if errs:
            report("FAIL", item, "；".join(errs))
            continue
        for key in ("version", "description"):
            vals = {m: got[m].get(key) for m in MANIFESTS}
            if len(set(map(json.dumps, vals.values()))) != 1:
                detail = "，".join(f"{m}={json.dumps(v, ensure_ascii=False)}" for m, v in vals.items())
                errs.append(f"三份 manifest 的 {key} 不一致（{detail}）")
        if errs:
            report("FAIL", item, "；".join(errs))
        else:
            report("ok", item)
    return data


def check_marketplace(root, plugins, rel, source_of):
    item = f"marketplace {rel}"
    d, err = load(root / rel)
    if err:
        report("FAIL", item, err)
        return {}
    entries = d.get("plugins") if isinstance(d, dict) else None
    if not isinstance(entries, list):
        report("FAIL", item, "没有 plugins 数组")
        return {}
    errs = []
    seen = {}
    for e in entries:
        name = e.get("name") if isinstance(e, dict) else None
        if not isinstance(name, str):
            errs.append("有条目缺 name")
            continue
        if name in seen:
            errs.append(f"{name} 重复登记")
        seen[name] = e
        src = source_of(e)
        if src != f"./plugins/{name}":
            errs.append(f"{name} 的 source 是 {json.dumps(src, ensure_ascii=False)}，应为 ./plugins/{name}")
    missing = [p for p in plugins if p not in seen]
    extra = [n for n in seen if n not in plugins]
    if missing:
        errs.append("漏登记：" + "、".join(missing))
    if extra:
        errs.append("登记了 plugins/ 下没有的：" + "、".join(extra))
    if errs:
        report("FAIL", item, "；".join(errs))
    else:
        report("ok", item)
    return seen


def check_claude_descriptions(entries, manifests):
    errs = []
    for name, e in entries.items():
        m = manifests.get(name, {}).get("plugin.json")
        if m is None:
            continue
        if e.get("description") != m.get("description"):
            errs.append(f"{name} 的 description 与 manifest 不一致")
    item = f"marketplace {CLAUDE_MP} description"
    if errs:
        report("FAIL", item, "；".join(errs))
    else:
        report("ok", item)


def check_interface(manifests):
    for p, got in manifests.items():
        m = got.get(".codex-plugin/plugin.json")
        if m is None:
            continue
        item = f"interface {p}"
        iface = m.get("interface")
        if not isinstance(iface, dict):
            report("FAIL", item, ".codex-plugin/plugin.json 没有 interface")
            continue
        bad = [k for k in ("displayName", "shortDescription", "longDescription")
               if not isinstance(iface.get(k), str) or not iface[k].strip()]
        if bad:
            report("FAIL", item, "interface 缺少或为空：" + "、".join(bad))
        else:
            report("ok", item)


def parse_version(v):
    m = VERSION_RE.match(v) if isinstance(v, str) else None
    return tuple(int(x) for x in m.groups()) if m else None


def one_step_up(old, new):
    ma, mi, pa = old
    return new in ((ma, mi, pa + 1), (ma, mi + 1, 0), (ma + 1, 0, 0))


def strip_version(d):
    return {k: v for k, v in d.items() if k != "version"}


def check_versions(root, plugins, manifests):
    item = "version"
    if git(root, "rev-parse", "--is-inside-work-tree").returncode != 0:
        report("SKIP", item, f"{root} 不是 git 工作副本，无法与已发布版本比较")
        return
    if git(root, "rev-parse", "--verify", "-q", f"{BASE}^{{commit}}").returncode != 0:
        report("SKIP", item, f"本地没有 {BASE}（无远程或未取到），无法与已发布版本比较")
        return
    sha = git(root, "rev-parse", "--short", f"{BASE}^{{commit}}").stdout.strip()
    report("ok", "version base", f"已发布版本取自本地的 {BASE}（{sha}）；它过时时先 git fetch")
    for p in plugins:
        pitem = f"version {p}"
        got = manifests.get(p, {})
        if len(got) != len(MANIFESTS):
            continue  # manifest 项已报 FAIL
        olds = {}
        for m in MANIFESTS:
            r = git(root, "show", f"{BASE}:plugins/{p}/{m}")
            if r.returncode != 0:
                olds = None
                break
            try:
                olds[m] = json.loads(r.stdout)
            except ValueError:
                olds = None
                break
        if olds is None:
            report("ok", pitem, f"{BASE} 上没有这个 plugin 的完整 manifest，视为未发布，不比")
            continue
        new_vs = {got[m].get("version") for m in MANIFESTS}
        old_vs = {olds[m].get("version") for m in MANIFESTS}
        if len(new_vs) != 1:
            continue  # manifest 项已报 FAIL
        if len(old_vs) != 1:
            report("FAIL", pitem, f"{BASE} 上三份 manifest 的 version 本就不一致，无法确定已发布版本")
            continue
        new_v, old_v = new_vs.pop(), old_vs.pop()
        new_t, old_t = parse_version(new_v), parse_version(old_v)
        if new_t is None or old_t is None:
            report("FAIL", pitem, f"version 不是 X.Y.Z：工作副本 {new_v}，{BASE} {old_v}")
            continue

        d = git(root, "diff", "--name-only", BASE, "--", f"plugins/{p}")
        u = git(root, "ls-files", "--others", "--exclude-standard", "--", f"plugins/{p}")
        if d.returncode != 0 or u.returncode != 0:
            report("FAIL", pitem, "git diff / ls-files 失败：" + (d.stderr or u.stderr).strip())
            continue
        changed = set(d.stdout.split("\n")) | set(u.stdout.split("\n"))
        changed.discard("")
        manifest_paths = {f"plugins/{p}/{m}" for m in MANIFESTS}
        content_changed = bool(changed - manifest_paths) or any(
            strip_version(got[m]) != strip_version(olds[m]) for m in MANIFESTS)

        if content_changed:
            if one_step_up(old_t, new_t):
                report("ok", pitem, f"{old_v} → {new_v}")
            elif new_t == old_t:
                report("FAIL", pitem, f"内容相对 {BASE} 有变化，version 仍是 {old_v}，没有升")
            else:
                report("FAIL", pitem, f"内容相对 {BASE} 有变化，version {old_v} → {new_v} 不是恰好升一级")
        elif new_t != old_t:
            report("FAIL", pitem, f"内容相对 {BASE} 没有变化，version 却从 {old_v} 改成了 {new_v}")
        else:
            report("ok", pitem, f"内容未变，{new_v}")


def main():
    ap = argparse.ArgumentParser(prog=PROG, description="校验 plugin manifest 与 marketplace")
    ap.add_argument("root", help="仓库根目录")
    args = ap.parse_args()
    root = Path(args.root)
    pdir = root / "plugins"
    if not pdir.is_dir():
        print(f"{PROG}: 找不到 {pdir}", file=sys.stderr)
        return 1
    plugins = sorted(c.name for c in pdir.iterdir() if c.is_dir() and not c.name.startswith("."))
    manifests = check_manifests(root, plugins)
    claude = check_marketplace(root, plugins, CLAUDE_MP, lambda e: e.get("source"))
    check_marketplace(root, plugins, CODEX_MP,
                      lambda e: e.get("source", {}).get("path") if isinstance(e.get("source"), dict) else None)
    check_claude_descriptions(claude, manifests)
    check_interface(manifests)
    check_versions(root, plugins, manifests)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
