---
name: unit-test
description: {{scope_lead}}agent-unit-test skill 与 test-writer 子代理：基于项目已有的单元测试框架（没有就问用户并协助安装），测试默认放独立目录并镜像源码结构，收尾时为改动文件补测试、只跑受影响的测试。{{scope_tail}}用于"给这个项目配单元测试""装 test-writer""让 agent 收尾时补测试""更新项目里的单元测试 skill"等场景。
disable-model-invocation: true
---

# 安装项目级 agent-unit-test skill

装两样东西：`agent-unit-test` skill 与写测试的 `test-writer` 子代理。装出的 skill 靠 description 自动触发，
本安装器不往指令文件写任何内容。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: skill-priority-project}}

{{include: pre-write}}

本安装器另外要查的冲突：第 6 步要补的框架配置项或运行测试的入口（`package.json` scripts、Makefile target 等），
项目里已有同名的、取值或命令与要写的不同。这一项是例外，不在「写入前检查」里查：要写什么到第 6 步才定得下来，
第 6 步写配置前单独查，有冲突照「写入前检查」的问法问用户。

## 通用步骤

1. **读旧约定**：已装过的（所在宿主安装节里 skill 的安装位置已有 `SKILL.md`），先读出旧 skill 的「本项目约定」一节，
   作为后续各步的依据（见「重装」）。没装过就跳过这一步。
2. **确认框架**：项目已有单元测试框架就沿用；
   多个并存时以已有测试最多的为准，拿不准时以旧表里的框架为准，没有旧表就问用户。monorepo 按包逐个确认。
   没有框架时按 `$TEMPLATE_DIR/agent-unit-test.md`「找不到框架时」一节问用户，用户同意后装成开发依赖；
   配置留到第 6 步，填约定留到第 7 步。用户不装框架就停止安装，告诉用户没装成，不写任何文件。
3. **定测试目录与映射**：
   - 先定「已有与源码同目录的测试怎么处理」：项目里没有这类测试的写「无」；有的，第 1 步读到的旧值是三个选项之一就沿用、
     不再问，否则按 `$TEMPLATE_DIR/agent-unit-test.md`「本项目约定」里这一项列出的选项问用户。安装时不搬这些测试。
     选 ② 的告诉用户：旧测试随对应源文件被改逐个迁移，想一次迁完的另作单独任务。
   - 选 ③ 的不定测试根目录，映射写与源文件同目录的模式，文件名标记照下面的规则定；其余按下面几条定。
   - 项目已有独立测试目录的沿用；语言或构建工具有约定测试目录的（如 Maven / Gradle 的 `src/test/java`）用约定；
     都没有才用 `tests/unit/`。monorepo 每个包各自一个。
   - 映射默认按源文件相对项目（包）根的完整路径镜像；只有单一源码根（如 `src/`）时可省掉这一级目录。
   - 文件名标记沿用项目已有测试的；没有才取框架默认。
   - 共享辅助代码沿用项目已有的位置；没有就放 `<测试根目录>/helpers/`（选 ③ 的放源码根下的 `test-helpers/` 之类）。
   - 语言本身已规定单元测试放法的（Go 的同目录 `_test.go`、Rust 的 `#[cfg(test)]` 模块），照语言惯例，
     不套独立目录与镜像规则。
4. **写入 skill**：执行所在宿主安装节里写入 skill 的命令，已有的整份覆盖。
5. **装写测试的子代理**：执行所在宿主安装节里装子代理的命令，已有的同名文件整份替换。
6. **配置框架**：先单独查「本安装器另外要查的冲突」，再按装好的 skill「框架配置要求」一节检查并补齐；
   项目有脚本约定（`package.json` scripts、Makefile 等）就补上运行测试的入口。框架是新装的、或测试目录是新定的，
   派刚装好的 `test-writer` 为项目里一个可测文件写一份真实测试，确认能被发现并跑通。派时交代第 2、3 步定下的
   框架、测试位置、映射与共享辅助代码的位置，以及本步补上的运行命令，并说明 skill 的「本项目约定」尚未填写，以这次交代的为准。
   当前会话还调不到新装的 `test-writer` 时，派一个通用子代理，把 `test-writer` 定义的正文连同上面的交代一起给它；
   没有子代理机制就按该定义自己写。
7. **填本项目约定**：把装好的 skill「本项目约定」一节里每个 `<…>` 连同尖括号换成实际值，尖括号里的说明不保留；
   路径与命令写成代码体，「无」不用代码体。表里 monorepo 每个包一行；表下两项写第 3 步定下的结果，用不上的写「无」；
   「已有与源码同目录的测试怎么处理」写所选项的编号连同原文，如「① 旧测试留在原处，新测试进测试根目录」。
   表里的每条命令都要实际跑过。
   从项目现状确定不了的值沿用旧值。「放在哪」一节不改。
8. **告知用户**：框架配置与依赖清单的改动要连同装出的文件一起提交进版本库；第 6 步写了测试的，写的测试文件是哪份、
   是否通过，一并告诉用户，要连同其它改动一起提交。
   再说一句：重装时保留的只有 skill 里的「本项目约定」一节。其余见所在宿主安装节。

## Claude Code 项目级安装

skill 装在 `.claude/skills/agent-unit-test/SKILL.md`。

写入 skill（第 4 步）：

```bash
{{include: project-root}}
mkdir -p .claude/skills/agent-unit-test
cp "$TEMPLATE_DIR/agent-unit-test.md" .claude/skills/agent-unit-test/SKILL.md
```

装子代理（第 5 步）：

```bash
{{include: project-root}}
mkdir -p .claude/agents
cp "$TEMPLATE_DIR/agents/test-writer.md" .claude/agents/
```

**告知用户**：`.claude/skills/agent-unit-test/` 与 `.claude/agents/test-writer.md` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。装好后可用 `/agent-unit-test` 调用，也会按描述自动触发；
重启 Claude Code 后生效。

## Codex 项目级安装

skill 装在 `.agents/skills/agent-unit-test/SKILL.md`。

写入 skill（第 4 步）：

```bash
{{include: project-root}}
mkdir -p .agents/skills/agent-unit-test
cp "$TEMPLATE_DIR/agent-unit-test.md" .agents/skills/agent-unit-test/SKILL.md
```

装子代理（第 5 步）：用渲染脚本的 `--replace` 替换同名旧 `.toml`，目标是软链时它会整批拒绝写入。

```bash
{{include: project-root}}
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
mkdir -p .codex/agents
python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/test-writer.md"
```

**告知用户**：`.agents/skills/agent-unit-test/` 与 `.codex/agents/test-writer.toml` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 或 `.codex/` 的项目要为这两处加例外。装好后可用 `$agent-unit-test` 调用，
也会按描述自动触发；开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：「本项目约定」一节整节，第 1 步读出，第 7 步填回。

- 表：框架、测试目录、映射、共享辅助代码、命令按第 2、3、6、7 步从项目现状重新确定，确定不了的才沿用旧表。
- 表下「已有与源码同目录的测试怎么处理」：旧值是三个选项之一时第 3 步沿用、不再问；旧值是「无」或现状已没有这类测试时，
  按现状重新确定，需要选时问用户。
- 表下「按语言惯例放测试的语言」：按项目现状重新确定。

{{include: state-mismatch}}
