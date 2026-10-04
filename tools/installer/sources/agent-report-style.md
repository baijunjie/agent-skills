---
name: report-style
description: {{scope_lead}}Concise+ 回答风格，Claude Code 装成 output style，Codex 写进 AGENTS.md。{{scope_tail}}用于"agent 报告太啰嗦""让它少说废话只给结论""配输出风格""装 output style"等场景。
disable-model-invocation: true
---

# 安装输出风格 Concise+

## 跨宿主约定

只执行当前宿主对应的分支。Claude Code 装 output style；Codex 分支改为把等价规则写进 `AGENTS.md`。

{{include: host-conventions}}

{{include: scope-select}}

{{include: markers}}

{{include: pre-write}}

本安装器另外要查的冲突：

- 要设的单值配置键已取别的值：Claude Code 要写的 `settings.json` 里 `"outputStyle"` 不是 `Concise+`，
  Codex 要写的 `config.toml` 里 `[features]` 的 `default_mode_request_user_input` 为 `false`。只问改不改：
  改成本安装器的值（完全覆盖），或保留原值（`outputStyle` 保留时只写入风格文件、不启用）；不提供融入。
- Claude Code：这次作用域的 `CLAUDE.md`（项目级看项目根目录的，用户级看用户级配置目录下的）里已有管回答风格、
  报告写法的规则。这个分支不往 `CLAUDE.md` 写标记，结果落进风格文件，不适用「指令文件里的标记」里的「冲突的处理结果」：
  选完全覆盖就删掉那段；选融入就并进风格文件、同样删掉那段，并说明下次重装会被覆盖。
  `CLAUDE.md` 是指向 `AGENTS.md` 的软链、读到的是本安装器 Codex 分支的标记范围时，不按冲突问，告知用户它与输出风格重复，
  问是否删掉这个标记范围（删掉后 Codex 也读不到）。
- Claude Code：另一层（用户级或项目级）也有一份同名风格、除「回答语言：」那一行外内容不一致时，
  告知用户两份都在、内容差在哪，留哪份交给用户定。
- Codex：`AGENTS.md` 标记范围之外已有管回答风格、报告写法的规则。
- Codex：按「共用的指令文件」询问时，说明 Claude Code 读到这一节会与它的 output style 重复。
- **这一项不按冲突问**：项目级安装时用户级指令文件里已有回答风格、报告写法的规则的，不改它，告知用户两份都会生效、内容差在哪。

Claude Code 还要看优先级更高、本安装器不写的设置文件（项目级安装看 `.claude/settings.local.json`，用户级安装看当前项目的
`.claude/settings.json` 与 `.claude/settings.local.json`）：其中 `"outputStyle"` 不是 `Concise+` 的不改，告知用户它会盖过本次设置。

## 选输出语言

风格里写定回答语言，在第一次写入之前定下来。重装时读得出旧语言（见「重装」的定制值）就沿用、跳过本节，除非用户这次明说要换。

1. **读系统的首选语言列表**：macOS 用 `defaults read -g AppleLanguages`；Linux 看 `$LANGUAGE`（冒号分隔的列表），
   没有再看 `$LC_ALL`、`$LC_MESSAGES`、`$LANG`；Windows 用 `powershell -NoProfile -Command "(Get-WinUserLanguageList).LanguageTag"`。
   locale 形式的值去掉 `.UTF-8` 这类编码后缀、`_` 换成 `-`（`en_US.UTF-8` → `en-US`）；保持原顺序，去掉重复与 `C`、`POSIX` 这类不是语言的值。
2. **让用户选一个**：让用户从选项里点选（提选项的工具用不了时以文字逐个编号列出），每项是列表里的一种语言，
   首选的排第一并注明是系统首选，用户可以自己填别的语言。列表读不到时直接问用户用哪种语言。
3. **用户没选就关掉或跳过时**用列表首位，列表也读不到就用这次对话所用的语言；用户说不装了就停止，什么都不写。
4. **写法**：把定下的语言写成它自己的名称，后附语言标签，如 `简体中文（zh-Hans）`、`English (en-US)`、
   `日本語（ja-JP）`；不是从系统列表选的，按 BCP 47 自行写标签。下面命令里记为 `STYLE_LANGUAGE`。

## Claude Code 项目级安装（默认）

1. **写入风格文件**：已有的整份覆盖。

   ```bash
   {{include: project-root}}
   : "${RENDER_STYLE:?}" "${TEMPLATE_DIR:?}"
   STYLE_LANGUAGE='<「选输出语言」定下的语言>'
   mkdir -p .claude/output-styles
   style=$(python3 "$RENDER_STYLE" --host claude --language "${STYLE_LANGUAGE:?}" "$TEMPLATE_DIR/output-styles/concise-plus.md") &&
     printf '%s\n' "$style" > .claude/output-styles/concise-plus.md
   ```

