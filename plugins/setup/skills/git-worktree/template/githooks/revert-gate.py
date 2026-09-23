#!/usr/bin/env python3
"""回退闸门：拦下「把目标分支上已合并的改动悄悄撤销掉」的更新。

典型成因是压平时换了基点却没合内容（如 `git reset --soft <目标分支>` 后提交），
旧代码被当成新改动压进去。`git merge --ff-only` 只校验祖先关系，照样快进成功，
所以在受守护的分支移动时按内容检查。受守护的是各 worktree 分支记录的目标分支
（`git config branch.<分支>.worktreeTarget`），外加 `git config revert-gate.branch` 常驻守护的分支
（可多值，通常是主分支）。只看记录、不看主工作副本当前在哪个分支，是为了不把人在自己的特性分支上
rebase、amend 也拦下来；没记录的目标分支因此不受守护。这份判定在 hook.sh 里有一份同样的 shell 版本，
两边要一起改：

1. 非快进只在被丢下的提交都没发布过时才可能放行（`pull --rebase`、改写还没推送的本地提交），
   且同样要过第 2 条的内容检查——同一个 clone 里没推送的提交也可能是别人刚合并的。
   与远端跟踪分支对齐、且不丢下本地未推送提交的移动直接放行（已发布的历史本地拦不回来）。
2. 移动前该分支上最近 WINDOW 个非 merge 提交里，有被这次移动撤销的就拒绝，判据见 find_reverts。
   只新增内容的提交被整体删掉不算撤销，所以撤销一个纯新增的提交拦不住——这是为了不把
   「删掉做完的计划文档」「去掉临时代码」这类正常清理挡下来。
3. 本次新增提交的信息里带 `Reverts: <sha>` 或 git revert 默认的
   `This reverts commit <sha>.` 时，放行对应提交——有意撤销必须留下记录。

用法：
  revert-gate.py reference-transaction <state>   由 hook.sh 调用，stdin 为 ref 更新列表
  revert-gate.py pre-push <remote> <url>         由 hook.sh 调用
  revert-gate.py check <目标分支> <new>          手动检查把目标分支移到 new；命中退出码 1，检查出错退出码 2

hook 模式下拒绝时退出码为 3，hook.sh 只把 3 当作拒绝（两边分开更新，这个约定不能改）：
闸门自身出错（含脚本跑不起来）时放行，宁可漏检一次，也不能让它卡死所有 ref 更新。
设置环境变量 REVERT_GATE_SKIP=1 可临时跳过，仅供人确认过的场合使用。依赖 git 2.28+。
"""

import os
import re
import subprocess
import sys
from collections import Counter

# 往回查多少个提交。回退通常来自同一时期并行开发的分支，基点落后不会太远；
# 太大则每次合并都要多读很多 blob。
WINDOW = 50

# 行级判定：C 增加的行消失、删掉的行重现，各自占比达到 RATIO 才算这个文件被还原。
# 「成批重现」另要求重现行数不少于 MIN_LINES，零星几行撞上是正常改动。
RATIO = 0.5
MIN_LINES = 3

# 超过这个大小的文件只做整文件比对、不读内容，免得每次合并都把大文件读进内存。
MAX_BLOB = 4 * 1024 * 1024

# 只由括号、标点、空白构成的行在任何文件里都大量重复，计入会制造假信号。
TRIVIAL_LINE = re.compile(r"^[\s{}()\[\];,.:<>/*#-]*$")

OVERRIDE = re.compile(
    r"^(?:Reverts:\s*|This reverts commit )([0-9a-f]{7,64})", re.MULTILINE | re.IGNORECASE
)

REJECTED = 3

OID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")

# 部分克隆里读 blob 可能触发联网补取，hook 里不能这样做；取不到的内容当作没读到。
GIT_ENV = dict(os.environ, GIT_NO_LAZY_FETCH="1")


def git(*args, check=True, stdin=None):
    result = subprocess.run(["git", *args], input=stdin, capture_output=True, check=False, env=GIT_ENV)
    if check and result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} 失败：{result.stderr.decode(errors='replace').strip()}")
    return result


def text(data):
    return data.decode("utf-8", errors="surrogateescape")


def guarded_branches():
    """受守护的分支名集合，见文件说明。"""
    out = git("config", "--get-regexp", r"^(branch\..*\.worktreetarget|revert-gate\.branch)$", check=False).stdout
    return {line.split(" ", 1)[1] for line in text(out).split("\n") if " " in line}


def is_null(oid):
    return not oid or set(oid) == {"0"}


def is_ancestor(a, b):
    return git("merge-base", "--is-ancestor", a, b, check=False).returncode == 0


