#!/usr/bin/env python3
"""把 Concise+ 回答规则模板按宿主渲染，输出到 stdout。

模板就是 Claude Code 的输出风格文件（带 frontmatter），正文里有且只有一个占位符：
{{OUTPUT_LANGUAGE}}，换成 --language 给的回答语言。

  --host claude   输出完整的输出风格文件，frontmatter 原样保留
  --host codex    Codex 没有输出风格机制，改为写进 AGENTS.md：去掉 frontmatter，以「# 输出风格：<frontmatter 的 name>」
                  为节标题，正文里的标题整体下移一级成为它的子节

其余逐字不变。指令文件的标记由安装器在外面包上，这里不输出，这样渲染失败时安装器不会写进半截标记。
"""

import argparse
import sys
from pathlib import Path

# 安装器是在装出去的 plugin 目录里跑本脚本的，import 同目录模块不要在那里留下 __pycache__。
sys.dont_write_bytecode = True

from markdown_headings import shift_headings  # noqa: E402

SECTION_LEVEL = 1
SECTION_TITLE = "输出风格：{name}"

LANGUAGE_PLACEHOLDER = "{{OUTPUT_LANGUAGE}}"
HOSTS = ("claude", "codex")


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


def fill(source: Path, text: str, language: str) -> str:
    if text.count(LANGUAGE_PLACEHOLDER) != 1:
        raise ValueError(f"{source}：须有且只有一个 {LANGUAGE_PLACEHOLDER} 占位符")
    return text.replace(LANGUAGE_PLACEHOLDER, language)


def render(source: Path, host: str, language: str) -> str:
    text = source.read_text(encoding="utf-8")
    name, body = split_frontmatter(source, text)
    if host == "claude":
        return fill(source, text, language)
    title = "#" * SECTION_LEVEL + " " + SECTION_TITLE.format(name=name)
    return f"{title}\n\n{shift_headings(source, fill(source, body, language), SECTION_LEVEL)}"


def main() -> int:
    parser = argparse.ArgumentParser(description="把 Concise+ 回答规则模板按宿主渲染，输出到 stdout。")
    parser.add_argument("source", type=Path, help="模板路径，即 Claude Code 的输出风格文件")
    parser.add_argument("--host", choices=HOSTS, required=True, help="目标宿主")
    parser.add_argument("--language", required=True, help="回答用的语言，如「简体中文（zh-Hans）」")
    args = parser.parse_args()
    language = args.language.strip()
    if not language or "\n" in language:
        parser.error("--language 须是非空的单行文字")

    try:
        sys.stdout.write(render(args.source, args.host, language))
    except (ValueError, OSError) as error:
        print(f"{parser.prog}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
