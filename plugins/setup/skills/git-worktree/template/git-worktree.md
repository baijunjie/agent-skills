# 开发流程：Git Worktree

- 所有产生代码变更的任务，都必须在独立的 git worktree + 独立分支上开发，不要直接在主工作副本的主分支上改动。只读排查、答疑等不产生改动的操作除外。
- 开工前从最新的主分支创建：worktree 统一放在仓库内的 `.claude/worktrees/<分支短名>/`（Claude Code 原生 worktree 目录，其它工具沿用同一位置，便于 .gitignore 统一），分支名按变更类型取 `feat/xxx`、`fix/xxx`、`refactor/xxx`、`docs/xxx`。
- 整个开发过程（含编辑、构建、测试、质量检查）都在该 worktree 内进行；主工作副本保持干净，便于随时对照主分支。
- 同步主分支用 `git rebase <主分支>`，回主工作副本用 `git merge --ff-only <分支>`：快进失败说明 rebase 没做干净，不要退回裸 merge 生成 merge commit。
- 合并前必须确认：功能已验证通过、收尾自检（代码自审、文档同步、质量检查）已完成、已 rebase 到最新主分支——rebase 带进来的新代码没参与过之前的验证，构建 / 测试 / 格式检查要在合并后的主分支上重跑一遍才算数。
- 合并回主分支须先向用户确认；合并完成后立即 `git worktree remove` 掉该 worktree 并删除分支，这是合并动作的一部分，不必再问、不要留到下次。
