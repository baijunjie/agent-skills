---
name: gallery
description: {{scope_lead}}agent-gallery skill 与 gallery-writer 子代理，按技术栈搭起 UI gallery 与快速检查。{{scope_tail}}用于"给项目配 UI gallery""装 gallery-writer""UI 改动先预览确认"等场景。
disable-model-invocation: true
---

# 安装 UI 状态 gallery

装两样东西：`agent-gallery` skill（改 gallery 怎么派、快速检查、交付时的预览与收尾清理）与维护 gallery 的 `gallery-writer` 子代理；
并按项目的技术栈选定、搭起 gallery 机制本身与它的快速检查：项目已有就沿用，没有就推荐方案、由用户选定。
本安装器不往指令文件写任何内容。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: skill-priority-project}}
{{include: subagent-rule}}

{{include: pre-write}}

本安装器另外要查的冲突：第 8 步要补的依赖、配置项、运行入口（`package.json` scripts、Makefile target 等）与忽略规则，
项目里已有同名而取值或命令不同的。这一项连同第 8 步要写的文件的查软链、查冲突，在第 6 步写入前做（要写什么第 3–5 步已定下），有问题照「写入前检查」处理；重装时只查这次要补写的，项目里已有的按第 8 步归项目所有，只核对、不问。

## gallery 必须具备的

不论选哪种方案、第三方还是自建，搭成后都要具备下面几项。补缺项的办法与方案、检查工具一样，都优先成熟的第三方，满足不了才自建。
前两项是快速检查的前提，补不上就停止安装；其余几项对该平台确实不适用、补不上或用户不接受补法的，由用户定停止安装还是记明缺项后继续：

| 能力 | 用来做什么 |
|---|---|
| 能程序化列出全部场景 | 快速检查逐个遍历，核对覆盖 |
| 场景渲染就绪、失败（mock 答不上、渲染异常、未捕获错误）能被程序读出 | 快速检查据此判通过与否 |
| 每个场景有稳定的直达入口（URL、deep link、启动参数等），主题、语言、尺寸等查看条件能写进入口 | 预览时给用户直达入口，同一个入口复现同一个界面 |
| 不依赖真实后端；mock 与真实接口共用一份类型或契约 | 摆出真实环境难以到达的状态；契约变了 mock 报错 |
| 不进生产构建产物 | 不把 mock 与调试页面发布出去 |
| 能从任一工作副本单独启动，多个工作副本同时启动互不干扰 | 在开发分支上起预览，不影响别处在跑的服务 |

## 通用步骤

项目没有 UI、用户不建 gallery、用户连渲染冒烟也不要、或「gallery 必须具备的」前两项补不上时，停止安装，告知用户没装成；第 6 步之前停止的不写任何文件。
第 6 步之后中断或停止的：是重装的，立即把第 1 步读到的旧约定原样填回；再逐项列出已写的改动（含第 6、7 步装出的 skill 与子代理），由用户定留不留。
安装中为验证而启动的服务，验证完就停掉；会用真实账号或写真实数据的，先问用户。

1. **读旧约定**：已装过的（所在宿主安装节里 skill 的安装位置已有 `SKILL.md`；没有时看另一宿主的安装位置），先读出旧 skill 的「本项目约定」一节，
   作为后续各步的依据（见「重装」）；都没装过就跳过。
2. **确认项目有 UI**：找界面代码（Web 前端、移动端、桌面端界面）。monorepo 列出有 UI 的包，请用户确认这次装哪些，后面各步逐包处理。
3. **定 gallery 方案**：
   - 该包已有 gallery（第三方的组件工作台，或自建的场景页面）就沿用，同一个包里多套并存时问用户。
     已有场景另有用途（组件文档、设计评审、视觉回归基线等）的，问用户 `gallery-writer` 管哪部分，不归它管的写进约定。
   - 没有就推荐一个并说明理由，问用户：优先项目技术栈的主流方案，能直接渲染项目的真实组件、维护活跃。
   - 对照「gallery 必须具备的」逐项核对所选方案（含沿用的），缺项的补法列给用户确认。
   用户选定后只记下，搭建在第 8 步。
4. **定 UI 检查项**：渲染冒烟必有（每个场景就绪、没有失败信号、没有未捕获错误）。其余按项目实际有的查看条件（语言含从右到左、主题、宽度等）
   与质量要求（无障碍、外观稳定等）推荐，列给用户选。全量快速检查要快到每次交付都跑得起：会明显拖慢全量的检查（如截图比对）另设命令，不进快速检查。
   再按项目结构列出共享层示例（改了会波及多个场景的目录与文件，如共享组件、样式与主题、i18n 机制、多个场景共用的 mock、契约与类型、gallery 机制），请用户确认。
5. **定预览方式**：应用本身能不能从当前工作副本单独启动、怎么避开别的工作副本、访问时要不要登录或配置；应用离不开真实后端、或拿不到预览所需条件（如登录凭据）的，只用 gallery 预览。
   再定预览临时位置：被版本库忽略、按工作副本隔离，只为预览加的临时场景放在 gallery 能加载到的地方，预览启动的服务与装上的构建记在那里；平台上两条做不到同时满足的，问用户。
