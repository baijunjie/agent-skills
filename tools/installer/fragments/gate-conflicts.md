<!--
回退闸门在「写入前检查」里要查的两条冲突：hook 入口、与另一个安装器共同拥有的三个脚本。
装闸门的安装器（setup-git 的 pr 与 worktree）在「本安装器另外要查的冲突：」下 include，
用变量 gate_peer 写另一个安装器名、gate_entry_ref 写本安装器里「融入」那一行在哪。
-->

- hook 入口：`git config core.hooksPath` 已设置，或 `$(git rev-parse --git-common-dir)/hooks/` 下已有不含
  `# revert-gate hook entry` 一行的 `reference-transaction` / `pre-push`。完全覆盖会让原来那套 hook 失效，询问时说明。
  入口里已调用 `.githooks/hook.sh` 的，按{{gate_entry_ref}}「融入」那一行处理，不算冲突。
- `.githooks/` 下的 `revert-gate.py`、`hook.sh`、`install.sh` 由本安装器与 `{{gate_peer}}` 共同拥有：
  这三个文件已有同一份闸门不算冲突，照常重装、不问；这三个之外，`.githooks/` 里别的文件只由写它的那个安装器管，不碰。
