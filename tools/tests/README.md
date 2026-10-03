# tools/tests

仓库级回归测试，不随 plugin 分发。

改了「改了这些必跑」列里的文件就跑对应套件，提交前（见 `docs/checklist.md`「提交前」）跑全套，开发与整改的中途不跑；该补哪些用例见 `docs/checklist.md`「改动后」。

| 套件 | 改了这些必跑 | 测什么 |
|---|---|---|
| `gate/` | `plugins/setup-git/scripts/githooks/` | 回退闸门：本地一层（reference-transaction）、pre-push 的受守护分支一层与 PR 一层、两个预检 `revert-gate.py check` / `check-pr`、切出点判据、`install.sh`（含 `--pr-only`） |
| `mutation/` | `plugins/setup-git/scripts/githooks/`、`tools/tests/gate/run.sh`（改用例名会让点名落空） | 闸门判据的变异测试：逐处改坏判据，确认指定的 gate 用例会 FAIL——回答「那些用例到底压没压在这段逻辑上」 |
| `build/` | `tools/installer/` 下的一切（`build.py`、源文件、片段），安装器的 `template/` 与 `agents/openai.yaml` | 安装器构建：基线（构建、`--check`、生成物 frontmatter）、`--check` 的比对，以及每一类校验的变异用例 |
| `scripts/` | `plugins/setup-agent/scripts/`、`tools/installer/fragments/project-root.md` | 三个渲染脚本（含其中两个共用的 `markdown_headings.py`），与 `project-root` 那行 shell 在 bash / zsh / sh / dash 下的行为 |
| `manifest/` | `plugins/` 下的任何文件（内容有变化就牵涉版本号）、两个 marketplace、`tools/tests/manifest/` | `check.py` 的每一项校验各有变异用例，并对真实仓库跑一遍：三份 manifest 的 `version`、`description` 一致，两个 marketplace 登记全部 plugin、`.claude-plugin/marketplace.json` 的 `description` 与 manifest 一致，`interface` 文案非空，相对 `origin/main` 版本只升一次（本地没有 `origin/main` 时该项 SKIP）；不校验的项见 `check.py` 模块 docstring |
| `cron/` | `plugins/setup-tools/skills/cron/template/cron/` | `setup-tools:cron` 的模板脚本：dry-run、安装与卸载、标记撞车与接管、标记计算、`tasks.conf` 读取、命令字段里 `%` 的转义 |

## 运行

```bash
bash tools/tests/run.sh                 # 全部套件
bash tools/tests/gate/run.sh            # 只跑闸门套件
bash tools/tests/gate/run.sh -v block_wrong_squash allow_git_revert   # 按名选跑，-v 打印每条命令与闸门输出
GATE_TEMPLATE_DIR=/path/to/githooks bash tools/tests/gate/run.sh      # 测另一份闸门（如改坏的副本）
TEST_JOBS=1 bash tools/tests/gate/run.sh                               # 退回串行（排查用例间干扰时用）
BUILD_PY=/path/to/build.py bash tools/tests/build/run.sh               # 测另一份 build.py
SCRIPTS_DIR=/path/to/scripts bash tools/tests/scripts/run.sh           # 测另一份渲染脚本目录
CRON_TEMPLATE_DIR=/path/to/cron bash tools/tests/cron/run.sh           # 测另一份 cron 模板
MANIFEST_CHECK=/path/to/check.py bash tools/tests/manifest/run.sh     # 测另一份 manifest 校验
```

各套件的入口、输出格式、`-v` 与按名选跑都相同。用例默认并行跑 4 条（每条各用各的临时目录，互不相干），`TEST_JOBS=1` 退回串行、`TEST_JOBS=8` 开大；全套约 3 分钟，其中 mutation 约 70 秒、gate 约 40 秒。

每个用例输出一行 `PASS <名字>` 或 `FAIL <名字>: <原因>`（失败时附日志末尾），任一失败退出码为 1。
最后一行 `repo_untouched` 比较运行前后真实仓库的 `HEAD`、`status --porcelain`、全部 ref 与本地配置；
运行期间有人在改工作副本时它也会报不一致，这时看它打印的差异判断。

依赖：bash（3.2 即可）、git 2.28+、python3（scripts 套件用 `tomllib`，要 3.11+）；scripts 套件另外测系统里有的 zsh、sh、dash，没有的跳过。

## 安全设计

### 实验与危险命令

