<!--
Claude Code 中同名 skill 用户级优先的说明，末尾接变量 subagent_rule。
装 skill 的 project-user 作用域源文件 include，接在 scope-select 之后。
-->

Claude Code 中同名 skill 是**用户级优先于项目级**，与「就近优先」的直觉相反。
所以要按项目定制的 skill，不要在用户级再装一份同名的。写入前发现另一层也有同名 skill 时，告知用户两份都在，Claude Code 实际生效的是用户级那份。{{subagent_rule}}
