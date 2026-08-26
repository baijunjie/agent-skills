---
name: dev-memory
description: 给当前项目装上（或更新）项目级 dev-memory skill，让开发记忆的读写规则随仓库提交。用于"给这个项目配开发记忆""初始化 dev-memory""更新项目里的记忆 skill"等场景。
disable-model-invocation: true
---

# 安装项目级 dev-memory skill

把开发记忆的读写规则写进当前项目的 `.claude/skills/dev-memory/`，随仓库提交，
让没装本 plugin 的人和其它 agent 也能用同一套规则，并允许各项目按自己的情况改。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 步骤

1. **定记忆目录**：项目已有的记忆目录（如 `docs/dev-memory/`）就沿用，没有则用 `docs/dev-memory/`。
2. **写入 skill**：

   ```bash
   mkdir -p .claude/skills/dev-memory
   cp "$CLAUDE_PLUGIN_ROOT/skills/dev-memory/template/dev-memory.md" .claude/skills/dev-memory/SKILL.md
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时（不在 plugin 环境里运行），用本 skill 目录下的 `template/dev-memory.md`。
3. **对齐路径**：记忆目录不是 `docs/dev-memory/` 时，把新文件里的路径全部改成实际目录。
4. **建索引**：记忆目录缺 `README.md` 就建一个只有标题和空索引的骨架，不要预填占位记忆。
5. **挂触发点**：skill 的 description 只进候选清单，模型未必想起来调用，而 `CLAUDE.md` 每次会话必读——
   在项目的 `CLAUDE.md` / `AGENTS.md` 里写明开工前调用 `dev-memory` 读记忆、被指正或开发收尾时调用它沉淀。
   已有指向记忆目录的说法改成指向 skill，`@` 前缀一并去掉。
   只写触发时机——步骤、判断标准、记忆格式留在 skill 里，不要复制成第二份。
6. **告知用户**：`.claude/skills/dev-memory/` 要提交进版本库，团队和其它 agent 才共用同一套规则；
   记忆目录是否提交、要不要进 `.gitignore` 由用户自己判断，不要替他决定，也不要主动改 `.gitignore`。
   装好后用 `/dev-memory` 调用，当前会话里没出现就重启一次 Claude Code。

## 已存在时

`.claude/skills/dev-memory/SKILL.md` 已存在时不要直接覆盖：与模板逐节比对，补齐模板有而它没有的规则，
保留项目自己加的内容和改过的路径。要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。
