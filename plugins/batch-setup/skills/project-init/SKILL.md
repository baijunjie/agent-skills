---
name: project-init
description: 给当前项目一次装上（或更新）一套默认的开发配置：setup-agent 的 subagents、docs、change-check、bug、plan、workflow 与 setup-git 的 worktree、pr 共八个安装器，不含输出风格与单元测试，全部只装进当前项目、随仓库提交。用于"初始化项目""给新项目装默认的 agent 配置""一次装好项目的开发流程""项目 init"等场景。
disable-model-invocation: true
---

# 初始化项目的默认开发配置

本 skill 自己不写任何文件：按下面的顺序读取八个安装器的 `SKILL.md`，照其中的步骤逐个装进**当前项目**。
那八个安装器禁止模型调用，只能读文件照做；它们的写入前检查、冲突处理、重装与定制值都照它们自己的 `SKILL.md` 执行；除下面「项目级安装」第 3 步列出的几点外，本 skill 不替它们做、也不改它们的做法。拿不准就汇报。

## 要装的安装器

一个装完再装下一个；`workflow` 只编排已装进项目的专职 skill，必须放最后：

1. `setup-agent:subagents`
2. `setup-agent:docs`
3. `setup-agent:change-check`
4. `setup-agent:bug`
5. `setup-agent:plan`
6. `setup-git:worktree`
7. `setup-git:pr`
8. `setup-agent:workflow`

**不装**：`setup-agent:report-style`（回答风格是个人偏好，要用单独装）与 `setup-agent:unit-test`
（项目初始化时还没有可沿用的测试框架，等有了再单独装；装好后重跑 `setup-agent:workflow`，工作流才会写进测试步骤）。

## 项目级安装

1. **确认在 git 仓库里**：当前目录不是 git 仓库时汇报，不装任何东西。
2. **找到兄弟 plugin**：取 `setup-agent` 与 `setup-git` 各自最新版本的目录；命令报「找不到 plugin」或退出码非零就汇报并停下，不要自己安装 plugin：

   ```bash
   ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/../..}}"
   bash "$ROOT/scripts/latest-plugins.sh" setup-agent setup-git
   ```

3. **按顺序读取并执行**：对每个安装器，读 `<plugin 目录>/skills/<skill>/SKILL.md`，执行当前宿主对应的**项目级安装**分支，同时遵守：
   - 安装节之外的节该做的照样做（如 `setup-git:pr` 的「装回退闸门」）：漏了不报错，装出来的东西却不全。
   - 带「选作用域」的安装器直接按项目级走，不再问用户。
   - 它的 shell 会先按 `$PLUGIN_ROOT`、`$CLAUDE_PLUGIN_ROOT` 定位模板，而它们此时指向本 plugin：
     执行该安装器里任何用到这两个变量的 shell，每次都先 `unset PLUGIN_ROOT CLAUDE_PLUGIN_ROOT`，并把 `SKILL_DIR` 设为**该安装器所在的目录**（`<plugin 目录>/skills/<skill>`）。
   - 它停下来问用户的（冲突、软链、要填的定制值如默认 PR 目标分支），原样转给用户，等用户决定、该安装器装完后再读下一个；不替用户回答。
   - 在写入任何文件或配置之前，因用户决定不装或失败而没装成的，记下原因，继续后面的，不回头重试；最后的 `workflow` 照样执行，缺的步骤它自会省略。
   - 已写入部分文件或配置后中途失败、或用户叫停的，停下汇报：列出已写入的，说明半装的 skill 会被 `workflow` 当作已装写进工作流且不报错，由用户决定清理（恢复到这次安装之前的状态，不是把列出的文件一律删掉）、重试还是保留后再继续。
4. **汇总**：在最终回复里按上面的顺序逐个写清装成、没装成（附原因）、半装后留着没清理的（附已写入的文件），再说明 `report-style` 与 `unit-test` 怎么单独装。
   最后提醒：装出的文件与指令文件的改动都要提交进版本库才随仓库生效。
