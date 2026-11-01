<!--
流程脚本在「写入前检查」里要查的冲突：与另一个安装器共同拥有的 `.githooks/flow-*.sh`。
装流程脚本的安装器（bjj-setup-git 的 pr 与 worktree）在「本安装器另外要查的冲突：」下 include，
用变量 flow_peer 写另一个安装器名。
-->

- `.githooks/` 下的流程脚本（`flow-*.sh`）由本安装器与 `{{flow_peer}}` 共同拥有：已有同一套文件不算冲突，照常重装、不问；
  `.githooks/` 里别的文件（如 `bjj-setup-git:revert-gate` 装的回退闸门）只由写它的那个安装器管，不碰。
