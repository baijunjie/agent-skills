#!/usr/bin/env python3
"""把安装器源文件展开成 plugins/setup-<领域>/skills/<skill>/SKILL.md。

源文件是 sources/<领域>-<skill>.md，公共片段是 fragments/<片段名>.md。语法只有两样，不支持条件与循环：
  {{include: 片段名}}   独占一行，替换为该片段内容；行首有缩进时片段每一行都补上同样的缩进，
                        以便放进列表项里的代码块；片段里也可以再 include 别的片段
  {{变量}}              替换为变量值；多行的变量值不补缩进，只能用在行首不缩进的行里

片段文件开头可以有一段只给维护者看的说明（首行恰为 <!--，到恰为 --> 的行为止），读入时去掉，不进生成物。

变量有四个来源：
  DEFAULTS    各安装器没声明时的回退值，INSTALLERS 可以覆盖
  按文件名推导 skill（skill 目录名）、name（源文件名；skill-targets 用它作装出的 skill 名和模板文件名）、
              marker（`setup-<领域>:<skill>`，指令文件里本安装器那对标记的名字）
  SCOPES      作用域决定的 description 措辞 scope_lead / scope_tail
  INSTALLERS  以源文件名为键，值为 (作用域, 变量)，只声明各安装器有差异的变量；
              不得声明推导出的与作用域决定的变量。正文要原样输出 {{…}} 占位符时，也经这里声明的变量输出

include 先于变量展开，所以片段里也能用变量。变量值要用 fragments/ 里的文案时经 fragment() 读进来，
这种值同样展开其中的变量，但不能再 include，也不能引用另一个经 fragment() 注入的变量。

用法：
  build.py           写出全部生成物
  build.py --check   生成物与源文件不一致时非零退出
"""
# 构建时的校验清单，按类别分组；任一项不过就报错退出。新增或修改校验时同步改这里与 tools/tests/build/。
#
# 展开
#   - include 的片段不存在、循环 include；fragment() 引用的片段不存在，或 lead 不是空白
#   - 未声明的变量；行首有缩进的行里引用了多行的变量值；去掉变量引用后行里仍有 {{ 或 }}。
#     报错指出出自源文件还是片段及其行号；经 fragment() 注入的片段同样逐行检查
#   - 经 fragment() 注入的片段里有 {{include: …}}，或引用了另一个经 fragment() 注入的变量
#   - 片段开头的说明块没有独占一行的 -->
#
# 登记与命名
#   - sources/ 下有没在 INSTALLERS 登记的源文件，或登记的源文件不存在
#   - plugins/setup-*/skills/ 下有不对应登记源文件的目录（含只剩 template/ 的残留目录），
#     或散落的普通文件（名为 .DS_Store 的跳过）
#   - 源文件名不是 <领域>-<skill>
#   - fragments/ 下有没被任何源文件 include、也没经 fragment() 引用的片段（全部安装器渲染完后查）
#
# INSTALLERS 声明
#   - scope 不是 SCOPES 里的作用域；声明了推导出的或作用域决定的变量
#   - 声明的变量在展开后的正文与注入的片段里都没被引用（DEFAULTS 有回退值也不豁免）
#   - template_sub 不匹配 TEMPLATE_SUB（须带前导 /、不带末尾 /，各段不能是 . 或 ..）
#   - extra_env 非空却不以换行开头，或有不是 <变量>="<值>" 的行；正文用到的 plugin 资源变量
#     （RESOURCE_USE：RENDER_* 与以 _DIR / _ROOT 结尾的大写名，含 ${…} 写法）既不在 BASE_VARS、
#     也没在正文里赋值、又没在 extra_env 里定义，或 extra_env 定义的变量在正文里没用到
#
# 模板
#   - TEMPLATE_DIR（template/ 加 template_sub）不存在
#   - include 了 skill-targets，template/<name>.md 却不存在
#   - 正文用 cat "$TEMPLATE_DIR/<文件>" >> 整块追加的模板不存在、不叫 INJECT.md，或首行不是空行
#   - TEMPLATE_DIR 下带 frontmatter name 的 *.md 模板（即装出的 skill），bash 代码块里没有装到 skills/<name> 的命令
#
# frontmatter
#   - 源文件或生成物首行不是 ---，或其后没有独占一行的结尾 ---；顶层键出现不止一次
#   - 源文件缺少 description；description 不以 {{scope_lead}} 开头，或 {{scope_tail}} 引用次数不是一次；
#     {{scope_tail}} 之后不是紧接末尾的「用于……等场景。」这一句（写成 {{scope_tail}}用于，其后到结尾的
#     「等场景。」之间不能再有「。」）
#   - description 去掉 {{scope_lead}} / {{scope_tail}} 后超过 DESC_LIMIT 个字符
#   - 源文件没有 disable-model-invocation: true
#   - 生成物的 description 含「: 」「 #」、以「:」结尾，或以 YAML 指示字符（YAML_INDICATORS）开头
#   - 生成物的 name 与所在目录名不一致
#   - agents/openai.yaml 不存在或有用制表符缩进的行；顶层 policy: 块的直接子键里没有
#     allow_implicit_invocation: false，或这个直接子键出现了不止一次（别的块下或更深一层的不算）
#
# 作用域
#   - project-user 的源文件没有 include scope-select（按展开结果计，手写「## 选作用域」不算），
#     或别的作用域的源文件 include 了它
#   - 代码块之外提到「项目级」「用户级」的 ## / ### 标题（行首缩进 0–3 个空格也算）不是整行合乎
#     PROJECT_SECTION / USER_SECTION 的写法
#   - 代码块之外的二级标题在生成物里重复（去掉行首缩进与末尾闭合的 # 后比较）
#   - 正文缺少该作用域必需的「## 选作用域」/ 项目级安装节 / 用户级安装节，或含不该有的
#   - 源文件或生成物结尾有未闭合的代码块围栏（围栏配对规则见 FENCE）
#
# 片段放法
#   - host-conventions、pre-write、reinstall、state-mismatch 没有在源文件顶层（不缩进）各直接 include 恰好一次
#   - 除 REPEATABLE 外，任一片段在一个安装器的展开结果里出现不止一次（直接、缩进、经别的片段，
#     还是经 fragment() 注入都算）
#   - setup-tools 的源文件（tools-*）include 了 skill-targets
#   - host-conventions 所在的节（其前最近的代码块之外的「## 」标题）不是「## 跨宿主约定」
#   - 顶层直接 include 的 markers 在 pre-write 之后
#   - pre-write / reinstall 之后的第一个非空行不以 FOLLOWED_BY 规定的开头起头
#
# 标记
#   - 源文件里手写了形似 setup 标记的文字（正文里的标记须写 {{marker}}）
#   - 生成物或该 skill 的 template/ 下的文件里有形似 setup 标记（LOOSE_MARKER）却不合 MARKER 格式的，
#     或标记名不等于 marker
#   - template/ 下某个文件的标记不是 begin、end 各一个且 begin 在前，也不是都没有（生成物不查成对：
#     那里的标记出现在命令里）
#   - 写指令文件（源文件含 {{marker}}，或 template/ 里有本安装器的标记）却没有在顶层 include markers，
#     或 include 了 markers 却不写指令文件
#   - template/ 里带本安装器成对标记的文件，标记范围内最浅的标题不是一级
#
# 步骤引用
#   - 生成物里「第 N 步」「第 N–M 步」「第 N、M 步」中的任一数字大于代码块之外编号列表项的最大序号。
#     只是最大步号检查：抓得出指向不存在步骤的引用，不保证指向的是正确的那一步
#
# 替换表（表头整行为「| 位置 | 原文 | 改成 |」，被改写的模板是 TEMPLATE_DIR 下的 <name>.md）
#   - 有替换表，被改写的模板却不存在
#   - 某行不是三列，或「位置」里没有「」
#   - 「位置」里每段「」在模板里不是恰好一个列表项（「- 」开头的行）以它开头
#   - 「原文」里每段「」在模板里不是恰好出现一次，或「位置」只有一段时不落在那一项里
#     （该项算到下一个缩进不深于它的非空行为止）。「改成」不查
#   - 「位置」有多段「」时，后一段锚定的列表项不在前一段之后；写了「共 N 条」而首尾锚点之间
#     （含首尾）与首个锚点同级的列表项不是 N 条
#
# 命令块
#   - 生成物里用到 $TEMPLATE_DIR 或 extra_env 定义的变量（含 ${…} 写法）的 bash 代码块，在第一次用到之前没有
#     `: "${<变量>:?}"` 守卫（以「: 」开头、含 "${<变量>:?…}" 的行，可与别的变量合写一行，不含 # 之后的注释，守卫之前的部分也不能含 #（包括 ${A#x} 这类展开）；内联在 cp 等命令里的 :? 不算守卫，须单独成行）；
#     报错指出生成物里该块的起始行与变量名。只查围栏信息串恰为 bash 的块（生成物里只有 bash 与 markdown 两种），正文里提到的这些变量不查
#   - 生成物里出现 Codex 用户级 skill 的旧位置（CODEX_SKILL_DIR：$X/skills、$CODEX_HOME/skills、.codex/skills 等）；
#     用户级 skill 固定写 $HOME/.agents/skills/<名>，项目级的 .agents/skills 与 .codex/agents 不受影响
#
# 文案
#   - sources/ 与 fragments/ 的文件里出现 BANNED_WORDS 里的说法（如「告诉用户」，见 docs/decisions.md「固定用语」）；
#     templates 里的不查
#
# 写出
#   - 写出前先渲染并校验全部安装器，任一报错就一个生成物都不写
#   - --check 按字节比较生成物（只是换行被改成 CRLF 也算不一致）；源文件与片段读入时 CRLF 与单独的 CR 都归一成 LF
#
# 不校验、靠维护者自觉：
#   - host-conventions、markers 以外各片段的放置位置与适用的源文件（见各片段文件开头的说明）；
#     pre-write / reinstall 之后只查第一个非空行的开头
#   - subagent_rule 只声明给装子代理的安装器；subagent-rule 直接 include 只用于装子代理的源文件
#   - description 里 {{scope_tail}} 以外只写本安装器独有的内容，且只写装出什么、用于什么场景
#     （长度由 DESC_LIMIT 兜底，写的是不是处理细节查不出来）
#   - reinstall 之后的定制值逐项写明从哪读、何时填回；装出的模板里待填位置写明记录什么、来自哪里
#   - #### 及更深的标题不参与作用域检查；「## 步骤」这类不提「项目级」「用户级」的标题不报错，只是不算安装节
#   - 用户级安装节是否 Claude Code、Codex 两个宿主都写了
#   - project-root 是否真放在要在仓库根目录执行的命令块里
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent


