<!--
一句话：gallery 快速检查只靠改对来通过，不删场景、不跳过、不放宽。
给 setup-agent:gallery 的运行时模板用（tools/installer/templates/ 下的模板源文件 include），不给安装器源文件用：agent-gallery 与 gallery-writer 都 include。
不得含 {{变量}}，build.py 会拦下。是一个列表项（「- 」开头），放在讲快速检查或收尾的那节列表中；失败怎么分流另写。
-->

- 只靠改对来通过：不为让检查通过而删场景，不跳过、不放宽检查，不改场景或 mock 去迁就应用的错误。
