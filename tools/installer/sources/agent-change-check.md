---
name: change-check
description: {{scope_lead}}agent-change-check skill 与 change-checker、ui-checker 子代理，收尾时审查改动并维护编码规范。{{scope_tail}}用于"给这个项目配代码审查""装 change-checker""整理编码规范"等场景。
disable-model-invocation: true
---

# 安装改动检查

装出 `agent-change-check` skill（怎么派、意见与规范建议怎么处理）与审查子代理（检查项与判断标准，只给意见不改文件）：
`change-checker` 审逻辑、需求、结构与编码规范；`ui-checker` 专审界面层面，项目级安装时只在项目有界面代码时才装。
项目级安装时还为项目梳理编码规范：已成体系的沿用，零碎或没有的经用户同意整理或新建成项目自己的规范文档；
之后审查只把够得上规范的缺口、过时与可精简的条目交用户定，沿用已有规范时提出精简方案，让规范保持精炼。
本安装器不往指令文件写任何内容。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: scope-select}}

{{include: skill-priority}}

{{include: pre-write}}

本安装器另外要查的冲突：第 6 步要新建或整理的规范文档的路径上已有不是规范的文件。第 6 步要写的每个文件（规范文档与第 3 步定下要改的原处）都按「写入前检查」查软链，与其它检查合成一次问。

## 编码规范的归属

规范文档是项目自己的文件，不是本安装器装出的内容：只在用户同意时由第 6 步新建或整理，写完归项目所有，
重装时不比对、不覆盖、不按「查手改」列出，只按第 3 步复查。装出的 skill 只在「本项目约定」里记它的路径。

规范文档的准入与写法：

{{include: convention-admission}}

- 界面相关的（样式与布局、界面状态、交互、可访问性、界面文案、界面组件）集中成一节或单独一份文档，由 `ui-checker` 对照，其余由 `change-checker` 对照。
- 条目以项目代码里一贯的做法、项目已有的规范来源与用户的决定为准。

## 通用步骤

第 1、2、3、6 步只在项目级安装时做；用户级安装没有项目，跳过它们。第 1–3 步只读取、只问用户，在「重装」的比对与「写入前检查」之前做完。

1. **读旧约定**：项目级安装、且已装过的（所在宿主安装节里 skill 的安装位置已有 `SKILL.md`），先读出旧 skill 的「本项目约定」一节，
   作为后续各步的依据（见「重装」）；当前宿主没装过时看另一宿主的项目级安装位置，都没装过就跳过。
2. **确认界面代码**：找界面代码（Web 前端、移动端、桌面端界面），列出所在路径（monorepo 逐包列出）请用户确认；没有界面就记「无」。
3. **梳理编码规范**：
   - 找项目已有的规范来源：指令文件、项目文档、skill、格式化与 Lint 配置里的规则说明，以及本安装器装过的子代理里不属于模板的项目条目；
     后者会被第 5 步覆盖，不当规范来源记路径：逐条问用户要不要整理进规范文档，这一问即「查手改」对这些条目的答复。
   - 已成体系（集中在一份或几份明确的规范文档里、按主题组织、条目判得出对错）的，沿用，记下路径；界面规范在哪份文档的哪一节一并记下。
   - 零碎（散落在多处、只有片言只语、彼此矛盾）的，向用户提议按「编码规范的归属」的写法整理成体系的规范文档：说清放在哪、分哪几节、每条从哪来、矛盾处各有哪些取法，原处的零散条目整理后删掉还是改成指向新文档。用户同意才整理，不同意就记现有各处的路径。
   - 规范条目在指令文件或其它安装器装出的文件里的，本安装器不改（整理后的原处、复查出的过时条目都一样），列给用户自己改。
   - 一处都没有的，向用户提议从项目代码一贯的做法归纳一份初稿；用户同意才建，不同意记「无」。
   - 第 1 步读到的旧值是用户上次在这两种提议里选定的（现有各处的路径或「无」），且现状没变的，沿用，不再提议。
   - 新文档的位置按项目的文档规范定，没有就问用户（默认 `docs/coding-standards.md`）。
   - 沿用已有规范文档时（含重装时第 1 步读到、仍在的）另做复查：
     - 逐条对照项目现状，找出引用的路径、工具、写法已不在项目里的，或与代码里一贯的做法矛盾的。
     - 按「编码规范的归属」的准入与形态审一遍，整理成精简方案（删除、合并、上提成原则、迁去别处；迁去别处的只从规范里删，内容与去处列给用户自己迁）。
     - 逐条列给用户，用户同意的才在第 6 步改；已不存在的文档从路径里去掉，告知用户，不再按「查手改」问。
