---
name: docs
description: 给当前项目装上（或更新）项目级 agent-docs skill 与 map-writer、product-writer、memory-writer 三个子代理，让总索引、项目地图、产品文档与开发记忆的读写规则随仓库提交。用于"给这个项目配文档规范""初始化项目文档结构""给这个项目配开发记忆""让 agent 维护文档""更新项目里的 agent-docs skill"等场景。
disable-model-invocation: true
---

# 安装项目级 agent-docs skill

把总索引、项目地图、产品文档与开发记忆的读写规则写进当前项目的宿主 skill 目录，随仓库提交。
触发点挂在项目的指令文件里——每次会话必读。

## 跨宿主约定

只执行当前宿主对应的 skill、子代理和指令文件分支。

模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；两者都为空时，先把 `SKILL_DIR`
设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），再按相对路径定位。
下面的变量定义要和后续命令放在同一次 shell 调用里，分开执行就每次重新定义：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  SETUP_ROOT="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/../.."
fi
TEMPLATE_DIR="$SETUP_ROOT/skills/docs/template"
RENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"
```

## 步骤

1. **定目录**：项目已有对应目录的沿用，没有则用默认的
   `docs/README.md`（总索引）、`docs/project-map.md`、`docs/product/`、`docs/memory/`。
2. **写入 skill**：Claude Code 先看 `.claude/skills/agent-docs/SKILL.md`，Codex 先看
   `.agents/skills/agent-docs/SKILL.md`；目标已在就转「已存在时」，不要执行下面的 `cp`——它会直接覆盖项目自己改过的那份。

   ```bash
   # Claude Code
   mkdir -p .claude/skills/agent-docs
   cp "$TEMPLATE_DIR/agent-docs.md" .claude/skills/agent-docs/SKILL.md

   # Codex
   mkdir -p .agents/skills/agent-docs
   cp "$TEMPLATE_DIR/agent-docs.md" .agents/skills/agent-docs/SKILL.md
   ```

3. **建骨架**：缺 `docs/README.md` 就建一个只有一行标题（如 `# 文档索引`）的骨架，条目写法按
   `agent-docs` 的「收尾：更新总索引」一节，以后由主 agent 维护。其它目录与文档有内容再建，
   不要预建空目录或占位文档。项目已有散落的文档时，按类归位是另一件事，先问用户要不要一起做。
4. **装子代理**：写入前逐个检查三个目标，**只安装缺的那几个**，已有的转「已存在时」。
   下面的命令按全部缺失写，只缺一部分时只保留缺的文件名——`cp -n` 遇到已有文件会静默跳过，
   渲染脚本遇到已有目标会整批拒绝、一个都不写。

   ```bash
   # Claude Code
   mkdir -p .claude/agents
   cp -n "$TEMPLATE_DIR/agents/map-writer.md" "$TEMPLATE_DIR/agents/product-writer.md" \
     "$TEMPLATE_DIR/agents/memory-writer.md" .claude/agents/

   # Codex
   mkdir -p .codex/agents
   python3 "$RENDER_AGENT" --output-dir .codex/agents "$TEMPLATE_DIR/agents/map-writer.md" \
     "$TEMPLATE_DIR/agents/product-writer.md" "$TEMPLATE_DIR/agents/memory-writer.md"
   ```

   Markdown 是唯一模板源。Codex 安装时由共享脚本机械提取 `name`、`description` 与完整正文，
   组装成 `.toml`，并按代理职责写入 Codex 的模型与 reasoning effort；不直接照搬 Claude Code
   的 `model`、`effort`，也不改写正文。
   两种宿主都装进项目目录，不是用户级配置目录。
5. **对齐项目**：目录与默认不同时，把 skill 与三个子代理定义里的路径全部改成实际目录，
   包括 frontmatter 的 `description`（Codex 改生成的 `.toml` 里的 `description` 与 `developer_instructions`）；
   项目另有与通用规则不同的约定，就地补写进 skill。
6. **挂触发点**：Claude Code 在项目根目录的 `CLAUDE.md`、Codex 在 `AGENTS.md` 里写明
   开工前调用 `agent-docs` 读总索引与相关文档、开发收尾时按 `agent-docs` 派子代理并更新总索引。
   指令文件不存在就新建；是软链就写到它指向的文件，并告知用户（这一步不受「现状与预期不符时」约束）。
   已有指向文档或记忆目录的说法改成指向 skill，`@` 前缀一并去掉。
   只写触发时机——读法、派谁与判断标准留在 skill 与子代理定义里，不要复制成第二份。
7. **告知用户**：项目中安装后的 `.claude/skills/agent-docs/` 与 `.claude/agents/` 下的三个子代理，
   或 `.agents/skills/agent-docs/` 与 `.codex/agents/` 下的三个 `.toml` 都要提交进版本库；
   `docs/memory/` 是否提交由用户自己判断，不要替用户决定，也不要主动改 `.gitignore`。
   Claude Code 装好后用 `/agent-docs` 调用，Codex 用 `$agent-docs`；新装的 skill 与子代理要重启对应宿主
   或开新会话才生效。

## 已存在时

宿主目标 skill 已存在时不要直接覆盖：与模板逐节比对，
补齐模板有而它没有的规则，保留项目自己加的内容和改过的路径、匹配模式。
子代理同理，逐个文件处理：Claude Code 的 `.md` 直接与模板比对；Codex 的 `.toml` 先把模板渲染到
临时目录（`python3 "$RENDER_AGENT" --output-dir "$(mktemp -d)" <模板>`），再与现有文件逐字段比对，
不要另找或创建一份 TOML 模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