# 被 include 或经 fragment() 引用过的片段名，用来找出没人用的孤立片段。
USED_FRAGMENTS: set[str] = set()


class Fragment(str):
    """经 fragment() 读进变量值的片段。渲染时按出处逐行做变量与残留检查，再展开其中的变量，最后接上 lead。"""

    name: str
    lead: str
    offset: int


def read_fragment(path: Path) -> tuple[str, int]:
    """片段原文去掉开头的说明块，连同被去掉的行数（报错时据此指回片段文件里的原始行号）。

    说明块只给维护者看：首行恰为 `<!--`，到第一个恰为 `-->` 的行为止，其后紧跟的一个空行一并去掉，
    都不进生成物。只认独占一行的 `<!--`，片段正文以带内容的 HTML 注释（如 setup 标记）开头时不受影响。
    """
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    if lines[0] != "<!--":
        return text, 0
    if "-->" not in lines[1:]:
        sys.exit(f"build.py: fragments/{path.name} 开头的说明块没有独占一行的 -->")
    skip = lines.index("-->", 1) + 1
    if skip < len(lines) and lines[skip] == "":
        skip += 1
    return "\n".join(lines[skip:]), skip


def fragment(name: str, lead: str = "") -> Fragment:
    """读出片段原文，供变量值使用：文案留在 fragments/ 里维护，不写进本脚本。

    lead 是接在片段之前的空白：变量接在某行句末时，靠它决定与前文同行（空格）还是另起一行（换行），
    片段本身不带首尾空白，变量为空时才不留多余的空白。
    """
    path = HERE / "fragments" / f"{name}.md"
    if not path.is_file():
        sys.exit(f"build.py: 变量引用的片段不存在 {name}")
    if lead.strip():
        sys.exit(f"build.py: fragment({name}) 的 lead 只能是空白")
    USED_FRAGMENTS.add(name)
    text, offset = read_fragment(path)
    value = Fragment(text.strip("\n"))
    value.name = name
    value.lead = lead
    value.offset = offset
    return value


# 安装器调用渲染脚本时需要的额外环境变量，接在 TEMPLATE_DIR 之后。
RENDER_AGENT = '\nRENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"'
RENDER_RULES = '\nRENDER_RULES="$SETUP_ROOT/scripts/render-subagent-rules.py"'
RENDER_STYLE = '\nRENDER_STYLE="$SETUP_ROOT/scripts/render-report-style.py"'
# 回退闸门的脚本由 setup-git 的 pr 与 worktree 两个安装器共用，放在 plugin 级 scripts/ 下。
GATE_DIR = '\nGATE_DIR="$SETUP_ROOT/scripts/githooks"'

# 各安装器没声明时取这里的值。
DEFAULTS = {
    "template_sub": "",  # TEMPLATE_DIR 在 skills/<skill>/template 下的子目录，带前导 /
    "extra_env": "",  # host-conventions 末尾追加的变量定义：渲染脚本的 RENDER_*、共用资源的 GATE_DIR 等
    "subagent_rule": "",  # skill-priority 里接在 skill 优先级后的子代理优先级说明
}

DERIVED = ("skill", "name", "marker")

# 作用域 -> (scope_lead, scope_tail, 正文须否含「## 选作用域」、项目级安装节、用户级安装节)。
# scope_lead 接在 description 开头、后面紧跟要装的东西；scope_tail 是独立成句的作用域说明，
# 放在「用于……等场景」之前。后三列是 check_scope 的期望：True 必须有，False 不得有。
SCOPES = {
    "project": ("给当前项目装上（或更新）", "只装进当前项目，随仓库提交。", False, True, False),
    "project-user": (
        "装上（或更新）",
        "默认装进当前项目随仓库提交，也可安装到用户级配置、对当前用户环境中的所有项目生效。",
        True,
        True,
        True,
    ),
    "user": ("在当前用户环境装上（或更新）", "装进用户级配置，对当前用户环境中的所有项目生效。", False, False, True),
}
SCOPE_VARS = ("scope_lead", "scope_tail")

