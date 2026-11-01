#!/bin/sh
#
# 把 tasks.conf 里的定时任务装成当前用户的 LaunchAgent。
#
# 每条任务一个 plist，装在 ~/Library/LaunchAgents 下，文件名即标签：<前缀>.<序号>-<名称 slug>.plist。
# 重复执行即为更新：先把本前缀下已装的全部卸掉删掉，再按 tasks.conf 重装，别的项目的 plist 原样保留。
#
#   sh <本目录>/install.sh             安装 / 更新
#   sh <本目录>/install.sh --dry-run   只打印将要写入的 plist，不动 ~/Library/LaunchAgents
#
set -euf   # -f 关掉通配：cron 字段里的 * 必须按字面走词拆分，不能被当成文件名通配

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

DRY_RUN=0
case "${1:-}" in
  '') ;;
  --dry-run) DRY_RUN=1 ;;
  *) die "未知参数: $1（可用: --dry-run）" ;;
esac

# 取第 $1 段；-s 让没有分隔符的行整段落空，好在后面报出明确的错
field() {
  trim "$(printf '%s\n' "$2" | cut -s -d'|' -f"$1")"
}

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# 名称 → 标签里可用的 slug。LC_ALL=C 按字节处理：中文名折算出的 `-` 个数才不随 locale 变。
slugify() {
  _s=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')
  _s=$(printf '%s' "$_s" | cut -c1-24 | LC_ALL=C sed 's/-$//')
  [ -n "$_s" ] || _s=task
  printf '%s' "$_s"
}

# 展开一个 cron 字段成空格分隔的取值表，`*` 原样输出。支持 n、a-b、*/n、a-b/n 与逗号列表。
# 解析不了就返回 1，由调用方报错——装上一个语义不同的时间表比装不上更糟。
expand_field() {
  _spec=$1
  _lo=$2
  _hi=$3
  [ "$_spec" = '*' ] && { printf '*'; return 0; }
  _out=''
  for _part in $(printf '%s' "$_spec" | tr ',' ' '); do
    _step=1
    _base=$_part
    case "$_part" in
      */*) _base=${_part%%/*}; _step=${_part##*/} ;;
    esac
    case "$_step" in ''|*[!0-9]*) return 1 ;; esac
    [ "$_step" -ge 1 ] || return 1
    case "$_base" in
      '*') _a=$_lo; _b=$_hi ;;
      *-*) _a=${_base%%-*}; _b=${_base##*-} ;;
      *)
        _a=$_base
        # 「n/step」在 cron 里是从 n 起步到字段上限，不是只有 n 这一个值
        if [ "$_step" -eq 1 ]; then _b=$_base; else _b=$_hi; fi
        ;;
    esac
    case "$_a$_b" in ''|*[!0-9]*) return 1 ;; esac
    [ "$_a" -ge "$_lo" ] && [ "$_b" -le "$_hi" ] && [ "$_a" -le "$_b" ] || return 1
    _i=$_a
    while [ "$_i" -le "$_b" ]; do
      _out="$_out $_i"
      _i=$((_i + _step))
    done
  done
  [ -n "$(trim "$_out")" ] || return 1
  printf '%s' "$(printf '%s\n' $_out | sort -n -u | tr '\n' ' ')"
}

# 一条 StartCalendarInterval 字典；值为 `*` 的键省略
calendar_entry() {
  printf '    <dict>\n'
  [ "$1" = '*' ] || printf '      <key>Minute</key><integer>%s</integer>\n' "$1"
  [ "$2" = '*' ] || printf '      <key>Hour</key><integer>%s</integer>\n' "$2"
  [ "$3" = '*' ] || printf '      <key>Day</key><integer>%s</integer>\n' "$3"
  [ "$4" = '*' ] || printf '      <key>Month</key><integer>%s</integer>\n' "$4"
  [ "$5" = '*' ] || printf '      <key>Weekday</key><integer>%s</integer>\n' "$5"
  printf '    </dict>\n'
}

