---
name: workflow
description: 在本机装上（或更新）跨工具共用的全局 agent 工作流：一份全局规则真身 + 子代理定义，软链进 Claude Code 与 Codex 的配置目录。用于"配一台新电脑""同步我的 agent 工作流""初始化全局规则""更新全局 AGENTS.md"等场景。
disable-model-invocation: true
---

# 安装全局 agent 工作流

把跨项目、跨工具共用的规则收成**一份真身**放在 `~/.config/agents/`，再软链进各工具的配置目录。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 目标布局

```text
~/.config/agents/
├── AGENTS.md              # 全局规则真身（工具无关；工具专属内容单独成节并标注）
└── claude-subagents/      # 通用子代理定义（只有 Claude Code 用得上）

<Claude 配置目录>/CLAUDE.md → ~/.config/agents/AGENTS.md
<Claude 配置目录>/agents    → ~/.config/agents/claude-subagents
~/.codex/AGENTS.md          → ~/.config/agents/AGENTS.md
```

## 步骤

1. **建真身**：

   ```bash
   mkdir -p ~/.config/agents/claude-subagents
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/workflow/template/AGENTS.md" ~/.config/agents/AGENTS.md
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/workflow/template/claude-subagents/"*.md ~/.config/agents/claude-subagents/
   ```

   已有内容怎么合并见「已存在时」。`$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/`。
2. **列出要接的配置目录**：Codex 固定是 `~/.codex`。Claude Code 默认 `~/.claude`，用户可能另有
   一个（工作/个人分开），从 shell 配置里带 `CLAUDE_CONFIG_DIR` 的 alias 或 export 找出来，
   找不到就问用户，**不要只接默认那一个**。
3. **接软链**：每个目标位置先判断它现在是什么——

   | 现状 | 处理 |
   |---|---|
   | 不存在 | 直接建链 |
   | 已指向本真身的软链 | 跳过 |
   | 指向别处的软链 | 问用户 |
   | **真实文件 / 目录** | **先把内容并进真身**，确认无误再替换；不要直接覆盖 |

   ```bash
   ln -sfn ~/.config/agents/AGENTS.md        <Claude 配置目录>/CLAUDE.md
   ln -sfn ~/.config/agents/claude-subagents <Claude 配置目录>/agents
   ln -sfn ~/.config/agents/AGENTS.md        ~/.codex/AGENTS.md
   ```

   `-n` 不能省：目标已经是指向目录的软链时，少了它会把新链建**进**那个目录里。
   子代理定义只接进 Claude 的配置目录，Codex 没有对应机制。
4. **多配置目录的切换**：第二个 Claude 配置目录靠环境变量切，在 shell 配置里留个 alias，例如
   `alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'`。**每个配置目录都是独立的安装
   环境**，plugin、marketplace、settings 都要各配一遍。
5. **告知用户**：以后改规则只改 `~/.config/agents/` 里的真身，各工具自动跟上，但**要重启工具
   才重新加载**。子代理定义只对 Claude Code 生效。

## 已存在时

真身里已有内容时不要覆盖：与 `template/` 逐节比对，补齐模板有而它没有的，保留本机自己加的。
反过来，本机有而模板没有、且不是这台机器专属的内容，回写进模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

被软链取代的原文件里如果有独有内容，先并进真身再删。

## 规则该放哪一层

| 内容 | 位置 |
|---|---|
| 跨项目跨工具都成立（注释、提交信息、收尾自检） | 本 skill 的 `AGENTS.md` |
| 只有某个工具有那套机制（子代理档位） | 同一份 `AGENTS.md`，单独成节并在标题里写明「仅适用于 X」 |
| 只对某台机器成立（路径、别名、本机装了什么） | 不进真身，留在该机器的 shell 配置里 |
| 某个项目特有 | 那个项目自己的指令文件、skill 与 `.claude/agents/`，随它的仓库提交 |