def has_commit(oid):
    return git("cat-file", "-e", f"{oid}^{{commit}}", check=False).returncode == 0


def rev_count(*args):
    return int(text(git("rev-list", "--count", *args).stdout).strip() or 0)


def batch_check(requests, fmt):
    """cat-file --batch-check，每个请求对应一行输出。请求里不能有换行。"""
    if not requests:
        return []
    request = "".join(f"{r}\n" for r in requests).encode("utf-8", "surrogateescape")
    out = git("cat-file", f"--batch-check={fmt}", stdin=request).stdout
    return text(out).split("\n")[:len(requests)]


def tree_entries(commit, paths):
    """paths 在 commit 里的 blob id，不存在（或不是普通文件）为 None。"""
    paths = [p for p in dict.fromkeys(paths) if "\n" not in p]
    lines = batch_check([f"{commit}:{p}" for p in paths], "%(objectname) %(objecttype)")
    result = {}
    # 找不到时回显的是请求本身加 " missing"，路径里可能有空格，只认「id + blob」这一种形态。
    for path, line in zip(paths, lines):
        oid, _, kind = line.partition(" ")
        result[path] = oid if kind == "blob" and OID.match(oid) else None
    return result


def read_blobs(oids):
    """按 blob id 读内容；超过 MAX_BLOB 的不读，返回里没有它。"""
    oids = [o for o in dict.fromkeys(oids) if o]
    wanted = []
    for oid, line in zip(oids, batch_check(oids, "%(objectsize)")):
        if line.isdigit() and int(line) <= MAX_BLOB:
            wanted.append(oid)
    if not wanted:
        return {}
    out = git("cat-file", "--batch", stdin="".join(f"{o}\n" for o in wanted).encode()).stdout
    blobs, pos = {}, 0
    for oid in wanted:
        eol = out.index(b"\n", pos)
        size = int(out[pos:eol].split()[-1])
        blobs[oid] = out[eol + 1:eol + 1 + size]
        pos = eol + 1 + size + 1
    return blobs


def lines_of(data):
    # 不用 splitlines：它还会在换页符、U+2028 等字符处断行，与 git 的行不一致。
    return Counter(line.strip() for line in text(data).split("\n") if not TRIVIAL_LINE.match(line))


def parse_raw(fields, i):
    """从 `-z --raw` 输出的第 i 个字段起解析一条文件变更，返回 ((改前 id, 改后 id, 路径), 下一个位置)。"""
    _, _, a, b, _ = text(fields[i])[1:].split(" ", 4)
    return ((None if is_null(a) else a, None if is_null(b) else b, text(fields[i + 1])), i + 2)


def tree_diff(a, b):
    """{路径: (a 里的 blob id, b 里的 blob id)}，只含两边不同的文件。"""
    fields = git("diff-tree", "-r", "-z", "--no-renames", a, b).stdout.split(b"\0")
    result, i = {}, 0
    while i + 1 < len(fields) and fields[i].startswith(b":"):
        (x, y, path), i = parse_raw(fields, i)
        result[path] = (x, y)
    return result


def recent_commits(base):
    """base 上最近 WINDOW 个非 merge 提交：[(sha, 标题, [(改前 id, 改后 id, 路径)])]。"""
    listing = text(git("log", "--no-merges", f"--max-count={WINDOW}", "--format=%H %s", base).stdout)
    subjects = dict(line.split(" ", 1) if " " in line else (line, "")
                    for line in listing.split("\n") if line)
    if not subjects:
        return []
    # --stdin 模式下每个提交先输出自己的 id、再跟文件列表；--root 让根提交与空树比较。
    out = git("diff-tree", "--stdin", "--root", "-r", "-z", "--no-renames",
              stdin="".join(f"{sha}\n" for sha in subjects).encode()).stdout
    fields = out.split(b"\0")
    changes, current, i = {sha: [] for sha in subjects}, None, 0
    while i < len(fields):
        field = text(fields[i])
        if OID.match(field.strip()):
            current, i = field.strip(), i + 1
        elif field.startswith(":") and current in changes and i + 1 < len(fields):
            change, i = parse_raw(fields, i)
            changes[current].append(change)
        else:
            i += 1
    return [(sha, subject, changes[sha]) for sha, subject in subjects.items()]


def overridden(old, new):
    messages = text(git("log", "--format=%B", f"{old}..{new}").stdout)
    return [m.lower() for m in OVERRIDE.findall(messages)]


def ratio(part, whole):
    return sum(part.values()) / sum(whole.values()) if whole else 1.0


