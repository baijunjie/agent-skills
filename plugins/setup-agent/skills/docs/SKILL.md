---
name: docs
description: 装上（或更新）agent-docs skill 与 map-writer、product-writer、memory-writer 三个子代理：总索引、项目地图、产品文档与开发记忆的读写规则，以及代码注释规范。默认装进当前项目随仓库提交，也可安装到用户级配置、对当前用户环境中的所有项目生效。用于"给这个项目配文档规范""初始化项目文档结构""给这个项目配开发记忆""让 agent 维护文档""更新项目里的 agent-docs skill""全局装文档规范"等场景。
disable-model-invocation: true
---

# 安装项目文档规范

装两样东西：`agent-docs` skill（读写规则与注释规范）与 `map-writer`、`product-writer`、`memory-writer`
三个子代理。装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

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
TEMPLATE_DIR="$SETUP_ROOT/skills/docs/template"
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

本安装器另外要查的冲突：

- **这一项不按冲突问**：当前宿主用户级指令文件（项目级安装时），或这次作用域的指令文件（项目级是项目根目录的 `CLAUDE.md` / `AGENTS.md`，用户级是用户级配置目录下的）里已有同类规则（注释规范或文档读写规则）的，不改它，告知用户两份都会生效、内容差在哪。

## 通用步骤

1. **定文档位置**：只在项目级安装时做。总索引、项目地图、产品文档、开发记忆四处，项目已有约定（已有对应的文件或目录）的沿用；
   项目里查不到、而已装的旧 skill 与子代理里写着位置的，那就是上次定下的，沿用它（见「重装」）；都没有则用默认的
   `docs/README.md`（总索引）、`docs/project-map.md`、`docs/product/`、`docs/memory/`。
2. **写入 skill**：执行所在宿主安装节里的 `cp`，已有的整份覆盖。项目级安装时，旧 skill 末尾有「本项目」一节的，
   先把它读出来再覆盖（见「重装」）。
3. **装子代理**：三个都装，已有的整份覆盖；Codex 用渲染脚本的 `--replace` 替换同名旧 `.toml`，
   目标是软链时它会整批拒绝写入。
4. **建骨架**：只在项目级安装时做。缺总索引就建一个只有一行标题（如 `# 总索引`）的骨架。其它目录与文档有内容再建，
   不要预建空目录或占位文档。项目已有散落的文档时，按类归位是另一件事，要不要一起做交给用户定。
5. **对齐项目**：只在项目级安装时做。
   - 四处文档位置（`docs/README.md`、`docs/project-map.md`、`docs/product/`、`docs/memory/`）里与默认不同的那几处，
     把 skill 与三个子代理定义里它们的默认位置出现的地方改成第 1 步定下的位置，与默认相同的不动；包括 frontmatter 的 `description`（Codex 改生成的 `.toml` 里的 `description` 与 `developer_instructions`）。
     `docs/` 作为文档目录根出现时（如「`docs/` 下的其它文档」），改成总索引所在的目录。
     skill 里「表中位置是默认值，项目对文档目录已有自己的约定时按项目的。」这一句随之改成
     「表中位置是本项目的文档位置。」。
   - 项目另有与通用规则不同的约定（来自项目里的规范文档，或用户交代），在 skill 末尾加一节 `## 本项目` 写进去，
     一条一行，写清它取代或补充的是哪条通用规则，行末注明出处：规范文档的路径 + 章节标题原文；用户口头交代的写「用户交代」。
     不改通用正文，一条都没有就不加这一节。已写在项目指令文件里的约定不要再抄一遍。
6. **告知用户**：除各安装节列的外，说明重装时保留的只有项目级安装时填写的文档位置与 skill 末尾的「本项目」一节，
   项目特有的约定请写进「本项目」一节。

用户级安装不定文档位置、不建骨架、不对齐项目：装出的 skill 不属于某个项目，文档位置在运行时按所在项目的约定判断，
没有约定用默认的。

## Claude Code 项目级安装（默认）

