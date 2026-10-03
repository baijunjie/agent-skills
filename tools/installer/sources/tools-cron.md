---
name: cron
description: {{scope_lead}}一套 crontab 定时任务安装器——任务清单 tasks.conf 加 install.sh / uninstall.sh。{{scope_tail}}用于"给这个项目配定时任务""装个 cron 安装脚本""把脚本挂到 crontab 上"等场景。
disable-model-invocation: true
---

# 安装项目级 cron 定时任务安装器

## 跨宿主约定

只写入当前宿主对应的指令文件。

{{include: host-conventions}}

{{include: markers}}

{{include: pre-write}}

本安装器另外要查的冲突：

- 项目里不是本安装器装出的 crontab 安装脚本，或项目已在用 crontab 以外的定时机制（本安装器只会装 crontab 这一套）。
- 第 6 步的统一入口里已有同名、命令不同的 `cron:install` / `cron:uninstall` 或对应 target。
- 指令文件标记范围之外已有定时任务怎么改的说明。

## 项目级安装

1. **定脚本位置**：项目里已有本安装器装出的 `cron/`（即模板的 `common.sh`、`install.sh`、`uninstall.sh`、`tasks.conf`）
   就沿用它所在的位置；否则项目已有脚本目录（`scripts/`、`bin/`、`tools/` 等）就放进它下面的 `cron/`，
   再否则用 `scripts/cron/`。项目里已有别的 crontab 安装脚本或定时机制时，按用户在「写入前检查」里的选择定。
2. **拷贝模板**：已装过的，先读出旧 `common.sh` 里 `PROJECT_ROOT`、`LOG_DIR`、`CRON_TAG` 的默认值，
   以及旧 `tasks.conf` 界线行之后的全部内容与界线行之前已启用的任务行（见「重装」），再执行下面的命令，
   已有的同名文件整份覆盖。`D` 设为第 1 步定的脚本目录，相对项目根目录（如 `scripts`）：

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   D=<脚本目录>
   : "${D:?}"
   mkdir -p "$D/cron"
   cp "$TEMPLATE_DIR/"* "$D/cron/"
   chmod +x "$D/cron/install.sh" "$D/cron/uninstall.sh"
   ```

3. **对齐项目**：`common.sh` 里要填的是下面三个变量的默认值，**直接改默认值**：

   | 变量 | 记录什么 | 怎么定 | 模板默认值 |
   |------|----------|--------|------------|
   | `PROJECT_ROOT` | 项目根目录 | 由项目现状得出：脚本不在 `<项目根>/<一级目录>/cron/` 这个深度时只改 `../..` 的层级，不写绝对路径（`common.sh` 随仓库提交，写死本机路径别人用不了）；判断不了时沿用第 2 步读出的旧值 | 脚本目录上溯两级 |
   | `LOG_DIR` | 任务输出的日志目录 | 由项目现状得出：项目已有约定的日志目录时用它；判断不了时沿用旧值 | `<项目根>/logs/cron` |
   | `CRON_TAG` | crontab 区块标记 | 重装时第 2 步读出的旧值原样填回。首次安装看 `--dry-run` 输出首行 `# >>> CRON:<标记> >>>` 里的默认标记：默认值是 `P<数字>` 形式的（目录名含非 ASCII 字符或没有字母数字，如中文名、`项目2`、`---`），取的是项目根路径的 cksum，项目一移动标记就变、旧区块留在 crontab 里，所以首次安装就填成固定标记——问用户要一个，用户没意见就用这个 `P<数字>`；其余的不问，保持模板默认值，`--dry-run` 报标记撞车或用户要求固定标记时才填（用户提供） | 由项目根目录名算出，目录名含非 ASCII 字符或没有字母数字时取项目根路径的 cksum |

   首次安装先按表定好 `PROJECT_ROOT`，再执行 `sh <脚本目录>/cron/install.sh --dry-run`（只读，见第 8 步）取标记；按上表填完 `LOG_DIR`、`CRON_TAG` 后再跑一次，报标记撞车的问用户要一个固定标记。
   重新判断出的 `PROJECT_ROOT` 与旧值指向的目录不同时，记下旧值解析出的绝对路径，第 9 步要用。