# cron 表达式 → plist 里的时间键。写到标准输出，解析不了就 die。
schedule_keys() {
  _name=$1
  _sched=$2

  case "$_sched" in
    @hourly)          printf '  <key>StartInterval</key><integer>3600</integer>\n'; return ;;
    @daily|@midnight) _sched='0 0 * * *' ;;
    @weekly)          _sched='0 0 * * 0' ;;
    @monthly)         _sched='0 0 1 * *' ;;
    @yearly|@annually) _sched='0 0 1 1 *' ;;
    @reboot)          printf '  <key>RunAtLoad</key><true/>\n'; return ;;
    @*) die "任务「${_name}」的快捷写法 $_sched 不支持（可用: @reboot @hourly @daily @weekly @monthly @yearly）" ;;
  esac

  _min=$(printf '%s\n' "$_sched" | awk '{print $1}')
  _hour=$(printf '%s\n' "$_sched" | awk '{print $2}')
  _dom=$(printf '%s\n' "$_sched" | awk '{print $3}')
  _mon=$(printf '%s\n' "$_sched" | awk '{print $4}')
  _dow=$(printf '%s\n' "$_sched" | awk '{print $5}')

  # 「每 N 分钟」用 StartInterval：机器睡过去再醒来时 launchd 会立刻补跑一次，
  # 而 StartCalendarInterval 只补跑错过的最后一个时刻，轮询型任务要前者。
  if [ "$_hour" = '*' ] && [ "$_dom" = '*' ] && [ "$_mon" = '*' ] && [ "$_dow" = '*' ]; then
    _n=''
    case "$_min" in
      '*') _n=1 ;;
      '*/'*) _n=${_min#*/} ;;
    esac
    if [ -n "$_n" ]; then
      case "$_n" in ''|*[!0-9]*) die "任务「${_name}」的分钟字段解析不了: $_min" ;; esac
      [ "$_n" -ge 1 ] || die "任务「${_name}」的步长必须 ≥ 1: $_min"
      printf '  <key>StartInterval</key><integer>%s</integer>\n' "$((_n * 60))"
      return
    fi
  fi

  _mins=$(expand_field "$_min" 0 59)   || die "任务「${_name}」的分钟字段解析不了: $_min"
  _hours=$(expand_field "$_hour" 0 23) || die "任务「${_name}」的小时字段解析不了: $_hour"
  _doms=$(expand_field "$_dom" 1 31)   || die "任务「${_name}」的日字段解析不了: $_dom"
  _mons=$(expand_field "$_mon" 1 12)   || die "任务「${_name}」的月字段解析不了: $_mon"
  _dows=$(expand_field "$_dow" 0 7)    || die "任务「${_name}」的星期字段解析不了: $_dow"

  # cron 里日与星期同时限定是「或」，launchd 是「与」，语义不同，不猜。
  if [ "$_doms" != '*' ] && [ "$_dows" != '*' ]; then
    die "任务「${_name}」同时限定了日和星期，cron 按「或」算而 launchd 按「与」算，拆成两条任务"
  fi
  # cron 的 7 与 0 都是周日，launchd 只认 0，去掉 7 免得多出一条等价条目
  case " $_dows " in
    *' 7 '*) _dows=$(printf '%s\n' $_dows | sed 's/^7$/0/' | sort -n -u | tr '\n' ' ') ;;
  esac

  _entries=''
  _count=0
  for _m in $_mins; do
    for _h in $_hours; do
      for _d in $_doms; do
        for _o in $_mons; do
          for _w in $_dows; do
            _count=$((_count + 1))
            [ "$_count" -le 200 ] || die "任务「${_name}」展开出超过 200 个时刻，用 */N 或拆成多条任务"
            _entries="$_entries$(calendar_entry "$_m" "$_h" "$_d" "$_o" "$_w")
"
          done
        done
      done
    done
  done

  printf '  <key>StartCalendarInterval</key>\n  <array>\n'
  printf '%s' "$_entries"
  printf '  </array>\n'
}

write_plist() {
  _label=$1
  _name=$2
  _sched=$3
  _offset=$4
  _cmd=$5
  _dest=$6

  # 命令整体交给 /bin/sh -c，日志由命令自己重定向——不用 plist 的 StandardOutPath / StandardErrorPath：
  # 那两个文件是 launchd 以自己的身份在 exec 之前打开的，日志落在外置宗卷上时会被 TCC 挡掉，
  # 整个任务起不来（退出码 78 EX_CONFIG）。交给 /bin/sh 自己开，走的才是 /bin/sh 的授权。
  # 命令外面套一层 { } 再重定向，否则命令里若有管道，日志只收得到最后一段的输出。
  _shcmd="{ $_cmd ; } >> \"$LOG_FILE\" 2>&1"
  [ "$_offset" = 0 ] || [ -z "$_offset" ] || _shcmd="sleep $_offset && $_shcmd"

  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '%s %s -->\n' "$OWNER_MARK" "$(xml_escape "$PROJECT_ROOT")"
    printf '<!-- 不要手改，改 tasks.conf 后重新执行 install.sh；任务：%s（%s）-->\n' \
      "$(xml_escape "$_name")" "$(xml_escape "$_sched")"
    printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    printf '<plist version="1.0">\n<dict>\n'
    printf '  <key>Label</key><string>%s</string>\n' "$(xml_escape "$_label")"
    printf '  <key>ProgramArguments</key>\n  <array>\n'
    printf '    <string>/bin/sh</string>\n    <string>-c</string>\n'
    printf '    <string>%s</string>\n' "$(xml_escape "$_shcmd")"
    printf '  </array>\n'
    printf '  <key>WorkingDirectory</key><string>%s</string>\n' "$(xml_escape "$PROJECT_ROOT")"
    printf '  <key>EnvironmentVariables</key>\n  <dict>\n'
    # launchd 给的 PATH 很小，nvm / fnm / homebrew 装的解释器都不在里面，这里把安装时的 PATH 固化进去。
    printf '    <key>PATH</key><string>%s</string>\n' "$(xml_escape "$PATH")"
    printf '  </dict>\n'
    schedule_keys "$_name" "$_sched"
    printf '</dict>\n</plist>\n'
  } > "$_dest"
}

