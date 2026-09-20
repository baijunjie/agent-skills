---
name: dev-memory
description: 给当前项目装上（或更新）项目级 dev-memory skill，让开发记忆的读写规则随仓库提交。用于"给这个项目配开发记忆""初始化 dev-memory""更新项目里的记忆 skill"等场景。
disable-model-invocation: true
---

# 安装项目级 dev-memory skill

把「记忆放在哪、开工前怎么读、收尾时派谁写」写进当前项目的宿主 skill 目录，随仓库提交。
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
TEMPLATE_DIR="$SETUP_ROOT/skills/dev-memory/template"
RENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"
```

## 步骤

1. **定记忆目录**：项目已有的记忆目录（如 `docs/dev-memory/`）就沿用，没有则用 `docs/dev-memory/`。
2. **写入 skill**：Claude Code 先看 `.claude/skills/dev-memory/SKILL.md`，Codex 先看
   `.agents/skills/dev-memory/SKILL.md`；目标已在就转「已存在时」，不要执行下面的 `cp`——它会直接覆盖项目自己改过的那份。

   ```bash
   # Claude Code
   mkdir -p .claude/skills/dev-memory
   cp "$TEMPLATE_DIR/dev-memory.md" .claude/skills/dev-memory/SKILL.md

   # Codex
   mkdir -p .agents/skills/dev-memory
   cp "$TEMPLATE_DIR/dev-memory.md" .agents/skills/dev-memory/SKILL.md
   ```

3. **对齐项目**：记忆目录不是 `docs/dev-memory/` 时把新文件里的路径全部改成实际目录；
   项目另有与通用规则不同的约定，就地补写进去。
4. **建索引**：记忆目录缺 `README.md` 就建一个只有标题和空索引的骨架，不要预填占位记忆。
5. **装写记忆的子代理**：

   ```bash
   # Claude Code
   mkdir -p .claude/agents
   cp -n "$TEMPLATE_DIR/agents/memory-writer.md" .claude/agents/

   # Codex
   mkdir -p .codex/agents
   "$RENDER_AGENT" --output-dir .codex/agents "$TEMPLATE_DIR/agents/memory-writer.md"
   ```

   Markdown 是唯一模板源。Codex 安装时由共享脚本机械提取 `name`、`description` 与完整正文，
   组装成 `.toml`；不映射 Claude Code 的 `model`、`effort`，也不改写正文。
   两种宿主都装进项目目录，不是用户级配置目录。写入前发现同名文件就转「已存在时」，不要覆盖。
6. **挂触发点**：Claude Code 在项目根目录的 `CLAUDE.md`、Codex 在 `AGENTS.md` 里写明开工前调用 `dev-memory` 读记忆、
   开发收尾时**派 `memory-writer` 子代理**沉淀。
   已有指向记忆目录的说法改成指向 skill，`@` 前缀一并去掉。
   只写触发时机——读法留在 skill 里，判断标准与写法留在 `memory-writer` 的定义里，
   不要复制成第二份。
7. **告知用户**：项目中安装后的 `.claude/skills/dev-memory/` 与 `.claude/agents/memory-writer.md`，
   或 `.agents/skills/dev-memory/` 与 `.codex/agents/memory-writer.toml` 都要提交进版本库；
   记忆目录是否提交、要不要进 `.gitignore` 由用户自己判断，不要替他决定，也不要主动改 `.gitignore`。
   Claude Code 装好后用 `/dev-memory` 调用；Codex 由当前环境按已安装 skill 发现机制加载。当前会话没生效时重启对应宿主。

## 已存在时

宿主目标 skill 已存在时不要直接覆盖：与模板逐节比对，补齐模板有而它没有的规则，
保留项目自己加的内容和改过的路径。Codex 子代理与 Markdown 模板转换后的字段逐项比对，
不要另找或创建一份 TOML 模板。要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