4. **填任务清单**：任务只写在 `tasks.conf` 的界线行 `# ---- 本项目的任务写在这一行之后 ----` 之后。
   第 2 步读出的旧内容原样填回到界线行之后（界线行之前读出的已启用任务行放在最前面），再加上用户已有的其它定时需求，**不要凭空编任务**——
   没有明确任务就让界线行之后保持空白交付。新加任务之前确认四件事：
   - 命令在项目根目录下能直接跑通（脚本要先编译的，命令里指向编译产物，不是源码）；
   - 解释器由版本管理器按会话注入 PATH 的（fnm、nvm 的 shell 集成等），命令里写解释器的绝对路径；
   - 跑得比调度间隔还久的任务会重叠执行，要么拉长间隔，要么让脚本自己加锁；
   - 密钥之类的敏感值走项目原有的 `.env` / 配置文件，不要写进 `tasks.conf`。
5. **忽略日志目录**：`.gitignore` 里确认日志目录已被忽略。
6. **注册入口**（项目有统一入口时才做）：`package.json` 加 `"cron:install"` / `"cron:uninstall"`，
   或 `Makefile` 加对应 target，命令就是 `sh <脚本目录>/cron/install.sh` / `uninstall.sh`。
7. **挂说明**：Codex 在项目根目录的 `AGENTS.md`、Claude Code 在 `CLAUDE.md` 里写下面这一行（没有就新建），`<脚本目录>` 换成第 1 步定的位置；
   格式和参数留在 `tasks.conf` 的注释里，不要复制成第二份。这一行包在本安装器的标记里（见「指令文件里的标记」）：

   ```markdown
   <!-- {{marker}}:begin -->

   定时任务改 `<脚本目录>/cron/tasks.conf` 后执行 `sh <脚本目录>/cron/install.sh` 生效，不要直接 `crontab -e`。

   <!-- {{marker}}:end -->
   ```
8. **不要替用户执行 `install.sh`**：它改的是用户账号的 crontab，不是仓库内容。
   交付后告知用户自己跑，或者明确征得同意再跑。用 `install.sh --dry-run`
   预览生成的区块是安全的，可以直接执行：它只读 crontab，找得到 `crontab` 命令时顺带检查标记撞车（撞车就报错退出），找不到时跳过这项检查。
9. **告知用户**：装出去的 `cron/` 目录，以及这次改到的指令文件、`.gitignore`、`package.json` / `Makefile` 都要提交进版本库；
   指令文件里的说明 Codex 开启新会话后生效，Claude Code 如未生效就重启。
   crontab 是**每台机器、每个账号各一份**，换机器或换用户都要重跑一次 `install.sh`；
   服务器上部署了新版代码后命令或路径有变的、以及这次是重装的，也要重跑。
   第 3 步记下了旧的 `PROJECT_ROOT` 时，提示用户先按旧项目根卸载、再装：
   `CRON_PROJECT_ROOT=<旧项目根的绝对路径> sh <脚本目录>/cron/uninstall.sh`，然后 `sh <脚本目录>/cron/install.sh`——
   crontab 区块的标记默认由项目根目录名算出，区块里还记着项目根，项目根变了，新脚本要么找不到旧区块，要么报标记撞车。
   重装时保留的只有 `cron/` 所在位置、`common.sh` 里 `PROJECT_ROOT`、`LOG_DIR`、`CRON_TAG` 的默认值与 `tasks.conf` 里的任务，
   任务请只写在界线行之后。

{{include: reinstall}}

本安装器的定制值：

- `cron/` 所在的脚本目录：第 1 步按已装的位置沿用。
- `common.sh` 里 `PROJECT_ROOT`、`LOG_DIR`、`CRON_TAG` 的默认值：第 2 步读出，第 3 步按表重新确定或填回。
- `tasks.conf` 界线行 `# ---- 本项目的任务写在这一行之后 ----` 之后的全部内容——任务行、被注释停用的任务、
  用户写的说明注释与空行；以及界线行之前已启用的任务行（不以 `#` 开头，多是用户直接把示例改成了启用的任务）。
  第 2 步一并读出，第 4 步原样填回到新模板的界线行之后，界线行之前的那些放在整段最前面；
  找不到界线行时按「现状与预期不符时」问用户。

{{include: state-mismatch}}
