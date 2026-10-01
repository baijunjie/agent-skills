#!/usr/bin/env python3
"""把 Concise+ 回答规则模板渲染成 Codex 的 AGENTS.md 里的一节，输出到 stdout。

模板就是 Claude Code 的输出风格文件（带 frontmatter），Claude Code 直接复制它，不经本脚本。
Codex 没有输出风格机制，改为写进 AGENTS.md：去掉 frontmatter，以「## 输出风格：<frontmatter 的 name>」
为节标题，正文里的标题整体下移两级成为它的子节，其余逐字不变。指令文件的标记由安装器在外面包上，
这里不输出，这样渲染失败时安装器不会写进半截标记。
"""

import argparse
import re
import sys
from pathlib import Path

SECTION_LEVEL = 2
SECTION_TITLE = "输出风格：{name}"

HEADING = re.compile(r"^(#{1,6})(?= )")
# 围栏：开头那行定下符号（` 或 ~）与长度，只有同一符号、不短于它、其后只有空白的行才收尾，
# 所以 ``` 块里的 ~~~ 行（反之亦然）不会提前结束代码块。缩进不限，列表项里的代码块也算。
FENCE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")


def fence_closes(opener: str, line: str) -> bool:
    m = FENCE.match(line)
    return bool(m) and m.group(1)[0] == opener[0] and len(m.group(1)) >= len(opener) and not m.group(2).strip()


def split_frontmatter(source: Path, text: str) -> tuple[str, str]:
    """返回 (frontmatter 里 name 的值, frontmatter 之后的正文)。"""
    lines = text.split("\n")
    if lines[0] != "---":
        raise ValueError(f"{source}：第一行必须是 frontmatter 的 ---")
    try:
        closing = lines.index("---", 1)
    except ValueError:
        raise ValueError(f"{source}：frontmatter 没有闭合的 ---") from None
    names = [line.partition(":")[2].strip() for line in lines[1:closing] if line.startswith("name:")]
    if len(names) != 1 or not names[0]:
        raise ValueError(f"{source}：frontmatter 须有且只有一个非空的 name")
    return names[0], "\n".join(lines[closing + 1 :]).lstrip("\n")


def demote(source: Path, body: str) -> str:
    """正文标题下移到节标题之下；代码块里以 # 开头的行不是标题，不动。"""
    out = []
    opener = ""
    for line in body.split("\n"):
        if opener:
            if fence_closes(opener, line):
                opener = ""
        elif fence := FENCE.match(line):
            opener = fence.group(1)
        elif m := HEADING.match(line):
            level = len(m.group(1)) + SECTION_LEVEL
            if level > 6:
                raise ValueError(f"{source}：标题下移后超过六级：{line}")
            line = "#" * SECTION_LEVEL + line
        out.append(line)
    return "\n".join(out)


def render(source: Path) -> str:
    name, body = split_frontmatter(source, source.read_text(encoding="utf-8"))
    title = "#" * SECTION_LEVEL + " " + SECTION_TITLE.format(name=name)
    return f"{title}\n\n{demote(source, body)}"


def main() -> int:
    parser = argparse.ArgumentParser(description="把 Concise+ 回答规则模板渲染成 Codex 的 AGENTS.md 里的一节，输出到 stdout。")
    parser.add_argument("source", type=Path, help="模板路径，即 Claude Code 的输出风格文件")
    args = parser.parse_args()

    try:
        sys.stdout.write(render(args.source))
    except (ValueError, OSError) as error:
        print(f"{parser.prog}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