SCOPE_SELECT = re.compile(r"^ {0,3}## 选作用域$")
# 安装节标题只认 `## [Claude Code |Codex ]项目级安装[（默认）]` 与对应的用户级，不按子串匹配。
# 提到「项目级」「用户级」的二级、三级标题都须整行合乎这两种写法，否则报错：换个写法
# （「## 项目级安装（可选）」「### 项目级安装」「## 用户级配置安装」）就能把安装节藏过作用域检查，
# 「## 不做项目级安装」之类的标题也会被误当成安装节的意思。
PROJECT_SECTION = re.compile(r"^## (?:Claude Code |Codex )?项目级安装(?:（默认）)?$")
USER_SECTION = re.compile(r"^## (?:Claude Code |Codex )?用户级安装$")
SECTION_WORDS = ("项目级", "用户级")
# 行首缩进 0–3 个空格仍是 Markdown 标题；缩进的安装节标题不合上面两种写法，会被当成写法不对报错。
SECTION_HEADING = re.compile(r"^ {0,3}###?[ \t]")
LEVEL2_HEADING = re.compile(r"^ {0,3}##[ \t]")
# 任意层级的 ATX 标题，取出 # 的个数判断层级。
ATX_HEADING = re.compile(r"^ {0,3}(#{1,6})[ \t]")
# 代码块围栏：开头那行定下符号（` 或 ~）与长度，只有同一符号、不短于它、其后只有空白的行才收尾。
# 缩进不限，列表项里的代码块也算。
FENCE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")
# 每一段都不能是 . 或 ..：TEMPLATE_DIR 不得跳出 template/。
TEMPLATE_SUB = re.compile(r"^(/(?!\.\.?(/|$))[\w.-]+)+$")
# extra_env 里每一行都是一条变量定义，值写成双引号字符串；正文用 $GATE_DIR 或 ${RENDER_X…} 这样引用。
ENV_DEFINITION = re.compile(r'^(\w+)="[^"\n]*"$')
# 指向 plugin 内资源的变量：RENDER_* 与以 _DIR / _ROOT 结尾的大写名。正文用到这类变量，
# 要么在 BASE_VARS 里，要么正文自己赋了值，否则必须在 extra_env 里声明——不然生成物里它是空的。
# 这项校验按命名认人：新加的 plugin 资源变量必须叫 RENDER_* 或以 _DIR / _ROOT 结尾，否则绕得过去。
RESOURCE_USE = re.compile(r"\$\{?(RENDER_\w+|[A-Z][A-Z0-9_]*_(?:DIR|ROOT))\b")
# host-conventions 定义的、宿主提供的，以及正文按「有就用、没有就默认」读的宿主环境变量。
BASE_VARS = {"TEMPLATE_DIR", "SETUP_ROOT", "SKILL_DIR", "PLUGIN_ROOT", "CLAUDE_PLUGIN_ROOT",
             "CLAUDE_CONFIG_DIR"}
# 正文自己赋过值的变量不算（如 `PROJECT_ROOT=$(git rev-parse --show-toplevel)`），
# 但只认 bash 代码块里的赋值：散文里顶格写一行 `X=…` 就能豁免掉这项校验。
LOCAL_ASSIGN = re.compile(r"^[ \t]*(\w+)=", re.MULTILINE)
# 不加引号的 YAML 标量不能以这些字符开头。
YAML_INDICATORS = set("-?:,[]{}#&*!|>'\"%@`")

# description 里作者自己写的部分（去掉 {{scope_lead}} / {{scope_tail}} 两处作用域措辞）的字符数上限。
# 安装器都是 disable-model-invocation: true、Codex 侧也关了隐式调用，只能由用户手动调用，description
# 不参与自动触发匹配，是用户在安装器列表里挑它时看的一句话：说清装出什么、装到哪、用于什么场景就够，
# 裁剪逻辑、条件分支、安装步骤这些处理细节写进正文。120 是现有 15 个安装器重写后的实际上限，
# 再长就说明细节又写回 description 了。
DESC_LIMIT = 120

# 源文件名 -> (作用域, 变量)。生成物路径、skill、name、marker 都由源文件名推导，这里只写各安装器真正不同的。
INSTALLERS = {
    "agent-plan": ("project-user", {}),
    "agent-bug": ("project-user", {}),
    "agent-change-check": (
        "project-user",
        {"extra_env": RENDER_AGENT, "subagent_rule": fragment("subagent-rule", lead="\n")},
    ),
    "agent-subagents": (
        "project-user",
        {
            "extra_env": RENDER_AGENT + RENDER_RULES,
            # 原文里的占位符本身就是 {{HOST_AGENT_CONFIGURATION}}，经变量输出以绕开语法检查。
            "host_agent_token": "{{HOST_AGENT_CONFIGURATION}}",
        },
    ),
    "agent-docs": (
        "project-user",
        {"extra_env": RENDER_AGENT, "subagent_rule": fragment("subagent-rule", lead="\n")},
    ),
    "agent-report-style": ("project-user", {"extra_env": RENDER_STYLE}),
    "agent-unit-test": ("project", {"extra_env": RENDER_AGENT}),
    "agent-workflow": ("project", {}),
    "git-commit": ("project-user", {}),
    "git-find-issues": ("project-user", {}),
    # 模板里的占位符本身就是 {{PR_BASE}}，经变量输出以绕开语法检查。
    "git-pr": ("project", {"pr_base_token": "{{PR_BASE}}", "extra_env": GATE_DIR,
                           "gate_peer": "setup-git:worktree", "gate_entry_ref": "「装回退闸门」里"}),
    "git-worktree": ("project", {"extra_env": GATE_DIR,
                                 "gate_peer": "setup-git:pr", "gate_entry_ref": "第 7 步"}),
    "knowledge-i18n-copy": ("project-user", {}),
    "tools-cron": ("project", {"template_sub": "/cron"}),
    "tools-codex-bridge": ("user", {"template_sub": "/claude"}),
}

INCLUDE = re.compile(r"^([ \t]*)\{\{include:\s*([\w-]+)\s*\}\}[ \t]*$")

# 每个源文件都要直接 include 的片段；markers 只有往指令文件写内容的才 include。
REQUIRED_INCLUDES = ("host-conventions", "pre-write", "reinstall", "state-mismatch")
# 在一个安装器的展开结果里可以出现多次的片段；其余片段不论直接还是经别的片段 include，都至多一次。
REPEATABLE = ("project-root",)
# 这两个片段之后的第一段必须是源文件补充的本安装器专属内容。
FOLLOWED_BY = {"pre-write": "本安装器另外要查的冲突：", "reinstall": "本安装器的定制值："}
VARIABLE = re.compile(r"\{\{(\w+)\}\}")
MARKER = re.compile(r"<!-- (setup-[\w-]+:[\w-]+):(begin|end) -->")
# 宽松匹配：凡是像 setup 标记开头的都要能按 MARKER 严格匹配，以抓出少空格、大小写不对、
# 连字符写成冒号或下划线、拼错 begin/end 之类的坏标记。
LOOSE_MARKER = re.compile(r"<!--\s*setup[-:_]", re.I)
# 正文里的步骤引用：「第 3 步」「第 2–4 步」「第 5、6 步」，取其中全部数字。
STEP_REF = re.compile(r"第 ?\d+(?: ?[–、] ?\d+)* ?步")
NUMBERED_ITEM = re.compile(r"^[ \t]*(\d+)\.[ \t]")
# 把模板整块追加进指令文件的命令：cat "$TEMPLATE_DIR/<文件>" >> <指令文件>。
APPEND_TEMPLATE = re.compile(r'cat "\$TEMPLATE_DIR/([^"]+)"[ \t]*>>')
# 写进指令文件（CLAUDE.md / AGENTS.md）的模板固定叫这个名字。
INJECT_TEMPLATE = "INJECT.md"
# 「位置」里写成「共 N 条」的区间条数断言，N 写阿拉伯数字或一到十。
RANGE_COUNT = re.compile(r"共 ?([0-9]+|[一二三四五六七八九十]) ?条")
CN_DIGITS = {c: i for i, c in enumerate("一二三四五六七八九十", start=1)}
# 替换表：表头整行是「| 位置 | 原文 | 改成 |」的 Markdown 表格，可以缩进放进列表项。
TABLE_ROW = re.compile(r"^[ \t]*\|(.*)\|[ \t]*$")
REPLACEMENT_HEADER = ["位置", "原文", "改成"]
LIST_ITEM = re.compile(r"^([ \t]*)- ")
# bash 代码块里对 TEMPLATE_DIR 与 extra_env 定义的变量的使用与守卫，按变量名套进这两个模板。
# 守卫行本身也含 ${<变量>:?}，须先按守卫认。
VAR_USE = r"\$(?:{var}\b|\{{{var}\b)"
VAR_GUARD = r'^[ \t]*: [^#]*"\$\{{{var}:\?[^}}]*\}}"'
# Codex 用户级 skill 不在 $CODEX_HOME（缺省 ~/.codex）下：凡是这个目录下的 skills 都是旧位置。
# 「.codex}」是 ${CODEX_HOME:-$HOME/.codex}/skills 的写法。
# 变量后可带 :-默认值 / :?提示，也可带引号：${X:?}/skills、"$X"/skills、"$HOME/.codex"/skills。
CODEX_SKILL_DIR = re.compile(r'(?:\$\{?(?:X|CODEX_HOME)(?::?[-?=+][^}]*)?\}?|\.codex\}?)"?/skills\b')
# 已禁用的说法 -> 改用什么。固定用语见 docs/decisions.md「固定用语」。
BANNED_WORDS = {"告诉用户": "按停不停改成「汇报」「告知用户」或「交给用户定」"}


