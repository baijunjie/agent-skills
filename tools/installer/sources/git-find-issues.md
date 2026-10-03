---
name: find-issues
description: {{scope_lead}}在指定 GitHub 仓库搜索相关 Issue 与 PR 的 git-find-issues skill。{{scope_tail}}用于"装 git-find-issues skill""装查 issue 的 skill""搜上游 Issue / PR"等场景。
disable-model-invocation: true
---

# 安装 git-find-issues skill

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
