---
name: workflow
description: {{scope_lead}}指令文件里的「工作流」一节与 agent-workflow-edit skill：按当前项目里已装的专职 skill（项目文档、单元测试、改动检查）写明开工前做什么、交付前按什么顺序自检，没装的步骤不写；agent-workflow-edit 规范以后怎么修改这一节。不装子代理。{{scope_tail}}用于"给这个项目配开发工作流""把测试、审查、文档串成交付流程""让 agent 交付前按顺序自检""更新项目的开发工作流"等场景。
disable-model-invocation: true
---

# 安装项目工作流

装两样东西，都只装进当前项目：指令文件里的「工作流」一节（开工前与交付前何时调用什么、按什么顺序），
与规范以后怎么修改这一节的 `agent-workflow-edit` skill。
不装子代理，也不装工作流里调用的专职 skill——那些各有安装器。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: skill-priority-project}}

{{include: markers}}

{{include: pre-write}}

本安装器另外要查的冲突：指令文件标记范围之外已有开工前、交付前做什么或按什么顺序自检的流程。

## 通用步骤

1. **查已装的专职 skill**：用所在宿主安装节里的命令查。工作流只为 `agent-docs`、`agent-unit-test`、
   `agent-change-check` 安排步骤，且**只认装在当前项目里的**：工作流写进随仓库提交的指令文件，用户级的 skill 不随仓库分发，队友那里没有。
   - 没装的 skill 对应的步骤整步省略，不写占位，也不顺手装上——没装说明用户没打算做这件事。
   - 只装在用户级的同样不写进工作流，告诉用户是哪几个，用户要求写进去再说。
   - 项目里一个都没装时，下面几步都不做，改按「一个专职 skill 都没装时」一节处理。
2. **按已装情况裁剪模板**：模板是 `$TEMPLATE_DIR/workflow.md`。`<!-- if-installed: <skill> -->` 到其后最近的
   `<!-- end-if -->` 是一段可省略的内容：该 skill 已装就保留内容、删掉这两行标记；没装就连内容整段删掉。
   裁剪后不留 `if-installed` / `end-if` 标记，交付前的步骤按剩下的重新连续编号，顺序不变；这两种标记之外的内容
   （「## 工作流」标题与引导句、交付前的总规则、静态检查、「### 本项目」小节与首尾的本安装器标记）始终保留。
3. **写入指令文件**：写所在宿主安装节里的指令文件，没有就新建。模板已带本安装器的标记。
   文件里已有这对标记时，先读出标记范围里「### 本项目」小节的条目。按「指令文件里的标记」
   写入裁剪后的内容。读出的条目原样填回新的「### 本项目」小节，替掉占位行；
   没有条目就留着新模板的占位行。条目锚定的步骤这次被裁掉了的，条目照样填回，告诉用户是哪几条。
4. **写入 skill**：执行所在宿主安装节里的 `cp`，已有的整份覆盖。
5. **告知用户**：写进工作流的步骤、因没装而省略的步骤、因只装在用户级而没写的步骤分别列出。
   再说一句：重装时保留的只有「### 本项目」小节——「工作流」一节的其余部分每次都按当前已装的 skill 重新生成，
   `agent-workflow-edit` 也整份覆盖；项目特有的步骤、顺序与跳过条件要写进这个小节。其余见所在宿主安装节。

## 一个专职 skill 都没装时

不写「## 工作流」一节：三个专职 skill 都没装，裁剪后只剩静态检查，构不成工作流。告诉用户项目里没有可编排的内容；
只装在用户级的照第 1 步告诉用户。

之前装过的（指令文件里有本安装器的标记，或项目里有 `agent-workflow-edit`），按标记范围里「### 本项目」小节的状态清理：

- **没有标记，或小节为空**（没有条目，只剩一行括号括起的占位说明或什么都没有）：有标记的删掉整个标记范围（含标记）；
  项目里有 `agent-workflow-edit` 的删掉它的 `SKILL.md`，目录空了再删目录。
- **小节有条目**：条目是用户写的，保留。标记范围里只留「## 工作流」标题与原样的「### 本项目」小节，模板内容全部删掉，
  标题只用来承载这些条目；
  `agent-workflow-edit` 照「写入 skill」一步整份覆盖，留着它以后改这个小节。告诉用户这些条目锚定的步骤都已不在，
  由他决定留还是删。

告诉用户删了什么、留了什么。

## Claude Code 项目级安装

指令文件是项目根目录的 `CLAUDE.md`。

查已装的专职 skill（第 1 步）：

```bash
{{include: project-root}}
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
for s in agent-docs agent-unit-test agent-change-check; do
  p=; u=
  [ -f ".claude/skills/$s/SKILL.md" ] && p=1
  [ -f "$C/skills/$s/SKILL.md" ] && u=1
  if [ -n "$p" ] && [ -n "$u" ]; then echo "$s: 项目+用户级"
  elif [ -n "$p" ]; then echo "$s: 项目"
  elif [ -n "$u" ]; then echo "$s: 仅用户级"
  fi
done
```

报「项目+用户级」的照样写进工作流，告知用户时指出是哪几个、本机 Claude Code 生效的是用户级那份。

写入 skill（第 4 步）：

```bash
{{include: project-root}}
mkdir -p .claude/skills/agent-workflow-edit
cp "$TEMPLATE_DIR/agent-workflow-edit.md" .claude/skills/agent-workflow-edit/SKILL.md
```

**告知用户**：`CLAUDE.md` 与 `.claude/skills/agent-workflow-edit/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为它加例外。指令文件在会话开始时读取，重启 Claude Code 后生效。

## Codex 项目级安装

指令文件是项目根目录的 `AGENTS.md`。

查已装的专职 skill（第 1 步）：

```bash
{{include: project-root}}
X=${CODEX_HOME:-$HOME/.codex}
for s in agent-docs agent-unit-test agent-change-check; do
  if [ -f ".agents/skills/$s/SKILL.md" ]; then echo "$s: 项目"
  elif [ -f "$HOME/.agents/skills/$s/SKILL.md" ] || [ -f "$X/skills/$s/SKILL.md" ]; then echo "$s: 仅用户级"
  fi
done
```

写入 skill（第 4 步）：

```bash
{{include: project-root}}
mkdir -p .agents/skills/agent-workflow-edit
cp "$TEMPLATE_DIR/agent-workflow-edit.md" .agents/skills/agent-workflow-edit/SKILL.md
```

**告知用户**：`AGENTS.md` 与 `.agents/skills/agent-workflow-edit/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 的项目要为它加例外。指令文件在会话开始时读取，开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：

- 标记范围里「### 本项目」小节的条目：第 3 步重建前读出，重建后原样填回；小节里只有一行括号括起的占位说明时算空，不读。
  其余内容是第 2 步按当前已装情况裁剪后的模板，不是模板原文，不读旧值。

{{include: state-mismatch}}