def locate(name: str) -> tuple[str, str]:
    """源文件名 <领域>-<skill> -> (plugin 目录名, skill 目录名)。领域名不含连字符，按第一个连字符切分。"""
    domain, sep, skill = name.partition("-")
    if not sep or not skill:
        sys.exit(f"{name}: 源文件名须为 <领域>-<skill>")
    return f"setup-{domain}", skill


def target_of(name: str) -> Path:
    plugin, skill = locate(name)
    return REPO / "plugins" / plugin / "skills" / skill / "SKILL.md"


def frontmatter(name: str, text: str, where: str) -> str:
    """首行 --- 与其后第一个独占一行的 --- 之间的内容。

    没有闭合的 --- 时报错：否则 frontmatter 会一直延伸到正文，正文里碰巧写的 name: / description:
    也会被当成 frontmatter 的键。
    """
    lines = text.split("\n")
    if lines[0] != "---":
        sys.exit(f"{name}: {where}首行必须是 ---")
    try:
        closing = lines.index("---", 1)
    except ValueError:
        sys.exit(f"{name}: {where}的 frontmatter 没有独占一行的结尾 ---")
    return "\n".join(lines[1:closing])


def check_keys(name: str, front: str, where: str) -> None:
    """frontmatter 的顶层键各恰好出现一次。

    YAML 对重复键取最后一个值且多数解析器不报错：后面再写一行 disable-model-invocation: false
    就会悄悄打开隐式调用，而只找「有没有 true 那一行」的检查照样通过。
    """
    keys = Counter(m.group(1) for m in re.finditer(r"^([\w-]+):(?=\s|$)", front, re.M))
    for key, count in sorted(keys.items()):
        if count > 1:
            sys.exit(f"{name}: {where}的 frontmatter 里 {key} 出现了 {count} 次，每个键只能写一次")


def check_plain_scalar(name: str, front: str) -> None:
    """生成物的 description 须是合法的 YAML 不加引号的标量。

    值里有「: 」会被当成嵌套映射、「 #」之后会被当成注释截掉，以指示字符开头的会被解析成别的结构或直接报错；
    宿主解析失败时整个 skill 加载不了。只查不加引号的写法：源文件的 description 须以 {{scope_lead}} 开头，
    加不了引号。
    """
    m = re.search(r"^description: (.*)$", front, re.M)
    value = m.group(1) if m else ""
    if ": " in value or " #" in value or value.endswith(":"):
        sys.exit(f"{name}: 生成物的 description 含「: 」「 #」或以「:」结尾，YAML 会解析错，改写成不含它们（中文冒号「：」可以）")
    if value[:1] in YAML_INDICATORS:
        sys.exit(f"{name}: 生成物的 description 以 YAML 指示字符 {value[0]} 开头，改写开头")


def check_frontmatter(name: str, text: str) -> None:
    """源文件的 frontmatter：键不重复、作用域措辞不手抄、安装器禁止隐式调用。"""
    front = frontmatter(name, text, "源文件")
    check_keys(name, front, "源文件")
    m = re.search(r"^description: (.*)$", front, re.M)
    if not m:
        sys.exit(f"{name}: 源文件缺少 description")
    desc = m.group(1)
    if not desc.startswith("{{scope_lead}}") or desc.count("{{scope_tail}}") != 1:
        sys.exit(f"{name}: description 须以 {{{{scope_lead}}}} 开头并引用一次 {{{{scope_tail}}}}")
    # scope_tail 本身以「。」收尾，之后只能是最后一句「用于……等场景。」，不能再接别的句子
    _, _, tail = desc.partition("{{scope_tail}}用于")
    if not tail.endswith("等场景。") or "。" in tail[:-1]:
        sys.exit(f"{name}: description 的 {{{{scope_tail}}}} 须紧接末尾的「用于……等场景。」这一句，写成 {{{{scope_tail}}}}用于……")
    own = len(desc.replace("{{scope_lead}}", "").replace("{{scope_tail}}", ""))
    if own > DESC_LIMIT:
        sys.exit(
            f"{name}: description 去掉作用域措辞后有 {own} 个字符，超过 {DESC_LIMIT}；"
            "安装器只能由用户手动调用，description 只给人挑安装器时看，只写装出什么、用于什么场景，"
            "处理细节写进正文"
        )
    if not re.search(r"^disable-model-invocation: true$", front, re.M):
        sys.exit(f"{name}: 源文件 frontmatter 须有 disable-model-invocation: true")
    openai = target_of(name).parent / "agents" / "openai.yaml"
    if not openai.is_file():
        sys.exit(f"{name}: 缺少 {openai.relative_to(REPO)}")
    values = policy_implicit_values(name, openai.relative_to(REPO), openai.read_text(encoding="utf-8"))
    if len(values) > 1:
        sys.exit(f"{name}: {openai.relative_to(REPO)} 的 policy: 块里 allow_implicit_invocation 出现了不止一次")
    if values != ["false"]:
        sys.exit(f"{name}: {openai.relative_to(REPO)} 须设 policy.allow_implicit_invocation: false")


def policy_implicit_values(name: str, where: Path, yaml: str) -> list[str]:
    """顶层 policy: 块的直接子键 allow_implicit_invocation 的取值，按出现顺序。

    直接子键指缩进等于块内最小缩进的行；别的块里、或更深一层的同名键都不算，否则写在
    interface: 下或嵌套在别的键里也能蒙混过关。取最小缩进而不是第一行的缩进：第一行缩进更深时
    YAML 会直接报错，不能让它把后面真正的直接子键当成更深一层放过去。
    """
    block: list[str] = []
    in_policy = False
    for lineno, line in enumerate(yaml.split("\n"), 1):
        if "\t" in line[: len(line) - len(line.lstrip())]:
            sys.exit(f"{name}: {where} 第 {lineno} 行用制表符缩进，YAML 只允许空格缩进")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[0].isspace():
            in_policy = re.match(r"^policy:\s*(#.*)?$", line) is not None
            continue
        if in_policy:
            block.append(line)
    if not block:
        return []
    child = min(len(line) - len(line.lstrip()) for line in block)
    return [
        m.group(1)
        for line in block
        if len(line) - len(line.lstrip()) == child
        and (m := re.match(r"^\s+allow_implicit_invocation:\s*(\S*?)\s*(#.*)?$", line))
    ]


