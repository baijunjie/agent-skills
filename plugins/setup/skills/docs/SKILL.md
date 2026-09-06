---
name: docs
description: 给当前项目装上（或更新）项目级 docs skill 与提交前的文档同步检查，让总索引、项目地图、产品文档的维护规则随仓库提交。用于"给这个项目配文档规范""初始化项目文档结构""让 agent 维护文档""更新项目里的 docs skill"等场景。
disable-model-invocation: true
---

# 安装项目级 docs skill

把项目正式文档（总索引 / 项目地图 / 产品文档）的维护规则写进当前项目的 `.claude/skills/docs/`，
随仓库提交。触发点挂在项目的指令文件里——每次会话必读。

`docs/` 下的其它东西（开发期的过程产物、各种辅助文档）不在管辖内，装的时候也不要把它们写进规则。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 步骤

1. **定文档目录**：项目已有对应目录的沿用，没有则用默认的
   `docs/README.md`（索引）、`docs/project-map.md`、`docs/product/`。
2. **写入 skill**：

   ```bash
   mkdir -p .claude/skills/docs
   cp "$CLAUDE_PLUGIN_ROOT/skills/docs/template/docs.md" .claude/skills/docs/SKILL.md
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/docs.md`。
3. **对齐项目**：目录与默认不同时把新文件里的路径全部改成实际目录；项目另有与通用规则不同的
   约定，就地补写进去。
4. **建骨架**：缺 `docs/README.md` 就建一个只有标题和空索引的骨架。项目地图与产品文档等有内容再建，
   不要预建空目录或占位文档。项目已有散落的文档时，按类归位是另一件事，先问用户要不要一起做。
5. **装写文档的子代理**（Claude Code 专属，其它工具跳过本步）：

   ```bash
   mkdir -p .claude/agents
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/docs/template/agents/doc-writer.md" .claude/agents/
   ```

   **装进项目的 `.claude/agents/`，不是 `~/.claude/agents/`**；已有同名文件不要覆盖。
6. **挂触发点**：在项目的 `CLAUDE.md` / `AGENTS.md` 里写明开工前调用 `docs` skill 建立上下文、
   一个阶段的开发收尾要写或改产品文档与项目地图时**派 `doc-writer` 子代理**。
   已有指向文档目录的说法改成指向 skill，`@` 前缀一并去掉。
   只写触发时机——写法与判断标准留在 skill 与 `doc-writer` 的定义里，不要复制成第二份。
7. **告知用户**：`.claude/skills/docs/` 与 `.claude/agents/doc-writer.md` 都要提交进版本库。
   装好后用 `/docs` 调用，当前会话里没生效就重启一次 Claude Code。

## 已存在时

`.claude/skills/docs/SKILL.md` 已存在时不要直接覆盖：与模板逐节比对，
补齐模板有而它没有的规则，保留项目自己加的内容和改过的路径、匹配模式。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。
