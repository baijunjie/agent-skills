X=${CODEX_HOME:-$HOME/.codex}
# 每个 skill 各自决定写入位置：$HOME/.agents/skills/<名> 已有就原地更新它，否则装到 $X/skills/<名>。
# 别两处各放一份同名 skill：两处都已存在时函数报错，停下来问用户，不自行删除其中一份。
codex_skill_dir() {
  if [ ! -d "$HOME/.agents/skills/$1" ]; then
    echo "$X/skills/$1"
  elif [ -d "$X/skills/$1" ]; then
    echo "$1：$HOME/.agents/skills 与 $X/skills 下都有，停下来问用户保留哪一份" >&2
    return 1
  else
    echo "$HOME/.agents/skills/$1"
  fi
}
