---
name: docs
description: 给当前项目装上（或更新）项目级 docs skill 与提交前的文档同步检查，让项目地图、产品文档、开发文档的维护规则随仓库提交。用于"给这个项目配文档规范""初始化项目文档结构""让 agent 维护文档""更新项目里的 docs skill"等场景。
disable-model-invocation: true
---

# 安装项目级 docs skill

把三类项目文档（项目地图 / 产品文档 / 开发文档）的维护规则写进当前项目的 `.claude/skills/docs/`，
随仓库提交，让没装本 plugin 的人和其它 agent 也能用同一套规则，并允许各项目按自己的情况改。

规则本身放 skill——它只在写文档时才需要，篇幅也不适合每次会话都读；
但「该读文档 / 该写文档了」这个时机模型未必想得起来，所以另外挂两个触发点：
指令文件（每次会话必读，其它工具也认）和提交前的检查 hook（只在 Claude Code 里跑 git commit 时兜底）。

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

   `$CLAUDE_PLUGIN_ROOT` 为空时（不在 plugin 环境里运行），用本 skill 目录下的 `template/docs.md`。
3. **对齐路径**：目录与默认不同时，把新文件里的路径全部改成实际目录。
4. **建骨架**：缺 `docs/README.md` 就建一个只有标题和空索引的骨架。项目地图、产品文档、开发文档等有内容再建，
   不要预建空目录或占位文档。项目已有散落的文档时，按三类归位是另一件事，先问用户要不要一起做。
5. **装提交前检查**：

   ```bash
   mkdir -p .claude/hooks
   cp "$CLAUDE_PLUGIN_ROOT/skills/docs/template/doc-sync-check.sh" .claude/hooks/doc-sync-check.sh
   chmod +x .claude/hooks/doc-sync-check.sh
   ```

   把脚本顶部的 `SRC_PATTERN` 改成项目实际的源码根目录，`DOC_PATTERN` 与提示文案里的路径对齐第 1 步。
   再注册进随仓库提交的 `.claude/settings.json`（不是 `settings.local.json`）：

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             {
               "type": "command",
               "if": "Bash(git commit *)",
               "command": "\"$CLAUDE_PROJECT_DIR/.claude/hooks/doc-sync-check.sh\"",
               "timeout": 10,
               "statusMessage": "核对文档同步"
             }
           ]
         }
       ]
     }
   }
   ```

   已有 `hooks` 配置的合并进去，不要整段覆盖。
6. **挂触发点**：在项目的 `CLAUDE.md` / `AGENTS.md` 里写明三件事——开工前读产品文档建立上下文，
   写或改文档时调用 `docs` skill，hook 不生效的场合（其它工具、手工提交）收尾时自己核对文档同步。
   前两件 hook 覆盖不到：它只管写不管读，也只在 Claude Code 里跑 git commit 时才出声。
   三件都只写触发时机，规则与清单留在 skill 里，不要复制成第二份。
   已有指向文档目录的说法改成指向 skill，`@` 前缀一并去掉。
7. **告知用户**：`.claude/skills/docs/`、`.claude/hooks/doc-sync-check.sh`、`.claude/settings.json`
   都要提交进版本库，团队和其它 agent 才共用同一套规则。hook 依赖 `jq`，缺了会静默放行。
   装好后用 `/docs` 调用，skill 或 hook 在当前会话里没生效就重启一次 Claude Code。

## 已存在时

`.claude/skills/docs/SKILL.md` 或 `.claude/hooks/doc-sync-check.sh` 已存在时不要直接覆盖：与模板逐节比对，
补齐模板有而它没有的规则，保留项目自己加的内容和改过的路径、匹配模式。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。
