---
name: change-check
description: 装上（或更新）agent-change-check skill 与 change-checker 子代理，收尾时审本次改动、只给意见不改文件。默认装进当前项目随仓库提交，也可安装到用户级配置、对当前用户环境中的所有项目生效。用于"给这个项目配代码审查""装 change-checker""更新审查规则"等场景。
disable-model-invocation: true
---

# 安装改动检查

装两样东西：`agent-change-check` skill（怎么派、意见怎么处理）与 `change-checker` 子代理（检查项与判断标准——查缺失、逻辑错误与结构问题，只给意见不改文件）。
装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

## 跨宿主约定

只执行当前宿主对应的分支。

模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；两者都为空时，先把 `SKILL_DIR`
设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），再按相对路径定位。
下面的变量定义要和后续命令放在同一次 shell 调用里，分开执行就每次重新定义：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  SETUP_ROOT="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/../.."
fi
TEMPLATE_DIR="$SETUP_ROOT/skills/change-check/template"
RENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"
```

## 选作用域

**默认装进当前项目**，随仓库提交，团队共用。用户明确说了「全局 / 用户级 / 所有项目 / 新电脑」时，才装进用户级配置目录。
当前目录不是 git 仓库时，先告知用户，确认改装用户级后再装，不要直接写进用户级配置。

Claude Code 中同名 skill 是**用户级优先于项目级**，与「就近优先」的直觉相反。
所以要按项目定制的 skill，不要在用户级再装一份同名的。写入前发现另一层也有同名 skill 时，告知用户两份都在，Claude Code 实际生效的是用户级那份。
Claude Code 中同名子代理是**项目级 `.claude/agents/` 优先于用户级**；写入前发现另一层也有同名子代理时，告知用户两份都在、实际生效的是项目级那份。

## 写入前检查

首次安装与重装都要做。这一节做完之前只读取，不写入、不删除任何文件。

- **查软链**：逐个确认将要写入或删除的路径本身——本安装器独占的目录（如装出的 skill 目录），要写入、整份替换或删除的文件——都不是软链（`[ -L <路径> ]`，路径末尾不带 `/`）。
  配置目录（`.claude/`、`.agents/`、`.codex/`、用户级配置目录）、其下多个安装器共用的 `skills/`、`agents/` 等目录，以及它们的上层目录是软链属正常布局，不查。
  要查的路径是软链，或有别的不符合预期的情况，按「现状与预期不符时」处理。
- **查冲突**：本安装器装出的是安装步骤里约定路径上做同一件事的 skill、子代理、脚本等文件（内容与模板差多少都算），照常重装、不问；其它安装器装出的内容各管各的，也不算。
  除此之外，要写入的位置已有与要写入的内容重叠或冲突的东西就是冲突：已有管同一件事的规则或流程；约定路径上的同名文件明显是另一样东西（用途不同）；已有的同一配置项取值与要写入的不同（定制值除外）。
  这几项各安装器都要查，本安装器另外要查的写在本节末尾。
  有冲突就**停下来问用户**是「完全覆盖」还是「融入现有内容」，用户选定前这一处不动手；安装步骤里说的「已有的直接 / 整份覆盖」只指本安装器装出的，冲突的那部分照用户的选择处理。
  - 问的时候写清冲突的是哪个文件、哪一段，以及两个选项各会改成什么样：完全覆盖是去掉现有的那部分、装本安装器的；
    融入是按用户的指示把要装的内容并进现有内容。两种做法的具体改法都先说给用户，不擅自定。
  - 两种结果都落进本安装器装出的内容，以后重装才界定得出：融入后与要写入内容重叠的部分落进本安装器装出的文件，
    落不进的，询问时说明下次重装还会再问。
  - 落进本安装器装出内容的部分以后照常重装，只有定制值所在的位置（见「重装」）会保留，所以融入的内容优先放进这些位置；
    这次安装的作用域下没有定制值的，询问时直说「融入只对这一次有效，下次重装会被覆盖」，建议选完全覆盖。

本安装器另外要查的冲突：无。

## 通用步骤

1. **写入 skill**：执行所在宿主安装节里的 `cp`，已有的整份覆盖。
2. **装子代理**：已有的整份覆盖；Codex 用渲染脚本的 `--replace` 替换同名旧 `.toml`，目标是软链时它会
   整批拒绝写入。项目级安装时，旧子代理「检查项」一节里有「本项目」表的，先把它读出来再覆盖
   （见「重装」；Codex 在旧 `.toml` 的 `developer_instructions` 里）。
3. **对齐项目**：只在项目级安装时做。项目有审查时必须知道、与通用检查项不同的约定——编码规范文档在哪、
   哪类改动必须额外盯的风险点——就在装好的子代理「检查项」一节加一张「本项目」表写进去
   （Codex 改 `.toml` 的 `developer_instructions`）。插入点固定在「代码以外的文件不套……两张表」那句之后、
   「## 敢于重组」之前，与前后各空一行。表的格式：

   ```markdown
   **本项目**

   | 检查 | 是则 | 出处 |
   |------|------|------|
   | <项目特有的检查，如「违反 docs/coding-style.md」「改了数据库迁移却没同步 schema 文档」> | <建议怎么改> | <规范文档的路径 + 章节标题原文；用户口头交代的写「用户交代」> |
   ```

   一行一条，内容来自项目里的规范文档或用户交代；只写项目确实有的，一条都没有就不加这张表。
   已写在项目指令文件里的约定不要再抄一遍。
4. **告知用户**：除各安装节列的外，说明重装时保留的只有项目级安装时填写的「本项目」表，
   项目特有的审查约定请写进这张表。

## Claude Code 项目级安装（默认）

```bash
top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/skills/agent-change-check .claude/agents
cp "$TEMPLATE_DIR/agent-change-check.md" .claude/skills/agent-change-check/SKILL.md
cp "$TEMPLATE_DIR/agents/change-checker.md" .claude/agents/
```

**告知用户**：`.claude/skills/agent-change-check/` 与 `.claude/agents/change-checker.md`
要提交进版本库才随仓库生效；`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。
装好后可用 `/agent-change-check` 调用，也会按描述自动触发；重启 Claude Code 后生效。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
: "${TEMPLATE_DIR:?}"
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/agent-change-check" "$C/agents"
cp "$TEMPLATE_DIR/agent-change-check.md" "$C/skills/agent-change-check/SKILL.md"
cp "$TEMPLATE_DIR/agents/change-checker.md" "$C/agents/"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；重启 Claude Code 后生效。