def find_reverts(old, new):
    """返回 old → new 撤销掉的提交：[(sha, 标题, [(文件, 说明)])]，按从新到旧。

    一个提交 C 在两种情况下算被撤销：
    - 整体撤销：C 改过、且到 old 仍保留着 C 的改动的每个文件，这次都被还原了，并且 C 删掉的行
      这次又被找了回来。只新增内容的提交被整体删掉是正常清理，不算。
    - 局部撤销：C 修改或删除的某个已有文件被还原，且 C 删掉的行成批重现——rebase 时把冲突一律
      解到自己这一侧就是这个形态。
    行比对只看行的多重集合、不看位置，所以 C 之后文件又被别的提交改过也比得出来。
    """
    touched = tree_diff(old, new)
    if not touched:
        return []
    allowed = overridden(old, new)
    candidates = [c for c in recent_commits(old)
                  if any(path in touched for _, _, path in c[2])
                  and not any(c[0].startswith(a) for a in allowed)]
    if not candidates:
        return []
    # 没被这次移动改到的文件在 old 与 new 里是同一份，只需 old 里那份来判断 C 的改动还在不在。
    untouched = tree_entries(old, [p for c in candidates for _, _, p in c[2] if p not in touched])
    blobs = read_blobs({oid for c in candidates for before, after, p in c[2] if p in touched
                        for oid in (before, after, *touched[p])})

    def content(oid):
        return b"" if oid is None else blobs.get(oid)

    findings = []
    for sha, subject, changes in candidates:
        live, whole, restored_any, partial, reverted = 0, True, False, [], []
        for before, after, path in changes:
            at_old, at_new = touched[path] if path in touched else (untouched.get(path),) * 2
            if at_old == before:
                continue  # C 在这个文件上的改动在 old 之前就已被撤掉，与这次移动无关
            live += 1
            if at_new == at_old:
                whole = False
                continue
            exact = at_new == before
            data = [content(o) for o in (before, after, at_old, at_new)]
            if None in data:
                # 没读到内容（太大、子模块或本地缺这个对象），只凭整文件比对；
                # 此时无从得知 C 删过什么，按删改过已有内容算。
                if not exact:
                    whole = False
                    continue
                reverted.append(path)
                if before is not None:
                    restored_any = True
                    partial.append((path, "整个文件回到了它之前的版本"))
                continue
            c_before, c_after, old_lines, new_lines = map(lines_of, data)
            alive = (c_after - c_before) & old_lines
            gone = (c_before - c_after) - old_lines
            lost, back = alive - new_lines, gone & new_lines
            if not (exact or ((alive or gone) and ratio(lost, alive) >= RATIO and ratio(back, gone) >= RATIO)):
                whole = False
                continue
            reverted.append(path)
            if back:
                restored_any = True
            # 只看「删掉的行成批重现」：C 只加不删时，把它加的东西去掉（如删掉临时实测代码）是正常改动。
            if before is not None and sum(back.values()) >= MIN_LINES:
                partial.append((path, "整个文件回到了它之前的版本" if exact else
                                f"它删掉的 {sum(gone.values())} 行里重现了 {sum(back.values())} 行，"
                                f"增加的 {sum(alive.values())} 行里消失了 {sum(lost.values())} 行"))
        if live and whole and restored_any:
            findings.append((sha, subject, [(p, "这个提交在此文件上的改动被还原") for p in reverted]))
        elif partial:
            findings.append((sha, subject, partial))
    return findings


def report(branch, old, new, findings, merge_hint):
    print(f"\n[revert-gate] 拒绝把 {branch} 移到 {new[:10]}："
          f"相对 {old[:10]}，这次更新撤销了 {branch} 上已有提交的改动。\n", file=sys.stderr)
    for c, subject, hits in findings:
        print(f"  {c[:10]} {subject}", file=sys.stderr)
        for f, why in hits:
            print(f"      {f}：{why}", file=sys.stderr)
    print(f"""
最常见的成因是压平时换了基点却没合内容（例如 `git reset --soft {branch}` 后提交）。
在分支上退回压平前，改为 `git reset --soft $(git merge-base HEAD {branch})` 压平，
再 `git rebase {branch}` 如实解冲突。
确属有意撤销时，经确认后改用 `git revert`，或在撤销它的提交信息里为每个被撤销的提交加一行 `Reverts: <sha>`。
""", file=sys.stderr)
    if merge_hint:
        # git merge / pull 先写工作树与暂存区、最后才更新 ref，被拦下时内容已经落进了当前工作副本。
        print("被拦的是 merge / pull 时，工作副本已被写成分支内容，用 `git reset --merge` 复原：\n"
              "它只还原这次写入的文件、保留其它未提交改动；被拦的是 commit 时不要用它，会丢掉暂存的改动。\n"
              "被拦的是 rebase 时用 `git rebase --abort` 退出。\n", file=sys.stderr)