2. **启用**：在项目的 `.claude/settings.json` 里设 `"outputStyle": "Concise+"`，只设这一个键，其它设置不动；这个键冲突、用户选了保留原值的不设。
3. **告知用户**：`.claude/output-styles/concise-plus.md` 与 `settings.json` 的改动要提交进版本库；
   `.gitignore` 整体忽略了 `.claude/` 的项目要为这两个文件加例外，否则改了也提交不进去。
   其余见「Claude Code 装完都要说的」。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

1. **写入风格文件**：已有的整份覆盖。

   ```bash
   : "${RENDER_STYLE:?}" "${TEMPLATE_DIR:?}"
   STYLE_LANGUAGE='<「选输出语言」定下的语言>'
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   mkdir -p "$C/output-styles"
   style=$(python3 "$RENDER_STYLE" --host claude --language "${STYLE_LANGUAGE:?}" "$TEMPLATE_DIR/output-styles/concise-plus.md") &&
     printf '%s\n' "$style" > "$C/output-styles/concise-plus.md"
   ```

2. **启用**：在 `$C/settings.json` 里设 `"outputStyle": "Concise+"`，只设这一个键，其它设置不动；这个键冲突、用户选了保留原值的不设。
3. **告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；其余见「Claude Code 装完都要说的」。

## Claude Code 装完都要说的

- 风格文件在启动时读取，重启 Claude Code 后生效。`outputStyle` 选了保留原值、或被更高优先级的设置盖过的，
  改说风格文件已写入但没有启用，要用时 `/output-style Concise+` 切换。
- 同一时刻只能启用一个 output style，启用它就用不了 `Explanatory` / `Learning`。
- `/output-style <名字>` 与 `/config` 菜单写的是当前项目的 `.claude/settings.local.json`：不进版本库，
  只对当前用户在这个项目里生效，替代不了这次写的 `settings.json`，却会一直盖过它。想切回内置风格可以用它们，
  要恢复本次设置就删掉 `settings.local.json` 里的那个键。

## Codex 项目级安装（默认）

1. **写规则**：目标是项目根目录的 `AGENTS.md`，没有就新建。命令把输出风格文件渲染成 `AGENTS.md` 里的一节：

   ```bash
   {{include: project-root}}
   : "${RENDER_STYLE:?}" "${TEMPLATE_DIR:?}"
   STYLE_LANGUAGE='<「选输出语言」定下的语言>'
   rules=$(python3 "$RENDER_STYLE" --host codex --language "${STYLE_LANGUAGE:?}" "$TEMPLATE_DIR/output-styles/concise-plus.md") &&
     printf '\n<!-- {{marker}}:begin -->\n\n%s\n\n<!-- {{marker}}:end -->\n' "$rules" >> AGENTS.md
   ```

2. **启用提问工具**：在项目的 `.codex/config.toml`（没有就新建）的 `[features]` 表里设 `default_mode_request_user_input = true`，
   只设这一个键，其它内容不动；这个键冲突、用户选了保留的不设。
3. **告知用户**：`AGENTS.md` 与 `.codex/config.toml` 的改动要提交进版本库；开启新会话后生效。
   项目级的 `.codex/config.toml` 只在用户信任这个项目时才加载。其余见「Codex 装完都要说的」。

## Codex 用户级安装

写法同项目级，目标是 Codex 用户级配置目录下的 `AGENTS.md`：

```bash
X=${CODEX_HOME:-$HOME/.codex}
: "${RENDER_STYLE:?}" "${TEMPLATE_DIR:?}"
STYLE_LANGUAGE='<「选输出语言」定下的语言>'
mkdir -p "$X"
rules=$(python3 "$RENDER_STYLE" --host codex --language "${STYLE_LANGUAGE:?}" "$TEMPLATE_DIR/output-styles/concise-plus.md") &&
  printf '\n<!-- {{marker}}:begin -->\n\n%s\n\n<!-- {{marker}}:end -->\n' "$rules" >> "$X/AGENTS.md"
```

然后在 `$X/config.toml` 的 `[features]` 表里设 `default_mode_request_user_input = true`，做法同项目级第 2 步。

**告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。其余见「Codex 装完都要说的」。

## Codex 装完都要说的

- `request_user_input` 是 Codex 向用户提选项的工具，默认只在 Plan 模式下提供；`default_mode_request_user_input`
  让默认模式也能用它，规则第 7 条靠它以选项提问。没开或用户选了保留 `false` 时，默认模式下的提问会退回文字。
- 这个特性在 Codex 里还处于开发阶段，启动时会提示开启了开发中的特性，行为也可能随版本变化；
  不想看到提示可以在用户级 `config.toml` 顶层设 `suppress_unstable_features_warning = true`。

{{include: reinstall}}

本安装器的定制值：

- 输出语言：旧风格文件（Codex 为 `AGENTS.md` 里本安装器的标记范围）中「回答语言：」之后、第一个「。」之前的文字。
  由用户选定，不按当前系统语言列表重新确定；读得出就直接用作 `STYLE_LANGUAGE`，渲染时已写进新内容，不另行填回；
  读不出就按「选输出语言」重新问。

{{include: state-mismatch}}
