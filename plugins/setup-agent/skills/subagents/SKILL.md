---
name: subagents
description: 装上（或更新）分派子代理的规则，与 mechanical、implement、investigate、architect 四个通用子代理。默认装进当前项目随仓库提交，也可安装到用户级配置、对当前用户环境中的所有项目生效。用于"装通用子代理""配子代理分派规则""配一台新电脑"等场景。
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
当前目录不是 git 仓库时汇报，用户同意改装用户级后再装，不要直接写进用户级配置。

**整份装齐**，不要因为「用户级可能已经装过」而缩水。

Claude Code 中同名子代理是**项目级 `.claude/agents/` 优先于用户级**；写入前发现另一层也有同名子代理时，告知用户两份都在、实际生效的是项目级那份。

## 指令文件里的标记

- **标记**：本安装器往指令文件（`CLAUDE.md` / `AGENTS.md`）写的内容，整块包在一对标记里：
  `<!-- setup-agent:subagents:begin -->` 开头、`<!-- setup-agent:subagents:end -->` 结尾，各独占一行，与相邻内容之间各空一行，免得粘连前后的段落、列表与表格。
  下文的「标记范围」指这对标记连同其间的内容。只按标记认，不按标题找：标记之外的内容不碰，节标题相同也不算本安装器的。
- **替换还是追加**：文件里没有这对标记就追加到文件末尾（新建的文件开头不留空行）；已有就只原位替换标记范围，不再追加第二份，标记与相邻内容之间原有的空行不变。
  安装步骤给出的写入命令以 `>> <文件>` 结尾、输出已带这对标记并以空行开头：已有标记时去掉 `>> <文件>` 执行，只取输出里从 begin 标记到 end 标记的那一段替换。
- **标题层级**：写入的内容顶层节标题用 `#`。目标文件把 `#` 只用作全文的文档标题、用 `##` 分节时，写入后把标记范围里的标题整体降一级，
  否则本安装器的节会挂到上一节底下成为它的子节。
- **冲突的处理结果**：冲突处理完，结果一律写进标记范围，标记之外原来那段删掉。
- **异常**：指令文件里本安装器的标记不成对（只出现一个、出现多对，或先后颠倒）时，按「现状与预期不符时」**停下来问用户**。
  要写的指令文件是链向另一宿主指令文件的软链时，不按「现状与预期不符时」处理，改按下面「共用的指令文件」。
- **共用的指令文件**：两个宿主的指令文件有一份是指向另一份的软链（如 `CLAUDE.md` → `AGENTS.md`，方向反过来也算）时，两个宿主读的是同一份。
  不论当前宿主的指令文件是软链还是被链向的那份，往它写入前都**停下来问用户**是否写进这份共用的文件，说明另一宿主也会读到；
  本安装器在另一宿主下也往这份文件写、且内容不同时，还要说明只会保留最后写入的那个宿主的版本。
  用户不写，就只跳过当前宿主的这一部分，另一宿主的照常装。这个软链在「写入前检查」里一并查。

## 写入前检查

首次安装与重装都要做。这一节做完之前只读取，不写入、不删除任何文件。

- **查软链**：将要写入、整份替换或删除的路径本身——包括本安装器独占的目录（如装出的 skill 目录）——都不能是软链（`[ -L <路径> ]`，路径末尾不带 `/`）。
  配置目录（`.claude/`、`.agents/`、`.codex/`、用户级配置目录）、其下多个安装器共用的 `skills/`、`agents/` 等目录，以及它们的上层目录是软链属正常布局，不查。
  要查的路径是软链，按「现状与预期不符时」处理。
- **查冲突**：本安装器装出的（安装步骤约定路径上做同一件事的 skill、子代理、脚本等，内容与模板差多少都算）不算冲突，其中的手改见「查手改」；其它安装器装出的各管各的，也不算。
  除此之外，要写入的位置已有与要写入内容重叠或冲突的东西就是冲突：已有管同一件事的规则或流程；约定路径上的同名文件用途不同；已有的同一配置项取值与要写入的不同（定制值除外）。
  这几项各安装器都要查，本安装器另外要查的写在本节末尾。
