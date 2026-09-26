#!/usr/bin/env python3

import argparse
import json
import os
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
    "doc-writer": {
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
    },
    "memory-writer": {
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
    },
}


def read_agent(source: Path) -> tuple[dict[str, str], str]:
    lines = source.read_text(encoding="utf-8").splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        raise ValueError(f"{source}: frontmatter must start on the first line")

    try:
        closing = next(
            index
            for index, line in enumerate(lines[1:], start=1)
            if line.rstrip("\r\n") == "---"
        )
    except StopIteration as error:
        raise ValueError(f"{source}: frontmatter is not closed") from error

    metadata: dict[str, str] = {}
    for line in lines[1:closing]:
        text = line.rstrip("\r\n")
        if not text or text.lstrip().startswith("#"):
            continue
        key, separator, value = text.partition(":")
        if not separator:
            raise ValueError(f"{source}: unsupported frontmatter line: {text}")
        metadata[key.strip()] = value.strip()

    for key in ("name", "description"):
        if not metadata.get(key):
            raise ValueError(f"{source}: missing {key} in frontmatter")

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
        raise ValueError(
            f"{source}: agent name {name!r} must match filename {source.stem!r}"
        )
    try:
        configuration = CODEX_AGENT_CONFIGURATION[name]
    except KeyError as error:
        raise ValueError(f"{source}: missing Codex agent configuration") from error

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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render Claude Markdown agent templates as Codex TOML agents."
    )
    parser.add_argument("sources", nargs="+", type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    if args.output_dir.is_symlink() or not args.output_dir.is_dir():
        parser.error(
            f"output directory must be an existing real directory: {args.output_dir}"
        )

    targets = [args.output_dir / f"{source.stem}.toml" for source in args.sources]
    if len(targets) != len(set(targets)):
        parser.error("multiple sources resolve to the same output filename")

    existing = [target for target in targets if target.exists() or target.is_symlink()]
    if existing:
        parser.error("refusing to overwrite: " + ", ".join(map(str, existing)))

    rendered = [render_agent(source) for source in args.sources]
    write_agents(list(zip(targets, rendered)))


if __name__ == "__main__":
    main()
