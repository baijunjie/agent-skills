
<!-- setup-agent:workflow:begin -->

# 工作流

本节只定开工前与交付前何时调用什么、按什么顺序、何时跳过；每一步怎么做以对应的 skill 为准，拿不准就汇报。

## 开工前

- 先确认分支是最新的：只 fetch 当前分支要合回去的那个分支（不必 fetch 全部），再看当前分支相对它有没有落后，落后就先对齐再动手。
<!-- if-installed: agent-docs -->
- 按 `agent-docs` skill 了解项目上下文。
<!-- end-if -->

## 交付前

自检针对本次改动全部写完后的一次**完整交付**，不是每一次编辑，阶段性提交也不算；用户要求推送、发 PR 或合并也算交付。交付时：

- 有需要用户确认的内容（待拍板的决定、要问的问题、用户说过要先过目的改动、影响较大的自行决定），
  先汇报，按反馈改完再重新判断。
- 没有就按以下顺序逐项自检：

<!-- if-installed: agent-unit-test -->
1. **补单元测试**：按 `agent-unit-test` skill 为本次改动补测试。
<!-- end-if -->
<!-- if-installed: agent-gallery -->
2. **gallery**：本次改动涉及 UI、mock 或 mock 依赖的接口契约时，按 `agent-gallery` skill 让 gallery 跟上并跑全量快速检查；都没涉及就跳过。
<!-- end-if -->
3. **静态检查**：执行项目约定的质量检查命令（格式化、类型检查、Lint 等），确认无报错。项目没约定就跳过。
<!-- if-installed: agent-change-check -->
4. **改动检查**：按 `agent-change-check` skill 审本次改动；按意见改了代码，先重跑静态检查与受影响的测试再复审；
   审查通过、或剩余意见已交给用户定后，才进入下一步。
<!-- end-if -->
<!-- if-installed: agent-docs -->
5. **文档更新**：本次改动要更新给后来者看的文档时，按 `agent-docs` skill 更新；与文档对齐时改了代码，
   重跑静态检查与受影响的测试。
<!-- end-if -->
<!-- if-installed: agent-gallery -->
6. **UI 预览**：本次改动涉及 UI 时，按 `agent-gallery` skill 从开发分支启动预览，把直达链接写进汇报，等用户确认；
   用户确认没问题、或同意把分支交出去（合并、推送提 PR 等）后，在交出去之前按它停掉预览、清理预览用的临时数据。没动 UI 就跳过。
<!-- end-if -->

## 本项目

（暂无。项目特有的步骤以上面的步骤名为锚点逐条写在这里，如「在『静态检查』之后：……」「『静态检查』的跳过条件：……」。）

<!-- setup-agent:workflow:end -->
