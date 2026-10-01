#!/usr/bin/env python3
"""把 Claude Code 的 Markdown 子代理模板渲染成 Codex 的 TOML 子代理，写进 --output-dir。

name、description 取自模板的 frontmatter，frontmatter 之后的正文原样成为 developer_instructions；
Codex 的 model、model_reasoning_effort 等配置只在本脚本的 CODEX_AGENT_CONFIGURATION 里维护。
输出目录须已存在，可以是指向目录的软链（配置目录链到 dotfiles 很常见）。全部渲染成功后才写，
不留下半批：
  默认         任一目标已存在（包括目标本身是软链）就整批拒绝，不覆盖；写到一半失败时删掉本次已建的文件。
  --replace    已存在的普通文件整份替换，不存在的新建；任一目标是软链（含悬空软链）或其它非普通文件就整批拒绝，
               免得写穿到链接指向的文件，或把链接换成普通文件、与原来链向的那份脱钩。先把全部内容写进同目录的
               临时文件，都写成功后再逐个原子改名到目标；写临时文件时失败就删掉临时文件，目标一个都不动。
"""

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path


CODEX_AGENT_CONFIGURATION = {
    "mechanical": {
        "model": "gpt-5.6-luna",
        "model_reasoning_effort": "low",
    },
    "implement": {
        "model": "gpt-5.6-terra",
        "model_reasoning_effort": "medium",
    },
    "change-checker": {
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
        "sandbox_mode": "read-only",
    },
    "investigate": {
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
    },
    "architect": {
        "model": "gpt-6-astra",
        "model_reasoning_effort": "xhigh",
    },
    "product-writer": {
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
    },
    "map-writer": {
        "model": "gpt-5.6-terra",
        "model_reasoning_effort": "high",
    },
    "memory-writer": {
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
    },
    "test-writer": {
        "model": "gpt-5.6-terra",
        "model_reasoning_effort": "high",
    },
}


def read_agent(source: Path) -> tuple[dict[str, str], str]:
    lines = source.read_text(encoding="utf-8").splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        raise ValueError(f"{source}：第一行必须是 frontmatter 的 ---")

    try:
        closing = next(
            index
            for index, line in enumerate(lines[1:], start=1)
            if line.rstrip("\r\n") == "---"
        )
    except StopIteration as error:
        raise ValueError(f"{source}：frontmatter 没有闭合的 ---") from error

    metadata: dict[str, str] = {}
    for line in lines[1:closing]:
        text = line.rstrip("\r\n")
        if not text or text.lstrip().startswith("#"):
            continue
        key, separator, value = text.partition(":")
        if not separator:
            raise ValueError(f"{source}：frontmatter 里有无法解析的行：{text}")
        metadata[key.strip()] = value.strip()

    for key in ("name", "description"):
        if not metadata.get(key):
            raise ValueError(f"{source}：frontmatter 缺少 {key}")

    instructions = "".join(lines[closing + 1 :])
    return metadata, instructions.removeprefix("\n")


def toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def toml_instructions(value: str) -> str:
    if "'''" not in value:
        return "'''\n" + value + "'''"
    return toml_string(value)


def render_agent(source: Path) -> str:
    metadata, instructions = read_agent(source)
    name = metadata["name"]
    if name != source.stem:
        raise ValueError(f"{source}：name {name!r} 须与文件名 {source.stem!r} 一致")
    try:
        configuration = CODEX_AGENT_CONFIGURATION[name]
    except KeyError as error:
        raise ValueError(f"{source}：CODEX_AGENT_CONFIGURATION 里没有 {name} 的 Codex 配置") from error

    fields = [
        f"name = {toml_string(name)}",
        f"description = {toml_string(metadata['description'])}",
    ]
    fields.extend(
        f"{key} = {toml_string(value)}"
        for key, value in configuration.items()
    )
    fields.append(f"developer_instructions = {toml_instructions(instructions)}")
    return "\n".join(fields) + "\n"


def write_agents(outputs: list[tuple[Path, str]]) -> None:
    created: list[tuple[Path, int, int]] = []
    try:
        for target, content in outputs:
            with target.open("x", encoding="utf-8") as output:
                identity = os.fstat(output.fileno())
                created.append((target, identity.st_dev, identity.st_ino))
                output.write(content)
    except BaseException:
        for target, device, inode in reversed(created):
            try:
                identity = target.lstat()
                if (identity.st_dev, identity.st_ino) == (device, inode):
                    target.unlink()
            except FileNotFoundError:
                pass
        raise


def new_file_mode() -> int:
    # mkstemp 建的文件权限是 0600；改成与普通新建文件一致的 0666 去掉 umask
    umask = os.umask(0)
    os.umask(umask)
    return 0o666 & ~umask


def replace_agents(outputs: list[tuple[Path, str]]) -> None:
    staged: list[tuple[Path, Path]] = []
    try:
        for target, content in outputs:
            mode = target.stat().st_mode & 0o7777 if target.exists() else new_file_mode()
            descriptor, temporary = tempfile.mkstemp(dir=target.parent, prefix=f".{target.name}.", suffix=".tmp")
            staged.append((Path(temporary), target))
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                output.write(content)
            os.chmod(temporary, mode)
    except BaseException:
        for temporary, _ in staged:
            temporary.unlink(missing_ok=True)
        raise
    # os.replace 作用于路径本身：即使改名前目标被换成了软链，被替换的也只是链接，不会写穿到它指向的文件
    for temporary, target in staged:
        os.replace(temporary, target)


def render_all(sources: list[Path], output_dir: Path, replace: bool) -> None:
    if not output_dir.is_dir():
        raise ValueError(f"输出目录须是已存在的目录：{output_dir}")

    targets = [output_dir / f"{source.stem}.toml" for source in sources]
    if len(targets) != len(set(targets)):
        raise ValueError("多个模板对应同一个输出文件名")

    if replace:
        # is_symlink 在 is_file 之前判断：指向普通文件的软链 is_file 也为真
        unsafe = [t for t in targets if t.is_symlink() or (t.exists() and not t.is_file())]
        if unsafe:
            raise ValueError("目标是软链或不是普通文件，拒绝替换：" + "、".join(map(str, unsafe)))
    else:
        existing = [target for target in targets if target.exists() or target.is_symlink()]
        if existing:
            raise ValueError("目标已存在，拒绝覆盖：" + "、".join(map(str, existing)))

    rendered = list(zip(targets, (render_agent(source) for source in sources)))
    (replace_agents if replace else write_agents)(rendered)


def main() -> int:
    parser = argparse.ArgumentParser(description="把 Claude Code 的 Markdown 子代理模板渲染成 Codex 的 TOML 子代理。")
    parser.add_argument("sources", nargs="+", type=Path, help="子代理模板路径，文件名即子代理名")
    parser.add_argument("--output-dir", required=True, type=Path, help="写入 .toml 的目录")
    parser.add_argument("--replace", action="store_true", help="整份替换已存在的普通文件；目标是软链时仍整批拒绝")
    args = parser.parse_args()

    try:
        render_all(args.sources, args.output_dir, args.replace)
    except (ValueError, OSError) as error:
        print(f"{parser.prog}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