- **查手改**：目标里已有本安装器装过的内容（这次是重装）时，按「重装」的「重装后留下什么」找出这次会被覆盖的手改，可以与模板比对；分不清是旧版模板的差异还是手改的，一并列出。
  安装步骤要删除的文件或目录里，凡不是这次模板原样装出的内容（用户自建的文件、改过的旧版文件）也一并列出。
  列出了的，写入任何文件之前就**停下来问用户**是否照常重装；一处也没有的照常重装，不必等确认。
  用户不照常重装的，不写入任何文件，结束并汇报；用户想留住手改的，把它当冲突按下面的「融入」处理。
- **有冲突时**：**停下来问用户**是「完全覆盖」还是「融入现有内容」，用户选定前不写入任何文件；安装步骤里说的「已有的直接 / 整份覆盖」只指本安装器装出的，冲突的那部分照用户的选择处理。
  - 问时写清冲突的是哪个文件、哪一段，两个选项各会改成什么样：完全覆盖是去掉现有的那部分、装本安装器的；融入是按用户的指示把要装的内容并进现有内容。具体改法先说给用户，不擅自定。
  - 融入的结果优先落进由用户填写的定制值位置，其次是本安装器装出的其它内容，以后重装才界定得出。询问时按「重装」的「重装后留下什么」说明融入的内容以后重装会不会留下；留不下的直说融入只对这一次有效（下次重装会再问，而原有的冲突内容这次就已去掉），并建议选完全覆盖。

本安装器另外要查的冲突：

- 指令文件标记范围之外已有分派子代理的规则（什么时候派、派给谁、怎么交代）；只有「# 全局规则」标题、底下没有这类规则的不算。
- 用户级安装、文件里还没有本安装器标记、已有的「# 全局规则」又不是文件里最后一个一级标题时
  （追加到末尾的规则会挂到别的标题下），按「现状与预期不符时」问用户。
- **这一项不按冲突问**：项目级安装时，当前宿主用户级指令文件里已有分派子代理规则的，不改它，告知用户两份都会生效、内容差在哪；用户级那份是本安装器装的且内容一致时，只说一句两处都装了。

## 写入的规则内容

写入的是命令渲染出的内容，不要直接拷 `INJECT.md`（原文带用户级标题与 `{{HOST_AGENT_CONFIGURATION}}` 占位符）。

用户级安装加 `--no-header` 渲染时，告知用户：渲染出的规则不含「与项目自己的指令文件冲突时，以项目的为准」这一句，
请用户确认已有的「# 全局规则」下有没有同样的约定。

## Claude Code 项目级安装（默认）

1. **写规则**：目标是项目根目录的 `CLAUDE.md`，没有就新建。

   ```bash
   top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   rules=$(python3 "$RENDER_RULES" --host claude --scope project "$TEMPLATE_DIR/INJECT.md") &&
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

1. **写规则**：标记范围之外已有「# 全局规则」标题时加 `--no-header` 渲染，规则挂到已有的那个标题下、
   不重复标题与首句；下面的命令自己判断：

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   F="$C/CLAUDE.md"
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   mkdir -p "$C"
   NOHEAD=
   if [ -f "$F" ] && awk '/^<!-- setup-agent:subagents:begin -->$/{s=1} !s{print} /^<!-- setup-agent:subagents:end -->$/{s=0}' "$F" | grep -qx '# 全局规则'; then NOHEAD=--no-header; fi
   echo "渲染参数：${NOHEAD:-（无，带「# 全局规则」标题）}"
   rules=$(python3 "$RENDER_RULES" --host claude --scope user $NOHEAD "$TEMPLATE_DIR/INJECT.md") &&
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
   rules=$(python3 "$RENDER_RULES" --host codex --scope project "$TEMPLATE_DIR/INJECT.md") &&
     printf '\n<!-- setup-agent:subagents:begin -->\n\n%s\n\n<!-- setup-agent:subagents:end -->\n' "$rules" >> AGENTS.md
   ```

