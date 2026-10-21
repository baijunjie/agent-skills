<!--
一句话：gallery 快速检查通过不说明摆的是最新的 UI，要确认外观与交互的实际打开看。
给 setup-agent:gallery 的运行时模板用（tools/installer/templates/ 下的模板源文件 include），不给安装器源文件用：agent-gallery 与 gallery-writer 都 include。
不得含 {{变量}}，build.py 会拦下。是一个列表项（「- 」开头），放在讲快速检查或收尾的那节列表中；怎么核对场景、预览怎么启停各自另写。
-->

- 检查通过只说明场景跑得起来，不说明它摆的是最新的 UI：外观与交互要确认的，实际打开看。