6. **写入 skill**：执行所在宿主安装节里写入 skill 的命令，已有的整份覆盖。
7. **装子代理**：执行所在宿主安装节里装子代理的命令，已有的整份覆盖。
8. **搭建 gallery**：
   - 改共享文件（`package.json`、配置、忽略规则等）前先记下原值，中断或停止时连同改动一起列给用户；按第 3–5 步定下的装依赖、写配置，补齐缺项，搭好第 4 步的检查，补上打开 gallery、快速检查全量与指定场景的运行入口与临时位置的忽略规则；
     已有的 gallery 不重建，已有的场景不搬。本步写出的依赖、配置、运行入口与 gallery 机制装好后归项目所有：重装时只核对「gallery 必须具备的」与检查项是否仍满足，缺了才补（约定里已记明的缺项不再补、不再问），不按「查手改」列出、也不覆盖。
   - `gallery-writer` 管的场景一个都还没有的，派刚装好的 `gallery-writer` 为一个代表性界面写第一个场景：交代第 3–5 步定下的方案、检查项与本步补上的命令，
     并说明 skill 的「本项目约定」尚未填写、以这次交代的为准。当前会话还调不到新装的 `gallery-writer` 时，派一个通用子代理，
     把 `gallery-writer` 定义的正文连同交代一起给它；没有子代理机制就按该定义自己写。
   - 跑通全量快速检查，并从当前工作副本启动一次 gallery、打开一个场景的直达入口确认看得到。
     已有场景跑不过的，列出清单，由用户定照样装完还是停止安装；不改应用代码，也不放宽检查。
   - 为既有界面补齐场景不在安装里做：列出项目里还没有场景的主要界面，留到第 10 步告知用户，可作为单独任务派 `gallery-writer` 补。
9. **填本项目约定**：把装好的 skill「本项目约定」一节里每个 `<…>` 连同尖括号换成实际值，尖括号里的说明不保留；
   路径与命令写成代码体，「无」不用代码体。表里每个 UI 包一行，表下各项各包不同时分别写明；表下各项写第 4、5 步定下的结果。表里与表下的每条命令都要实际跑过。
10. **告知用户**：依赖清单、配置、运行入口与忽略规则的改动要连同装出的文件一起提交进版本库；第 8 步写了场景的，说明写的是哪个、快速检查是否通过，它也要提交；
    列出还没有场景的主要界面与跑不过的已有场景。项目已装 `setup-agent:workflow` 的，重装它才会把 gallery 与 UI 预览写进交付前的步骤。其余见所在宿主安装节。

## Claude Code 项目级安装

skill 装在 `.claude/skills/agent-gallery/SKILL.md`。

写入 skill（第 6 步）：

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/skills/agent-gallery
cp "$TEMPLATE_DIR/agent-gallery/SKILL.template.md" .claude/skills/agent-gallery/SKILL.md
```

装子代理（第 7 步）：

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/agents
cp "$TEMPLATE_DIR/agents/gallery-writer.md" .claude/agents/
```

**告知用户**：`.claude/skills/agent-gallery/` 与 `.claude/agents/gallery-writer.md` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。装好后可用 `/agent-gallery` 调用，也会按描述自动触发；
重启 Claude Code 后生效。

## Codex 项目级安装

skill 装在 `.agents/skills/agent-gallery/SKILL.md`。

写入 skill（第 6 步）：

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/agent-gallery
cp "$TEMPLATE_DIR/agent-gallery/SKILL.template.md" .agents/skills/agent-gallery/SKILL.md
```

装子代理（第 7 步）：用渲染脚本的 `--replace` 替换同名旧 `.toml`。

```bash
{{include: project-root}}
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
mkdir -p .codex/agents
python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/gallery-writer.md"
```

**告知用户**：`.agents/skills/agent-gallery/` 与 `.codex/agents/gallery-writer.toml` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 或 `.codex/` 的项目要为这两处加例外。装好后可用 `$agent-gallery` 调用，
也会按描述自动触发；开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：「本项目约定」一节整节，第 1 步读出，第 9 步填回。约定的表还只剩 `<…>`、其中的命令本身执行不了（场景跑不过不算）、或用户转达了装出的 skill 报告约定要改的项时，不算无变更，照常重装并重新确定这些位置。第 8 步写出的依赖、配置与运行入口不进比对，只按第 8 步核对。

- 表：按第 2、3 步与只读查看的项目现状重新确定，确定不了的才沿用旧表；第 8 步补出的命令与旧值不同的，第 9 步填表前再问；第 3 步用户定的方案与 `gallery-writer` 管的范围，方案还在用就沿用、不再问。
- 表下「UI 检查项」：用户选定的检查项原样沿用，不再问；工具已不在项目里的重新问。
- 表下「共享层示例」：用户确认过的原样沿用，已不存在的路径去掉；项目里新出现的共享目录按第 4 步列给用户确认。
- 表下「应用预览」：按第 5 步从项目现状重新确定，确定不了的沿用。
- 表下「预览临时位置」：已填的原样保留，换了会认不出旧记录里的服务与构建；还没填的按第 5 步定。

{{include: state-mismatch}}
