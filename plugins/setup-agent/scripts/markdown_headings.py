#!/usr/bin/env python3
"""Markdown 标题层级平移，供渲染脚本共用。

写进指令文件的内容顶层节标题用 `#`（见安装器的「指令文件里的标记」），而模板的层级按它自己的
形态写，所以渲染时要整体平移。代码块里以 # 开头的行不是标题，不动；平移出 1–6 级就报错，
免得静默生成非法层级。
"""

import re
from pathlib import Path

# 行首缩进 0–3 个空格、# 之后跟空格或制表符的才是 ATX 标题，平移时保留原有缩进。
HEADING = re.compile(r"^( {0,3})(#{1,6})(?=[ \t])")
# 围栏：开头那行定下符号（` 或 ~）与长度，只有同一符号、不短于它、其后只有空白的行才收尾，
# 所以 ``` 块里的 ~~~ 行（反之亦然）不会提前结束代码块。缩进不限，列表项里的代码块也算。
FENCE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")


def fence_closes(opener: str, line: str) -> bool:
    m = FENCE.match(line)
    return bool(m) and m.group(1)[0] == opener[0] and len(m.group(1)) >= len(opener) and not m.group(2).strip()


def shift_headings(source: Path, body: str, delta: int) -> str:
    """把正文里的标题层级平移 delta 级（正数下移、负数上移）。

    结尾仍有未闭合的围栏时报错：否则其后的标题全被当成代码块，静默地不平移。
    """
    out = []
    opener = ""
    for line in body.split("\n"):
        if opener:
            if fence_closes(opener, line):
                opener = ""
        elif fence := FENCE.match(line):
            opener = fence.group(1)
        elif m := HEADING.match(line):
            indent, hashes = m.groups()
            level = len(hashes) + delta
            if level > 6:
                raise ValueError(f"{source}：标题下移后超过六级：{line}")
            if level < 1:
                raise ValueError(f"{source}：标题上移后不足一级：{line}")
            line = indent + "#" * level + line[len(indent) + len(hashes) :]
        out.append(line)
    if opener:
        raise ValueError(f"{source}：代码块围栏 {opener} 到结尾都没有闭合")
    return "\n".join(out)