## Codex 项目级安装（默认）

```bash
top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/agent-change-check .codex/agents
cp "$TEMPLATE_DIR/agent-change-check.md" .agents/skills/agent-change-check/SKILL.md
python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/change-checker.md"
```

**告知用户**：`.agents/skills/agent-change-check/` 与 `.codex/agents/change-checker.toml`
要提交进版本库才随仓库生效；`.gitignore` 整体忽略了 `.agents/` 或 `.codex/` 的项目要为这两处加例外。
装好后可用 `$agent-change-check` 调用，也会按描述自动触发；开启新会话后生效。

## Codex 用户级安装

```bash
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
D="$HOME/.agents/skills/agent-change-check"
X=${CODEX_HOME:-$HOME/.codex}
mkdir -p "$D" "$X/agents"
cp "$TEMPLATE_DIR/agent-change-check.md" "$D/SKILL.md"
python3 "$RENDER_AGENT" --replace --output-dir "$X/agents" "$TEMPLATE_DIR/agents/change-checker.md"
```

**告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。

## 重装

每次运行都按当前模板重装，不判断版本，也不与模板比对。目标里已有本安装器装过的内容时，依次做下面四件事：

- **读定制值**：从旧文件里读出本安装器的定制值，作为这次填写这些位置的依据。定制值只限安装过程本来就要
  填写的位置，逐项写在本节末尾，写「无」的不读。能从项目现状重新确定的以现状为准，旧值只在现状确定不了、
  或本来就由用户填写时沿用。
- **清理**：只清理这一次要写的位置——整份替换的文件由安装步骤的写入命令直接覆盖；模板里没有的文件不管，
  同一目录里的其它内容不碰；安装步骤另有清理约定的照做。用户对冲突做了选择的那部分照他的选择处理。
- **装新的**：按安装步骤写入。
- **填回**：把读出的定制值填回新文件的对应位置。

**告知用户**时说明：本安装器装出的内容里，定制值以外的手改，重装时会被覆盖；定制值为「无」的，说这个安装器没有可定制的位置。
不要修改已安装 plugin 内的模板。

本安装器的定制值：

- 子代理「检查项」一节里的「本项目」表（项目级安装）：第 2 步覆盖前读出，第 3 步对照项目重新核对——
  出处是规范文档的，文档还在、约定还成立的沿用，已不存在的去掉；出处为「用户交代」的原样沿用。
- 用户级安装：无。

## 现状与预期不符时

下列情况，以及各节指明要按本节处理的情形，**停下来问用户**，不要照写、照删，也不要自行修复：

- 要写入、替换或删除的路径不是普通文件 / 目录。最常见的是软链：写入会写穿到它指向的地方，删掉或整份替换的
  只是链接本身、原来链向的那份从此脱钩，而且这几种情况表面上都不报错。
- 安装步骤里的命令报错退出、拒绝写入。
