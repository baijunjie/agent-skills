---
name: ui-copy
description: 装上（或更新）多语言 App 界面文案规范 knowledge-ui-copy skill：各语言语体、破坏性操作与确认框、进行态、报错、括号空格、iOS / Android / Web 大小写、术语统一与多端同步。默认装进当前项目，随仓库提交、团队共用，项目安装时可补本项目的语种、资源位置与术语；也可安装到用户级配置。用于"装界面文案规范""给项目配本地化规范""统一多语言文案""新电脑装文案规范"等场景。
disable-model-invocation: true
---

# 安装 knowledge-ui-copy skill

只装 `knowledge-ui-copy` skill 本体，不装子代理，也不改指令文件。装好后就能独立工作。

## 跨宿主约定

只执行当前宿主对应的分支。模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；
两者都为空时，先把 `SKILL_DIR` 设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），
再按相对路径定位。执行写入前先确定：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$PLUGIN_ROOT/skills/ui-copy/template"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$CLAUDE_PLUGIN_ROOT/skills/ui-copy/template"
else
  TEMPLATE_DIR="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/template"
fi
```

## 选作用域

**默认装进当前项目**，随仓库提交，团队共用。用户明确说了「全局 / 用户级 / 所有项目 / 新电脑」，
或当前目录不是 git 仓库时，才装进用户级配置目录。

两层可以同时装：同名 skill 以项目级为准，所以项目要定制时装一份项目级的，
不要去改用户级那份。

## 通用步骤

1. **写入 skill**：先看目标 `SKILL.md` 在不在；已在就转「已存在时」，不要执行 `cp`——它会直接覆盖改过的那份。
   各宿主、各作用域的区别只在目标路径，见后面各节。
2. **对齐项目**：只在项目安装时做，写入之后再做。在装好的 `SKILL.md` 末尾加「本项目」一节，写入写文案时
   必须知道、通用规范里没有的事实：
   - 支持的语种清单、源语言（以哪种语言、哪一端为准同步）与缺译时回退的语言
   - 与模板「默认」不同的风格选择：各语言敬称档位、中日文括号全角 / 半角、日文 ASCII 词前后是否加空格、ko 请求用 -세요 还是 -(으)십시오、zh-Hant 地区用语（台 / 港）
   - 文案资源文件的位置，以及项目自带的排版、校验命令
   - 项目术语表：易混概念各自的叫法、页面上必须写全称的对象
   - 不按界面语体改的文件（语音触发短语、法务、营销文案）
   - 项目已有的文案规范文档路径 + 章节

   只写从项目里查得到的事实，不猜；项目文档里已写明的规则只指路，不复述。什么都没有就不加这一节。
   与通用规范冲突的项目约定写进这一节，不改通用正文。

## Claude Code 项目安装（默认）

```bash
mkdir -p .claude/skills/knowledge-ui-copy
cp "$TEMPLATE_DIR/knowledge-ui-copy.md" .claude/skills/knowledge-ui-copy/SKILL.md
```

**告知用户**：`.claude/skills/knowledge-ui-copy/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为它加例外。装好后可用 `/knowledge-ui-copy` 调用，也会按描述自动触发。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，由 `CLAUDE_CONFIG_DIR` 决定，没设就是 `~/.claude`；
下面用 `C` 指代它，不要写死路径。

```bash
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/knowledge-ui-copy"
cp "$TEMPLATE_DIR/knowledge-ui-copy.md" "$C/skills/knowledge-ui-copy/SKILL.md"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；重启 Claude Code 后生效。

## Codex 项目安装（默认）

```bash
mkdir -p .agents/skills/knowledge-ui-copy
cp "$TEMPLATE_DIR/knowledge-ui-copy.md" .agents/skills/knowledge-ui-copy/SKILL.md
```

**告知用户**：`.agents/skills/knowledge-ui-copy/` 要提交进版本库才随仓库生效。开启新会话后生效。

## Codex 用户级安装

使用 `CODEX_HOME`；未设置时回退到 `$HOME/.codex`。`$HOME/.agents/skills/knowledge-ui-copy` 已经有一份时
就地更新它，否则装到 `$X/skills/knowledge-ui-copy`：

```bash
X=${CODEX_HOME:-$HOME/.codex}
if [ -d "$HOME/.agents/skills/knowledge-ui-copy" ]; then
  D="$HOME/.agents/skills/knowledge-ui-copy"
else
  D="$X/skills/knowledge-ui-copy"
fi
mkdir -p "$D"
cp "$TEMPLATE_DIR/knowledge-ui-copy.md" "$D/SKILL.md"
```

**告知用户**：说明实际写入的用户级配置目录；重启 Codex 后生效。

## 已存在时

已有同名 skill 时不要覆盖：与模板逐节比对，补齐模板有而它没有的规则，
保留项目或用户自己加的内容。项目安装时同样按「对齐项目」核对「本项目」一节，缺的补上。不要修改已安装 plugin 内的模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
