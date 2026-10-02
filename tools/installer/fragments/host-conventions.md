<!--
模板资源路径的解析说明，与定义 SETUP_ROOT、TEMPLATE_DIR 的 shell；TEMPLATE_DIR 那行末尾接变量 extra_env。
每个源文件都 include 一次，放在源文件自己写的「## 跨宿主约定」标题之下。
-->

模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；两者都为空时，先把 `SKILL_DIR`
设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），再按相对路径定位。
下面的变量定义要和后续命令放在同一次 shell 调用里，分开执行就每次重新定义：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  SETUP_ROOT="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/../.."
fi
TEMPLATE_DIR="$SETUP_ROOT/skills/{{skill}}/template{{template_sub}}"{{extra_env}}
```