def remote_tips(branch):
    return text(git("for-each-ref", "--format=%(objectname)", f"refs/remotes/*/{branch}").stdout).split()


def check_move(branch, old, new, local, merge_hint=False):
    """检查受守护的分支 branch 从 old 到 new 的一次移动，放行返回 True。local 表示移动的是本地分支。"""
    if is_null(old) or is_null(new) or old == new:
        return True
    # 被丢下、且不在任何远端跟踪分支上的提交数：同一个 clone 里没推送的提交也可能是别人刚合并的。
    unpushed = rev_count(old, f"^{new}", "--not", "--remotes")
    if local and not unpushed and new in remote_tips(branch):
        return True
    if not is_ancestor(old, new):
        # 被丢下的提交里只要有一个已在远端跟踪分支上，就是在改写已发布的历史。
        published = rev_count(old, f"^{new}") - unpushed
        if not local or published:
            print(f"\n[revert-gate] 拒绝把 {branch} 从 {old[:10]} 移到 {new[:10]}：不是快进，"
                  f"会丢掉已发布的提交，{branch} 不许改写已发布的历史。\n"
                  f"被拦的是 rebase 时先 `git rebase --abort`；要与远端对齐用 "
                  f"`git reset --hard <远端>/{branch}`，再把本地提交重新接上去——它同样会丢掉本地没推送的提交，"
                  f"包括别人刚合并进来的，先确认过再做。\n", file=sys.stderr)
            return False
    # find_reverts 不要求 old 是 new 的祖先：非快进时同样以 old 为参照，丢下的本地提交也在检查之列。
    findings = find_reverts(old, new)
    if findings:
        report(branch, old, new, findings, merge_hint)
        return False
    return True


def reference_transaction(state):
    lines = text(sys.stdin.buffer.read()).split("\n")
    if state != "prepared":
        return 0
    guarded = guarded_branches()
    for line in lines:
        parts = line.split()
        if len(parts) != 3 or not parts[2].startswith("refs/heads/"):
            continue
        branch = parts[2][len("refs/heads/"):]
        if branch not in guarded:
            continue
        old, new = parts[0], parts[1]
        # 未指定期望旧值的更新会以全零作为旧值传进来；此刻 ref 已锁住但仍是旧值。
        if is_null(old):
            old = text(git("rev-parse", "--verify", "-q", parts[2], check=False).stdout).strip()
        if not OID.match(old or "") or not OID.match(new):
            continue  # 符号引用的值（ref:...）不是提交
        if not check_move(branch, old, new, local=True, merge_hint=True):
            return REJECTED
    return 0


def pre_push():
    guarded = guarded_branches()
    ok = True
    for line in text(sys.stdin.buffer.read()).split("\n"):
        parts = line.split()
        if len(parts) != 4 or not parts[2].startswith("refs/heads/"):
            continue
        branch = parts[2][len("refs/heads/"):]
        local, remote = parts[1], parts[3]
        # 远端提交本地没有时判断不了内容，交给远端拒绝非快进。
        if branch not in guarded or is_null(remote) or is_null(local) or not has_commit(remote):
            continue
        ok = check_move(branch, remote, local, local=False) and ok
    return 0 if ok else REJECTED


def main(argv):
    if os.environ.get("REVERT_GATE_SKIP") == "1":
        return 0
    mode = argv[1] if len(argv) > 1 else ""
    try:
        if mode == "reference-transaction":
            return reference_transaction(argv[2] if len(argv) > 2 else "")
        if mode == "pre-push":
            return pre_push()
        if mode == "check" and len(argv) == 4:
            old = text(git("rev-parse", "--verify", f"refs/heads/{argv[2]}^{{commit}}").stdout).strip()
            new = text(git("rev-parse", "--verify", f"{argv[3]}^{{commit}}").stdout).strip()
            return 0 if check_move(argv[2], old, new, local=False) else 1
    except Exception as e:  # noqa: BLE001 —— 任何意外都按文件说明里的出错策略处理
        print(f"[revert-gate] 检查出错{'' if mode == 'check' else '，已放行'}：{e!r}", file=sys.stderr)
        return 2 if mode == "check" else 0
    print(f"[revert-gate] 用法不对：{' '.join(argv[1:]) or '(无参数)'}", file=sys.stderr)
    return 2 if mode == "check" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
