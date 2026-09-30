---
name: unit-test
description: 给当前项目装上（或更新）项目级 agent-unit-test skill 与 test-writer 子代理：基于项目已有的单元测试框架（没有就问用户并协助安装），测试放独立目录并镜像源码结构，收尾时为改动文件补测试、只跑受影响的测试。用于"给这个项目配单元测试""装 test-writer""让 agent 收尾时补测试""更新项目里的单元测试 skill"等场景。
disable-model-invocation: true
---

# 安装项目级 agent-unit-test skill

把「测试写在哪、收尾时派谁补、跑哪些」写进当前项目的宿主 skill 目录，随仓库提交。
触发点挂在项目的指令文件里——每次会话必读。

## 跨宿主约定

只执行当前宿主对应的 skill、子代理和指令文件分支。

模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；两者都为空时，先把 `SKILL_DIR`
设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），再按相对路径定位。执行写入前先确定：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  SETUP_ROOT="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/../.."
fi
TEMPLATE_DIR="$SETUP_ROOT/skills/unit-test/template"
RENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"
```

## 步骤

1. **写入 skill**：Claude Code 先看 `.claude/skills/agent-unit-test/SKILL.md`，Codex 先看
   `.agents/skills/agent-unit-test/SKILL.md`；目标已在就转「已存在时」，不要执行下面的 `cp`——它会直接覆盖项目自己改过的那份，
   也不要重做第 2–4 步。

   ```bash
   # Claude Code
   mkdir -p .claude/skills/agent-unit-test
   cp "$TEMPLATE_DIR/agent-unit-test.md" .claude/skills/agent-unit-test/SKILL.md

   # Codex
   mkdir -p .agents/skills/agent-unit-test
   cp "$TEMPLATE_DIR/agent-unit-test.md" .agents/skills/agent-unit-test/SKILL.md
   ```

2. **确认框架**：从依赖清单、测试配置、已有测试判断项目用的单元测试框架，有就沿用；
   多个并存时以已有测试最多的为准，拿不准就问用户。monorepo 按包逐个确认。
   没有框架时按装好的 skill「找不到框架时」一节处理。
3. **定测试目录与映射**：
   - 项目已有独立测试目录的沿用；语言或构建工具有约定测试目录的（如 Maven / Gradle 的 `src/test/java`）用约定；
     都没有才用 `tests/unit/`。monorepo 每个包各自一个。
   - 映射默认按源文件相对项目（包）根的完整路径镜像；只有单一源码根（如 `src/`）时可省掉这一级目录。
   - 文件名标记沿用项目已有测试的；没有才取框架默认。
   - 已有测试与源码同目录时不要搬，先问用户选哪种：旧测试留在原处、新测试进测试根目录（默认）；
     全部迁移到测试根目录；全部沿用同目录。
   - 语言本身已规定单元测试放法的（Go 的同目录 `_test.go`、Rust 的 `#[cfg(test)]` 模块），照语言惯例，
     不套独立目录与镜像规则。
4. **配置框架**：按装好的 skill「找不到框架时」一节的配置要求检查并补齐；项目有脚本约定
   （`package.json` scripts、Makefile 等）就补上运行测试的入口。框架是新装的、或测试目录是新定的，
   要用一份真实测试确认能被发现并跑通——为项目里一个可测文件写，不要留占位测试。
5. **填本项目约定**：把「本项目约定」表的每个占位换成实际值，monorepo 每个包一行。
   表里的每条命令都要实际跑过；框架没有按改动选测试的能力就如实写「无」。
   用户选的旧测试放法与按语言惯例放测试的语言，都写进「放在哪」一节。
6. **装写测试的子代理**：

   ```bash
   # Claude Code
   mkdir -p .claude/agents
   cp -n "$TEMPLATE_DIR/agents/test-writer.md" .claude/agents/

   # Codex
   mkdir -p .codex/agents
   "$RENDER_AGENT" --output-dir .codex/agents "$TEMPLATE_DIR/agents/test-writer.md"
   ```

   Markdown 是唯一模板源。Codex 安装时由共享脚本机械提取 `name`、`description` 与完整正文，
   组装成 `.toml`，并按代理职责写入 Codex 的模型与 reasoning effort；不直接照搬 Claude Code
   的 `model`、`effort`，也不改写正文。
   两种宿主都装进项目目录，不是用户级配置目录。写入前发现同名文件就转「已存在时」，不要覆盖。
7. **挂触发点**：Claude Code 在项目根目录的 `CLAUDE.md`、Codex 在 `AGENTS.md` 里写明开发收尾、代码审查之前调用 `agent-unit-test` skill、
   **派 `test-writer` 子代理**补测试并运行受影响的测试。它是符号链接时写它指向的实际文件。
   只写触发时机——放法与运行范围留在 skill 里，可测判据与写法留在 `test-writer` 的定义里，
   不要复制成第二份；什么算收尾由指令文件已有的规则决定，不要另写一套。已有意思相同的说法就不再追加。
8. **告知用户**：项目中安装后的 `.claude/skills/agent-unit-test/` 与 `.claude/agents/test-writer.md`，
   或 `.agents/skills/agent-unit-test/` 与 `.codex/agents/test-writer.toml`，连同框架配置与依赖清单的改动都要提交进版本库；
   `.gitignore` 整体忽略了 `.claude/` 或 `.codex/` 的项目要为这几处加例外。
   Claude Code 装好后用 `/agent-unit-test` 调用；Codex 由当前环境按已安装 skill 发现机制加载。当前会话没生效时重启对应宿主。

## 已存在时

宿主目标 skill 已存在时不要直接覆盖：与模板逐节比对，补齐模板有而它没有的规则，
保留项目自己加的内容；约定表以已填好的为准，只核对命令还能跑、框架还在依赖里。Codex 子代理与 Markdown 模板转换后的字段逐项比对，
不要另找或创建一份 TOML 模板。要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
