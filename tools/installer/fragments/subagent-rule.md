<!--
一句话：Claude Code 中同名子代理项目级优先，两层都有时告知用户生效的是项目级那份。
装子代理的安装器用：引用 skill-priority 的在 INSTALLERS 里经 fragment() 作为 subagent_rule 注入；
不引用的直接 include（project 接在 skill-priority-project 之后，project-user 接在 scope-select 之后）。
-->

Claude Code 中同名子代理是**项目级 `.claude/agents/` 优先于用户级**；写入前发现另一层也有同名子代理时，告知用户两份都在、实际生效的是项目级那份。
