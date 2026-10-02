<!--
切到仓库根目录的一行 shell，不在 git 仓库里时整条命令失败退出。
由要在仓库根目录执行的命令块与 skill-targets include；一个安装器里可以出现多次。
-->

top=$(git rev-parse --show-toplevel) && cd "$top" || exit 1
