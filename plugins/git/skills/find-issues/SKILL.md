---
name: find-issues
description: 在指定的 Git 仓库中搜索与问题描述相关的 Issue 和 PR。用于"这个问题上游有人提过吗""帮我搜下 xxx 仓库的 issue""查查有没有相关 PR"等场景。
---

# 查找 Issue / PR

在指定的 Git 仓库中搜索与问题描述相关的 Issue 和 PR。

参数格式：`<仓库地址> <问题描述>`
Claude Code 示例：`/git:find-issues https://github.com/anthropics/claude-code 快捷键无法自定义`
Codex 示例：`$git:find-issues https://github.com/anthropics/claude-code 快捷键无法自定义`

请从当前用户请求中解析仓库地址和问题描述：

1. 如果缺少仓库地址或问题描述，请向用户询问缺失的信息，拿到所有信息后再继续
2. 从仓库地址中提取 `owner/repo`（支持 `https://github.com/owner/repo` 或 `owner/repo` 格式）
3. 使用 `gh search issues` 和 `gh search prs` 在该仓库中搜索与问题描述相关的内容
4. 将搜索结果以列表形式输出，每项包含：
   - 标题
   - 链接
   - 状态（open/closed）
   - 简要说明其与问题的关联
5. 如果没有找到相关结果，告知用户并建议调整描述或手动创建 Issue
