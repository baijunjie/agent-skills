---
name: subagents
description: 装上（或更新）分派子代理的规则与四个通用子代理（mechanical、implement、investigate、architect）。默认装进当前项目随仓库提交，也可安装到用户级配置、对当前用户环境中的所有项目生效。用于"装通用子代理""配子代理分派规则""配一台新电脑""同步我的子代理规则"等场景。
disable-model-invocation: true
---

# 安装分派子代理规则与通用子代理

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
TEMPLATE_DIR="$SETUP_ROOT/skills/subagents/template"
RENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"
RENDER_RULES="$SETUP_ROOT/scripts/render-subagent-rules.py"
```

## 选作用域

**默认装进当前项目**，随仓库提交，团队共用。用户明确说了「全局 / 用户级 / 所有项目 / 新电脑」时，才装进用户级配置目录。
当前目录不是 git 仓库时，先告知用户，确认改装用户级后再装，不要直接写进用户级配置。

**整份装齐**，不要因为「用户级可能已经装过」而缩水。

Claude Code 中同名子代理是**项目级 `.claude/agents/` 优先于用户级**；写入前发现另一层也有同名子代理时，告知用户两份都在、实际生效的是项目级那份。

## 指令文件里的标记

- **标记**：本安装器往指令文件（`CLAUDE.md` / `AGENTS.md`）写的内容，整块包在一对标记里：
  `<!-- setup-agent:subagents:begin -->` 开头、`<!-- setup-agent:subagents:end -->` 结尾，各独占一行，与相邻内容之间各空一行，
  免得粘连前后的段落、列表与表格。下文的「标记范围」指这对标记
  连同其间的内容。不按标题去找，标记之外的内容不碰，节标题相同也不算本安装器的。
- **替换还是追加**：安装步骤给出的写入命令以 `>> <文件>` 结尾，输出已带这对标记，并以空行开头。
  - 文件里没有这对标记，就当作本安装器还没往这个文件写过：照原样执行，追加到文件末尾。开头的空行用来与原有内容隔开；
    追加后 begin 标记与上文之间没空出一行的（原文件末尾没有换行）补一个空行，新建的文件删掉开头的空行。
  - 文件里已有这对标记：去掉命令末尾的 `>> <文件>` 执行，只用输出里从 begin 标记到 end 标记的那一段替换标记范围，
    写回原位置，不再追加第二份。替换内容不带前导空行，标记与相邻内容之间原有的空行保持不变，重装多少次空行都不会累积。
  - 安装步骤直接给出带标记的内容、不经命令输出的，照同样的做法追加或替换。
- **标题层级**：写入的内容顶层节标题用 `#`，跟指令文件按 `#` 分节的常规一致。目标文件把 `#` 只用作全文的文档标题、
  用 `##` 分节时，写入后把标记范围里的标题整体降一级对齐：层级不对齐，本安装器的节会挂到上一节底下成为它的子节。
- **冲突**：指令文件里本安装器的标记范围是本安装器装出的，照常重装、不问；其它安装器标记范围里的内容各管各的，
  也不算冲突。标记范围之外已有管同一件事的规则或流程才是冲突。
- **冲突的处理结果**：冲突处理完，结果一律写进标记范围，标记之外原来那段删掉。
- **重装**：指令文件里清理的是本安装器的标记范围，同一指令文件里的其它内容不碰。
- **异常**：下列情况按「现状与预期不符时」**停下来问用户**，不要照写，也不要自行修复；软链要在「写入前检查」里一并查。
  - 指令文件里本安装器的标记不成对：只出现一个、出现多对，或先后颠倒。
  - 要写的指令文件本身是软链。链向另一宿主的指令文件时，按下面「共用的指令文件」处理。
- **共用的指令文件**：另一宿主的指令文件是指向要写的这份的软链（如 `CLAUDE.md` → `AGENTS.md`）时，两个宿主读的是同一份。
  写入前**停下来问用户**：说明这一点，问是否写进这份共用的文件；写进去后，按宿主渲染的内容只会保留最后写入的那个宿主的版本。
  这个软链同样在「写入前检查」里一并查。

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

本安装器另外要查的冲突：

- 指令文件标记范围之外已有分派子代理的规则（什么时候派、派给谁、怎么交代）。
  标记之外只有「# 全局规则」标题、底下没有这类规则的不算冲突。
- 用户级、文件里还没有本安装器标记、且标记之外已有「# 全局规则」时：它不是文件里最后一个一级标题的
  （追加到末尾的规则会挂到别的标题下），按「现状与预期不符时」问用户。
- **这一项不按冲突问**：项目级安装时，当前宿主用户级指令文件里已有同类规则（分派子代理规则）的，不改它，告知用户两份都会生效、内容差在哪；用户级的是本安装器装的且内容一致时，只说一句两处都装了。

## 写入的规则内容

写入的是命令渲染出的内容，不要直接拷 `rules.md`（原文带用户级标题与 `{{HOST_AGENT_CONFIGURATION}}` 占位符）。

用户级安装加 `--no-header` 渲染时，告知用户：这样渲染出的规则不含「与项目自己的指令文件冲突时，以项目的为准」这一句，
请用户确认已有的「# 全局规则」下有没有同样的约定。

