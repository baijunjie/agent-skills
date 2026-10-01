#!/usr/bin/env python3
"""把安装器源文件展开成 plugins/setup-<领域>/skills/<skill>/SKILL.md。

源文件是 sources/<领域>-<skill>.md，公共片段是 fragments/<片段名>.md。语法只有两样：
  {{include: 片段名}}   独占一行，替换为该片段内容；行首有缩进时片段每一行都补上同样的缩进，
                        以便放进列表项里的代码块；片段里也可以再 include 别的片段
  {{变量}}              替换为变量值

变量有四个来源：
  DEFAULTS    各安装器没声明时的回退值，INSTALLERS 可以覆盖
  按文件名推导 skill（skill 目录名）、name（源文件名；skill-targets 用它作装出的 skill 名和模板文件名）、
              marker（`setup-<领域>:<skill>`，指令文件里本安装器那对标记的名字）
  SCOPES      作用域决定的 description 措辞 scope_lead / scope_tail
  INSTALLERS  各安装器声明的变量；不得声明推导出的与作用域决定的变量，声明了就报错

include 先于变量展开，所以片段里也能用变量。经 fragment() 读进变量值的片段同样展开其中的变量，
但不能再 include，也不能引用另一个经 fragment() 注入的变量。

构建时校验的完整清单只在仓库根目录 AGENTS.md「校验」节维护。写出前先渲染并校验全部安装器，
任一报错就一个文件都不写。

用法：
  build.py           写出全部生成物
  build.py --check   生成物与源文件不一致时非零退出
"""
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
    value = Fragment(path.read_text(encoding="utf-8").strip("\n"))
    value.name = name
    value.lead = lead
    return value


# 安装器调用渲染脚本时需要的额外环境变量，接在 TEMPLATE_DIR 之后。
RENDER_AGENT = '\nRENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"'
RENDER_RULES = '\nRENDER_RULES="$SETUP_ROOT/scripts/render-subagent-rules.py"'
RENDER_STYLE = '\nRENDER_STYLE="$SETUP_ROOT/scripts/render-report-style.py"'

# 各安装器没声明时取这里的值。
DEFAULTS = {
    "template_sub": "",  # TEMPLATE_DIR 在 skills/<skill>/template 下的子目录，带前导 /
    "extra_env": "",  # host-conventions 末尾追加的环境变量定义，调用渲染脚本的安装器用它追加 RENDER_*
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

SCOPE_SELECT = re.compile(r"^## 选作用域$")
# 安装节标题只认 `## [Claude Code |Codex ]项目级安装[（默认）]` 与对应的用户级，不按子串匹配。
# 提到「项目级安装」「用户级安装」的二级、三级标题都须整行合乎这两种写法，否则报错：换个写法
# （「## 项目级安装（可选）」「### 项目级安装」）就能把安装节藏过作用域检查，「## 不做项目级安装」
# 之类的标题也会被误当成安装节的意思。
PROJECT_SECTION = re.compile(r"^## (?:Claude Code |Codex )?项目级安装(?:（默认）)?$")
USER_SECTION = re.compile(r"^## (?:Claude Code |Codex )?用户级安装$")
SECTION_WORDS = ("项目级安装", "用户级安装")
SECTION_HEADING = re.compile(r"^###? ")
# 代码块围栏：开头那行定下符号（` 或 ~）与长度，只有同一符号、不短于它、其后只有空白的行才收尾。
# 缩进不限，列表项里的代码块也算。
FENCE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")
TEMPLATE_SUB = re.compile(r"^(/[\w.-]+)+$")
# extra_env 里每一行都是一条变量定义；正文用 $RENDER_X 或 ${RENDER_X…} 引用。
ENV_DEFINITION = re.compile(r"^(\w+)=")
RENDER_USE = re.compile(r"\$\{?(RENDER_\w+)")

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
    "git-pr": ("project", {"pr_base_token": "{{PR_BASE}}"}),
    "git-worktree": ("project", {}),
    "knowledge-i18n-copy": ("project-user", {}),
    "tools-cron": ("project", {"template_sub": "/cron"}),
    "tools-codex-bridge": ("user", {"template_sub": "/claude"}),
}

INCLUDE = re.compile(r"^([ \t]*)\{\{include:\s*([\w-]+)\s*\}\}[ \t]*$")

# 每个源文件都要直接 include 的片段；markers 只有往指令文件写内容的才 include。
REQUIRED_INCLUDES = ("host-conventions", "pre-write", "reinstall", "state-mismatch")
# 至多 include 一次的片段（不论直接还是经别的片段）。
AT_MOST_ONCE = ("scope-select",)
# 这两个片段之后的第一段必须是源文件补充的本安装器专属内容。
FOLLOWED_BY = {"pre-write": "本安装器另外要查的冲突：", "reinstall": "本安装器的定制值："}
VARIABLE = re.compile(r"\{\{(\w+)\}\}")
MARKER = re.compile(r"<!-- (setup-[\w-]+:[\w-]+):(begin|end) -->")
# 宽松匹配：凡是像 setup 标记开头的都要能按 MARKER 严格匹配，以抓出少空格、大小写不对、
# 连字符写成冒号或下划线、拼错 begin/end 之类的坏标记。
LOOSE_MARKER = re.compile(r"<!--\s*setup[-:_]", re.I)


