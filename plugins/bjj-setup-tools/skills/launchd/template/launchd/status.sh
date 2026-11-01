#!/bin/sh
#
# 一眼看清本项目的定时任务现在是什么状态：装了哪几条、加载了没、上次跑成什么样、日志最后几行。
#
#   sh <本目录>/status.sh          日志默认看最后 8 行
#   sh <本目录>/status.sh 20       看最后 20 行
#   sh <本目录>/status.sh 0        不看日志
#
set -euf   # -f 关掉通配：cron 字段里的 * 必须按字面走词拆分，不能被当成文件名通配

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

LOG_LINES=${1:-8}
case "$LOG_LINES" in
  ''|*[!0-9]*) die "日志行数要是个非负整数: $LOG_LINES" ;;
esac

require_launchctl

plists=$(installed_plists)
if [ -z "$plists" ]; then
  printf '没有装任何任务（标签前缀 %s）\n' "$LABEL_PREFIX"
  printf '装：sh %s/install.sh\n' "$SCRIPT_DIR"
  exit 0
fi

# plutil -extract 取不到键时返回非 0，这里统一吞掉，由调用方按空值处理
pl() {
  plutil -extract "$2" raw -o - -- "$1" 2>/dev/null </dev/null || true
}

printf '定时任务状态（标签前缀 %s）\n' "$LABEL_PREFIX"
printf '  项目目录: %s\n' "$PROJECT_ROOT"
printf '  清单文件: %s\n' "$TASKS_FILE"
printf '\n'

# launchctl list 一次取全，省得每条任务都 fork 一次
loaded=$(launchctl list 2>/dev/null </dev/null || true)

while IFS= read -r p; do
  [ -n "$p" ] || continue
  label=$(label_of "$p")

  # 任务名与原始 cron 表达式写在 plist 的注释行里（install.sh 生成时放进去的）
  desc=$(sed -n 's/.*任务：\(.*\)-->.*/\1/p' "$p" | head -n 1)
  [ -n "$desc" ] || desc="（plist 里没有任务注释，可能是手改过）"

  owner=$(plist_owner "$p")

  printf '%s\n' "$desc"
  printf '  标签    %s\n' "$label"

  interval=$(pl "$p" StartInterval)
  if [ -n "$interval" ]; then
    printf '  触发    每 %s 秒\n' "$interval"
  elif grep -q StartCalendarInterval "$p"; then
    # 日历条目是缩进 4 个空格的 <dict>；根 dict 与 EnvironmentVariables 那层不算在内
    printf '  触发    日历式，%s 个时刻（plutil -p %s 看全部）\n' \
      "$(grep -c '^    <dict>' "$p" | tr -d ' ')" "$p"
  elif [ -n "$(pl "$p" RunAtLoad)" ]; then
    printf '  触发    仅加载时跑一次\n'
  else
    printf '  触发    未知\n'
  fi

  # 命令是 install.sh 包过一层重定向的，显示时把壳剥掉，只给人看真正执行的那段
  cmd=$(pl "$p" ProgramArguments.2)
  cmd=$(printf '%s' "$cmd" | sed -e 's/^{ //' -e 's/ ; } >>.*$//')
  printf '  命令    %s\n' "$cmd"

  line=$(printf '%s\n' "$loaded" | awk -v l="$label" '$3 == l { print; exit }')
  if [ -z "$line" ]; then
    printf '  加载    否 —— plist 在但没加载，跑一次 install.sh\n'
  else
    pid=$(printf '%s' "$line" | awk '{print $1}')
    code=$(printf '%s' "$line" | awk '{print $2}')
    runs=$(launchctl print "$DOMAIN/$label" 2>/dev/null </dev/null | sed -n 's/.*runs = \([0-9]*\).*/\1/p' | head -n 1)
    [ -n "$runs" ] || runs='?'
    if [ "$pid" = '-' ]; then
      state="此刻没在跑"
    else
      state="正在跑（PID $pid）"
    fi
    case "$code" in
      0)  verdict='上次退出码 0' ;;
      -*) verdict="上次被信号杀掉（$code）" ;;
      *)  verdict="上次退出码 $code —— 失败，看下面的日志" ;;
    esac
    printf '  加载    是，%s，%s，累计跑过 %s 次\n' "$state" "$verdict" "$runs"
  fi

  if [ -n "$owner" ] && [ "$owner" != "$PROJECT_ROOT" ]; then
    printf '  注意    这个 plist 是 %s 装的，不是当前项目\n' "$owner"
  fi
  printf '\n'
done <<LIST
$plists
LIST

if [ "$LOG_LINES" -gt 0 ]; then
  if [ -f "$LOG_FILE" ]; then
    printf '日志 %s（最后 %s 行）\n' "$LOG_FILE" "$LOG_LINES"
    tail -n "$LOG_LINES" "$LOG_FILE" | sed 's/^/  /'
  else
    printf '日志 %s —— 还没有这个文件，说明任务一次都没成功跑起来过\n' "$LOG_FILE"
  fi
fi
