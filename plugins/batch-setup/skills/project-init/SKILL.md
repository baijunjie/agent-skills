---
name: project-init
description: 给当前项目装上（或更新）一套默认的开发配置：按序读取并执行 setup-agent 的 subagents、docs、change-check、bug、plan、workflow 与 setup-git 的 worktree、pr 八个安装器，不装输出风格与单元测试。全部只装进当前项目，随仓库提交。用于"初始化项目""给新项目装默认的 agent 配置""一次装好项目的开发流程""项目 init"等场景。
disable-model-invocation: true
---

# 初始化项目的默认开发配置

本 skill自己不写任何文件，也没有模板：它按固定顺序读取下面八个安装器的 `SKILL.md`，照其中的步骤逐个安装，全部装进**当前项目**。
那八个安装器禁止模型调用，所以不能通过 skill 机制触发，只能读文件照做；它们的写入前检查、冲突处理、重装与定制值都照它们自己的 `SKILL.md` 执行，本 skill不替它们做、也不改它们的做法。

## 要装的安装器

按这个顺序，一个装完再装下一个：

| 顺序 | 安装器 | 所在 plugin | 排在这里的原因 |
|---|---|---|---|
| 1 | `setup-agent:subagents` | `setup-agent` | 无依赖，先装通用的子代理分派规则与子代理 |
| 2 | `setup-agent:docs` | `setup-agent` | 工作流要按它装出的 `agent-docs` 编排 |
| 3 | `setup-agent:change-check` | `setup-agent` | 工作流要按它装出的 `agent-change-check` 编排 |
| 4 | `setup-agent:bug` | `setup-agent` | 无依赖 |
| 5 | `setup-agent:plan` | `setup-agent` | 无依赖 |
| 6 | `setup-git:worktree` | `setup-git` | 无依赖 |
| 7 | `setup-git:pr` | `setup-git` | 无依赖 |
| 8 | `setup-agent:workflow` | `setup-agent` | 只编排已装进项目的专职 skill，必须排在 2、3 之后，放最后 |

**不装**：`setup-agent:report-style`（回答风格是个人偏好，要用单独装）与 `setup-agent:unit-test`
（项目初始化时还没有可沿用的测试框架，等有了再单独装；装好后重跑 `setup-agent:workflow`，工作流才会写进测试步骤）。

## 项目级安装

1. **确认在 git 仓库里**：当前目录不是 git 仓库时汇报，不装任何东西。
2. **找到兄弟 plugin**：`setup-agent` 与 `setup-git` 装在本 plugin 的同级目录下，每个 plugin 一层版本目录。
   用下面的命令取各自的最新版本目录，两个 plugin 的目录都要有；命令输出「找不到 plugin」或退出码非零就汇报并停下，不要自己安装 plugin：

   ```bash
   if [ -n "${PLUGIN_ROOT:-}" ]; then
     SELF="$PLUGIN_ROOT"
   elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
     SELF="$CLAUDE_PLUGIN_ROOT"
   else
     SELF="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/../.."
   fi
   BASE=$(cd "$SELF/.." && pwd -P)
   for p in setup-agent setup-git; do
     v=$(ls "$BASE/../$p" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
     [ -n "$v" ] || { echo "找不到 plugin：$p" >&2; rc=1; continue; }
     echo "$p $(cd "$BASE/../$p/$v" && pwd -P)"
   done
   exit "${rc:-0}"
   ```

   缓存里会残留旧版本目录，只取版本号最大的那个；`$SELF` 所在的目录名是本 plugin 的版本，`$BASE` 是本 plugin 的目录，`$BASE/..` 才是各 plugin 并列的那一层。
3. **按顺序读取并执行**：对上表每个安装器，读 `<plugin 目录>/skills/<skill>/SKILL.md`，执行当前宿主对应的**项目级安装**分支，同时遵守：
   - 安装节之外的节该做的照样做（如 `setup-git:pr` 的「装回退闸门」）：它们不分宿主，漏了不报错，装出来的东西却少一半。
   - 带「选作用域」的安装器直接按项目级走，不再问用户。
   - 它的「跨宿主约定」里的 shell 会按 `$PLUGIN_ROOT`、`$CLAUDE_PLUGIN_ROOT` 定位模板，这两个变量此时指向的是本 plugin，会读错模板：
     执行那段 shell 时先 `unset PLUGIN_ROOT CLAUDE_PLUGIN_ROOT`，并把 `SKILL_DIR` 设为**该安装器所在的目录**（`<plugin 目录>/skills/<skill>`）。
   - 它停下来问用户的（冲突、软链、要填的定制值如默认 PR 目标分支），把问题原样转给用户，
     等用户决定、该安装器装完后再读下一个；不替用户回答。
   - 某个安装器因用户决定不装、或安装失败而没装成的，记下原因，继续后面的，不回头重试；
     最后的 `workflow` 照样执行，它只编排已装进项目的 skill，缺的步骤自会省略。
4. **汇总**：在最终回复里按上表顺序逐个写清装成、没装成（附原因）；再说明没装的两个：`report-style` 与
   `unit-test` 怎么单独装。每个安装器自己的「告知用户」内容已在它那一步说过，不重复；
   只补一句整体提示：装出的文件与指令文件的改动都要提交进版本库才随仓库生效。

重复运行本 skill就是把这八个按当前模板全部重装一遍。