def outside_fences(name: str, lines: list[str], where: str) -> list[int]:
    """不在代码块里的行的下标；围栏行本身也算在代码块里。

    结尾仍有未闭合的围栏时报错：否则其后的内容全被当成代码块，标题检查就看不到它们。
    """
    out, opener, opened_at = [], "", 0
    for index, line in enumerate(lines):
        m = FENCE.match(line)
        if opener:
            if m and m.group(1)[0] == opener[0] and len(m.group(1)) >= len(opener) and not m.group(2).strip():
                opener = ""
        elif m:
            opener, opened_at = m.group(1), index
        else:
            out.append(index)
    if opener:
        sys.exit(f"{name}: {where}第 {opened_at + 1} 行的代码块围栏 {opener} 到结尾都没有闭合")
    return out


def headings(name: str, text: str) -> list[str]:
    """代码块之外的二级、三级标题行。"""
    lines = text.split("\n")
    return [lines[i].rstrip() for i in outside_fences(name, lines, "生成物") if SECTION_HEADING.match(lines[i])]


def check_scope(name: str, scope: str, text: str) -> None:
    """正文的节须与作用域一一对应：该有的安装节必须有，不该有的不能有。"""
    expected = SCOPES[scope][2:]
    found = headings(name, text)
    for h in found:
        if any(word in h for word in SECTION_WORDS) and not (PROJECT_SECTION.match(h) or USER_SECTION.match(h)):
            sys.exit(
                f"{name}: 标题 {h} 提到了项目级或用户级，须整行写成 ## [Claude Code |Codex ]项目级安装[（默认）]"
                " 或 ## [Claude Code |Codex ]用户级安装"
            )
    # 按 Markdown 的标题文字比较：去掉行首缩进与末尾可选的闭合 #，「  ## X」「## X ##」都算「## X」
    level2 = [re.sub(r"[ \t]+#+$", "", h.strip()) for h in found if LEVEL2_HEADING.match(h)]
    for h, count in Counter(level2).items():
        if count > 1:
            sys.exit(f"{name}: 代码块之外的二级标题 {h} 出现了 {count} 次")
    actual = tuple(any(p.match(h) for h in found) for p in (SCOPE_SELECT, PROJECT_SECTION, USER_SECTION))
    labels = ("「## 选作用域」", "项目级安装节", "用户级安装节")
    for label, want, has in zip(labels, expected, actual):
        if want != has:
            sys.exit(f"{name}: 作用域为 {scope}，正文{'须含' if want else '不得含'}{label}")


def bash_blocks(text: str):
    """逐个 yield 围栏信息串恰为 bash 的代码块正文（不含围栏行）。"""
    opener, buffer, is_bash = "", [], False
    for line in text.split("\n"):
        m = FENCE.match(line)
        if opener:
            if m and m.group(1)[0] == opener[0] and len(m.group(1)) >= len(opener) and not m.group(2).strip():
                if is_bash:
                    yield "\n".join(buffer)
                opener, buffer = "", []
            elif is_bash:
                buffer.append(line)
        elif m:
            opener, buffer = m.group(1), []
            is_bash = m.group(2).strip() == "bash"


def check_extra_env(name: str, extra_env: str, text: str) -> None:
    """extra_env 定义的变量与正文里用到的 plugin 资源变量（RENDER_* 与 *_DIR / *_ROOT）须一一对应。

    extra_env 由 host-conventions 无条件引用，「声明了却没引用」的通用检查对它永远不触发，所以在这里按
    变量名双向比对。它接在 TEMPLATE_DIR 那行末尾，非空时须以换行开头，否则第一条定义会粘在那一行上。
    """
    if extra_env and not extra_env.startswith("\n"):
        sys.exit(f"{name}: extra_env 须以换行开头，否则会接在 TEMPLATE_DIR 那一行末尾")
    defined = set()
    for line in extra_env.split("\n")[1:]:
        m = ENV_DEFINITION.match(line)
        if not m:
            sys.exit(f'{name}: extra_env 里每一行都须是 <变量>="<值>" 的定义，现在有：{line}')
        defined.add(m.group(1))
    assigned = set()
    for block in bash_blocks(text):
        assigned |= set(LOCAL_ASSIGN.findall(block))
    used = {m.group(1) for m in RESOURCE_USE.finditer(text)}
    for var in sorted(used - defined - BASE_VARS - assigned):
        sys.exit(f"{name}: 正文用到了 ${var}，INSTALLERS 的 extra_env 却没有定义它")
    for var in sorted(defined):
        if not re.search(rf"\$\{{?{var}\b", text):
            sys.exit(f"{name}: extra_env 定义了 {var}，正文却没有用到")


def check_markers(name: str, marker: str, text: str, where: str, paired: bool) -> bool:
    """标记名都须等于 marker；返回 text 里有没有标记。

    paired 时 begin / end 要么各恰好一个且 begin 在前，要么都没有。只对 template/ 开：生成物里的标记
    出现在 awk 正则、printf 字面量等命令里，个数与顺序不代表装出的结果。
    """
    for m in LOOSE_MARKER.finditer(text):
        if not MARKER.match(text, m.start()):
            line = text.count("\n", 0, m.start()) + 1
            sys.exit(f"{name}: {where}第 {line} 行的 setup 标记格式不对，须为 <!-- setup-<领域>:<skill>:begin|end -->")
    kinds = []
    for m in MARKER.finditer(text):
        if m.group(1) != marker:
            sys.exit(f"{name}: {where}里的标记 {m.group(1)} 与本安装器的标记名 {marker} 不一致")
        kinds.append(m.group(2))
    if paired and kinds not in ([], ["begin", "end"]):
        sys.exit(f"{name}: {where}里的标记须为 begin、end 各一个且 begin 在前，现在依次是 {'、'.join(kinds)}")
    return bool(kinds)


def check_marked_heading_level(name: str, text: str, where: str) -> None:
    """模板里标记范围内最浅的标题须是一级。

    markers 片段约定写进指令文件的内容顶层节标题用 `#`：顶层写成 `##` 的话，装出来这一节会挂到
    指令文件上一个 `#` 节底下成为它的子节，而指令文件里不报错、也看不出来。
    """
    lines = text.split("\n")
    begin = end = None
    for index, line in enumerate(lines):
        m = MARKER.search(line)
        if m and m.group(2) == "begin":
            begin = index
        elif m and m.group(2) == "end":
            end = index
    if begin is None or end is None:
        return
    span = lines[begin + 1 : end]
    levels = [
        (index, len(ATX_HEADING.match(span[index]).group(1)))
        for index in outside_fences(name, span, where)
        if ATX_HEADING.match(span[index])
    ]
    if not levels:
        return
    top = min(level for _, level in levels)
    if top != 1:
        index = next(i for i, level in levels if level == top)
        sys.exit(
            f"{name}: {where}标记范围里最浅的标题是 {top} 级（第 {begin + 2 + index} 行 "
            f"{span[index].strip()}），写进指令文件的内容顶层节标题须用 #"
        )


def check_step_refs(name: str, text: str) -> None:
    """「第 N 步」里的 N 不能超过正文中编号列表项的最大序号。

    步骤重排或删减后旧引用最常见的失效方式是指向不存在的步骤，按最大序号查就能抓住，又不必判断
    引用属于哪个列表（一个安装器常有多个编号列表）。指向存在但不对的步骤查不出来。
    """
    lines = text.split("\n")
    top = max(
        (int(m.group(1)) for i in outside_fences(name, lines, "生成物") if (m := NUMBERED_ITEM.match(lines[i]))),
        default=0,
    )
    for m in STEP_REF.finditer(text):
        if max(int(n) for n in re.findall(r"\d+", m.group(0))) > top:
            line = text.count("\n", 0, m.start()) + 1
            sys.exit(f"{name}: 生成物第 {line} 行引用了「{m.group(0)}」，正文编号列表最大只到第 {top} 步")