2. **装子代理**：已有的同名 `.toml` 整份替换。

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

1. **写规则**：标记范围之外已有「# 全局规则」标题时加 `--no-header` 渲染，规则挂到已有的那个标题下、
   不重复标题与首句；下面的命令自己判断：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   F="$X/AGENTS.md"
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   mkdir -p "$X"
   NOHEAD=
   if [ -f "$F" ] && awk '/^<!-- setup-agent:subagents:begin -->$/{s=1} !s{print} /^<!-- setup-agent:subagents:end -->$/{s=0}' "$F" | grep -qx '# 全局规则'; then NOHEAD=--no-header; fi
   echo "渲染参数：${NOHEAD:-（无，带「# 全局规则」标题）}"
   rules=$(python3 "$RENDER_RULES" --host codex --scope user $NOHEAD "$TEMPLATE_DIR/INJECT.md") &&
     printf '\n<!-- setup-agent:subagents:begin -->\n\n%s\n\n<!-- setup-agent:subagents:end -->\n' "$rules" >> "$F"
   ```

2. **装子代理**：同项目级：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   : "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
   mkdir -p "$X/agents"
   python3 "$RENDER_AGENT" --replace --output-dir "$X/agents" "$TEMPLATE_DIR/agents/"*.md
   ```

3. **告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。

## 重装

每次运行都按当前模板重装，不判断版本；装不装不靠与模板比对决定（「写入前检查」查手改时可以比对）。目标里已有本安装器装过的内容时，依次做下面四件事：

- **读定制值**：从旧文件里读出本安装器的定制值，作为这次填写这些位置的依据。定制值只限安装过程本来就要填写的位置，
  逐项写在本节末尾，写「无」的不读。各项这次沿用旧值还是按现状重定，见下面「重装后留下什么」。
- **清理**：只清理这一次要写的位置：整份替换的文件由安装步骤的写入命令直接覆盖，指令文件只替换本安装器的标记范围，模板里没有的文件与同一目录里的其它内容不碰；
  安装步骤另有清理约定、或用户对冲突做了选择的，照它处理。
- **装新的**：按安装步骤写入。
- **填回**：把读出的定制值填回新文件的对应位置。用户在「写入前检查」选了融入的，融入在填回、按现状重定之后做，结果以融入后的为准。

**重装后留下什么**：只有由用户填写的定制值原样保留；由现状推导的定制值（含手改过的）按这次的现状重写，现状确定不了才沿用旧值。本安装器装出的其余内容都按模板覆盖；安装步骤约定删除的文件或目录，连同其中的内容（包括用户自建的文件）一并删掉。
这一次选了融入的以融入结果为准，不改变以后重装的去留。这是重装去留的唯一定义，别处说保留、覆盖都以此为准。

**告知用户**时按「重装后留下什么」说明以后重装保留什么、覆盖什么；定制值为「无」的，说这个安装器没有可定制的位置。
不要修改已安装 plugin 内的模板。

本安装器的定制值：无。

## 现状与预期不符时

下列情况，以及各节指明要按本节处理的情形，**停下来问用户**，不要照写、照删，也不要自行修复：

- 要写入、替换或删除的路径不是普通文件 / 目录（「写入前检查」里说明不查的配置目录等除外），最常见的是软链：写入会写穿到它指向的那份，删除或整份替换会让那份从此脱钩，都不报错。
  用户同意写进软链指向的那份时，只原地修改它，不先删后建，也不整份替换链接本身。
- 安装步骤里的命令报错退出、拒绝写入。
- 按安装步骤与项目现状确定不了要写什么、写到哪。
