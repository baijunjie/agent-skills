---
name: bug
description: 装上（或更新）agent-bug-report 与 agent-bug-fix 两个 skill，把缺陷记成工单、定位根因后修复。默认装进当前项目随仓库提交，也可安装到用户级配置、对当前用户环境中的所有项目生效。用于"给这个项目配 bug 工单流程""装 bug-report / bug-fix""全局装 bug skill"等场景。
disable-model-invocation: true
---

# 安装 bug 工单 skill

装 `agent-bug-report` 与 `agent-bug-fix` 两个 skill：前者把缺陷记成 bug 工单，
后者复现、定位根因后只改代码修复。装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

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
TEMPLATE_DIR="$SETUP_ROOT/skills/bug/template"
```

## 选作用域

**默认装进当前项目**，随仓库提交，团队共用。用户明确说了「全局 / 用户级 / 所有项目 / 新电脑」时，才装进用户级配置目录。
当前目录不是 git 仓库时，先告知用户，确认改装用户级后再装，不要直接写进用户级配置。

Claude Code 中同名 skill 是**用户级优先于项目级**，与「就近优先」的直觉相反。
所以要按项目定制的 skill，不要在用户级再装一份同名的。写入前发现另一层也有同名 skill 时，告知用户两份都在，Claude Code 实际生效的是用户级那份。

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

1. **定目录**：只在项目级安装时做。bug 工单目录项目已有约定的沿用；项目里查不到约定、而已装的旧 skill
   里写着目录的，那就是上次定下的，沿用它（见「重装」）；都没有则用默认的 `docs/bugs/`。
   只确定目录，不改文件。
2. **写入 skill**：`agent-bug-report`、`agent-bug-fix` 两个都执行所在宿主安装节里的 `cp`，已有的整份覆盖。
3. **对齐目录**：只在项目级安装时做。目录与默认的 `docs/bugs/` 不同时，改的是**项目里已写入的那两份** skill
   （不是 `$TEMPLATE_DIR` 里的模板），按顺序做：先把两份里「工单目录默认 `docs/bugs/`，项目已有自己的约定时按项目的。」
   整句改成「本项目的工单目录是 `<实际目录>`。」；再把其余出现的 `docs/bugs/` 改成实际目录，包括 frontmatter 的 `description`，其它路径不动。
4. **告知用户**：除各安装节列的外，说明重装时保留的只有项目级安装时填写的 bug 工单目录。

用户级安装不定目录、不对齐：bug 工单目录是所在项目的，装出的 skill 在运行时按项目的约定找，
没有约定用默认的 `docs/bugs/`。

## Claude Code 项目级安装（默认）

```bash
top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/skills/agent-bug-report .claude/skills/agent-bug-fix
cp "$TEMPLATE_DIR/agent-bug-report.md" .claude/skills/agent-bug-report/SKILL.md
cp "$TEMPLATE_DIR/agent-bug-fix.md" .claude/skills/agent-bug-fix/SKILL.md
```

**告知用户**：`.claude/skills/agent-bug-report/` 与 `.claude/skills/agent-bug-fix/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。
装好后可用 `/agent-bug-report`、`/agent-bug-fix` 调用，也会按描述自动触发；
如未生效，重启 Claude Code。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
: "${TEMPLATE_DIR:?}"
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/agent-bug-report" "$C/skills/agent-bug-fix"
cp "$TEMPLATE_DIR/agent-bug-report.md" "$C/skills/agent-bug-report/SKILL.md"
cp "$TEMPLATE_DIR/agent-bug-fix.md" "$C/skills/agent-bug-fix/SKILL.md"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；bug 工单目录由 skill 在各项目里
按项目约定判断。如未生效，重启 Claude Code。

## Codex 项目级安装（默认）

```bash
top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
: "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/agent-bug-report .agents/skills/agent-bug-fix
cp "$TEMPLATE_DIR/agent-bug-report.md" .agents/skills/agent-bug-report/SKILL.md
cp "$TEMPLATE_DIR/agent-bug-fix.md" .agents/skills/agent-bug-fix/SKILL.md
```

**告知用户**：`.agents/skills/agent-bug-report/` 与 `.agents/skills/agent-bug-fix/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 的项目要为这两处加例外。
装好后可用 `$agent-bug-report`、`$agent-bug-fix` 调用，也会按描述自动触发；
开启新会话后生效。

## Codex 用户级安装

```bash
: "${TEMPLATE_DIR:?}"
D1="$HOME/.agents/skills/agent-bug-report"
D2="$HOME/.agents/skills/agent-bug-fix"
mkdir -p "$D1" "$D2"
cp "$TEMPLATE_DIR/agent-bug-report.md" "$D1/SKILL.md"
cp "$TEMPLATE_DIR/agent-bug-fix.md" "$D2/SKILL.md"
```

**告知用户**：说明实际写入的用户级配置目录；bug 工单目录由 skill 在各项目里按项目约定判断。
开启新会话后生效。

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

- bug 工单目录（项目级安装）：旧 skill 里「本项目的工单目录是 …」一句写的目录，没有这一句就是默认的 `docs/bugs/`；
  由第 1 步按「项目约定 → 旧值 → 默认」重新确定，第 3 步填回。
- 用户级安装：无。

## 现状与预期不符时

下列情况，以及各节指明要按本节处理的情形，**停下来问用户**，不要照写、照删，也不要自行修复：

- 要写入、替换或删除的路径不是普通文件 / 目录。最常见的是软链：写入会写穿到它指向的地方，删掉或整份替换的
  只是链接本身、原来链向的那份从此脱钩，而且这几种情况表面上都不报错。
- 安装步骤里的命令报错退出、拒绝写入。
