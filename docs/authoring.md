# 编写 skill 与 plugin

新增 skill 与 plugin 的登记步骤，以及 SKILL.md 的 frontmatter、参数传递、附带资源与共享模板；面向新增或修改 skill、plugin 的维护者与 agent，什么时候读见 AGENTS.md「什么时候读什么」。

## 新增 skill 与 plugin

### 新增 skill

1. 写 skill 本体：运行时 skill 手写 `plugins/<plugin>/skills/<skill>/SKILL.md`；`setup-*` 安装器不手写 `SKILL.md`，按 `docs/installers.md` 写源文件、登记、生成。
2. 在 `README.md` 对应 plugin 的表格中补一行，说明列只写一句话（装什么、解决什么问题、有无改指令文件或装子代理之类的特殊影响），安装器还要填与 `scope` 一致的作用域列。新增安装器或改 `scope` 时，该 plugin 三个 manifest 与 `.claude-plugin/marketplace.json` 的 `description` 里的作用域摘要、`README.md` 里的安装器个数一起同步。
3. 在 `.claude/settings.json` 的 `permissions.allow` 中加入 `Skill(<plugin>:<skill>)`，按 plugin 分组，组的顺序同 `.claude-plugin/marketplace.json` 的 `plugins` 数组，组内按字母序。
4. 禁止隐式调用或需要 Codex UI 的 skill，创建 `agents/openai.yaml`；禁止隐式调用的设 `policy.allow_implicit_invocation: false`。

### 新增 plugin

创建三个 manifest（`plugin.json`、`.codex-plugin/plugin.json`、`.claude-plugin/plugin.json`），在两个 marketplace 的 `plugins` 数组中登记，再在 `README.md` 的安装、更新命令与「可用 Skills」中补上。三个 manifest 的 `description` 一字不差，`.claude-plugin/marketplace.json` 里照抄它；`.codex-plugin/plugin.json` 的 `interface` 文案与它保持一致。plugin 名表达领域或能力组；宿主适用性由具体 skill 的描述与实现分支决定，不要因某个 skill 只配置某一宿主就把整个 plugin 排除出另一 marketplace。

## Frontmatter

YAML frontmatter 必须位于文件最开头，`---` 是第一行。必填 `name`（kebab-case，与目录名一致）与 `description`（做什么、什么时候用、含触发关键词，模型靠它决定是否自动调用）。常用可选项：

- `disable-model-invocation: true` — 禁止模型自动调用，只能由用户显式 `/plugin:skill`（Codex 为 `$plugin:skill`）触发，Codex 侧在 `agents/openai.yaml` 映射为 `allow_implicit_invocation: false`。流程编排类 skill（如 `discuss`、`optimize`）应加上，否则会被误触发
- `model` — 覆盖模型档位（`fable` / `opus` / `sonnet` / `haiku`）
- `allowed-tools` — 限制可用工具；不确定时不要加，避免过度约束

## 参数传递

跨宿主 skill 直接以当前用户请求为输入，不要在正文中放 `$ARGUMENTS`：Claude Code 在正文没有参数占位符时会把调用参数追加为 `ARGUMENTS: <value>`；Codex 的调用参数本来就在当前用户请求中。只有明确仅面向 Claude Code、且必须把参数插入正文特定位置或按位置拆分时，才用 `$ARGUMENTS`、`$ARGUMENTS[N]` 或 `$N`，规则见 [Claude Code Skills「Pass arguments to skills」](https://code.claude.com/docs/en/skills#pass-arguments-to-skills)。

## 附带资源与共享模板

- skill 携带的脚本、模板放在自己目录下，用 `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}/skills/<skill>/<file>` 引用（安装后路径不可预测，先用 Codex 的 `PLUGIN_ROOT`，回退到 Claude Code 的 `CLAUDE_PLUGIN_ROOT`）。
- 同一 plugin 内多个 skill 共用的资源放 plugin 级 `scripts/`，不要让一个 skill 引另一个 skill 的 `template/`——单独装其中一个就会读到不属于它的路径。依赖同一 `scripts/` 的 skill 必须留在同一 plugin，plugin 之间不共享文件。
- 附带的模板文件不要命名为 `SKILL.md`。
- 共享指令正文只维护一份，禁止另建宿主版本或作用域副本，宿主差异由 `plugins/setup-agent/scripts/` 的渲染脚本生成：Agent 模板的 Codex 版由 `render-codex-agent.py` 生成，模型与 reasoning effort 在其中集中映射（新增 agent 时必须同时补齐），Claude 版的模型配置写在模板 frontmatter；`setup-agent:subagents` 的规则由 `render-subagent-rules.py` 生成；`setup-agent:report-style` 以 Claude Code 输出风格文件为唯一模板，Codex 那一节由 `render-report-style.py` 生成。
- 渲染脚本的写法：有模块 docstring；参数由 argparse 校验；出错时输出 `<脚本名>: <错误信息>` 到 stderr 并以 1 退出，不抛 traceback；自己写的消息用中文。直接写文件的渲染脚本全部渲染成功后才写，替换语义见其 docstring；安装器重装时用 `--replace`，不要先 `rm` 目标再渲染（会把软链换成普通文件，渲染失败时旧文件也没了）。
