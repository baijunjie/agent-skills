#!/usr/bin/env python3
"""把分派子代理的共享规则模板按宿主与作用域渲染，输出到 stdout。

模板里唯一的 {{HOST_AGENT_CONFIGURATION}} 占位符换成该宿主的模型配置小节。模板以用户级的
「# 全局规则」标题与首句开头，输出的层级按去处定：

  --scope project              去掉这个标题与首句（项目指令文件本身就是项目的规则），余下的标题整体上移
                               一级，让「分派子代理」成为顶层的 `#` 节——写进指令文件的内容顶层用 `#`，
                               否则这一节会挂到上一节底下（见安装器的「指令文件里的标记」）
  --scope user                 原样保留，「分派子代理」是「# 全局规则」下的 `##` 子节
  --scope user --no-header     去掉这个标题与首句、层级不动，挂到目标文件里已有的「# 全局规则」下

指令文件的标记由安装器在外面包上，这里不输出。
"""

import argparse
import sys
from pathlib import Path

# 安装器是在装出去的 plugin 目录里跑本脚本的，import 同目录模块不要在那里留下 __pycache__。
sys.dont_write_bytecode = True

from markdown_headings import shift_headings  # noqa: E402


USER_HEADER = """# 全局规则

与项目自己的指令文件冲突时，以项目的为准。

"""

HOST_AGENT_CONFIGURATION = {
    "claude": """### Claude Code 模型配置

- 具名子代理的 model 与 effort 由 agent 定义决定，派发时不要覆盖。
- 用内置 agent（`general-purpose` / `Explore` / `Plan`）时仍要显式传 `model`，但它们的 effort
  一定跟着主会话，所以别拿它们跑廉价的批量任务。
- 新增或修改 agent 定义时只写档位名
  （模型 `fable` / `opus` / `sonnet` / `haiku`，effort `low` / `medium` / `high` / `xhigh` / `max`），
  不要写具体模型版本号，避免模型换代后规则失效。
""",
    "codex": """### Codex 模型选择

- 具名子代理的 model 与 model_reasoning_effort 由 TOML agent 定义决定，派发时不要覆盖。
""",
}

PLACEHOLDER = "{{HOST_AGENT_CONFIGURATION}}"


def render_rules(source: Path, host: str, scope: str, no_header: bool = False) -> str:
    template = source.read_text(encoding="utf-8")
    if template.count(PLACEHOLDER) != 1:
        raise ValueError(f"{source}：须有且只有一个 {PLACEHOLDER} 占位符")
    if not template.startswith(USER_HEADER):
        raise ValueError(f"{source}：开头的用户级标题与首句和渲染脚本里的不一致")

    rendered = template.replace(PLACEHOLDER, HOST_AGENT_CONFIGURATION[host].rstrip())
    if scope == "project":
        rendered = shift_headings(source, rendered.removeprefix(USER_HEADER), -1)
    elif no_header:
        rendered = rendered.removeprefix(USER_HEADER)
    return rendered


def main() -> int:
    parser = argparse.ArgumentParser(description="把分派子代理的共享规则渲染成指定宿主与作用域要写入的内容，输出到 stdout。")
    parser.add_argument("source", type=Path, help="共享规则模板 rules.md 的路径")
    parser.add_argument("--host", choices=HOST_AGENT_CONFIGURATION, required=True, help="目标宿主")
    parser.add_argument("--scope", choices=("project", "user"), required=True, help="安装作用域")
    parser.add_argument("--no-header", action="store_true",
                        help="只用户级：去掉「# 全局规则」标题与首句、层级不动，挂到目标文件里已有的那个标题下")
    args = parser.parse_args()
    if args.no_header and args.scope == "project":
        parser.error("--no-header 只用于 --scope user：project 本来就不带「# 全局规则」标题")

    try:
        sys.stdout.write(render_rules(args.source, args.host, args.scope, args.no_header))
    except (ValueError, OSError) as error:
        print(f"{parser.prog}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