跑实验、测试或任何会改 git / crontab 状态的命令时守下面几条；每条冒号前是规则，后面是原因。

- 实验（尤其 git、cron）按 `docs/decisions.md`「不在真实仓库里做 git 实验」，在自己 `mktemp -d` 的目录里做，不用共享的 scratchpad 根目录：共享目录可能被别人清空。
- 每条 git 命令带 `-C <临时目录内的路径>`，命令块以 `cd … || exit 1` 开头；真实仓库里只做只读查询，不执行 push、commit、reset、rebase、branch 等：曾有子代理在共享目录被清空、`cd` 失败后照常执行，把未发布的提交推到了远程。
- 涉及 crontab 时在 PATH 前面放假的 `crontab`，确认 `command -v crontab` 不是 `/usr/bin/crontab`：真实 crontab 是用户全局状态。

### 测试框架的兜底

测试会大量执行 reset、rebase、push 等改写操作，绝不能落到真实仓库上。`lib/common.sh` 负责兜底：

- `make_tmp` 用 `mktemp -d` 建临时根 `T` 并 `cd` 进去，退出时只删自己建的那个目录；
  同时隔离环境：`HOME`、`GIT_CONFIG_GLOBAL` 指向 `T` 内，`GIT_CONFIG_SYSTEM=/dev/null`，
  `GIT_CEILING_DIRECTORIES` 设为 `T` 的父目录（git 向上找不到 `T` 外的仓库），`GIT_TERMINAL_PROMPT=0`。
- 测试里的 `git` 是包装函数：必须带 `-C <目录>`，目录与当前目录都必须在 `T` 之内，否则记下违规并退出；
  有违规时套件整体判失败。
- 依赖当前目录的命令（`install.sh`、闸门脚本）只经 `run_at <T 内的目录> <命令>` 执行。
- 对真实仓库只做只读查询（`repo_snapshot`），不依赖共享的临时目录。
- `build/` 只在 `T` 里那份 `tools/installer/` 与 `plugins/setup-*/` 的拷贝上运行 `build.py`（它按自身位置定位仓库根），
  真实工作副本只被复制、不被写。
- `manifest/` 的变异用例在 `T` 里那份 `plugins/` 与 marketplace 的拷贝上运行（拷贝自带 git 仓库与 `T` 内的 bare remote，
  `origin/main` 即拷贝时的状态）；对真实仓库只经 `check.py` 做只读的 `rev-parse`、`show`、`diff --name-only`、`ls-files`。
- `cron/` 绝不碰真实 crontab：被测脚本经 `env -i` 运行，`PATH` 只含 `T` 里自建的 bin（必需工具的软链，
  加一个读写用例目录里文件的假 `crontab`）；开跑前核对这份 bin 解析到的 `crontab` 是假脚本、
  另一份不含 `crontab` 的 bin 解析不到它，不符就整套不跑。

## 新增用例

在套件的 `run.sh` 里加：

```bash
register block_something          # 名字即 run.sh <名字> 选跑时用的名字
case_block_something() {
  fixture                         # 复制基础夹具：$A（装了闸门、检出 main）、$B（同事）、$R（bare remote）
  ...                             # 用 git -C、put、commit_all、new_wt、new_pr、b_push、precheck(_pr) 等搭场景
  try git -C "$A" reset --hard HEAD~1
  expect_blocked "reset --hard"   # 非零退出且输出里有 [revert-gate]
  expect_out "已发布"             # 只断言关键片段，不断言整句
  assert_ref "$A" main "$before"
}
```

- 闸门新增或修改一条判据时，三样一起落地：拦得住的 `block_*`、不误拦的 `allow_*`，以及 `mutation/` 里一条 `teeth_*`——把这条判据改坏，声明哪几条 gate 用例会因此 FAIL。少了 `teeth_*`，下次有人改坏它仍然全绿。
- 命名：`block_*` 拦下、`allow_*` 放行、`edge_*` 已知边界（断言当前行为，行为变了会失败，
  提醒同步闸门文档里的已知边界）、`check_*` 预检结果、`install_*` 安装脚本。
- 断言工具见 `lib/common.sh` 的用例框架（`try`、`expect_rc`、`expect_out`、`fail` 等）与 `gate/run.sh` 的夹具小工具。
- 用例在独立子 shell 里以 `set -e` 运行，夹具步骤失败会以「意外出错」报出所在行；
  被测命令的失败用 `try` 捕获后再断言。