def locate(name: str) -> tuple[str, str]:
    """源文件名 <领域>-<skill> -> (plugin 目录名, skill 目录名)。领域名不含连字符，按第一个连字符切分。"""
    domain, sep, skill = name.partition("-")
    if not sep or not skill:
        sys.exit(f"{name}: 源文件名须为 <领域>-<skill>")
    return f"setup-{domain}", skill


def target_of(name: str) -> Path:
    plugin, skill = locate(name)
    return REPO / "plugins" / plugin / "skills" / skill / "SKILL.md"


def check_frontmatter(name: str, text: str) -> None:
    """源文件的 frontmatter：作用域措辞不手抄、安装器禁止隐式调用。"""
    front = text.split("\n---\n", 1)[0]
    m = re.search(r"^description: (.*)$", front, re.M)
    if not m:
        sys.exit(f"{name}: 源文件缺少 description")
    desc = m.group(1)
    if not desc.startswith("{{scope_lead}}") or desc.count("{{scope_tail}}") != 1:
        sys.exit(f"{name}: description 须以 {{{{scope_lead}}}} 开头并引用一次 {{{{scope_tail}}}}")
    if "{{scope_tail}}用于" not in desc or not desc.endswith("等场景。"):
        sys.exit(f"{name}: description 的 {{{{scope_tail}}}} 须紧接末尾的「用于……等场景。」，写成 {{{{scope_tail}}}}用于……")
    if not re.search(r"^disable-model-invocation: true$", front, re.M):
        sys.exit(f"{name}: 源文件 frontmatter 须有 disable-model-invocation: true")
    openai = target_of(name).parent / "agents" / "openai.yaml"
    if not openai.is_file():
        sys.exit(f"{name}: 缺少 {openai.relative_to(REPO)}")
    if not policy_disables_implicit(openai.read_text(encoding="utf-8")):
        sys.exit(f"{name}: {openai.relative_to(REPO)} 须设 policy.allow_implicit_invocation: false")


def policy_disables_implicit(yaml: str) -> bool:
    """顶层 policy: 块（其后缩进的行）里有 allow_implicit_invocation: false；别的块里的同名键不算。"""
    in_policy = False
    for line in yaml.split("\n"):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[0].isspace():
            in_policy = re.match(r"^policy:\s*(#.*)?$", line) is not None
        elif in_policy and re.match(r"^\s+allow_implicit_invocation:\s*false\s*(#.*)?$", line):
            return True
    return False


def outside_fences(lines: list[str]) -> list[int]:
    """不在代码块里的行的下标；围栏行本身也算在代码块里。"""
    out, opener = [], ""
    for index, line in enumerate(lines):
        m = FENCE.match(line)
        if opener:
            if m and m.group(1)[0] == opener[0] and len(m.group(1)) >= len(opener) and not m.group(2).strip():
                opener = ""
        elif m:
            opener = m.group(1)
        else:
            out.append(index)
    return out


def headings(text: str) -> list[str]:
    """代码块之外的二级、三级标题行。"""
    lines = text.split("\n")
    return [lines[i].rstrip() for i in outside_fences(lines) if SECTION_HEADING.match(lines[i])]


def check_scope(name: str, scope: str, text: str) -> None:
    """正文的节须与作用域一一对应：该有的安装节必须有，不该有的不能有。"""
    expected = SCOPES[scope][2:]
    found = headings(text)
    for h in found:
        if any(word in h for word in SECTION_WORDS) and not (PROJECT_SECTION.match(h) or USER_SECTION.match(h)):
            sys.exit(
                f"{name}: 标题 {h} 提到了安装节，须整行写成 ## [Claude Code |Codex ]项目级安装[（默认）]"
                " 或 ## [Claude Code |Codex ]用户级安装"
            )
    actual = tuple(any(p.match(h) for h in found) for p in (SCOPE_SELECT, PROJECT_SECTION, USER_SECTION))
    labels = ("「## 选作用域」", "项目级安装节", "用户级安装节")
    for label, want, has in zip(labels, expected, actual):
        if want != has:
            sys.exit(f"{name}: 作用域为 {scope}，正文{'须含' if want else '不得含'}{label}")


