---
name: docs
description: {{scope_lead}}agent-docs skill 与 map-writer、product-writer、memory-writer 三个子代理：总索引、项目地图、产品文档与开发记忆的读写规则，以及代码注释规范。{{scope_tail}}用于"给这个项目配文档规范""初始化项目文档结构""给这个项目配开发记忆""让 agent 维护文档""更新项目里的 agent-docs skill""全局装文档规范"等场景。
disable-model-invocation: true
---

# 安装项目文档规范

装两样东西：`agent-docs` skill（读写规则与注释规范）与 `map-writer`、`product-writer`、`memory-writer`
三个子代理。装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: scope-select}}

{{include: skill-priority}}

{{include: pre-write}}

本安装器另外要查的冲突：

- **这一项不按冲突问**：当前宿主用户级指令文件（项目级安装时），或这次作用域的指令文件（项目级是项目根目录的 `CLAUDE.md` / `AGENTS.md`，用户级是用户级配置目录下的）里已有同类规则（注释规范或文档读写规则）的，不改它，告知用户两份都会生效、内容差在哪。

## 通用步骤

1. **定文档位置**：只在项目级安装时做。总索引、项目地图、产品文档、开发记忆四处，项目已有约定（已有对应的文件或目录）的沿用；
   项目里查不到、而已装的旧 skill 与子代理里写着位置的，那就是上次定下的，沿用它（见「重装」）；都没有则用默认的
   `docs/README.md`（总索引）、`docs/project-map.md`、`docs/product/`、`docs/memory/`。
2. **写入 skill**：执行所在宿主安装节里的 `cp`，已有的整份覆盖。项目级安装时，旧 skill 末尾有「本项目」一节的，
   先把它读出来再覆盖（见「重装」）。
3. **装子代理**：三个都装，已有的整份覆盖；Codex 用渲染脚本的 `--replace` 替换同名旧 `.toml`，
   目标是软链时它会整批拒绝写入。
4. **建骨架**：只在项目级安装时做。缺总索引就建一个只有一行标题（如 `# 总索引`）的骨架。其它目录与文档有内容再建，
   不要预建空目录或占位文档。项目已有散落的文档时，按类归位是另一件事，要不要一起做交给用户定。
5. **对齐项目**：只在项目级安装时做。
   - 四处文档位置（`docs/README.md`、`docs/project-map.md`、`docs/product/`、`docs/memory/`）里与默认不同的那几处，
     把 skill 与三个子代理定义里它们的默认位置出现的地方改成第 1 步定下的位置，与默认相同的不动；包括 frontmatter 的 `description`（Codex 改生成的 `.toml` 里的 `description` 与 `developer_instructions`）。
     `docs/` 作为文档目录根出现时（如「`docs/` 下的其它文档」），改成总索引所在的目录。
     skill 里「表中位置是默认值，项目对文档目录已有自己的约定时按项目的。」这一句随之改成
     「表中位置是本项目的文档位置。」。
   - 项目另有与通用规则不同的约定（来自项目里的规范文档，或用户交代），在 skill 末尾加一节 `## 本项目` 写进去，
     一条一行，写清它取代或补充的是哪条通用规则，行末注明出处：规范文档的路径 + 章节标题原文；用户口头交代的写「用户交代」。
     不改通用正文，一条都没有就不加这一节。已写在项目指令文件里的约定不要再抄一遍。
6. **告知用户**：除各安装节列的外，说明重装时保留的只有项目级安装时填写的文档位置与 skill 末尾的「本项目」一节，
   项目特有的约定请写进「本项目」一节。

用户级安装不定文档位置、不建骨架、不对齐项目：装出的 skill 不属于某个项目，文档位置在运行时按所在项目的约定判断，
没有约定用默认的。

## Claude Code 项目级安装（默认）

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/skills/agent-docs .claude/agents
cp "$TEMPLATE_DIR/agent-docs.md" .claude/skills/agent-docs/SKILL.md
cp "$TEMPLATE_DIR/agents/map-writer.md" "$TEMPLATE_DIR/agents/product-writer.md" \
  "$TEMPLATE_DIR/agents/memory-writer.md" .claude/agents/
```

**告知用户**：`.claude/skills/agent-docs/` 与 `.claude/agents/` 下的三个子代理要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。
开发记忆（第 1 步定下的目录）按随仓库提交设计；用户不打算提交的，告知用户这样队友读不到，不主动改 `.gitignore`。
装好后可用 `/agent-docs` 调用，也会按描述自动触发；重启 Claude Code 后生效。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
: "${TEMPLATE_DIR:?}"
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/agent-docs" "$C/agents"
cp "$TEMPLATE_DIR/agent-docs.md" "$C/skills/agent-docs/SKILL.md"
cp "$TEMPLATE_DIR/agents/map-writer.md" "$TEMPLATE_DIR/agents/product-writer.md" \
  "$TEMPLATE_DIR/agents/memory-writer.md" "$C/agents/"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；没有建任何项目文档，
文档位置由 skill 在各项目里按项目约定判断。重启 Claude Code 后生效。

## Codex 项目级安装（默认）

```bash
{{include: project-root}}
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/agent-docs .codex/agents
cp "$TEMPLATE_DIR/agent-docs.md" .agents/skills/agent-docs/SKILL.md
python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/map-writer.md" \
  "$TEMPLATE_DIR/agents/product-writer.md" "$TEMPLATE_DIR/agents/memory-writer.md"
```

**告知用户**：`.agents/skills/agent-docs/` 与 `.codex/agents/` 下的三个 `.toml` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 或 `.codex/` 的项目要为这两处加例外。
开发记忆（第 1 步定下的目录）按随仓库提交设计；用户不打算提交的，告知用户这样队友读不到，不主动改 `.gitignore`。
装好后可用 `$agent-docs` 调用，也会按描述自动触发；开启新会话后生效。

## Codex 用户级安装

```bash
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
D="$HOME/.agents/skills/agent-docs"
X=${CODEX_HOME:-$HOME/.codex}
mkdir -p "$D" "$X/agents"
cp "$TEMPLATE_DIR/agent-docs.md" "$D/SKILL.md"
python3 "$RENDER_AGENT" --replace --output-dir "$X/agents" "$TEMPLATE_DIR/agents/map-writer.md" \
  "$TEMPLATE_DIR/agents/product-writer.md" "$TEMPLATE_DIR/agents/memory-writer.md"
```

**告知用户**：说明实际写入的用户级配置目录；没有建任何项目文档，文档位置由 skill 在各项目里按项目约定判断。
开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：

- 文档位置（项目级安装）：总索引、项目地图、产品文档、开发记忆四处的路径，旧 skill 与子代理里写的就是上次定下的
  （旧 skill 里写着「表中位置是本项目的文档位置。」时，表中位置就是旧值）。
  第 1 步按「项目约定 → 旧值 → 默认」重新确定，第 5 步填回 skill 与三个子代理；作为目录根出现的位置随总索引所在的目录而定，不单独读。
- skill 末尾的「本项目」一节（项目级安装）：第 2 步覆盖前读出，第 5 步按每条的出处判断——有文档出处的按现状重查，
  文档还在、约定还成立的沿用，已不存在的去掉；出处为「用户交代」的原样沿用。
- 用户级安装：无。

{{include: state-mismatch}}
