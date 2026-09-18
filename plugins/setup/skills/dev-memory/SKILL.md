---
name: dev-memory
description: 给当前项目装上（或更新）项目级 dev-memory skill，让开发记忆的读写规则随仓库提交。用于"给这个项目配开发记忆""初始化 dev-memory""更新项目里的记忆 skill"等场景。
disable-model-invocation: true
---

# 安装项目级 dev-memory skill

把「记忆放在哪、开工前怎么读、收尾时派谁写」写进当前项目的 `.claude/skills/dev-memory/`，
随仓库提交。触发点挂在项目的指令文件里——每次会话必读。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 步骤

1. **定记忆目录**：项目已有的记忆目录（如 `docs/dev-memory/`）就沿用，没有则用 `docs/dev-memory/`。
2. **写入 skill**：**先看 `.claude/skills/dev-memory/SKILL.md` 在不在**，在就转「已存在时」，
   不要执行下面的 `cp`——它会直接覆盖项目自己改过的那份。

   ```bash
   mkdir -p .claude/skills/dev-memory
   cp "$CLAUDE_PLUGIN_ROOT/skills/dev-memory/template/dev-memory.md" .claude/skills/dev-memory/SKILL.md
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/dev-memory.md`。
3. **对齐项目**：记忆目录不是 `docs/dev-memory/` 时把新文件里的路径全部改成实际目录；
   项目另有与通用规则不同的约定，就地补写进去。
4. **建索引**：记忆目录缺 `README.md` 就建一个只有标题和空索引的骨架，不要预填占位记忆。
5. **装写记忆的子代理**：

   ```bash
   mkdir -p .claude/agents
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/dev-memory/template/agents/memory-writer.md" .claude/agents/
   ```

   **装进项目的 `.claude/agents/`，不是 `~/.claude/agents/`**；已有同名文件 `cp -n` 会静默跳过，
   跳过了就转「已存在时」，不要当成装好了。
6. **挂触发点**：在项目根目录的 `CLAUDE.md` 里写明开工前调用 `dev-memory` 读记忆、
   开发收尾时**派 `memory-writer` 子代理**沉淀。
   已有指向记忆目录的说法改成指向 skill，`@` 前缀一并去掉。
   只写触发时机——读法留在 skill 里，判断标准与写法留在 `memory-writer` 的定义里，
   不要复制成第二份。
7. **告知用户**：`.claude/skills/dev-memory/` 与 `.claude/agents/memory-writer.md`
   都要提交进版本库；
   记忆目录是否提交、要不要进 `.gitignore` 由用户自己判断，不要替他决定，也不要主动改 `.gitignore`。
   装好后用 `/dev-memory` 调用，当前会话里没出现就重启一次 Claude Code。

## 已存在时

`.claude/skills/dev-memory/SKILL.md` 已存在时不要直接覆盖：与模板逐节比对，补齐模板有而它没有的规则，
保留项目自己加的内容和改过的路径。要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
