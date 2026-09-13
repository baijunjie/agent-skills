---
name: cron
description: 给当前项目装上（或更新）一套 crontab 定时任务安装器——任务清单 tasks.conf 加 install.sh / uninstall.sh，随仓库提交。用于"给这个项目配定时任务""装个 cron 安装脚本""把脚本挂到 crontab 上""加一个每天跑的定时任务"等场景。
disable-model-invocation: true
---

# 安装项目级 cron 定时任务安装器

把「定时任务写在哪、怎么装进 crontab、怎么卸载」落成项目自己的 sh 脚本，随仓库提交。
装好后改任务只动 `tasks.conf`，不用记 crontab 语法，也不用 `crontab -e` 手工编辑。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 机制

- 任务清单 `tasks.conf` 一行一个任务：`名称 | cron 表达式 [+秒偏移] | 命令`。
- `install.sh` 把清单展开成 crontab 记录，包在 `# >>> CRON:<TAG> >>>` 标记区块里写回，
  区块外的内容原样保留；`TAG` 取项目目录名，同一份 crontab 里多个项目互不干扰。
- 区块固化安装时的 `PATH`，解决 cron 环境找不到 nvm / pyenv / homebrew 装的解释器。

## 步骤

1. **定脚本位置**：项目已有脚本目录（`scripts/`、`bin/`、`tools/` 等）就放进它下面的 `cron/`，
   否则用 `scripts/cron/`。
2. **拷贝模板**：

   ```bash
   mkdir -p scripts/cron
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/cron/template/cron/"* scripts/cron/
   chmod +x scripts/cron/install.sh scripts/cron/uninstall.sh
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时（不在 plugin 环境里运行），用本 skill 目录下的 `template/cron/`。
3. **对齐项目**：`common.sh` 里只有两处按项目改——

   | 变量 | 默认 | 什么时候要改 |
   |------|------|--------------|
   | `PROJECT_ROOT` | 脚本目录上溯两级 | 脚本不在 `<项目根>/<一级目录>/cron/` 这个深度时 |
   | `LOG_DIR` | `<项目根>/logs/cron` | 项目已有约定的日志目录 |

4. **填任务清单**：从用户已有的定时需求写进 `tasks.conf`，**不要凭空编任务**——
   没有明确任务就把示例保持注释状态交付。填之前确认三件事：
   - 命令在项目根目录下能直接跑通（脚本要先编译的，命令里指向编译产物，不是源码）；
   - 跑得比调度间隔还久的任务会重叠执行，要么拉长间隔，要么让脚本自己加锁；
   - 密钥之类的敏感值走项目原有的 `.env` / 配置文件，不要写进 `tasks.conf`。
5. **忽略日志目录**：`.gitignore` 里确认日志目录已被忽略。
6. **注册入口**（项目有统一入口时才做）：`package.json` 加 `"cron:install"` / `"cron:uninstall"`，
   或 `Makefile` 加对应 target，命令就是 `sh scripts/cron/install.sh` / `uninstall.sh`。
7. **挂说明**：在项目的 `CLAUDE.md` / `AGENTS.md` 里写明定时任务改 `scripts/cron/tasks.conf`
   后跑 `install.sh`，不要直接 `crontab -e`——这是后来者唯一推不出来的一条，写一行就够，
   格式和参数留在 `tasks.conf` 的注释里，不要复制成第二份。
8. **不要替用户执行 `install.sh`**：它改的是用户账号的 crontab，不是仓库内容。
   交付后告诉用户自己跑，或者明确征得同意再跑。用 `sh scripts/cron/install.sh --dry-run`
   预览生成的区块是安全的，可以直接执行。
9. **告知用户**：`scripts/cron/` 要提交进版本库；
   crontab 是**每台机器、每个账号各一份**，换机器或换用户都要重跑一次 `install.sh`；
   服务器上部署了新版代码后，命令或路径有变的也要重跑。

## 已存在时

项目已有 cron 安装脚本时不要直接覆盖：先读懂它现有的任务清单格式，把模板缺的能力
（标记区块隔离、`PATH` 固化、`%` 转义、子分钟偏移）补进去，任务内容原样保留。
现有实现用的是别的机制（systemd timer、launchd、平台自带的 scheduler），不要改成 crontab，
告诉用户这个 skill 不适用。
