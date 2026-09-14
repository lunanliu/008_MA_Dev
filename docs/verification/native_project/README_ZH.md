# 一次性原生工程迁移检查

此目录保存T10_MIGRATE_GUI001的一次性入口、冻结记录与证据，不是日常仿真启动框架。日常GUI入口是vivado/T10_SFO/T10_SFO.xpr，重建工程使用tools/vivado/create_project.tcl。

检查已结束，先读[最终复核报告](REPORT_ZH.md)。原生工程创建和重开通过；末尾报告错误经离线恢复，原退出码1和损坏报告原文保留。旧冻结入口含该已知末尾错误，只作证据，不应再次用作日常启动入口。升级时自动产生的实例模板和XML、以及本轮未执行的仿真/综合范围，均在最终报告中说明。

原始34份XCI保存在baseline/original_ip_xci.zip，只作历史证据，不是可编辑工程源。baseline/原始参数JSON的436处值被configElementInfo无文本节点覆盖；CONFIG_BASELINE_CORRECTION.json逐项记录修正。没有修改XCI算法数据。

本次原生操作只在新目录创建/打开工程，read_ip引用ip/config，限定同一IPDEF原生迁移到FLGB，再核对PARAM_VALUE、MODELPARAM、74源、34IP和关闭重开。禁止IP输出生成、综合、实现或仿真。预算新增1个Vivado/4GiB/1200秒，已批准保留用户GUI PID38288，总Vivado最多2个，绝不关闭该GUI。

run_native_project.ps1是一轮检查的有限进程监管；正常GUI使用不依赖它或Python。review_native_project.py只读本次结果。任何原生失败保留work/下独立目录，不修改参考答案掩盖问题。最终状态以独立复核为准。