4. **写入 skill**：执行所在宿主安装节里写入 skill 的命令，已有的整份覆盖。
5. **装子代理**：执行所在宿主安装节里装子代理的命令，已有的整份覆盖：`change-checker` 都装；`ui-checker` 用户级安装时装，
   项目级安装时只在第 2 步记下的界面代码不是「无」时装。项目级安装、界面代码为「无」、而本安装器装过 `ui-checker` 的，执行安装节里删除它的命令。
6. **写规范文档**：只在第 3 步用户同意了新建、整理或改动时做：按「编码规范的归属」写规范文档，整理时原有条目的含义不丢；
   第 3 步定下要删或改成指向新文档的原处，一并改。
7. **填本项目约定**：把装好的 skill「本项目约定」一节里「编码规范」「界面代码」两项的 `<…>` 连同尖括号换成实际值，尖括号里的说明不保留；路径写成代码体，「无」「未指定」不用代码体。
   项目级安装填第 2、3、6 步的结果；用户级安装两项都填「未指定」。
8. **告知用户**：除各安装节列的外，第 5 步删了 `ui-checker` 的说明这次删除也要提交；第 6 步写了或改了规范文档、改了原处的，说明改了哪些文件、改了什么，它要连同装出的文件一起提交进版本库；
   说明以后审查只把复核过、够得上规范的建议交给用户定，同意的才改进规范文档；重装时保留什么见「重装」。

## Claude Code 项目级安装（默认）

写入 skill（第 4 步）：

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/skills/agent-change-check
cp "$TEMPLATE_DIR/agent-change-check/SKILL.template.md" .claude/skills/agent-change-check/SKILL.md
```

装子代理（第 5 步），`change-checker`：

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/agents
cp "$TEMPLATE_DIR/agents/change-checker.md" .claude/agents/
```

界面代码不是「无」时，`ui-checker`：

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/agents
cp "$TEMPLATE_DIR/agents/ui-checker.md" .claude/agents/
```

界面代码为「无」、本安装器装过 `ui-checker` 时，删除它：

```bash
{{include: project-root}}
rm -f .claude/agents/ui-checker.md
```

**告知用户**：`.claude/skills/agent-change-check/` 与 `.claude/agents/` 下装出的子代理要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为这几处加例外。装好后可用 `/agent-change-check` 调用，也会按描述自动触发；重启 Claude Code 后生效。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
: "${TEMPLATE_DIR:?}"
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/agent-change-check" "$C/agents"
cp "$TEMPLATE_DIR/agent-change-check/SKILL.template.md" "$C/skills/agent-change-check/SKILL.md"
cp "$TEMPLATE_DIR/agents/change-checker.md" "$TEMPLATE_DIR/agents/ui-checker.md" "$C/agents/"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；重启 Claude Code 后生效。

## Codex 项目级安装（默认）

写入 skill（第 4 步）：

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/agent-change-check
cp "$TEMPLATE_DIR/agent-change-check/SKILL.template.md" .agents/skills/agent-change-check/SKILL.md
```

装子代理（第 5 步）：用渲染脚本的 `--replace` 替换同名旧 `.toml`。`change-checker`：

```bash
{{include: project-root}}
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
mkdir -p .codex/agents
python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/change-checker.md"
```

界面代码不是「无」时，`ui-checker`：

```bash
{{include: project-root}}
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
mkdir -p .codex/agents
python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/ui-checker.md"
```

界面代码为「无」、本安装器装过 `ui-checker` 时，删除它：

```bash
{{include: project-root}}
rm -f .codex/agents/ui-checker.toml
```

**告知用户**：`.agents/skills/agent-change-check/` 与 `.codex/agents/` 下装出的子代理要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 或 `.codex/` 的项目要为这几处加例外。装好后可用 `$agent-change-check` 调用，也会按描述自动触发；开启新会话后生效。

## Codex 用户级安装

```bash
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
D="$HOME/.agents/skills/agent-change-check"
X=${CODEX_HOME:-$HOME/.codex}
mkdir -p "$D" "$X/agents"
cp "$TEMPLATE_DIR/agent-change-check/SKILL.template.md" "$D/SKILL.md"
python3 "$RENDER_AGENT" --replace --output-dir "$X/agents" "$TEMPLATE_DIR/agents/change-checker.md" "$TEMPLATE_DIR/agents/ui-checker.md"
```

**告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：skill「本项目约定」一节里「编码规范」「界面代码」两项的取值，第 1 步读出，第 7 步填回，分别按第 2、3 步重新确定，已当场由用户确认的不再按「查手改」重问；这一节的其余文字随模板，旧节里多出的内容按「查手改」列出。
第 1–3 步的结果要改定制值或写规范文档的，不算无变更，照常重装。用户级安装：无。

{{include: state-mismatch}}