def quoted(cell: str) -> list[str]:
    """单元格里最外层「」括起的文字；允许嵌套，内层的「」算作文字的一部分。"""
    out, depth, start = [], 0, 0
    for i, ch in enumerate(cell):
        if ch == "「":
            if depth == 0:
                start = i + 1
            depth += 1
        elif ch == "」" and depth:
            depth -= 1
            if depth == 0:
                out.append(cell[start:i])
    return out


def item_spans(template: str) -> list[tuple[str, int, int, int]]:
    """模板里每个列表项的 (去掉「- 」后的首行, 起点, 终点, 缩进)，终点前是该项连同其下更深缩进的行与空行。"""
    lines = template.split("\n")
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line) + 1)
    spans = []
    for i, line in enumerate(lines):
        m = LIST_ITEM.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        end = i + 1
        while end < len(lines) and (not lines[end].strip() or len(lines[end]) - len(lines[end].lstrip()) > indent):
            end += 1
        spans.append((line[m.end() :], offsets[i], offsets[end], indent))
    return spans


def check_replacements(name: str, text: str, template_path: Path) -> None:
    """替换表里引用的模板原文必须真实存在：装出时照表改模板，原文对不上就会悄悄漏改。

    「位置」列里每段「」是列表项的开头，模板里须恰好有一个列表项以它开头；「原文」列里每段「」须在模板里
    恰好出现一次，「位置」只有一段时还须落在那一项里。「改成」列不查。

    「位置」给出多段「」时是一段区间（「从以 A 开头的那条起，到以 B 开头的那条为止」）：后一个锚点须在前一个之后，
    写了「共 N 条」就按区间内与首个锚点同级的列表项核对条数——往区间中间插一条、或把其中一条移出去，
    装出时照旧会被整体换掉，而正文还写着原来的条数，两边都不报错。
    """
    lines = text.split("\n")
    rows, in_table = [], False
    for i in outside_fences(name, lines, "生成物"):
        m = TABLE_ROW.match(lines[i])
        cells = [c.strip() for c in m.group(1).split("|")] if m else []
        if cells == REPLACEMENT_HEADER:
            in_table = True
        elif not m:
            in_table = False
        elif in_table and not set("".join(cells)) <= set("-: "):
            rows.append((i + 1, cells))
    if not rows:
        return
    if not template_path.is_file():
        sys.exit(f"{name}: 正文有替换表，替换的模板 {template_path.relative_to(REPO)} 却不存在")
    template = template_path.read_text(encoding="utf-8")
    spans = item_spans(template)
    where = template_path.relative_to(REPO)
    for lineno, cells in rows:
        if len(cells) != 3:
            sys.exit(f"{name}: 生成物第 {lineno} 行的替换表行须有 位置 / 原文 / 改成 三列")
        anchors = quoted(cells[0])
        if not anchors:
            sys.exit(f"{name}: 生成物第 {lineno} 行替换表的「位置」须用「」写出所在列表项的开头")
        items = []
        for anchor in anchors:
            found = [span for span in spans if span[0].startswith(anchor)]
            if len(found) != 1:
                sys.exit(f"{name}: 生成物第 {lineno} 行替换表的位置「{anchor}」在 {where} 里有 {len(found)} 个列表项以它开头，须恰好一个")
            items.append(found[0])
        for i, (earlier, later) in enumerate(zip(items, items[1:])):
            if later[1] <= earlier[1]:
                sys.exit(
                    f"{name}: 生成物第 {lineno} 行替换表的位置「{anchors[i + 1]}」"
                    f"在 {where} 里不在「{anchors[i]}」那一条之后"
                )
        declared = RANGE_COUNT.search(cells[0])
        if declared and len(items) > 1:
            n = declared.group(1)
            count = int(n) if n.isdigit() else CN_DIGITS[n]
            inside = [s for s in spans if items[0][1] <= s[1] <= items[-1][1] and s[3] == items[0][3]]
            if len(inside) != count:
                sys.exit(
                    f"{name}: 生成物第 {lineno} 行替换表写的是「{declared.group(0)}」，"
                    f"{where} 里从「{anchors[0]}」到「{anchors[-1]}」之间（含首尾）却有 {len(inside)} 条同级列表项"
                )
        for original in quoted(cells[1]):
            count = template.count(original)
            if count != 1:
                sys.exit(f"{name}: 生成物第 {lineno} 行替换表的原文「{original}」在 {where} 里出现了 {count} 次，须恰好一次")
            at = template.index(original)
            if len(items) == 1 and not items[0][1] <= at < items[0][2]:
                sys.exit(f"{name}: 生成物第 {lineno} 行替换表的原文「{original}」不在以「{anchors[0]}」开头的那一项里")


def template_skill_name(path: Path) -> str:
    """模板 frontmatter 里的 name，没有 frontmatter 或没有 name 时为空串。"""
    lines = path.read_text(encoding="utf-8").split("\n")
    if lines[0] != "---" or "---" not in lines[1:]:
        return ""
    m = re.search(r"^name: (.*)$", "\n".join(lines[1 : lines.index("---", 1)]), re.M)
    return m.group(1).strip() if m else ""


def bash_lines(text: str) -> list[str]:
    """生成物里全部 bash 代码块内的行（不含围栏本身）。"""
    out, opener, is_bash = [], "", False
    for line in text.split("\n"):
        m = FENCE.match(line)
        if opener:
            if m and m.group(1)[0] == opener[0] and len(m.group(1)) >= len(opener) and not m.group(2).strip():
                opener = ""
            elif is_bash:
                out.append(line)
        elif m:
            opener, is_bash = m.group(1), m.group(2).strip() == "bash"
    return out


def check_appended_templates(name: str, text: str, template_dir: Path) -> None:
    """被 `cat "$TEMPLATE_DIR/<文件>" >> <指令文件>` 整块追加的模板，首行必须是空行。

    文件名固定 INJECT.md：这个目录下别的模板装的是 skill、子代理、输出风格，看名字就得分得出哪份会被
    写进 CLAUDE.md / AGENTS.md。经渲染脚本写进去的（如 setup-agent:subagents）同名，但不走这条命令，
    这里查不到，靠约定。
    markers 片段约定这种模板「以空行开头」：没有它，追加时 begin 标记会贴在指令文件原有的最后一行下面，
    粘连前面的段落、列表与表格，而重装时按「新建的文件删掉开头的空行」又找不到那一行。两头都不报错。
    """
    for rel in APPEND_TEMPLATE.findall("\n".join(bash_lines(text))):
        tpl = template_dir / rel
        if not tpl.is_file():
            sys.exit(f"{name}: 正文要追加的模板 {(template_dir / rel).relative_to(REPO)} 不存在")
        if tpl.name != INJECT_TEMPLATE:
            sys.exit(f"{name}: 写进指令文件的模板要命名为 {INJECT_TEMPLATE}，现在是 {tpl.name}")
        if not tpl.read_text(encoding="utf-8").startswith("\n"):
            sys.exit(f"{name}: 模板 {tpl.relative_to(REPO)} 被整块追加进指令文件，首行必须是空行")


def check_installed_skill_names(name: str, text: str, template_dir: Path) -> None:
    """装出的 skill 模板的 frontmatter name 与安装命令里的目录名必须一致。

    TEMPLATE_DIR 下直接放着的带 frontmatter name 的 `*.md` 就是要装成 skill 的模板，装到的目录名必须是那个 name——
    两个宿主都只按目录名找 skill。改了模板的 name 而没改安装命令（或反过来），装出的 skill 不报错、只是不被触发，
    指令文件里指向它的入口也跟着指空。子目录下的子代理、输出风格模板装到别处，不在此列。
    """
    commands = "\n".join(bash_lines(text))
    for tpl in sorted(template_dir.glob("*.md")):
        skill_name = template_skill_name(tpl)
        if not skill_name:
            continue
        # 只看 bash 代码块：正文散文里也会提到 skills/<name>（如「告知用户」那几条），
        # 拿整份生成物去找，只改安装命令、散文照旧的改法就蒙过去了。
        # 后面不接名字字符，否则 skills/<name> 会被 skills/<name>-x 这样的另一个目录名蒙过去。
        if not re.search(rf"skills/{re.escape(skill_name)}(?![\w-])", commands):
            sys.exit(
                f"{name}: 模板 {tpl.relative_to(REPO)} 的 frontmatter name 是 {skill_name}，"
                f"bash 代码块里却没有装到 skills/{skill_name} 的命令"
            )


