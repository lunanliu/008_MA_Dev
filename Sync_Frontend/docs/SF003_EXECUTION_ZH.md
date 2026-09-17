# SF003：正确FLGB综合、125MHz独立物理与CLIP导出复读

唯一Luna=01a0a161-e434-7142-8927-1f5314daafd5；Astra=01a0a162-c115-7af1-89be-49726f987f84。SF002已正式复核通过限定短联合行为；本包不改DUT，不重复SF001/SF002，不跑MATLAB/长帧。

## 准入与资源

资源grant仍SYNC_FRONTEND_SHARED_VIVADO_20260914。总管家已核实GUI14300属于I16_AddSub_CLIP独立工程，仅编辑，无原生计算，非本XPR；闲置GUI不计计算槽，但GUI及Java内存全部计入。21:00左右可用约10.06GiB。启动前重新核对用户GUI是否启动实际run；若全机已有2项计算，则延后新阶段，不关闭GUI/不改用户工程。T10原34768/28856不触碰。

本对只启动一个项目主作业，IP OOC子作业属于该树。general.maxThreads=8和synth.maxThreads=8经physical_run_pre.tcl进入真实run子进程，每次PRE同时在该run私有cwd放已锁定ROM。IP并发本包取4：10GiB可用、按每个IP子任务暂估1.5GiB加调度父进程与余量，16个同时启动会超过现有余量。主synth/impl launch_jobs=16但只有单个run就绪；xelab本包不启动。不得因看到jobs4误改回2或无资源评估拉满16。启动内存下降可进一步下调并记录依据，估算峰值只是告警，保留计算，真正保护按严重持续资源压力/明确工具错误/确证停滞。

预计IP+top综合15–45分钟，route20–60分钟，EDIF/VHDL复读3–15分钟；整体40–120分钟，硬保护180分钟。包括全部子任务内存，预计本树峰值8GiB。计时保护针对本SF003，不影响T10。

## 固定文件与命令

源/入口/CLIP文件/新约束的SHA见reports/design/SF003_files.csv。XPR仍vivado/Sync_Frontend/Sync_Frontend.xpr，top=sync_frontend_top，part=xcvu11p-flgb2104-2-e。实际34-SV列表与tools/sf003_rtl_sources.txt比较，禁止递归拼源。15个已迁FLGB IP被配置为正式项目run，不修改CONFIG.*、位宽、舍入、reset或IP版本；若工具更新管理XCI的生成状态字段，保留pre/post及字段差异并确认CONFIG不变，不能把科学配置变化当元数据更新。

在新work/SF003_attempt_<UTC>记录真实命令/源SHA/版本/总资源/所属PID父链。第一条：

    & C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -notrace -source D:/008_MA_Dev/Sync_Frontend/tools/run_physical.tcl -tclargs <本attempt绝对路径> 4

通过真实synth_1/impl_1运行。完整EDIF在综合完成且黑盒为0后导出，route失败仍保留成功合成与DCP。脚本不会reset成功run；普通报告命令错误只修报告阶段，禁止重综合/重route。若run失败，先封存该run完整证据，仅失败阶段在私有修订中恢复，不能覆盖失败证据。

物理初门通过且本阶段树已退出后，调用：

    & C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -notrace -source D:/008_MA_Dev/Sync_Frontend/tools/check_clip_export.tcl -tclargs <成功physical目录> <全新export_check目录>

第二条只重读现成完整EDIF，并综合纯VHDL连线wrapper，不重新计算原RTL/IP。CLIP包产生于export_check/package；不得提前写正式release PASS标签。NI占位符被等价替换后检查继承的单125MHz时钟；这只是本地包装/约束作用域检查，不是NI全目标编译。

## 通过门与保存

必需：正确part/top/源集；全部真实run PRE回读8/8；top无黑盒；ROM初始化信息可查且非空（若实例名优化变化需从真实层级定位，不能直接屏蔽）；完整route状态；WNS和WHS均>=0，只有1个8ns时钟，无MMCM/PLL；report_timing_summary的TNS/THS及所有内部/同步I/O路径需通过，无未约束内部时钟。IO预算独立设置1ns max/0ns min，仅reset_n异步输入不套同步IO延迟，不能用false path隐藏其他违例。

保存synth/routed DCP、完整EDIF、utilization/timing详细路径/route/clock/CDC/DRC/methodology/highfanout/实际选源/IP状态/ROM初始化和子进程日志；资源通过门以器件容量及报告为准，不另造70%软门槛。报告中的未约束reset_n、警告及NI未验证边界逐项列出，exit0不等于最终PASS。

导出门：完整EDIF独立link零黑盒；VHDL wrapper与EDIF再link零黑盒；XML32个逻辑端口类型/方向与VHDL吻合；XML声明0 MMCM/DCM/新增BUFG与实际资源相符；继承clock=125MHz断言通过。检查核心端口与SV、wrapper端口与clip/ports.json，展开bit宽度；同包含EDF/VHDL/XML/XDC，不依赖旧绝对路径。保留导出前后资源对照。XDC不含OOC I/O预算/LOC/全局false path。

普通路径、私有环境、Tcl属性/报告命令兼容可自主修复，修订另存，保留原意；不得改DUT/器件/IO预算/时钟/阈值来通过。若只有NI占位符/真实层级名称解析不符，可定位等价clock pin并保留前后映射，仍要求同一继承8ns时钟，不删除断言。确定性设计/时序/黑盒/ROM问题立即保留结果交回Astra。

取消只作用本次记录的PID树，先正常工具取消/退出，硬保护时才定向收尾已确认子孙；禁止按名字kill，不能以主PID消失证明全树退出。成功/失败均确认本次树归零且T10/用户GUI保留。完成以SF003+attempt+event去重回交，发布reports/SF003_completion.json，状态待Astra复核。
