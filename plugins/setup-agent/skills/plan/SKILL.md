---
name: plan
description: 装上（或更新）agent-plan-write 与 agent-plan-exec 两个 skill，把方案写成开发计划文档、按它逐里程碑开发。默认装进当前项目随仓库提交，也可安装到用户级配置、对当前用户环境中的所有项目生效。用于"给这个项目配开发计划流程""装 plan-write / plan-exec"等场景。
disable-model-invocation: true
---

# 安装开发计划 skill

装 `agent-plan-write` 与 `agent-plan-exec` 两个 skill：前者把方案写成开发计划文档，
后者按计划文档逐里程碑开发。装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

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
TEMPLATE_DIR="$SETUP_ROOT/skills/plan/template"
```

## 选作用域

**默认装进当前项目**，随仓库提交，团队共用。用户明确说了「全局 / 用户级 / 所有项目 / 新电脑」时，才装进用户级配置目录。
用户说的是更新、重装而没指明作用域时，先看当前项目与用户级配置里哪一层已有本安装器装出的内容（约定路径上已有的同名文件即算，判定见「写入前检查」的「查冲突」），在那一层重装；两层都有的，问用户。
按默认装进项目、而当前目录不是 git 仓库时汇报，用户同意改装用户级后再装，不要直接写进用户级配置；用户已明说用户级、或只有用户级已装的，不受此限。

Claude Code 中同名 skill 是**用户级优先于项目级**，与「就近优先」的直觉相反。
所以要按项目定制的 skill，不要在用户级再装一份同名的。写入前发现另一层也有同名 skill 时，告知用户两份都在，Claude Code 实际生效的是用户级那份。

## 写入前检查

首次安装与重装都要做；重装时先按「重装」比对，无变更就不做这一节。这一节做完之前只读取，不写入、不删除任何文件。

- **查软链**：将要写入、整份替换或删除的路径本身——包括本安装器独占的目录（如装出的 skill 目录）——都不能是软链（`[ -L <路径> ]`，路径末尾不带 `/`）。
  配置目录（`.claude/`、`.agents/`、`.codex/`、用户级配置目录）、其下多个安装器共用的 `skills/`、`agents/` 等目录，以及它们的上层目录是软链属正常布局，不查。
  要查的路径是软链，按「现状与预期不符时」处理。
- **查冲突**：本安装器装出的（安装步骤约定路径上做同一件事的 skill、子代理、脚本等，内容与模板差多少都算；装出的文件没有标记，约定路径上已有的同名文件一律按「装过」处理、不判断用途是否相同，这次即重装）不算冲突，其中的手改见「查手改」；其它安装器装出的各管各的，也不算。
  除此之外，要写入的位置已有与要写入内容重叠或冲突的东西就是冲突：已有管同一件事的规则或流程；已有的同一配置项取值与要写入的不同（定制值除外）。
  这几项各安装器都要查，本安装器另外要查的写在本节末尾。
- **查手改**：目标里已有本安装器装过的内容（这次是重装）时，按「重装」的「重装后留下什么」找出这次会被覆盖的手改，与模板比对；没有版本记录，分不清是旧版模板的差异还是手改，所以有差异的一律列出。
  安装步骤要删除的文件或目录里，凡不是这次模板原样装出的内容（用户自建的文件、改过的旧版文件）也一并列出。
  列出了的，写入任何文件之前就**停下来问用户**是否照常重装（软链、冲突要问的，与这一问合成一次问）。
  用户不照常重装的，不写入任何文件，结束并汇报；用户想留住手改的，本安装器的定制值不是「无」时，把它当冲突按下面的「融入」处理；是「无」时手改留不到下次重装，只能二选一：不重装，或覆盖后把手改另存成别的名字自行保留。
- **有冲突时**：**停下来问用户**是「完全覆盖」还是「融入现有内容」，用户选定前不写入任何文件；安装步骤里说的「已有的直接 / 整份覆盖」只指本安装器装出的，冲突的那部分照用户的选择处理。
  - 问时写清冲突的是哪个文件、哪一段，两个选项各会改成什么样：完全覆盖是去掉现有的那部分、装本安装器的；融入是按用户的指示把要装的内容并进现有内容。具体改法先说给用户，不擅自定。
  - 融入的结果优先落进由用户填写的定制值位置，其次是本安装器装出的其它内容，以后重装才界定得出。询问时按「重装」的「重装后留下什么」说明融入的内容以后重装会不会留下；留不下的直说融入只对这一次有效（下次重装会再问，而原有的冲突内容这次就已去掉），并建议选完全覆盖。

本安装器另外要查的冲突：无。

## 通用步骤

1. **定目录**：只在项目级安装时做；用户级不定目录、不对齐，装出的 skill 运行时按所在项目的约定找。
   开发计划文档目录项目已有约定的沿用；查不到约定、而已装的旧 skill 里写着目录的，沿用旧值（见「重装」）；
   都没有用默认的 `docs/plans/`。只确定目录，不改文件。
2. **写入 skill**：`agent-plan-write`、`agent-plan-exec` 两个都执行所在宿主安装节里的 `cp`，已有的整份覆盖。
3. **对齐目录**：只在项目级安装、且目录不是默认的 `docs/plans/` 时做。改的是**项目里已写入的那两份** skill，
   不是 `$TEMPLATE_DIR` 里的模板。先把两份里「开发计划文档目录默认 `docs/plans/`，项目已有自己的约定时按项目的。」
   整句改成「本项目的开发计划文档目录是 `<实际目录>`。」；再把其余出现的 `docs/plans/` 改成实际目录，
   包括 frontmatter 的 `description`，其它路径不动。
4. **告知用户**：除各安装节列的外，说明重装时保留的只有项目级安装时填写的开发计划文档目录。

## Claude Code 项目级安装（默认）

```bash
top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/skills/agent-plan-write .claude/skills/agent-plan-exec
cp "$TEMPLATE_DIR/agent-plan-write/SKILL.template.md" .claude/skills/agent-plan-write/SKILL.md
cp "$TEMPLATE_DIR/agent-plan-exec/SKILL.template.md" .claude/skills/agent-plan-exec/SKILL.md
```

**告知用户**：`.claude/skills/agent-plan-write/` 与 `.claude/skills/agent-plan-exec/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。
装好后可用 `/agent-plan-write`、`/agent-plan-exec` 调用，也会按描述自动触发；
如未生效，重启 Claude Code。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
: "${TEMPLATE_DIR:?}"
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/agent-plan-write" "$C/skills/agent-plan-exec"
cp "$TEMPLATE_DIR/agent-plan-write/SKILL.template.md" "$C/skills/agent-plan-write/SKILL.md"
cp "$TEMPLATE_DIR/agent-plan-exec/SKILL.template.md" "$C/skills/agent-plan-exec/SKILL.md"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；开发计划文档目录由 skill 在各项目里
按项目约定判断。如未生效，重启 Claude Code。