def check_extra_env(name: str, extra_env: str, text: str) -> None:
    """extra_env 定义的变量与正文里用到的 $RENDER_* 须一一对应。

    extra_env 由 host-conventions 无条件引用，「声明了却没引用」的通用检查对它永远不触发，所以在这里按
    变量名双向比对。它接在 TEMPLATE_DIR 那行末尾，非空时须以换行开头，否则第一条定义会粘在那一行上。
    """
    if extra_env and not extra_env.startswith("\n"):
        sys.exit(f"{name}: extra_env 须以换行开头，否则会接在 TEMPLATE_DIR 那一行末尾")
    defined = set()
    for line in extra_env.split("\n")[1:]:
        m = ENV_DEFINITION.match(line)
        if not m:
            sys.exit(f"{name}: extra_env 里每一行都须是 <变量>=<值> 的定义，现在有：{line}")
        defined.add(m.group(1))
    used = set(RENDER_USE.findall(text))
    for var in sorted(used - defined):
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

    unfenced = outside_fences(lines)
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
        if "{{" in VARIABLE.sub("", line) or "}}" in VARIABLE.sub("", line):
            sys.exit(f"{name}: 残留 {{{{ 或 }}}}，{origin}：{line.strip()}")
    return "\n".join(VARIABLE.sub(lambda m: variables[m.group(1)], line) for line, _ in lines)


def expand(name: str, rel: str, via: str, stack: tuple) -> list[tuple[str, str]]:
    """展开 include，返回 (行, 出处) 列表；出处用于报错时指回源文件或片段的原始行。"""
    path = HERE / rel
    if not path.is_file():
        sys.exit(f"{name}: 片段不存在 {Path(rel).stem}（{via}）")
    if rel in stack:
        sys.exit(f"{name}: 循环 include {' -> '.join(stack + (rel,))}")
    text = path.read_text(encoding="utf-8")
    lines = text.rstrip("\n").split("\n") if rel.startswith("fragments/") else text.split("\n")
    out = []
    for lineno, line in enumerate(lines, 1):
        origin = f"{rel} 第 {lineno} 行" + (f"（{via}引入）" if via else "")
        m = INCLUDE.match(line)
        if not m:
            out.append((line, origin))
            continue
        indent, frag = m.groups()
        USED_FRAGMENTS.add(frag)
        for sub, sub_origin in expand(name, f"fragments/{frag}.md", f"{rel} 第 {lineno} 行", stack + (rel,)):
            out.append((indent + sub if sub else sub, sub_origin))
    return out


def render(name: str, scope: str, declared: dict) -> str:
    if scope not in SCOPES:
        sys.exit(f"{name}: 未知作用域 {scope}")
    for key in declared:
        if key in SCOPE_VARS or key in DERIVED:
            sys.exit(f"{name}: {key} 由作用域或源文件名决定，不能在 INSTALLERS 里声明")
    if "template_sub" in declared and not TEMPLATE_SUB.match(declared["template_sub"]):
        sys.exit(f"{name}: template_sub 须形如 /<目录>[/<目录>…]，带前导 /、不带末尾 /，现在是 {declared['template_sub']!r}")
    rel = f"sources/{name}.md"
    source = (HERE / rel).read_text(encoding="utf-8")
    check_frontmatter(name, source)
    included = check_contract(name, source)
    lines = expand(name, rel, "", ())
    # 片段每被 include 一次（不论经由哪个片段），展开结果里就有一行出自它的第 1 行
    includes = Counter(m.group(1) for _, origin in lines if (m := re.match(r"(\S+) 第 1 行", origin)))
    for frag in AT_MOST_ONCE:
        if includes[f"fragments/{frag}.md"] > 1:
            sys.exit(f"{name}: {frag} 只能 include 一次")
    if name.startswith("tools-") and includes["fragments/skill-targets.md"]:
        sys.exit(f"{name}: setup-tools 装出的 skill 不带领域前缀，不能 include skill-targets")

    injected = {key: value for key, value in declared.items() if isinstance(value, Fragment)}
    for key, value in injected.items():
        for lineno, line in enumerate(value.split("\n"), 1):
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
            for lineno, line in enumerate(value.split("\n"), 1)
        ]
        variables[key] = value.lead + substitute(name, origins, plain)
    text = substitute(name, lines, variables)
    check_extra_env(name, variables["extra_env"], text)

    if not text.startswith("---\n"):
        sys.exit(f"{name}: 生成物第一行必须是 ---")
    front = text.split("\n---\n", 1)[0]
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
    if includes["fragments/skill-targets.md"]:
        if not (template / f"{name}.md").is_file():
            sys.exit(f"{name}: include 了 skill-targets，模板 {(template / f'{name}.md').relative_to(REPO)} 却不存在")
    for f in sorted(template.rglob("*")):
        if f.is_file():
            where = f"{f.relative_to(REPO)} "
            text_f = f.read_text(encoding="utf-8", errors="ignore")
            writes_instruction_file |= check_markers(name, marker, text_f, where, paired=True)
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
    # 全部渲染、校验通过后才写，免得后面的安装器报错时留下一半已更新的生成物
    outputs = [(target_of(name), render(name, scope, declared)) for name, (scope, declared) in INSTALLERS.items()]
    check_orphans()
    stale = []
    for path, content in outputs:
        if check:
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                stale.append(path.relative_to(REPO))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
    for target in stale:
        print(f"生成物过期：{target}（运行 tools/installer/build.py）", file=sys.stderr)
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