def check_env_guards(name: str, text: str, extra_env: str) -> None:
    """用到 $TEMPLATE_DIR 或 extra_env 里定义的变量的 bash 代码块，须在第一次用到之前先 `: "${<变量>:?}"`。

    这些变量只在 host-conventions 那一块里定义，命令块分开执行时它们是空的，cp "$TEMPLATE_DIR/x" 会去读根目录下的
    /x，渲染脚本也会读错文件，都不一定报错；守卫让它在空时立刻失败。
    """
    checks = {}
    for var in ["TEMPLATE_DIR", *(m.group(1) for m in map(ENV_DEFINITION.match, extra_env.split("\n")[1:]) if m)]:
        checks[var] = (re.compile(VAR_GUARD.format(var=var)), re.compile(VAR_USE.format(var=var)))
    lines = text.split("\n")
    opener, start, guarded, is_bash = "", 0, set(), False
    for index, line in enumerate(lines):
        m = FENCE.match(line)
        if opener:
            if m and m.group(1)[0] == opener[0] and len(m.group(1)) >= len(opener) and not m.group(2).strip():
                opener = ""
            elif is_bash:
                for var, (guard, use) in checks.items():
                    if var in guarded:
                        continue
                    if guard.match(line):
                        guarded.add(var)
                    elif use.search(line):
                        sys.exit(
                            f'{name}: 生成物第 {start + 1} 行起的 bash 代码块在第 {index + 1} 行用到 ${var} 之前'
                            f'没有 : "${{{var}:?}}" 守卫'
                        )
        elif m:
            opener, start, guarded = m.group(1), index, set()
            is_bash = m.group(2).strip() == "bash"


def check_codex_skill_dir(name: str, text: str) -> None:
    """Codex 用户级 skill 固定装到 $HOME/.agents/skills，见 docs/decisions.md。"""
    for m in CODEX_SKILL_DIR.finditer(text):
        line = text.count("\n", 0, m.start()) + 1
        sys.exit(f"{name}: 生成物第 {line} 行写了 {m.group(0)}，Codex 用户级 skill 固定装到 $HOME/.agents/skills/<名>")


def check_banned_words() -> None:
    """sources/ 与 fragments/ 里不得出现已禁用的说法。"""
    for path in sorted((HERE / "sources").glob("*.md")) + sorted((HERE / "fragments").glob("*.md")):
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for word, fix in BANNED_WORDS.items():
                if word in line:
                    sys.exit(f"{path.relative_to(HERE)} 第 {lineno} 行用了「{word}」，{fix}（见 docs/decisions.md「固定用语」）")


def check_contract(name: str, text: str) -> set[str]:
    """源文件里公共片段的放法：必需的片段各直接 include 一次，位置与紧随其后的专属段落合乎约定。

    返回直接 include 的片段名，供 render 判断用了标记的安装器有没有 include markers。
    """
    lines = text.split("\n")
    positions: dict[str, list[int]] = {}
    for index, line in enumerate(lines):
        m = INCLUDE.match(line)
        if m and not m.group(1):
            positions.setdefault(m.group(2), []).append(index)
    for frag in REQUIRED_INCLUDES:
        if len(positions.get(frag, [])) != 1:
            sys.exit(f"{name}: 源文件须在顶层直接 include 一次 {frag}")
    for index, line in enumerate(lines, 1):
        if LOOSE_MARKER.search(line):
            sys.exit(f"{name}: 源文件第 {index} 行手写了 setup 标记，正文里的标记须写 <!-- {{{{marker}}}}:begin|end -->")
    at = {frag: found[0] for frag, found in positions.items()}

    unfenced = outside_fences(name, lines, "源文件")
    heading = next(
        (lines[i] for i in reversed(unfenced) if i < at["host-conventions"] and lines[i].startswith("## ")), None
    )
    if heading != "## 跨宿主约定":
        sys.exit(f"{name}: host-conventions 须放在「## 跨宿主约定」之下，现在所在的节是 {heading}")
    if "markers" in at and at["markers"] > at["pre-write"]:
        sys.exit(f"{name}: markers 须放在 pre-write 之前")
    for frag, lead in FOLLOWED_BY.items():
        following = next((line for line in lines[at[frag] + 1 :] if line.strip()), "")
        if not following.startswith(lead):
            sys.exit(f"{name}: {frag} 之后的第一段须以「{lead}」开头，没有的写「无」")
    return set(at)


def substitute(name: str, lines: list[tuple[str, str]], variables: dict) -> str:
    """检查每行的变量都已声明、没有残留的 {{ 或 }}，再替换变量。"""
    # 变量值本身可以含 {{（如模板里的占位符），所以残留检查放在替换之前，先剔除合法的变量引用
    for line, origin in lines:
        for key in VARIABLE.findall(line):
            if key not in variables:
                sys.exit(f"{name}: 未声明的变量 {key}，{origin}：{line.strip()}")
            # 替换只是字符串替换，多行值的后续行不会补上这一行的缩进，放进列表项会跑出列表
            if line[:1].isspace() and "\n" in variables[key]:
                sys.exit(f"{name}: 缩进的行里不能引用多行的变量 {key}，{origin}：{line.strip()}")
        if "{{" in VARIABLE.sub("", line) or "}}" in VARIABLE.sub("", line):
            sys.exit(f"{name}: 残留 {{{{ 或 }}}}，{origin}：{line.strip()}")
    return "\n".join(VARIABLE.sub(lambda m: variables[m.group(1)], line) for line, _ in lines)


def expand(name: str, rel: str, via: str, stack: tuple, includes: Counter) -> list[tuple[str, str]]:
    """展开 include，返回 (行, 出处) 列表；出处用于报错时指回源文件或片段的原始行。

    includes 累计每个片段被 include 的次数，不论直接还是经别的片段。
    """
    path = HERE / rel
    if not path.is_file():
        sys.exit(f"{name}: 片段不存在 {Path(rel).stem}（{via}）")
    if rel in stack:
        sys.exit(f"{name}: 循环 include {' -> '.join(stack + (rel,))}")
    if rel.startswith("fragments/"):
        text, offset = read_fragment(path)
        lines = text.rstrip("\n").split("\n")
    else:
        offset = 0
        lines = path.read_text(encoding="utf-8").split("\n")
    out = []
    for lineno, line in enumerate(lines, 1 + offset):
        origin = f"{rel} 第 {lineno} 行" + (f"（{via}引入）" if via else "")
        m = INCLUDE.match(line)
        if not m:
            out.append((line, origin))
            continue
        indent, frag = m.groups()
        USED_FRAGMENTS.add(frag)
        includes[frag] += 1
        for sub, sub_origin in expand(name, f"fragments/{frag}.md", f"{rel} 第 {lineno} 行", stack + (rel,), includes):
            out.append((indent + sub if sub else sub, sub_origin))
    return out