[ -f "$TASKS_FILE" ] || die "找不到任务清单: $TASKS_FILE"

# dry-run 只读不写，所以不要求 launchctl（在别的系统上也能预览），但仍核对前缀没被别的项目占用。
[ "$DRY_RUN" -eq 1 ] || require_launchctl
check_prefix_owner

# dry-run 的首行给出标签前缀：任务清单还空着时也要看得到它，装之前就好核对撞不撞车。
if [ "$DRY_RUN" -eq 1 ]; then
  printf '标签前缀: %s\n' "$LABEL_PREFIX"
  printf '项目目录: %s\n' "$PROJECT_ROOT"
  printf '日志文件: %s\n' "$LOG_FILE"
  printf 'plist 目录: %s\n' "$AGENT_DIR"
fi

# 先把本前缀下已装的清掉，再按 tasks.conf 重装；tasks.conf 删掉的任务才不会留在机器上。
if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$AGENT_DIR" "$LOG_DIR"
  removed=$(remove_all)
  [ "$removed" = 0 ] || printf '已卸载旧的 %s 个 LaunchAgent\n' "$removed"
fi

index=0
installed=0
while IFS= read -r raw || [ -n "$raw" ]; do
  case "$(trim "$raw")" in
    ''|'#'*) continue ;;
  esac

  index=$((index + 1))
  name=$(field 1 "$raw")
  sched=$(field 2 "$raw")
  cmd=$(trim "$(printf '%s\n' "$raw" | cut -s -d'|' -f3-)")

  [ -n "$cmd" ] || die "任务「${name}」缺少命令，检查 $TASKS_FILE"

  # cron 表达式末尾的 "+秒,秒" 是子分钟调度偏移
  offsets=''
  case "$sched" in
    *' +'*)
      offsets=${sched##* +}
      sched=$(trim "${sched% +*}")
      ;;
  esac

  case "$sched" in
    @*) ;;
    *)
      [ "$(printf '%s\n' "$sched" | wc -w | tr -d ' ')" = 5 ] \
        || die "任务「${name}」的 cron 表达式不是 5 个字段: $sched" ;;
  esac

  slug=$(slugify "$name")
  off_list=$(printf '%s' "${offsets:-0}" | tr ',' ' ')
  off_count=$(printf '%s' "$off_list" | wc -w | tr -d ' ')
  for off in $off_list; do
    case "$off" in ''|*[!0-9]*) die "任务「${name}」的偏移不是秒数: $off" ;; esac
    # 多个偏移才在标签里带 -sN，单个偏移的标签保持干净
    if [ "$off_count" = 1 ]; then
      label="$LABEL_PREFIX.$index-$slug"
    else
      label="$LABEL_PREFIX.$index-$slug-s$off"
    fi
    dest="$AGENT_DIR/$label.plist"

    if [ "$DRY_RUN" -eq 1 ]; then
      tmp=$(mktemp)
      write_plist "$label" "$name" "$sched" "$off" "$cmd" "$tmp"
      printf '%s\n' "--- $dest ---"
      cat "$tmp"
      rm -f "$tmp"
      continue
    fi

    write_plist "$label" "$name" "$sched" "$off" "$cmd" "$dest"
    plutil -lint "$dest" >/dev/null </dev/null || die "生成的 plist 不合法: $dest"
    launchctl bootout "$DOMAIN/$label" >/dev/null 2>&1 </dev/null || true
    launchctl bootstrap "$DOMAIN" "$dest" </dev/null || die "launchctl bootstrap 失败: $dest"
    launchctl enable "$DOMAIN/$label" >/dev/null 2>&1 </dev/null || true
    installed=$((installed + 1))
    printf '  - %s  (%s%s)  →  %s\n' "$name" "$sched" \
      "$([ "$off" = 0 ] && printf '' || printf ' +%ss' "$off")" "$label"
  done
done < "$TASKS_FILE"

[ "$DRY_RUN" -eq 0 ] || exit 0

printf '已安装 %s 个 LaunchAgent（标签前缀 %s）\n' "$installed" "$LABEL_PREFIX"
printf '  项目目录: %s\n' "$PROJECT_ROOT"
printf '  日志文件: %s\n' "$LOG_FILE"
printf '  plist 目录: %s\n' "$AGENT_DIR"
printf '\n`sh %s/status.sh` 看状态，`sh %s/uninstall.sh` 卸载\n' "$SCRIPT_DIR" "$SCRIPT_DIR"
printf 'LaunchAgent 跟着当前用户的登录会话：注销或关机期间不跑，重新登录后自动加载。\n'
