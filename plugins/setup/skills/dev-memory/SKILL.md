---
name: dev-memory
description: 给当前项目装上（或更新）项目级 dev-memory skill，让开发记忆的读写规则随仓库提交。用于"给这个项目配开发记忆""初始化 dev-memory""更新项目里的记忆 skill"等场景。
disable-model-invocation: true
---

# 安装项目级 dev-memory skill

把「记忆放在哪、开工前怎么读、收尾时派谁写」写进当前项目的 `.claude/skills/dev-memory/`，
随仓库提交。另挂两个触发点：指令文件与提交前的收尾闸门。

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

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/dev-memory.md`。
3. **对齐路径**：记忆目录不是 `docs/dev-memory/` 时，把新文件里的路径全部改成实际目录。
4. **建索引**：记忆目录缺 `README.md` 就建一个只有标题和空索引的骨架，不要预填占位记忆。
5. **装收尾闸门**：调度器一份、本 skill 的检查片段一份，分开装。

   ```bash
   mkdir -p .claude/hooks/wrapup.d
   # 判据是「它认不认识 wrapup.d」，不是「文件在不在」：更早的单文件版本把检查逻辑写在
   # 自己体内，留着它片段就没人读，装了等于没装。
   grep -q 'wrapup\.d' .claude/hooks/wrapup-check.sh 2>/dev/null \
     || cp "$CLAUDE_PLUGIN_ROOT/scripts/wrapup-check.sh" .claude/hooks/wrapup-check.sh
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/dev-memory/template/wrapup.d/"*.sh .claude/hooks/wrapup.d/
   chmod +x .claude/hooks/wrapup-check.sh .claude/hooks/wrapup.d/*.sh
   ```

   换掉旧版调度器时，把它已经调好的 `SRC_PATTERN` 抄进新的；**旧版体内的检查逻辑不要往新调度器里搬**，
   那些现在由片段承担。新装的调度器把 `SRC_PATTERN` 改成项目实际的源码根目录。
   片段里的 `MEMORY_DIR` 对齐第 1 步定下的记忆目录。
   再把 `$CLAUDE_PLUGIN_ROOT/scripts/wrapup-hook-settings.json` 合并进随仓库提交的
   `.claude/settings.json`（不是 `settings.local.json`；已有 `hooks` 配置的并进去，不要整段覆盖）。
6. **装写记忆的子代理**（Claude Code 专属，其它工具跳过本步）：

   ```bash
   mkdir -p .claude/agents
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/dev-memory/template/agents/memory-writer.md" .claude/agents/
   ```

   **装进项目的 `.claude/agents/`，不是 `~/.claude/agents/`**；已有同名文件不要覆盖。
7. **挂触发点**：在项目的 `CLAUDE.md` / `AGENTS.md` 里写明开工前调用 `dev-memory` 读记忆、
   开发收尾时**派 `memory-writer` 子代理**沉淀。
   已有指向记忆目录的说法改成指向 skill，`@` 前缀一并去掉。
   只写触发时机——读法留在 skill 里，判断标准与写法留在 `memory-writer` 的定义里，
   不要复制成第二份。
8. **告知用户**：`.claude/skills/dev-memory/`、`.claude/agents/memory-writer.md`、
   `.claude/hooks/wrapup-check.sh` 与 `.claude/settings.json` 都要提交进版本库；
   hook 依赖 `jq`，缺了会静默放行；
   记忆目录是否提交、要不要进 `.gitignore` 由用户自己判断，不要替他决定，也不要主动改 `.gitignore`。
   装好后用 `/dev-memory` 调用，当前会话里没出现就重启一次 Claude Code。

## 已存在时

`.claude/skills/dev-memory/SKILL.md` 已存在时不要直接覆盖：与模板逐节比对，补齐模板有而它没有的规则，
保留项目自己加的内容和改过的路径。要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。