def render(name: str, scope: str, declared: dict) -> str:
    if scope not in SCOPES:
        sys.exit(f"{name}: 未知作用域 {scope}")
    for key in declared:
        if key in SCOPE_VARS or key in DERIVED:
            sys.exit(f"{name}: {key} 由作用域或源文件名决定，不能在 INSTALLERS 里声明")
    if "template_sub" in declared and not TEMPLATE_SUB.match(declared["template_sub"]):
        sys.exit(f"{name}: template_sub 须形如 /<目录>[/<目录>…]，带前导 /、不带末尾 /，各段不能是 . 或 ..，现在是 {declared['template_sub']!r}")
    rel = f"sources/{name}.md"
    source = (HERE / rel).read_text(encoding="utf-8")
    check_frontmatter(name, source)
    included = check_contract(name, source)
    includes: Counter = Counter()
    lines = expand(name, rel, "", (), includes)
    injected = {key: value for key, value in declared.items() if isinstance(value, Fragment)}
    # 经 fragment() 注入的片段同样落进正文，与直接 include 一起计数，免得同一段文字出现两遍
    for value in injected.values():
        includes[value.name] += 1
    for frag, count in sorted(includes.items()):
        if count > 1 and frag not in REPEATABLE:
            sys.exit(f"{name}: {frag} 在展开结果里被 include 了 {count} 次，只能一次")
    if scope == "project-user" and not includes["scope-select"]:
        sys.exit(f"{name}: 作用域为 project-user，须 include scope-select")
    if scope != "project-user" and includes["scope-select"]:
        sys.exit(f"{name}: 作用域为 {scope}，不得 include scope-select")
    if name.startswith("tools-") and includes["skill-targets"]:
        sys.exit(f"{name}: setup-tools 装出的 skill 不带领域前缀，不能 include skill-targets")

    for key, value in injected.items():
        for lineno, line in enumerate(value.split("\n"), 1 + value.offset):
            if INCLUDE.match(line):
                sys.exit(f"{name}: 经 fragment() 注入的片段不能 include，fragments/{value.name}.md 第 {lineno} 行（变量 {key}）")
            for ref in VARIABLE.findall(line):
                if ref in injected:
                    sys.exit(
                        f"{name}: 经 fragment() 注入的片段不能引用另一个注入的变量 {ref}，"
                        f"fragments/{value.name}.md 第 {lineno} 行（变量 {key}）"
                    )
    referenced = {key for line, _ in lines for key in VARIABLE.findall(line)}
    referenced |= {key for value in injected.values() for key in VARIABLE.findall(value)}
    for key in declared:
        if key not in referenced:
            sys.exit(f"{name}: INSTALLERS 声明的变量 {key} 在展开后的正文里没有被引用")

    plugin, skill = locate(name)
    marker = f"{plugin}:{skill}"
    variables = {**DEFAULTS, "skill": skill, "name": name, "marker": marker, **dict(zip(SCOPE_VARS, SCOPES[scope])), **declared}

    # 注入的片段只能引用普通变量，不能再引用另一个注入的片段
    plain = {key: value for key, value in variables.items() if key not in injected}
    for key, value in injected.items():
        origins = [
            (line, f"fragments/{value.name}.md 第 {lineno} 行（经变量 {key} 注入）")
            for lineno, line in enumerate(value.split("\n"), 1 + value.offset)
        ]
        variables[key] = value.lead + substitute(name, origins, plain)
    text = substitute(name, lines, variables)
    check_extra_env(name, variables["extra_env"], text)

    front = frontmatter(name, text, "生成物")
    check_keys(name, front, "生成物")
    check_plain_scalar(name, front)
    m = re.search(r"^name: (.*)$", front, re.M)
    if not m or m.group(1).strip() != skill:
        sys.exit(f"{name}: frontmatter 的 name 须为所在目录名 {skill}")
    check_scope(name, scope, text)
    check_markers(name, marker, text, "生成物", paired=False)
    # 写指令文件的安装器：源文件正文引用了 {{marker}}，或 template/ 里有本安装器的标记。
    # 按生成物判断不行——markers 片段自己就带 {{marker}}。
    writes_instruction_file = "{{marker}}" in source
    template = target_of(name).parent / "template"
    template_dir = Path(f"{template}{variables['template_sub']}")
    if not template_dir.is_dir():
        sys.exit(f"{name}: TEMPLATE_DIR 指向的目录不存在 {template_dir.relative_to(REPO)}")
    check_step_refs(name, text)
    check_env_guards(name, text, variables["extra_env"])
    check_codex_skill_dir(name, text)
    check_replacements(name, text, template_dir / f"{name}.md")
    check_installed_skill_names(name, text, template_dir)
    check_appended_templates(name, text, template_dir)
    if includes["skill-targets"]:
        if not (template / f"{name}.md").is_file():
            sys.exit(f"{name}: include 了 skill-targets，模板 {(template / f'{name}.md').relative_to(REPO)} 却不存在")
    for f in sorted(template.rglob("*")):
        # .DS_Store 由 Finder 自动生成、不进版本库，不按模板检查
        if f.is_file() and f.name != ".DS_Store":
            where = f"{f.relative_to(REPO)} "
            text_f = f.read_text(encoding="utf-8", errors="ignore")
            if check_markers(name, marker, text_f, where, paired=True):
                writes_instruction_file = True
                check_marked_heading_level(name, text_f, where)
    if writes_instruction_file and "markers" not in included:
        sys.exit(f"{name}: 源文件或 template/ 里有本安装器的标记，源文件却没有 include markers")
    if "markers" in included and not writes_instruction_file:
        sys.exit(f"{name}: include 了 markers，但源文件正文没有引用 {{{{marker}}}}、template/ 里也没有本安装器的标记")
    return text


def check_registry() -> None:
    sources = {p.stem for p in (HERE / "sources").glob("*.md")}
    for stem in sorted(sources - INSTALLERS.keys()):
        sys.exit(f"sources/{stem}.md 没有在 INSTALLERS 里登记")
    for stem in sorted(INSTALLERS.keys() - sources):
        sys.exit(f"INSTALLERS 登记的 {stem} 没有源文件 sources/{stem}.md")
    dirs = {target_of(n).parent for n in INSTALLERS}
    for path in sorted(REPO.glob("plugins/setup-*/skills/*")):
        # .DS_Store 由 Finder 自动生成、不进版本库，不算散落文件
        if path.name == ".DS_Store":
            continue
        if not path.is_dir():
            sys.exit(f"{path.relative_to(REPO)} 散落在 skills/ 下，skills/ 下只能是安装器目录")
        if path not in dirs:
            sys.exit(f"{path.relative_to(REPO)} 没有对应的登记源文件（安装器 SKILL.md 不得手写，残留目录要删掉）")


def check_orphans() -> None:
    """全部安装器渲染完后调用：fragments/ 下的片段都须被 include 或经 fragment() 引用过。"""
    for stem in sorted({p.stem for p in (HERE / "fragments").glob("*.md")} - USED_FRAGMENTS):
        sys.exit(f"fragments/{stem}.md 没有被任何源文件 include，也没有经 fragment() 引用")


def main() -> int:
    check = sys.argv[1:] == ["--check"]
    if sys.argv[1:] and not check:
        print(__doc__, file=sys.stderr)
        return 2
    check_registry()
    check_banned_words()
    # 全部渲染、校验通过后才写，免得后面的安装器报错时留下一半已更新的生成物
    outputs = [(target_of(name), render(name, scope, declared)) for name, (scope, declared) in INSTALLERS.items()]
    check_orphans()
    stale = []
    for path, content in outputs:
        if check:
            # 按字节比：read_text 会把 CRLF 归一成 LF，被改成 CRLF 的生成物就比不出来
            if not path.is_file() or path.read_bytes() != content.encode("utf-8"):
                stale.append(path.relative_to(REPO))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
    for target in stale:
        print(f"生成物过期：{target}（运行 tools/installer/build.py）", file=sys.stderr)
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
