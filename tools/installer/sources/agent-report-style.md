---
name: report-style
description: {{scope_lead}}Concise+ 回答规则，让 Claude Code 使用自定义 output style，Codex 把等价规则写进 AGENTS.md。{{scope_tail}}用于"agent 报告太啰嗦""让它少说废话只给结论""别顺着我说""配输出风格""装 output style"等场景。
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

- Claude Code：要写的 `settings.json` 里 `"outputStyle"` 已设成 `Concise+` 以外的风格。这个键只能取一个值，
  所以只问改不改：改成 `Concise+`（完全覆盖），或保留原值、只写入风格文件不启用；不提供融入。
- Claude Code：这次作用域的 `CLAUDE.md`（项目级看项目根目录的，用户级看用户级配置目录下的）里已有管回答风格、
  报告写法的规则。Claude Code 分支不往 `CLAUDE.md` 写标记：选完全覆盖就删掉那段；选融入就并进风格文件，
  并说明下次重装会被覆盖。
- Claude Code：另一层（用户级或项目里）也有一份同名风格时，内容一致没有影响；不一致就告诉用户两份都在、
  内容差在哪，留哪份交给用户定。
- Codex：`AGENTS.md` 标记范围之外已有管回答风格、报告写法的规则。

Claude Code 还要看优先级高于要写的那份、本安装器不写的设置文件：项目级安装看 `.claude/settings.local.json`，
用户级安装看当前项目的 `.claude/settings.json` 与 `.claude/settings.local.json`。其中 `"outputStyle"` 已设成
`Concise+` 以外的风格时，这几份不改，告诉用户它会盖过本次设置。

## Claude Code 项目级安装（默认）

1. **写入风格文件**：已有的同名文件直接覆盖。

   ```bash
   {{include: project-root}}
   mkdir -p .claude/output-styles
   cp "$TEMPLATE_DIR/output-styles/concise-plus.md" .claude/output-styles/
   ```

2. **启用**：在项目的 `.claude/settings.json` 里设 `"outputStyle": "Concise+"`，只设这一个键，其它设置不动；这个键冲突、用户选了保留原值的不设。
3. **告知用户**：`.claude/output-styles/concise-plus.md` 与 `settings.json` 的改动要提交进版本库；
   `.gitignore` 整体忽略了 `.claude/` 的项目要为这两个文件加例外，否则改了也提交不进去。
   其余见「Claude Code 装完都要说的」。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

1. **写入风格文件**：已有的同名文件直接覆盖。

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   mkdir -p "$C/output-styles"
   cp "$TEMPLATE_DIR/output-styles/concise-plus.md" "$C/output-styles/"
   ```

2. **启用**：在 `$C/settings.json` 里设 `"outputStyle": "Concise+"`，只设这一个键，其它设置不动；这个键冲突、用户选了保留原值的不设。
3. **告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；其余见「Claude Code 装完都要说的」。

## Claude Code 装完都要说的

- 风格文件在启动时读取，重启 Claude Code 后生效。
- 同一时刻只能启用一个 output style，启用它就用不了 `Explanatory` / `Learning`。
- `/output-style <名字>` 与 `/config` 菜单写的是当前项目的 `.claude/settings.local.json`：不进版本库，
  只对当前用户在这个项目里生效，替代不了这次写的 `settings.json`，却会一直盖过它。想切回内置风格可以用它们，
  要恢复本次设置就删掉 `settings.local.json` 里的那个键。

## Codex 项目级安装（默认）

1. **写规则**：目标是项目根目录的 `AGENTS.md`，没有就新建。命令把输出风格文件渲染成 `AGENTS.md` 里的一节，
   并带上本安装器的标记，追加还是替换按「指令文件里的标记」处理：

   ```bash
   {{include: project-root}}
   : "${RENDER_STYLE:?}" "${TEMPLATE_DIR:?}"
   rules=$(python3 "$RENDER_STYLE" "$TEMPLATE_DIR/output-styles/concise-plus.md") &&
     printf '\n<!-- {{marker}}:begin -->\n\n%s\n\n<!-- {{marker}}:end -->\n' "$rules" >> AGENTS.md
   ```

2. **告知用户**：`AGENTS.md` 的改动要提交进版本库；开启新会话后生效。

## Codex 用户级安装

写法同项目级，目标是 Codex 用户级配置目录下的 `AGENTS.md`：

```bash
X=${CODEX_HOME:-$HOME/.codex}
: "${RENDER_STYLE:?}" "${TEMPLATE_DIR:?}"
mkdir -p "$X"
rules=$(python3 "$RENDER_STYLE" "$TEMPLATE_DIR/output-styles/concise-plus.md") &&
  printf '\n<!-- {{marker}}:begin -->\n\n%s\n\n<!-- {{marker}}:end -->\n' "$rules" >> "$X/AGENTS.md"
```

**告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：无。

{{include: state-mismatch}}
