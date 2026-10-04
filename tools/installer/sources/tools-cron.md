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

- 项目里不是本安装器装出的 crontab 安装脚本，或项目已在用 crontab 以外的定时机制（本安装器只装 crontab 这一套）。
- 第 6 步的统一入口里已有同名、命令不同的 `cron:install` / `cron:uninstall` 或对应 target。
- 指令文件标记范围之外已有定时任务怎么改的说明。

## 项目级安装

1. **定脚本位置**：已有本安装器装出的 `cron/`（模板的 `common.sh`、`install.sh`、`uninstall.sh`、`tasks.conf`）就沿用它的位置；
   否则放进项目已有脚本目录（`scripts/`、`bin/`、`tools/` 等）下的 `cron/`，没有就用 `scripts/cron/`。
2. **拷贝模板**：已装过的，先按「重装」读出定制值，再执行下面的命令，已有的同名文件整份覆盖。`D` 设为第 1 步定的脚本目录，相对项目根目录（如 `scripts`）：

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   D=<脚本目录>
   : "${D:?}"
   mkdir -p "$D/cron"
   cp "$TEMPLATE_DIR/"* "$D/cron/"
   chmod +x "$D/cron/install.sh" "$D/cron/uninstall.sh"
   ```

3. **对齐项目**：直接改 `common.sh` 里下面三个变量的默认值：

   | 变量 | 记录什么 | 怎么定 | 模板默认值 |
   |------|----------|--------|------------|
   | `PROJECT_ROOT` | 项目根目录 | 由项目现状得出：脚本不在 `<项目根>/<一级目录>/cron/` 这个深度时只改 `../..` 的层级，不写绝对路径（`common.sh` 随仓库提交）；判断不了时沿用第 2 步读出的旧值（首次安装用模板默认值） | 脚本目录上溯两级 |
   | `LOG_DIR` | 任务输出的日志目录 | 由项目现状得出：项目已有约定的日志目录时用它；判断不了时沿用第 2 步读出的旧值（首次安装用模板默认值） | `<项目根>/logs/cron` |
   | `CRON_TAG` | crontab 区块标记，要求项目移动后不变、不与别的项目撞车 | 旧 `common.sh` 里还是模板默认值（首次安装看新拷贝的）、算出的又是 `P<数字>`（取自项目根路径的 cksum，项目一移动就变）时，问用户要一个固定标记（用户提供），用户没意见就填这个 `P<数字>`；其余情形重装时旧值原样填回、首次安装保持模板默认值，用户要求时才填固定标记 | 由项目根目录名算出；目录名含非 ASCII 字符或没有字母数字时取项目根路径的 cksum |

   先定好 `PROJECT_ROOT`（重装时 `CRON_TAG` 先按旧值填回），再执行 `sh <脚本目录>/cron/install.sh --dry-run`，按首行 `# >>> CRON:<标记> >>>` 里的标记与上表定好 `LOG_DIR`、`CRON_TAG`，再跑一次确认不撞车。
   标记撞车（`--dry-run` 报错，或只读的 `crontab -l` 里同标记的区块下一行记的项目根不是本项目）时，问用户那个项目还在不在用：在用就要一个固定标记，已弃用就请用户先在那个项目里卸掉它的区块再装。
   重装时在只读的 `crontab -l` 里找本项目的旧区块（项目搬家、改名后它记的还是旧标记与旧项目根），认不准就问用户；它的标记与最终定下的不同时记下旧标记，第 9 步要用。

4. **填任务清单**：任务只写在 `tasks.conf` 的界线行 `# ---- 本项目的任务写在这一行之后 ----` 之后。
   先按「重装」填回读出的旧内容，再加用户已有的其它定时需求；**不要凭空编任务**，没有明确任务就让界线行之后保持空白交付。新加的任务要满足：
   - 命令在项目根目录下能直接跑通，要先编译的指向编译产物；
   - 解释器由版本管理器按会话注入 PATH 的（fnm、nvm 的 shell 集成等），写解释器的绝对路径；
   - 可能跑得比调度间隔还久的，拉长间隔或让脚本自己加锁，免得重叠执行；
   - 密钥等敏感值走项目原有的 `.env` / 配置文件，不写进 `tasks.conf`（它随仓库提交）。
5. **忽略日志目录**：`.gitignore` 还没忽略日志目录的，加上。
6. **注册入口**（项目有统一入口时才做）：`package.json` 加 `"cron:install"` / `"cron:uninstall"`，
   或 `Makefile` 加对应 target，命令就是 `sh <脚本目录>/cron/install.sh` / `uninstall.sh`。
7. **挂说明**：Codex 在项目根目录的 `AGENTS.md`、Claude Code 在 `CLAUDE.md` 里写下面这段（没有就新建），`<脚本目录>` 换成第 1 步定的位置；
   任务格式和参数只留在 `tasks.conf` 的注释里，不复制到这里：

   ```markdown
   <!-- {{marker}}:begin -->

   定时任务改 `<脚本目录>/cron/tasks.conf` 后执行 `sh <脚本目录>/cron/install.sh` 生效，不要直接 `crontab -e`。

   <!-- {{marker}}:end -->
   ```
8. **不要替用户执行 `install.sh`**：它改的是用户账号的 crontab，不是仓库内容；交付后告知用户自己跑，或明确征得同意再跑。
   `install.sh --dry-run` 只读 crontab，可以直接执行。
9. **告知用户**：
   - 装出的 `cron/` 与这次改到的指令文件、`.gitignore`、`package.json` / `Makefile` 都要提交；指令文件里的说明 Codex 开启新会话后生效，Claude Code 如未生效就重启。
   - crontab 每台机器、每个账号各一份：换机器或换用户、服务器部署的新版改了命令或路径、以及这次是重装的，都要重跑 `install.sh`；第 3 步记下了旧标记的，先 `CRON_TAG=<旧标记> sh <脚本目录>/cron/uninstall.sh` 再装，否则旧区块留在 crontab 里、任务跑两遍也不报错；卸载报撞车时不要硬删，按第 3 步的撞车处理。
   - 以后的任务只写在 `tasks.conf` 的界线行之后：界线行之前的改动，重装时只保留已启用的任务行。

{{include: reinstall}}

本安装器的定制值：

- `cron/` 所在的脚本目录：第 1 步按已装的位置沿用。
- `common.sh` 里 `PROJECT_ROOT`、`LOG_DIR`、`CRON_TAG` 的默认值：第 2 步读出，第 3 步按表重新确定或填回。
- `tasks.conf` 界线行之后的全部内容（任务行、被注释停用的任务、用户写的注释与空行），以及界线行之前已启用（不以 `#` 开头）的任务行：
  第 2 步读出，第 4 步原样填回到新模板的界线行之后，界线行之前的那些放在最前面。

{{include: state-mismatch}}