## Claude Code 项目级安装（默认）

1. **写规则**：目标是项目根目录的 `CLAUDE.md`，没有就新建。

   ```bash
   top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   rules=$(python3 "$RENDER_RULES" --host claude --scope project "$TEMPLATE_DIR/rules.md") &&
     printf '\n<!-- setup-agent:subagents:begin -->\n\n%s\n\n<!-- setup-agent:subagents:end -->\n' "$rules" >> CLAUDE.md
   ```

2. **装子代理**：已有的整份覆盖。

   ```bash
   top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
   : "${TEMPLATE_DIR:?}"
   mkdir -p .claude/agents
   cp "$TEMPLATE_DIR/agents/"*.md .claude/agents/
   ```

3. **告知用户**：`CLAUDE.md` 与 `.claude/agents/` 的改动要提交进版本库才随仓库生效；
   `.gitignore` 整体忽略了 `.claude/` 的项目要为 `.claude/agents/` 加例外，否则子代理提交不进去。
   `CLAUDE.md` 与子代理都在会话开始时读取，重启 Claude Code 后生效。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

1. **写规则**：标记范围之外已有「# 全局规则」标题时加 `--no-header` 渲染——它不重复这个标题与首句，
   写出的规则直接挂到已有的那个标题下；下面的命令会自己判断：

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   F="$C/CLAUDE.md"
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   mkdir -p "$C"
   NOHEAD=
   if [ -f "$F" ] && awk '/^<!-- setup-agent:subagents:begin -->$/{s=1} !s{print} /^<!-- setup-agent:subagents:end -->$/{s=0}' "$F" | grep -qx '# 全局规则'; then NOHEAD=--no-header; fi
   echo "渲染参数：${NOHEAD:-（无，带「# 全局规则」标题）}"
   rules=$(python3 "$RENDER_RULES" --host claude --scope user $NOHEAD "$TEMPLATE_DIR/rules.md") &&
     printf '\n<!-- setup-agent:subagents:begin -->\n\n%s\n\n<!-- setup-agent:subagents:end -->\n' "$rules" >> "$F"
   ```

2. **装子代理**：已有的整份覆盖。

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   : "${TEMPLATE_DIR:?}"
   mkdir -p "$C/agents"
   cp "$TEMPLATE_DIR/agents/"*.md "$C/agents/"
   ```

3. **告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；规则与子代理都在会话开始时读取，
   重启 Claude Code 后生效。

## Codex 项目级安装（默认）

1. **写规则**：目标是项目根目录的 `AGENTS.md`，没有就新建。

   ```bash
   top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   rules=$(python3 "$RENDER_RULES" --host codex --scope project "$TEMPLATE_DIR/rules.md") &&
     printf '\n<!-- setup-agent:subagents:begin -->\n\n%s\n\n<!-- setup-agent:subagents:end -->\n' "$rules" >> AGENTS.md
   ```

2. **装子代理**：用渲染脚本的 `--replace` 替换与模板同名的旧 `.toml`（只动这几个），目标是软链时它会整批拒绝写入：

   ```bash
   top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
   : "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
   mkdir -p .codex/agents
   python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/"*.md
   ```

3. **告知用户**：`AGENTS.md` 与 `.codex/agents/` 的改动要提交进版本库才随仓库生效；
   `.gitignore` 整体忽略了 `.codex/` 的项目要为 `.codex/agents/` 加例外，否则子代理提交不进去。
   开启新会话后生效。

## Codex 用户级安装

1. **写规则**：标记范围之外已有「# 全局规则」标题时加 `--no-header` 渲染——它不重复这个标题与首句，
   写出的规则直接挂到已有的那个标题下；下面的命令会自己判断：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   F="$X/AGENTS.md"
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   mkdir -p "$X"
   NOHEAD=
   if [ -f "$F" ] && awk '/^<!-- setup-agent:subagents:begin -->$/{s=1} !s{print} /^<!-- setup-agent:subagents:end -->$/{s=0}' "$F" | grep -qx '# 全局规则'; then NOHEAD=--no-header; fi
   echo "渲染参数：${NOHEAD:-（无，带「# 全局规则」标题）}"
   rules=$(python3 "$RENDER_RULES" --host codex --scope user $NOHEAD "$TEMPLATE_DIR/rules.md") &&
     printf '\n<!-- setup-agent:subagents:begin -->\n\n%s\n\n<!-- setup-agent:subagents:end -->\n' "$rules" >> "$F"
   ```

2. **装子代理**：与项目级相同，用 `--replace` 替换与模板同名的旧 `.toml`：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   : "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
   mkdir -p "$X/agents"
   python3 "$RENDER_AGENT" --replace --output-dir "$X/agents" "$TEMPLATE_DIR/agents/"*.md
   ```

3. **告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。

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

本安装器的定制值：无。

## 现状与预期不符时

下列情况，以及各节指明要按本节处理的情形，**停下来问用户**，不要照写、照删，也不要自行修复：

- 要写入、替换或删除的路径不是普通文件 / 目录。最常见的是软链：写入会写穿到它指向的地方，删掉或整份替换的
  只是链接本身、原来链向的那份从此脱钩，而且这几种情况表面上都不报错。
- 安装步骤里的命令报错退出、拒绝写入。
