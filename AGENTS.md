# Agent Skills

个人 agent skills 仓库。以 Claude Code 与 Codex plugin marketplace 形式分发，skill 本身遵循 [Agent Skills 规范](https://agentskills.io/specification)，以便被其它支持该标准的工具复用。

## 结构

```
.claude-plugin/marketplace.json     # Claude Code marketplace 定义，列出所有 plugin
.agents/plugins/marketplace.json    # Codex marketplace 定义，列出所有 plugin
tools/installer/                     # 安装器 SKILL.md 的生成机制，不随 plugin 分发
├── build.py                          # 生成与校验脚本，INSTALLERS 在这里登记
├── sources/<领域>-<skill>.md         # 安装器源文件
└── fragments/<片段名>.md             # 安装器公共片段
plugins/<plugin>/                    # 每个 plugin 都同时分发到 Claude Code 与 Codex
├── plugin.json                       # Codex plugin 元信息
├── .codex-plugin/plugin.json         # Codex plugin 安装清单
├── .claude-plugin/plugin.json        # Claude Code plugin 元信息
├── scripts/                          # 同一 plugin 内多个 skill 共用的资源（可选）
└── skills/<skill>/
    ├── SKILL.md                      # skill 本体；setup-* 下的由 tools/installer 生成
    ├── agents/openai.yaml            # Codex 的调用策略与 UI（可选）
    └── template/                     # 安装器要装出去的模板（可选）
```

Plugin 名即调用前缀：`plugins/dev/skills/discuss/SKILL.md` 在 Claude Code 中对应 `/dev:discuss`，在 Codex 中对应 `$dev:discuss`。

## 新增 skill 与 plugin

### 新增 skill

1. 写 skill 本体：
   - 运行时 skill：手写 `plugins/<plugin>/skills/<skill>/SKILL.md`，frontmatter 见「Frontmatter」。
   - `setup-*` 安装器：不手写 `SKILL.md`。写 `tools/installer/sources/<领域>-<skill>.md`，在 `build.py` 的 `INSTALLERS` 登记并声明 `scope`，再运行 `python3 tools/installer/build.py` 生成，见「安装器生成机制」。
2. 在 `README.md` 对应 plugin 的表格中补一行；安装器要填作用域列，与 `scope` 一致。新增安装器或改 `scope` 时，该 plugin 三个 manifest 与 `.claude-plugin/marketplace.json` 的 `description` 里的作用域摘要、`README.md` 里的安装器个数与作用域列一起同步。
3. 在 `.claude/settings.json` 的 `permissions.allow` 中加入 `Skill(<plugin>:<skill>)`，按 plugin 分组，组的顺序同 `.claude-plugin/marketplace.json` 的 `plugins` 数组，组内按字母序。
4. 禁止隐式调用或需要 Codex UI 的 skill，创建 `agents/openai.yaml`；禁止隐式调用的设 `policy.allow_implicit_invocation: false`。

### 新增 plugin

创建 `plugins/<plugin>/plugin.json`、`plugins/<plugin>/.codex-plugin/plugin.json` 与 `plugins/<plugin>/.claude-plugin/plugin.json`，并分别在 `.agents/plugins/marketplace.json` 与 `.claude-plugin/marketplace.json` 的 `plugins` 数组中登记；再在 `README.md` 的安装、更新命令与「可用 Skills」中补上。安装器类 plugin 的命名与划分见「安装器」。

三个 manifest 的 `description` 一字不差；`.claude-plugin/marketplace.json` 里该 plugin 的 `description` 照抄它，改动时几处一起改。`.codex-plugin/plugin.json` 的 `interface` 文案（`shortDescription`、`longDescription` 等）是 Codex UI 上的展示，内容与 `description` 保持一致。

plugin 名表达领域或能力组；宿主适用性由具体 skill 的描述与实现分支决定。不要因某个 skill（如 `codex-bridge`）只配置某一目标宿主，就把整个 plugin 排除出另一 marketplace。

## Frontmatter

YAML frontmatter 必须位于文件最开头，`---` 是第一行，前面不能有注释或空行。

必填：

- `name` — kebab-case，与所在目录名一致
- `description` — 说明做什么、什么时候用，包含触发关键词；模型靠它决定是否自动调用

常用可选项：

- `disable-model-invocation: true` — 禁止模型自动调用；Claude Code 中只能由用户显式 `/plugin:skill` 触发。Codex 中对应 `$plugin:skill`，并在 `agents/openai.yaml` 映射为 `allow_implicit_invocation: false`。流程编排类 skill（如 `discuss`、`optimize`）应加上，否则会被误触发
- `model` — 覆盖模型档位（`fable` / `opus` / `sonnet` / `haiku`）
- `allowed-tools` — 限制可用工具；不确定时不要加，避免过度约束

## 参数传递

跨宿主 skill 直接以当前用户请求为输入，不要在正文中放 `$ARGUMENTS`：Claude Code 在正文没有参数占位符时，
会把调用参数自动追加为 `ARGUMENTS: <value>`；Codex 的调用参数本来就在当前用户请求中。

只有明确仅面向 Claude Code、且必须把参数插入正文特定位置或按位置拆分时，才使用 `$ARGUMENTS`、
`$ARGUMENTS[N]` 或 `$N`。具体替换规则见 [Claude Code Skills「Pass arguments to skills」](https://code.claude.com/docs/en/skills#pass-arguments-to-skills)。

## 附带资源与共享模板

### 附带资源

skill 需要携带脚本、模板等文件时，放在自己的目录下，用 `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}/skills/<skill>/<file>` 引用——
plugin 安装后的实际路径不可预测，优先使用 Codex 提供的 `PLUGIN_ROOT`，并回退到 Claude Code 的 `CLAUDE_PLUGIN_ROOT`。

**同一 plugin 内多个 skill 共用的资源放 plugin 级 `scripts/`**（`${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}/scripts/<file>`），
不要让一个 skill 去引另一个 skill 的 `template/`——那样两者就绑死了，单独装其中一个会读到不属于它的路径。
plugin 根目录下的任意文件都会随安装一并分发。

附带的模板文件不要命名为 `SKILL.md`，避免与 skill 本体混淆。

### Agent 模板

Agent 模板的共享指令正文只维护一份，禁止另建重复的宿主版本。Claude 模板的模型配置由 Claude Markdown frontmatter 明确定义；Codex 模板的模型与 reasoning effort 由 `plugins/setup-agent/scripts/render-codex-agent.py` 集中映射和生成，两者不要求使用相同的模型名称。新增 agent 时必须同时补齐 Codex 的 model 与 model_reasoning_effort 映射。renderer 从共享模板提取 `name`、`description` 和完整正文生成 Codex 所需的 `developer_instructions`，宿主专属配置只在各自的配置源中维护。

`setup-agent:subagents` 装的规则同样只维护一份共享模板；宿主和安装作用域的差异由 `plugins/setup-agent/scripts/render-subagent-rules.py` 集中生成，禁止另建宿主摘要版或作用域副本。

`setup-agent:report-style` 装的回答规则（Concise+）同样只维护一份共享模板，即 Claude Code 的输出风格文件，Claude Code 直接复制它；Codex 写进 `AGENTS.md` 的那一节由 `plugins/setup-agent/scripts/render-report-style.py` 从它生成，禁止另建宿主版本。

`plugins/setup-agent/scripts/` 下的渲染脚本保持同一写法：有模块 docstring；参数由 argparse 校验（`required=True` / `choices`）；渲染出错时输出 `<脚本名>: <错误信息>` 到 stderr 并以 1 退出，不抛 traceback；自己写的消息用中文。

直接写文件的渲染脚本（`render-codex-agent.py`）全部渲染成功后才写，不留下半批：默认遇到任一已存在的目标就整批拒绝；`--replace` 只替换普通文件，任一目标是软链（含悬空软链）就整批拒绝，先写临时文件、全部写成功后再原子替换。安装器重装时用 `--replace`，不要在安装命令里先 `rm` 目标再渲染：那样软链会被删掉换成普通文件、与原来链向的那份脱钩，渲染失败时旧文件也没了。

## 安装器

### 命名与归属

需要装进项目或用户级配置的，做成 `setup-*` plugin 下的安装器（模板放 skill 自己的 `template/`）；不需要的作为运行时 plugin（如 `dev`、`create`）。

安装器类 plugin 统一以 `setup-` 为前缀，按领域划分：`setup-agent` 装 agent 的开发工作方式、`setup-git` 装 Git 规范与流程、`setup-tools` 装开发辅助工具、`setup-knowledge` 装知识类规范。plugin 按领域划分，不按作用域。作用域是安装器自己的属性，在 `INSTALLERS` 的 `scope` 声明；仅用户级的安装器也放进对应领域，如 `setup-tools:codex-bridge`。`scope` 的取值：

- `project`：只装进当前项目，随仓库提交
- `project-user`：默认装进当前项目，也可装进用户级配置
- `user`：只装进用户级配置

`setup-<领域>` 下的安装器名不重复领域前缀，装出去的 skill 名带 `<领域>-` 前缀（如 `setup-git:commit` 装出 `git-commit`、`setup-agent:docs` 装出 `agent-docs`），避免装进项目或用户级后与其它 skill 重名；`setup-tools` 例外，装出的 skill 不加 `tools-` 前缀（如 `setup-tools:codex-bridge` 装出 `claude`），所以 `setup-tools` 的安装器不能 include `skill-targets`——它按源文件名 `tools-<skill>` 命名装出的 skill。

依赖同一 plugin 级 `scripts/` 的 skill 必须留在同一 plugin，因为 plugin 之间不共享文件。

### 安装器生成机制

`setup-*` plugin 下的安装器 `SKILL.md` 由 `tools/installer/build.py` 从源文件与公共片段生成，让公共步骤只维护一份。生成物提交进仓库，**不得手改**：改源文件或片段后运行 `python3 tools/installer/build.py` 重新生成。凡改了 `tools/installer/` 或安装器的 `template/`、`agents/openai.yaml`，提交前都运行 `python3 tools/installer/build.py --check`，生成物与源文件不一致时非零退出并列出文件。安装器的 `agents/openai.yaml` 与 `template/` 在各 skill 目录下手工维护，不由构建生成。

源文件语法只有两种，不支持条件与循环：

- `{{include: 片段名}}`：独占一行，替换为片段内容；行首有缩进时片段的每一行补上同样的缩进，可直接放进列表项。片段里也可以再 include 片段。
- `{{变量}}`：替换为变量值。include 先于变量展开，所以片段里也能用变量。

#### 片段

| 片段 | 内容 | 谁引用 |
|------|------|--------|
| `host-conventions` | 模板路径解析说明与定义 `SETUP_ROOT`、`TEMPLATE_DIR` 的 shell 片段，`TEMPLATE_DIR` 那行末尾接变量 `extra_env` | 所有源文件，放在源文件自己写的「## 跨宿主约定」标题之下 |
| `scope-select` | 「## 选作用域」：默认装进当前项目，用户明确要求时才装进用户级 | `project-user` 的源文件 |
| `skill-priority` | Claude Code 中同名 skill 用户级优先于项目级、两层都有时告诉用户两份都在且生效的是用户级那份，第 2 行句末接变量 `subagent_rule` | 装 skill 的 `project-user` 源文件 |
| `skill-priority-project` | 一句话：Claude Code 中同名 skill 用户级优先，写入前发现用户级也有同名 skill 时告诉用户项目级这份不会生效 | 装 skill 的 `project` 源文件，放在 `host-conventions` 之后 |
| `subagent-rule` | 一句话：Claude Code 中同名子代理是项目级优先，两层都有时告诉用户两份都在且生效的是项目级那份 | 引用 `skill-priority` 且装子代理的安装器在 `INSTALLERS` 里经 `fragment("subagent-rule", lead="\n")` 作为 `subagent_rule` 的值声明，另起一行接在 `skill-priority` 之后；只装子代理、不引用 `skill-priority` 的源文件直接 include |
| `project-root` | 切到仓库根目录的一行 shell | 源文件里要在仓库根目录执行的命令块；`skill-targets` |
| `skill-targets` | Claude Code / Codex × 项目级（默认）/ 用户级四个安装节，把 `template/<name>.md` 装成同名 skill | 只装一个 skill 的 `project-user` 源文件（`setup-tools` 除外，见「命名与归属」） |
| `codex-user-skill-dir` | 放进 Codex 用户级安装命令块的 shell：定义 `X` 与函数 `codex_skill_dir <名>`，输出该 skill 的写入目录（`$HOME/.agents/skills/<名>` 已有就用它，否则 `$X/skills/<名>`），两处都有时报错、要求停下来问用户 | `skill-targets` 与自己写 Codex 用户级 skill 安装节的源文件；先对每个 skill 取目录（`D=$(codex_skill_dir <名>) \|\| exit 1`），全部取到再写入 |
| `markers` | 「## 指令文件里的标记」：成对 HTML 注释标记的定义，追加还是替换标记范围，及冲突、重装范围、标记异常、指令文件本身是软链与另一宿主的指令文件链向它（两宿主共用一份）的处理 | 往指令文件写内容的源文件，放在 `pre-write` 之前 |
| `pre-write` | 「## 写入前检查」：首次安装与重装都做；查软链、查冲突，有冲突问用户「完全覆盖」还是「融入现有内容」 | 所有源文件 |
| `reinstall` | 「## 重装」：读定制值 → 清理本安装器这次要写的位置 → 装新的 → 填回，不判断版本 | 所有源文件 |
| `state-mismatch` | 「## 现状与预期不符时」：要停下来问用户的情形 | 所有源文件 |

#### INSTALLERS

`build.py` 的 `INSTALLERS` 以源文件名为键，值为 `(scope, 变量)`，只声明作用域与各安装器有差异的变量：

- `scope`：取值见「命名与归属」。它决定 description 的作用域措辞 `scope_lead` / `scope_tail`，构建时也按它校验正文。
- 变量：没声明的取 `DEFAULTS` 的回退值——`template_sub`（`TEMPLATE_DIR` 在 `template/` 下的子目录，带前导 `/`、不带末尾 `/`，如 `/cron`）、`extra_env`（接在 `TEMPLATE_DIR` 那行末尾的环境变量定义，以换行开头、每行一条 `<变量>=<值>`，调用渲染脚本的安装器用它追加 `RENDER_AGENT` / `RENDER_RULES` / `RENDER_STYLE`，定义的与正文用到的 `RENDER_*` 一一对应）、`subagent_rule`（默认为空）。正文要原样输出 `{{…}}` 占位符时，也经这里声明的变量输出，以绕开残留语法检查。变量值要用 `fragments/` 里的文案时用 `fragment()` 读进来：这种值和正文一样展开其中的变量、做残留检查，但不能再 include，也不能引用另一个经 `fragment()` 注入的变量。片段读入时去掉首尾换行；变量接在某行句末时，用 `lead` 参数（只能是空白）决定与前文同行还是另起一行，变量为空时就不留多余的空白。

下列变量与路径由源文件名 `<领域>-<skill>`（领域是 plugin 名去掉 `setup-`，不含连字符）推导或由作用域决定，不能在 `INSTALLERS` 里声明：

- 生成物路径：`plugins/setup-<领域>/skills/<skill>/SKILL.md`
- `skill`：skill 目录名
- `name`：源文件名；`skill-targets` 用它作装出的 skill 名和模板文件名
- `marker`：`setup-<领域>:<skill>`，指令文件里本安装器那对标记的名字
- `scope_lead` / `scope_tail`：由 `scope` 决定

#### 源文件契约

源文件写本安装器独有的步骤与顺序；片段里的规则不在源文件里复述。

- frontmatter 写在源文件里，`name` 等于 skill 目录名，并设 `disable-model-invocation: true`；该 skill 的 `agents/openai.yaml` 设 `policy.allow_implicit_invocation: false`。`description` 以 `{{scope_lead}}` 开头，引用一次 `{{scope_tail}}`，紧接在末尾的「用于……等场景。」之前，写成 `{{scope_tail}}用于……等场景。`，其余只写自己独有的部分。
- 「## 跨宿主约定」标题（及引导句）写在源文件里，其下 include `host-conventions`。
- `host-conventions`、`pre-write`、`reinstall`、`state-mismatch` 每个源文件都在顶层（不缩进）各 include 一次；往指令文件写内容的再 include `markers`，放在 `pre-write` 之前。
- 正文与 `scope` 一致：`project` 必须有项目级安装节，不含「选作用域」与用户级安装节；`project-user` 含「选作用域」、项目级安装节与用户级安装节；`user` 必须有用户级安装节，不含「选作用域」与项目级安装节。安装节只认代码块之外、整行形如 `## [Claude Code |Codex ]项目级安装[（默认）]` / `## [Claude Code |Codex ]用户级安装` 的二级标题，不用「## 步骤」之类认不出作用域的标题；代码块之外提到「项目级安装」「用户级安装」的二级、三级标题都必须是这两种写法，「## 项目级安装（可选）」「### 项目级安装」「## 不做项目级安装」都不行。
- `{{include: pre-write}}` 之后紧接「本安装器另外要查的冲突：……」，没有的写「无」。
- `{{include: reinstall}}` 之后紧接「本安装器的定制值：……」，逐项写从哪读、何时填回，没有的写「无」。
- 往指令文件写内容的安装器才 include `markers`：以源文件正文引用了 `{{marker}}`、或 `template/` 里有本安装器的标记为准。源文件正文写 `{{marker}}`；`template/` 里写字面的 `<!-- setup-<领域>:<skill>:begin|end -->`；两处都只能是本安装器的名字。`template/` 里每个文件的标记要么 begin、end 各一个且 begin 在前，要么都没有。追加还是替换标记范围由 `markers` 统一规定，源文件只引用「指令文件里的标记」一节，不复述做法。
- 装出的模板里安装时要填写的位置，要写明它记录什么、来自哪里（项目现状 / 用户选定 / 用户提供）；有固定选项的逐项列出，并标出默认值。

#### 校验

`build.py` 遇到下列情况直接报错退出；这是校验的唯一清单，`build.py` 的 docstring 只指向这里。

- 展开：片段不存在、循环 include、未声明的变量、展开后残留 `{{` 或 `}}`，报错指出出自源文件还是片段及其行号；经 `fragment()` 注入变量值的片段同样检查，且其中有 `{{include: …}}` 或引用了另一个注入的变量时报错
- `fragments/` 下有没被任何源文件 include、也没经 `fragment()` 引用的片段
- `INSTALLERS`：声明的变量在展开后的正文里没被引用（`DEFAULTS` 有回退值也不豁免），或声明了推导与作用域决定的变量；`scope` 不是已知作用域；`template_sub` 不匹配 `^(/[\w.-]+)+$`（`/`、`/cron/` 都报错）
- `extra_env`：非空却不以换行开头，或有不是 `<变量>=<值>` 的行；展开后的正文用到的 `$RENDER_*`（含 `${RENDER_…}`）没在 `extra_env` 里定义，或 `extra_env` 定义的变量在正文里没用到。`host-conventions` 总是引用 `{{extra_env}}`，上一条的「没被引用」对它不起作用，靠这条双向比对
- 登记：`sources/` 下有没登记的源文件、登记的源文件不存在；`plugins/setup-*/skills/` 下有不对应登记源文件的目录（含只剩 `template/` 的残留目录）或散落的普通文件（`.DS_Store` 除外）；源文件名不是 `<领域>-<skill>`
- 模板：`TEMPLATE_DIR`（`template/` 加 `template_sub`）不存在；include 了 `skill-targets` 的，`template/<name>.md` 不存在
- frontmatter：生成物首行不是 `---`，或 `name` 与所在目录名不一致；源文件缺少 description，description 不以 `{{scope_lead}}` 开头、`{{scope_tail}}` 引用次数不是一次、没有写成 `{{scope_tail}}用于` 或不以「等场景。」结尾；没有 `disable-model-invocation: true`；`agents/openai.yaml` 不存在，或顶层 `policy:` 块里没有 `allow_implicit_invocation: false`（写在 `interface:` 等别的块下不算）
- 作用域：正文缺少该作用域必需的节，或含不该有的节；代码块之外提到「项目级安装」「用户级安装」的 `##` / `###` 标题不合安装节的写法（见「源文件契约」）。代码块按开头那行的围栏配对结尾：开头是三个及以上的反引号或 `~`，结尾须是同一符号、不短于开头；找 `host-conventions` 所在的节时同样跳过代码块
- 片段放法：缺少必需的顶层 include 或重复 include；`scope-select` include 了不止一次；`setup-tools` 的源文件 include 了 `skill-targets`；`host-conventions` 不在「## 跨宿主约定」之下；`markers` 不在 `pre-write` 之前；`pre-write` / `reinstall` 之后的第一段不以「本安装器另外要查的冲突：」/「本安装器的定制值：」开头
- 标记：源文件里手写了字面的 setup 标记；生成物或该 skill 的 `template/` 里有形似 setup 标记（`<!--` 加可选空白再加 `setup` 与 `-` / `:` / `_`，不区分大小写）、却不符合 `<!-- setup-<领域>:<skill>:begin|end -->` 格式的标记，或标记名不等于 `marker`；`template/` 里某个文件的标记不是 begin、end 各一个且 begin 在前（生成物里的标记出现在命令里，不查成对）；写指令文件（见「源文件契约」）却没有 include `markers`，或 include 了 `markers` 却不写指令文件

不校验、靠维护者自觉的契约：除 `host-conventions`、`markers` 外各片段的放置位置（如 `skill-priority-project` 在 `host-conventions` 之后；`pre-write` / `reinstall` 只校验紧跟的那一段）；`subagent_rule` 只声明给装子代理的安装器；description 里 `{{scope_tail}}` 以外的部分只写本安装器独有的内容；`reinstall` 之后定制值逐项写明来源与填回时机；装出的模板里待填位置写明记录什么、来自哪里；`skill-priority` / `skill-priority-project` / `skill-targets` 只用在符合「谁引用」一列的源文件里。

写出前先渲染并校验全部安装器，任一报错就一个生成物都不写。

### 指令文件里的工作流

指令文件（`CLAUDE.md` / `AGENTS.md`）里开工前与交付前的工作流只写在「工作流」一节，只由 `setup-agent:workflow` 写入；其它安装器与装出的 skill 不得自己往指令文件里写工作流内容。

## 分发与发布

安装、更新与排查命令见 `README.md`；发布推送后按其「更新」一节刷新 marketplace 并更新 plugin，再用「排查」一节的命令确认加载的是新版本。

### 分发

marketplace 名为 `bjj-agent-skills` 而非仓库名 `agent-skills`——后者是 Anthropic 保留名，只允许 `anthropics` 组织的 GitHub 源使用。Codex 沿用同一 marketplace 名，以保持选择器一致。

开发调试本仓库时同样用 GitHub 源装 Claude Code plugin，不要用 `claude plugin marketplace add <本地路径>` 直接加载工作副本：GitHub 源会把仓库 clone 到 `plugins/marketplaces/bjj-agent-skills/`，运行时与工作副本无关；本地源的问题见 `README.md`「安装」。

### 发布

GitHub marketplace 的仓库快照与已安装 plugin 缓存是两层。发布 plugin 内容改动时，先同步提升该 plugin 在以下三个 manifest 中的 `version`，再提交推送：

- `plugins/<plugin>/plugin.json`
- `plugins/<plugin>/.codex-plugin/plugin.json`
- `plugins/<plugin>/.claude-plugin/plugin.json`

改 `tools/installer/` 后，`plugins/` 下生成物有变化的每个 plugin 都要同步提升三处 `version`。

版本以已发布版本（`origin/main` 上的 `version`）为基准，相对它的连续改动只升一次，未推送前的后续改动不再叠加。内容有破坏性变更或新增能力升 minor，只改内容升 patch。

Claude Code 的 `plugin update` 按版本判断是否需要更新，版本不变时会认为已是最新版。Codex 刷新 marketplace 后重新安装可能覆盖同版本内容，但发布流程不得依赖该行为。两边都以递增且三处一致的 plugin 版本作为新版本边界。
