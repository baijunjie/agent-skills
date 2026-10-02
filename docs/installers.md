# 安装器

`setup-*` 安装器的命名与归属、生成、源文件契约；面向新增或修改安装器、片段、`build.py` 的维护者与 agent，什么时候读见 AGENTS.md「什么时候读什么」。

## 命名与归属

需要装进项目或用户级配置的，做成 `setup-*` plugin 下的安装器（模板放 skill 自己的 `template/`）；不需要的作为运行时 plugin（如 `dev`、`create`）。

安装器类 plugin 按领域划分、不按作用域：

| plugin | 领域 |
|---|---|
| `setup-agent` | agent 的开发工作方式 |
| `setup-git` | Git 规范与流程 |
| `setup-tools` | 开发辅助工具 |
| `setup-knowledge` | 知识类规范 |

作用域是安装器自己的属性，在 `INSTALLERS` 声明：

| 作用域 | 含义 |
|---|---|
| `project` | 只装进当前项目，随仓库提交 |
| `project-user` | 默认装进当前项目，也可装进用户级配置 |
| `user` | 只装进用户级配置 |

- 仅用户级的安装器也放进对应领域，如 `setup-tools:codex-bridge`。
- `setup-<领域>` 下的安装器名不重复领域前缀，装出去的 skill 名带 `<领域>-` 前缀（如 `setup-git:commit` 装出 `git-commit`），避免与其它 skill 重名；`setup-tools` 例外，装出的 skill 不加 `tools-` 前缀。
- `batch-setup` 不是安装器：它不走 `build.py`、`SKILL.md` 手写，作用是按固定顺序读取并执行多个安装器的 `SKILL.md`（安装器禁止模型调用，不能经 skill 机制触发）。名字不用 `setup-*`，免得被 `build.py` 当成安装器目录。

## 生成

安装器 `SKILL.md` 是生成物、不得手改，见 AGENTS.md「硬规则」。改了 `tools/installer/` 或安装器的 `template/`、`agents/openai.yaml` 后，运行 `python3 tools/installer/build.py` 重新生成（任一安装器校验不过就一个文件都不写），提交前再跑 `python3 tools/installer/build.py --check`（生成物与源文件不一致时非零退出并列出文件）。

- 语法（`{{include: 片段名}}`、`{{变量}}`）、变量来源与 `INSTALLERS` 的写法见 `build.py` 模块 docstring 与注释。`INSTALLERS` 只声明 `scope` 与有差异的变量，生成物路径、`skill`、`name`、`marker` 由源文件名推导。
- 片段每个文件开头的说明块写它做什么、哪类源文件引用、放在哪；改片段前先看它，新增片段照同样格式写说明块。
- 安装器的 `agents/openai.yaml` 与 `template/` 手工维护，不由构建生成。

## 源文件契约

源文件只写本安装器独有的步骤与顺序，片段里的规则不复述。要点：

- frontmatter 写在源文件里，设 `disable-model-invocation: true`；`description` 以 `{{scope_lead}}` 开头，末句写成 `{{scope_tail}}用于……等场景。`。
- 安装节标题与作用域一致，只用 `## [Claude Code |Codex ]项目级安装[（默认）]` / `## [Claude Code |Codex ]用户级安装`；`project-user` include `scope-select`。
- 装出的模板里安装时要填写的位置，写明它记录什么、来自哪里（项目现状 / 用户选定 / 用户提供），有固定选项的逐项列出并标出默认值。
- 用「第 N 步」引用步骤时，步骤写成编号列表项，范围与并列写成「第 N–M 步」「第 N、M 步」。
- 要求装出后改写模板原文的，写成表头为 `| 位置 | 原文 | 改成 |` 的替换表：「位置」用「」写出所在列表项的开头，「原文」用「」写出一字不差的原文（整条删掉写「整条」）。

### 必有的段与片段

没有的内容写「无」：

| 位置 | 要求 | 其后紧接 |
|---|---|---|
| 「## 跨宿主约定」 | 其下 include `host-conventions` | |
| 顶层 `pre-write` | include 一次 | 「本安装器另外要查的冲突：……」 |
| 顶层 `reinstall` | include 一次 | 「本安装器的定制值：……」，逐项写从哪读、何时填回 |
| 顶层 `state-mismatch` | include 一次 | |

往指令文件写内容的，再在 `pre-write` 之前 include `markers`，正文写 `{{marker}}`，模板里写字面标记。

### 校验

校验全部在 `build.py`，按类别分组列在文件顶部注释里，连同不校验、靠自觉的约定；那是唯一的权威清单。改校验时的测试要求见 `docs/checklist.md`「改动后」。
