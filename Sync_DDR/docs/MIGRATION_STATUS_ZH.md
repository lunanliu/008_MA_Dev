# 迁移状态与继承证据（2026-09-17）

原项目：D:/007 Dev/OTA_RTL_0829/output/DDR_Control_VHDL_20260916_rev02。原任务 Astra 01a0a162-c115-7af1-89be-49726f987f84、Luna 01a0a161-e434-7142-8927-1f5314daafd5 已遵用户要求停止后续DDR工作；新任务负责完整生命周期。旧目录保留，只读追溯。

原冻结包16文件未改。当前复制的工作RTL/TB/约束/参考资料逐字节保持；完整旧包与执行修复rev01至rev05保存在history。旧manifest/VALIDATION_JOB及PowerShell/Tcl包含旧绝对路径和过期grant，均只作证据，不直接执行。

- rev01：WMI订阅权限拒绝，EDA未开始。
- rev02：输出路径预检失败，EDA未开始。
- rev03：首次EDA根14:37:47.6535152Z，create阶段报 Vivado 12-172，含空格路径被当文件列表分开。write/read未开始，完整Job三空。
- rev04：create14:46:48.7479128Z至14:46:59.8094177Z，exit1；add_files路径修复已生效，后续 Common 17-170 Unknown option '-mt 16'。完整Job至14:47:01.8515205Z三空，write/read仍NOT_RUN。
- rev05：原Astra暂停前准备 -dict [list xsim.elaborate.xelab.more_options {-mt 16}] 形式；ValidateOnly PASS，但最终完整独立复核未完成，未派单、未EDA。入口原SHA F59D61797F4CEAADB758F7E9DEEBD13442A92B101AAACBDB045C9CFCFC0EAB10，仅历史身份。

旧grant DDR_REV02_REV03_FUNCTIONAL_20260917T143558Z 与14:52:47.6387679Z截止撤销，不转移/复用/续预算。总管家14:51:38.0897053Z只读现场native0；空扫描是当时快照，结合03/04 Job闭合记录，不声称完整历史进程身份全部采集。

history内 project/DDR_Control.xpr 为空源集；project_retry04/DDR_Control.xpr 只完成2RTL+1XDC+sim_write，缺sim_read。它们是失败现场，不是新工程交付。新任务需要在当前根生成干净完整工程；不删除历史。

目前写/读功能仿真、综合、实现时序、NI和板测均未验收。执行脚本失败不能归因为RTL功能失败。后续在原功能授权内自行修复与验证，先申请新的本任务资源窗口。