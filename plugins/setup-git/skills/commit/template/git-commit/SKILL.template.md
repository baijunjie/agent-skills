---
name: git-commit
description: 按 Conventional Commits 规范生成 Git 提交。用于提交代码、撰写 commit message、选择 type/scope、归纳多点改动等场景。
---

# Git Commit

## 提交范围

- **一次调用只产生一个 commit，不拆分**：改动跨多个 type 也全部归入这一个提交。
- 暂存区有内容时只提交暂存区；暂存区为空时提交全部改动（含新文件）。
- 密钥、本地配置、构建产物这类不该入库的文件，先问用户，不要自己决定提交或排除。

## Type 与 scope

type 只用 `feat` `fix` `refactor` `perf` `style` `docs` `test` `build` `ci` `chore` `revert`，按以下原则取：

- type 取**主要改动**；为它服务的测试、文档、依赖、配置与代码适配是配套产物，不决定 type（新功能附带测试仍是 `feat`，升级依赖连带的代码适配仍是 `build`）。
- 主次分不清时，改变对外行为的优先于不改变的：修 bug 顺便重构取 `fix`，逻辑与格式一起改按逻辑归类。
- 配置按是否影响运行行为分：新增影响运行行为的配置项是 `feat`，只动工具、IDE、忽略文件等工程配置是 `chore`；打包与依赖归 `build`，CI / CD 与发布配置归 `ci`。
- `style` 只限不改语义的格式（含删未用 import、调 import 顺序）；文档与注释里的内容，包括文档中的代码示例，归 `docs`。

scope 优先用受影响的包 / 模块名，单包内可细到子模块；跨包或难以归类时省略。

## 格式

```
<type>[(<scope>)][!]: <subject>

[optional body]

[optional footer]
```

- subject ≤ 72 列，按显示宽度计（全角字符占两列），句末不加标点；英文用祈使句、首字母小写；概括整体意图，细节留给 body。
- body 在 subject 说不清「为什么」、或多个改动点需分别交代时写，每行同样 ≤ 72 列；改动点用 `- ` 逐条列出，一条一件事，按重要性排序。
- 不兼容改动在 type / scope 后加 `!`，并在 footer 写 `BREAKING CHANGE: <说明>`。
- 提交信息语言与仓库历史保持一致，没有历史时随用户的语言。
- message 通过 HEREDOC 传入，保留换行。

## 撰写身份

- 不要在 commit 消息里留下任何 AI 痕迹：不写 `Co-Authored-By`、不写「Generated with …」、不提 AI 协助，以人类开发者的口吻撰写。

拿不准就汇报。
