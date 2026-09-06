---
name: report-style
description: 在本机装上（或更新）自定义 output style「Concise+」，让 Claude Code 的回答只给结果、不复述过程，需要确认的事项与疑问必须显式列出，且不先肯定再转折。用于"agent 报告太啰嗦""让它少说废话只给结论""别顺着我说""配输出风格""装 output style"等场景。
disable-model-invocation: true
---

# 安装全局输出风格 Concise+

内置 `Concise` 的基础上补两类硬要求：**需要用户拍板的事项与没搞清楚的疑问**必须单独列出、
不许混在正文里；**不附和**——不先肯定再转折，分歧当分歧说。
真身放 `~/.config/agents/`，软链进各 Claude 配置目录。

Output style 是 Claude Code 专有机制，Codex 等其它工具没有对应物，不受影响。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 目标布局

```text
~/.config/agents/claude-output-styles/concise-plus.md   # 真身
<Claude 配置目录>/output-styles → ~/.config/agents/claude-output-styles
```

## 步骤

1. **建真身**：

   ```bash
   mkdir -p ~/.config/agents/claude-output-styles
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/report-style/template/claude-output-styles/concise-plus.md" ~/.config/agents/claude-output-styles/
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/`。
2. **列出要接的配置目录**：默认 `~/.claude`，用户可能另有一个（工作 / 个人分开），
   从 shell 配置里带 `CLAUDE_CONFIG_DIR` 的 alias 或 export 找出来，找不到就问用户，
   **不要只接默认那一个**。
3. **接软链**：每个目标位置先判断它现在是什么——

   | 现状 | 处理 |
   |---|---|
   | 不存在 | 直接建链 |
   | 已指向本真身的软链 | 跳过 |
   | 指向别处的软链 | 问用户 |
   | **真实目录** | **先把里面的 style 文件挪进真身**，确认无误再替换；不要直接覆盖 |

   ```bash
   ln -sfn ~/.config/agents/claude-output-styles <Claude 配置目录>/output-styles
   ```

   `-n` 不能省：目标已经是指向目录的软链时，少了它会把新链建**进**那个目录里。
4. **启用**：每个配置目录的 `settings.json` 里设 `"outputStyle": "Concise+"`。
   用户想自己在界面里选就告诉他入口在 `/config` 的 Output style 一项（`/output-style` 已并入 `/config`）。
5. **告知用户**：重启 Claude Code 才生效；同一时刻只能启用一个 output style，启用它就用不了
   `Explanatory` / `Learning`，切回内置在同一个入口。
   全局 / 项目指令文件里还留着同类的报告规范时提醒用户删掉，免得两份规则并存后各自漂移。

## 已存在时

真身已存在时不要覆盖：与模板逐条比对，补齐模板有而它没有的规则，保留本机自己加的。
反过来，本机有而模板没有、且不是这台机器专属的内容，回写进模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。
