---
name: docs
description: 给当前项目装上（或更新）项目级 docs skill 与提交前的文档同步检查，让项目地图、产品文档、开发文档的维护规则随仓库提交。用于"给这个项目配文档规范""初始化项目文档结构""让 agent 维护文档""更新项目里的 docs skill"等场景。
disable-model-invocation: true
---

# 安装项目级 docs skill

把三类项目文档（项目地图 / 产品文档 / 开发文档）的维护规则写进当前项目的 `.claude/skills/docs/`，
随仓库提交。另挂两个触发点：指令文件与提交前的收尾闸门。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 步骤

1. **定文档目录**：项目已有对应目录的沿用，没有则用默认的
   `docs/README.md`（索引）、`docs/project-map.md`、`docs/product/`、`docs/development/`。
2. **写入 skill**：

   ```bash
   mkdir -p .claude/skills/docs
   cp "$CLAUDE_PLUGIN_ROOT/skills/docs/template/docs.md" .claude/skills/docs/SKILL.md
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/docs.md`。
3. **对齐路径**：目录与默认不同时，把新文件里的路径全部改成实际目录。
4. **建骨架**：缺 `docs/README.md` 就建一个只有标题和空索引的骨架。项目地图、产品文档、开发文档等有内容再建，
   不要预建空目录或占位文档。项目已有散落的文档时，按三类归位是另一件事，先问用户要不要一起做。
5. **装收尾闸门**：调度器一份、本 skill 的检查片段一份，分开装。

   ```bash
   mkdir -p .claude/hooks/wrapup.d
   # 判据是「它认不认识 wrapup.d」，不是「文件在不在」：更早的单文件版本把检查逻辑写在
   # 自己体内，留着它片段就没人读，装了等于没装。
   grep -q 'wrapup\.d' .claude/hooks/wrapup-check.sh 2>/dev/null \
     || cp "$CLAUDE_PLUGIN_ROOT/scripts/wrapup-check.sh" .claude/hooks/wrapup-check.sh
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/docs/template/wrapup.d/"*.sh .claude/hooks/wrapup.d/
   chmod +x .claude/hooks/wrapup-check.sh .claude/hooks/wrapup.d/*.sh
   ```

   调度器开箱即用，`NON_SRC_PATTERN` 用排除法认源码（文档与配置之外都算），
   本项目还有别的非源码目录再补进去。片段里的 `DOC_PATTERN` 对齐第 1 步定下的文档目录：**同目录下若有别项收尾检查自己的子目录，要排除掉**，否则那一项的改动会被算成「文档已同步」。
   再把 `$CLAUDE_PLUGIN_ROOT/scripts/wrapup-hook-settings.json` 合并进随仓库提交的
   `.claude/settings.json`（不是 `settings.local.json`；已有 `hooks` 配置的并进去，不要整段覆盖）。
6. **装写文档的子代理**（Claude Code 专属，其它工具跳过本步）：

   ```bash
   mkdir -p .claude/agents
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/docs/template/agents/doc-writer.md" .claude/agents/
   ```

   **装进项目的 `.claude/agents/`，不是 `~/.claude/agents/`**；已有同名文件不要覆盖。
7. **挂触发点**：在项目的 `CLAUDE.md` / `AGENTS.md` 里写明三件事——开工前读产品文档建立上下文，
   要写或改文档时派 `doc-writer` 子代理，hook 不生效的场合（其它工具、手工提交）收尾时自己核对。
   三件都只写触发时机，规则与清单留在 skill 里，不要复制成第二份。
   已有指向文档目录的说法改成指向 skill，`@` 前缀一并去掉。
8. **告知用户**：`.claude/skills/docs/`、`.claude/agents/doc-writer.md`、
   `.claude/hooks/wrapup-check.sh`、`.claude/settings.json` 都要提交进版本库。
   hook 依赖 `jq`，缺了会静默放行。
   装好后用 `/docs` 调用，skill 或 hook 在当前会话里没生效就重启一次 Claude Code。

## 已存在时

`.claude/skills/docs/SKILL.md` 或收尾闸门脚本已存在时不要直接覆盖：与模板逐节比对，
补齐模板有而它没有的规则，保留项目自己加的内容和改过的路径、匹配模式。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。
