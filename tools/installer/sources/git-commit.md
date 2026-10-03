---
name: commit
description: {{scope_lead}}按 Conventional Commits 规范生成提交的 git-commit skill。{{scope_tail}}用于"装 git-commit skill""给项目配提交规范""统一 commit message 格式"等场景。
disable-model-invocation: true
---

# 安装 git-commit skill

装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: scope-select}}

{{include: skill-priority}}

{{include: pre-write}}

本安装器另外要查的冲突：无。

{{include: skill-targets}}

{{include: reinstall}}

本安装器的定制值：无。

{{include: state-mismatch}}
