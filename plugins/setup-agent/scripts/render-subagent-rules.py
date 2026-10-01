#!/usr/bin/env python3
"""把分派子代理的共享规则模板按宿主与作用域渲染，输出到 stdout。

模板里唯一的 {{HOST_AGENT_CONFIGURATION}} 占位符换成该宿主的模型配置小节。模板以用户级的
「# 全局规则」标题与首句开头：user 作用域原样保留，project 作用域去掉它们，因为项目指令文件
本身就是项目的规则。指令文件的标记由安装器在外面包上，这里不输出。
"""

import argparse
import sys
from pathlib import Path


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


def render_rules(source: Path, host: str, scope: str) -> str:
    template = source.read_text(encoding="utf-8")
    if template.count(PLACEHOLDER) != 1:
        raise ValueError(f"{source}：须有且只有一个 {PLACEHOLDER} 占位符")
    if not template.startswith(USER_HEADER):
        raise ValueError(f"{source}：开头的用户级标题与首句和渲染脚本里的不一致")

    rendered = template.replace(PLACEHOLDER, HOST_AGENT_CONFIGURATION[host].rstrip())
    if scope == "project":
        rendered = rendered.removeprefix(USER_HEADER)
    return rendered


def main() -> int:
    parser = argparse.ArgumentParser(description="把分派子代理的共享规则渲染成指定宿主与作用域要写入的内容，输出到 stdout。")
    parser.add_argument("source", type=Path, help="共享规则模板 rules.md 的路径")
    parser.add_argument("--host", choices=HOST_AGENT_CONFIGURATION, required=True, help="目标宿主")
    parser.add_argument("--scope", choices=("project", "user"), required=True, help="安装作用域")
    args = parser.parse_args()

    try:
        sys.stdout.write(render_rules(args.source, args.host, args.scope))
    except (ValueError, OSError) as error:
        print(f"{parser.prog}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