- 新增套件：建 `tools/tests/<套件>/run.sh`，source `lib/common.sh`，调用 `make_tmp`，登记用例后 `run_cases "$@"`；
  顶层 `run.sh` 会自动发现它。

### mutation 套件

- 命名：`teeth_<被改坏的判据>`，另有 `baseline_unmutated`。
- `teeth` 接「文件、原文、新文、`--`、期望 FAIL 的 gate 用例名…、可选的 `--` 加对照用例（见下一条）」，在用例目录里
  复制一份闸门、改坏、用 `GATE_TEMPLATE_DIR` 指过去跑那几条用例，断言它们确实 FAIL。
- 每条变异都带一条期望 PASS 的**对照用例**（默认 `block_update_ref_published`）：闸门被改成跑不起来时点名的
  `block_*` 也会 FAIL，报错字串与「这段逻辑没人钉住」一样，对照绿着才说明 FAIL 是这处判据变了引起的。
  变异会动到默认那条时，自己换一条不受影响的 `block_*`。
- 点名的用例与对照都要登记进 `BASELINE_CASES`，`teeth` 会核对；`baseline_unmutated` 用未改坏的副本把它们
  整批跑一遍——没验证过「本来是绿的」的用例，将来因为别的原因变红时对应的 teeth 会变成永远空转的 PASS。
- `mut` 报「出现 0 次」是闸门改写后锚点失效了：**重新对锚点**，不是删掉这条 teeth，也不是放宽唯一性检查。
  锚点优先挑这条判据独有的短标识符（`busy_branches()`、`rename_sources(`、`forkPoint`），少用跨行的实参表。
- 这个套件不认 `GATE_TEMPLATE_DIR`：锚点钉死在仓库这份闸门的字面文本上，指向别处会逐条报「出现 0 次」。

### build 套件

每个用例从基础夹具复制出副本 `$W`（`$S` 源文件、`$F` 片段、`$P` plugins、`$BPY` 副本里的 build.py），
用 `mut sub <文件> <原文> <新文> [<次数>]`、`mut append` 等施加一处破坏——原文出现次数不符时 `mut` 报错，
免得源文件改动后破坏悄悄落空。只有一两行的用例用 `bad <名字> '<函数体>'` 登记（体前自动 `fixture`）：

```bash
bad bad_something 'mut append "$S/agent-plan.md" $'"'"'\n{{no_such_var}}\n'"'"'
  expect_build_fails "未声明的变量 no_such_var"'
```

- `expect_build_fails <片段>...`：写模式与 `--check` 都退出码 1、输出含全部片段，且写模式报错后生成物一个不变；
  `expect_build_ok`：两种模式都通过。
- 命名：`bad_*` 应报错、`allow_*` 看似可疑但应放行、`check_*` 测 `--check` 的比对、`baseline_*` 未破坏的副本。
- `build.py` 新增或修改校验时在这里补用例；改完可用 `BUILD_PY` 指向删掉该校验的副本，确认对应用例会 FAIL。

### scripts 与 cron 套件

- scripts 的命名按被测对象：`codex_*`、`rules_*`、`style_*`、`root_*`；渲染脚本的报错用 `expect_script_error <脚本名> <片段>...`
  断言（退出码 1、以脚本名开头、没有 traceback）。`render-codex-agent.py` 的写入失败、改名失败经 `patched '<补丁>' <参数>...`
  在加载模块后替换 `mod.os.replace` 等再调用 `main()` 构造。
- cron 用 `new_project <项目根> [<脚本目录>]` 建项目（脚本目录写入 `$CRON`），`cron_sh [--nocron] [--env K=V]... <脚本> [参数]`
  运行被测脚本，`block_count` / `block_owner` 查假 crontab 里的区块。

### manifest 套件

- 命名：`baseline_*` 未改动的副本、`bad_*` 应报 FAIL、`allow_*` 应通过、`skip_*` 应报 SKIP、`repo_*` 真实仓库。
  `expect_check_fails <项> <片段>...` 断言退出码 1 且输出含 `FAIL <项>`，`expect_check_ok` 断言通过；`jset`、`set_version`、`bump` 改 JSON 与版本号。
- `check.py` 新增或修改校验时在这里补用例；改完可用 `MANIFEST_CHECK` 指向删掉该校验的副本，确认对应用例会 FAIL。