## Codex 项目级安装（默认）

```bash
top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
: "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/agent-plan-write .agents/skills/agent-plan-exec
cp "$TEMPLATE_DIR/agent-plan-write/SKILL.template.md" .agents/skills/agent-plan-write/SKILL.md
cp "$TEMPLATE_DIR/agent-plan-exec/SKILL.template.md" .agents/skills/agent-plan-exec/SKILL.md
```

**告知用户**：`.agents/skills/agent-plan-write/` 与 `.agents/skills/agent-plan-exec/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 的项目要为这两处加例外。
装好后可用 `$agent-plan-write`、`$agent-plan-exec` 调用，也会按描述自动触发；
开启新会话后生效。

## Codex 用户级安装

```bash
: "${TEMPLATE_DIR:?}"
D1="$HOME/.agents/skills/agent-plan-write"
D2="$HOME/.agents/skills/agent-plan-exec"
mkdir -p "$D1" "$D2"
cp "$TEMPLATE_DIR/agent-plan-write/SKILL.template.md" "$D1/SKILL.md"
cp "$TEMPLATE_DIR/agent-plan-exec/SKILL.template.md" "$D2/SKILL.md"
```

**告知用户**：说明实际写入的用户级配置目录；开发计划文档目录由 skill 在各项目里按项目约定判断。
开启新会话后生效。

## 重装

不判断版本，只比内容。目标里已有本安装器装过的内容（这次是重装）时，先**只读地比对**：按安装步骤推出这次会写出的每个文件，与现有文件逐个比；定制值所列位置的差异不算，缺文件算有差异。只有全部一致才算无变更，汇报「无需更新」后结束，不做「写入前检查」、不写任何文件；有差异、判不了、拿不准一律算有变更，不再判断、无条件重装：依次做下面四件事（有变更的重装仍要先过「写入前检查」，其中的软链、冲突、手改要问用户的照问）：

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

本安装器的定制值：

- 开发计划文档目录（项目级安装）：旧 skill 里「本项目的开发计划文档目录是 …」一句写的目录，没有这一句就是默认的 `docs/plans/`；
  由第 1 步按「项目约定 → 旧值 → 默认」重新确定，第 3 步填回。
- 用户级安装：无。

## 现状与预期不符时

下列情况，以及各节指明要按本节处理的情形，**停下来问用户**，不要照写、照删，也不要自行修复：

- 要写入、替换或删除的路径不是普通文件 / 目录（「写入前检查」里说明不查的配置目录等除外），最常见的是软链：写入会写穿到它指向的那份，删除或整份替换会让那份从此脱钩，都不报错。
  用户同意写进软链指向的那份时，只原地修改它，不先删后建，也不整份替换链接本身。
- 安装步骤里的命令报错退出、拒绝写入。
- 按安装步骤与项目现状确定不了要写什么、写到哪。
