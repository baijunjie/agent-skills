#!/usr/bin/env python3

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
        raise ValueError(f"{source}: expected exactly one {PLACEHOLDER} placeholder")
    if not template.startswith(USER_HEADER):
        raise ValueError(f"{source}: user-level header does not match the renderer")

    rendered = template.replace(PLACEHOLDER, HOST_AGENT_CONFIGURATION[host].rstrip())
    if scope == "project":
        rendered = rendered.removeprefix(USER_HEADER)
    return rendered


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render the shared workflow rules for one host and scope."
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("--host", choices=HOST_AGENT_CONFIGURATION, required=True)
    parser.add_argument("--scope", choices=("project", "user"), required=True)
    args = parser.parse_args()

    sys.stdout.write(render_rules(args.source, args.host, args.scope))


if __name__ == "__main__":
    main()