```bash
top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/skills/agent-docs .claude/agents
cp "$TEMPLATE_DIR/agent-docs.md" .claude/skills/agent-docs/SKILL.md
cp "$TEMPLATE_DIR/agents/map-writer.md" "$TEMPLATE_DIR/agents/product-writer.md" \
  "$TEMPLATE_DIR/agents/memory-writer.md" .claude/agents/
```

**告知用户**：`.claude/skills/agent-docs/` 与 `.claude/agents/` 下的三个子代理要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。
开发记忆（第 1 步定下的目录）按随仓库提交设计；用户不打算提交的，告知用户这样队友读不到，不主动改 `.gitignore`。
装好后可用 `/agent-docs` 调用，也会按描述自动触发；重启 Claude Code 后生效。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
: "${TEMPLATE_DIR:?}"
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/agent-docs" "$C/agents"
cp "$TEMPLATE_DIR/agent-docs.md" "$C/skills/agent-docs/SKILL.md"
cp "$TEMPLATE_DIR/agents/map-writer.md" "$TEMPLATE_DIR/agents/product-writer.md" \
  "$TEMPLATE_DIR/agents/memory-writer.md" "$C/agents/"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；没有建任何项目文档，
文档位置由 skill 在各项目里按项目约定判断。重启 Claude Code 后生效。

## Codex 项目级安装（默认）

```bash
top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/agent-docs .codex/agents
cp "$TEMPLATE_DIR/agent-docs.md" .agents/skills/agent-docs/SKILL.md
python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/map-writer.md" \
  "$TEMPLATE_DIR/agents/product-writer.md" "$TEMPLATE_DIR/agents/memory-writer.md"
```

**告知用户**：`.agents/skills/agent-docs/` 与 `.codex/agents/` 下的三个 `.toml` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 或 `.codex/` 的项目要为这两处加例外。
开发记忆（第 1 步定下的目录）按随仓库提交设计；用户不打算提交的，告知用户这样队友读不到，不主动改 `.gitignore`。
装好后可用 `$agent-docs` 调用，也会按描述自动触发；开启新会话后生效。

## Codex 用户级安装

```bash
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
D="$HOME/.agents/skills/agent-docs"
X=${CODEX_HOME:-$HOME/.codex}
mkdir -p "$D" "$X/agents"
cp "$TEMPLATE_DIR/agent-docs.md" "$D/SKILL.md"
python3 "$RENDER_AGENT" --replace --output-dir "$X/agents" "$TEMPLATE_DIR/agents/map-writer.md" \
  "$TEMPLATE_DIR/agents/product-writer.md" "$TEMPLATE_DIR/agents/memory-writer.md"
```

**告知用户**：说明实际写入的用户级配置目录；没有建任何项目文档，文档位置由 skill 在各项目里按项目约定判断。
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

- 文档位置（项目级安装）：总索引、项目地图、产品文档、开发记忆四处的路径，旧 skill 与子代理里写的就是上次定下的
  （旧 skill 里写着「表中位置是本项目的文档位置。」时，表中位置就是旧值）。
  第 1 步按「项目约定 → 旧值 → 默认」重新确定，第 5 步填回 skill 与三个子代理；作为目录根出现的位置随总索引所在的目录而定，不单独读。
- skill 末尾的「本项目」一节（项目级安装）：第 2 步覆盖前读出，第 5 步按每条的出处判断——有文档出处的按现状重查，
  文档还在、约定还成立的沿用，已不存在的去掉；出处为「用户交代」的原样沿用。
- 用户级安装：无。

## 现状与预期不符时

下列情况，以及各节指明要按本节处理的情形，**停下来问用户**，不要照写、照删，也不要自行修复：

- 要写入、替换或删除的路径不是普通文件 / 目录。最常见的是软链：写入会写穿到它指向的地方，删掉或整份替换的
  只是链接本身、原来链向的那份从此脱钩，而且这几种情况表面上都不报错。
- 安装步骤里的命令报错退出、拒绝写入。
