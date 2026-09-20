---
name: docs
description: 给当前项目装上（或更新）项目级 docs skill 与 doc-writer 子代理，让总索引、项目地图、产品文档的维护规则随仓库提交。用于"给这个项目配文档规范""初始化项目文档结构""让 agent 维护文档""更新项目里的 docs skill"等场景。
disable-model-invocation: true
---

# 安装项目级 docs skill

把项目正式文档（总索引 / 项目地图 / 产品文档）的维护规则写进当前项目的宿主 skill 目录，随仓库提交。
触发点挂在项目的指令文件里——每次会话必读。

`docs/` 下的其它东西（开发期的过程产物、各种辅助文档）不在管辖内，装的时候也不要把它们写进规则。

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
TEMPLATE_DIR="$SETUP_ROOT/skills/docs/template"
RENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"
```

## 步骤

1. **定文档目录**：项目已有对应目录的沿用，没有则用默认的
   `docs/README.md`（索引）、`docs/project-map.md`、`docs/product/`。
2. **写入 skill**：Claude Code 先看 `.claude/skills/docs/SKILL.md`，Codex 先看
   `.agents/skills/docs/SKILL.md`；目标已在就转「已存在时」，不要执行下面的 `cp`——它会直接覆盖项目自己改过的那份。

   ```bash
   # Claude Code
   mkdir -p .claude/skills/docs
   cp "$TEMPLATE_DIR/docs.md" .claude/skills/docs/SKILL.md

   # Codex
   mkdir -p .agents/skills/docs
   cp "$TEMPLATE_DIR/docs.md" .agents/skills/docs/SKILL.md
   ```

3. **对齐项目**：目录与默认不同时把新文件里的路径全部改成实际目录；项目另有与通用规则不同的
   约定，就地补写进去。
4. **建骨架**：缺 `docs/README.md` 就建一个只有标题和空索引的骨架。项目地图与产品文档等有内容再建，
   不要预建空目录或占位文档。项目已有散落的文档时，按类归位是另一件事，先问用户要不要一起做。
5. **装写文档的子代理**：

   ```bash
   # Claude Code
   mkdir -p .claude/agents
   cp -n "$TEMPLATE_DIR/agents/doc-writer.md" .claude/agents/

   # Codex
   mkdir -p .codex/agents
   "$RENDER_AGENT" --output-dir .codex/agents "$TEMPLATE_DIR/agents/doc-writer.md"
   ```

   Markdown 是唯一模板源。Codex 安装时由共享脚本机械提取 `name`、`description` 与完整正文，
   组装成 `.toml`；不映射 Claude Code 的 `model`、`effort`，也不改写正文。
   两种宿主都装进项目目录，不是用户级配置目录。写入前发现同名文件就转「已存在时」，不要覆盖。
6. **挂触发点**：Claude Code 在项目根目录的 `CLAUDE.md`、Codex 在 `AGENTS.md` 里写明开工前调用 `docs` skill 建立上下文、
   一个阶段的开发收尾要写或改产品文档与项目地图时**派 `doc-writer` 子代理**。
   已有指向文档目录的说法改成指向 skill，`@` 前缀一并去掉。
   只写触发时机——写法与判断标准留在 skill 与 `doc-writer` 的定义里，不要复制成第二份。
7. **告知用户**：项目中安装后的 `.claude/skills/docs/` 与 `.claude/agents/doc-writer.md`，
   或 `.agents/skills/docs/` 与 `.codex/agents/doc-writer.toml` 都要提交进版本库。
   Claude Code 装好后用 `/docs` 调用；Codex 由当前环境按已安装 skill 发现机制加载。当前会话没生效时重启对应宿主。

## 已存在时

宿主目标 skill 已存在时不要直接覆盖：与模板逐节比对，
补齐模板有而它没有的规则，保留项目自己加的内容和改过的路径、匹配模式。
Codex 子代理与 Markdown 模板转换后的字段逐项比对，不要另找或创建一份 TOML 模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
