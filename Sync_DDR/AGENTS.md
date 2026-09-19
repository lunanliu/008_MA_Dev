# Sync_DDR 独立单任务规则（用户 2026-09-17 最新指令）

用户明确要求：把同步前端正在做的 VHDL DDR 读写工作迁入本目录，单独新建一个任务，统一设计、执行、复核和验证。本条覆盖父目录历史的 Astra/Luna 双任务配对规则，仅作用于 Sync_DDR。不得另建执行任务、设计任务或把工作派回前端/OTA 的 Luna。当前任务是唯一工程写入者；总管家只协调迁移、资源和用户要求。

工作根为 D:/008_MA_Dev/Sync_DDR，父目录 D:/008_MA_Dev；本地直接工作，不创建额外 worktree，不修改其他四个 Sync 工程。读 README_ZH.md、docs/PROJECT_SPEC_ZH.md、docs/MIGRATION_STATUS_ZH.md 和 docs/RTL_HARDWARE_DESIGN_STANDARD_ZH.md 后推进。

先明确真实硬件的时钟周期、吞吐/延迟、DDR 延迟和带宽假设、背压/FIFO容量、复位/取消/同时事件优先级及资源预算，再设计流水/握手；禁止只连功能信号后靠最终测试发现必然失败。单任务仍须分清设计自审、执行记录和验收判断，不能把自审称为独立外部复核。

用户已有功能验证授权继续由本任务承接：修复工程/执行入口，必要 xvhdl/xelab 与两个短 XSim DDR 行为测试；不自动运行综合、实现、时序实验、NI编译、板测或 MATLAB。模型/推理/速度保留用户设置。

history/与旧目录只读，所有旧grant和deadline失效。先把本地入口改为当前工程路径，冻结明确top/source set/实际源清单、脚本/输入身份、预算和输出，再由总管家签发本任务的新独立资源窗口；无需重新问用户同一功能范围。等待资源期间可继续设计审查和执行入口修复。中央资源记录由总管家单写：D:/007 Dev/OTA_RTL_0829/reports/operations/sync_frontend/resource_slot.json。

全机最多2个Vivado主作业、1个MATLAB，本任务最多1个Vivado；general.maxThreads=8，xelab最多16，当前不综合/IP重建。物理内存估计仅告警，结合提交余量、分页和全体工具进程进展判断。取消仅作用于自己的内核Job或核对PID+创建时间的所属进程；不按名字kill，不关闭用户应用或修改分页。历史PID身份采样缺口诚实保留，结束依据完整Job三空。

普通路径、Tcl/PowerShell参数、日志解析或报告错误由本任务自行版本化修复，保留失败证据，只重试失败/未运行阶段，不因报告错误重跑成功计算，不放松科学门槛。固定整体deadline不因attempt重置。最终分别报告工程完整性、功能仿真、综合/实现时序、持续吞吐、NI/板测；exit0不等于PASS。不生成CLIP XML，由用户手工接入LabVIEW FPGA。