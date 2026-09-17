# OTA004/A06R2：只读既有DCP的报告恢复与有界时序定位

## 当前范围和证据
用户已明确批准向原 Astra 01a0ac17-f298-7201-848c-58d09e90ebb4 交接 Sync OTA 路径、哈希、时序/失败报告和运行状态并修复；只与原唯一 Luna 01a0ac17-4f21-7be3-8690-540c11497b1e 配对。旧 A06R1 grant/05:48:23Z 截止已过期。本包冻结不是启动准入，须总管家独立给新的具体时间/资源 grant。

A06R1静态复核见 reports/OTA004/A06R1_ASTRA_STATIC_REVIEW_20260917.json：302项输入、14项交接证据哈希匹配。smoke严格PASS；核心综合成功（0 errors / 0 critical warnings）；两阶段累计111/121进程身份与历史采样集合完全一致，最后连续3采样为空、截止前关闭。外层失败仅说明Gray门未完成，不能据此宣称CDC/时序已通过。

固定输入：work/OTA004/synth_a06r1/sync_ota_synth.dcp，187800130 bytes，SHA256 AC2E40A1B04CEE538F76BC5028CC8E2C3836459742D260488E231D6DD436F33E。EDIF SHA256 636882516C625C955831D90133F52BF3687A57DFE527D1BCFE70D2F20A888ADA 保留。旧DCP/EDIF、全部smoke/综合/失败日志、302项旧输入不动。旧核心runme另作逐字节副本 docs/provenance/OTA004_A06R2_core_runme.log，防止后续真正RTL综合覆盖其历史身份。

本包不修改RTL、TB、算法、量化舍入、端口、IP参数或125/150/500MHz时钟；原三工程只读。只 open_checkpoint 现有DCP，不打开XPR、不调用prepare、generate_target、reset/launch_run、synth_design、仿真或implementation，不重写DCP/EDIF，不加false path/clock group/waiver，不生成XML。

## 精确报告修复
另存 tools/vivado/audit_ota004_a06r2_gray.tcl，保留A06R1原件。安全解释器只解析导出的数据与只读对象查询，不执行完整XDC。

1. 显式跟踪已观察到的 current_design 和 current_instance -quiet（回根）/字面层级路径。每个非根scope必须解析为一个真实存在的非primitive层级对象。未知参数、嵌套未审语法、未解析scope一律FAIL。通过限定scope补全查询路径，不改变设计实际current_instance，也不应用任何约束。
2. query返回内部对象token，正确处理 report_exceptions 导出的嵌套 list/get_pins。源仅接受真实 C pin、目的仅接受真实 D pin；通过 get_cells -of_objects 找唯一owning cell，核对pin名、REF_PIN_NAME、IS_PRIMITIVE、FD类型和Gray寄存器名。cell约束仍保留原cell身份。
3. 既有 constraints.tsv 记录归一化源/目的cell集合；新 query_objects.tsv 逐条保留scope、get_pins/get_cells类型、原pin/cell全名、归属cell、pin类型和primitive。512条证据应包含256个C/D pin对象与256个scope限定cell对象，不能只删/C或/D字符串蒙混归一化。

六个FIFO、24个Gray宏、128目的位以及双向位宽/钟名/周期门槛不变。max_delay必须来自有效例外且datapath_only/源周期正确；bus-skew必须来自实际约束且等于较小周期。每目的位有效timing path及REQUIREMENT正确，每宏原生report_bus_skew scope/From/To/Requirement必须可解析。未知/缺失/空报告均FAIL。原生bus-skew表格格式尚未观测，静态夹具不代替native；原始报告全部留证供必要适配。

## CDC报告适配与保留事项
实际A06R1报告有299明细、9块（6个内部时钟对及3个input port clock块），并有False Path例外列、CDC-9 Info和CDC-26 Warning。新parser识别这些已观测官方规则/描述及列值，仍严格检查身份、非空摘要、每块连续行号、逐类别计数闭合、未知规则拒绝。只读同一DCP恢复出的canonical明细必须与冻结原报告逐项一致，不能静默丢掉输入端口或告警。

原控制门槛不变：CDC-1=0、CDC-13=0；12条CDC-10必须全是原审查的精确复位端点/时钟对/深度。新识别的告警不是新增豁免；全部182条Warning（CDC-6=1、CDC-15=171、CDC-26=10）仍作为待审记录。报告恢复通过与完整CDC资格分开，结果明确标为 REPORT_RECOVERY_PASS_WITH_OPEN_TIMING_AND_CDC_WARNINGS，不能宣称设计整体CDC通过。

## 同一次DCP读取的有界时序覆盖
当前综合、未布局布线估计：clk125 WNS+2.410ns/0失败；clk150 -2.358ns/2240失败；clk500 -1.279ns/347失败。两条最差路径不足以代表2587端点。

在Gray审计之前导出一次有界路径覆盖，确保报告格式错误不丢失后续RTL修复所需资料：
- 同域 clk125 最多4条、clk150最多32条、clk500最多32条，每终点最多1条。
- 源clk150分别到 cfo/observation_backend、sfo/two_pass_transport/output_buffer、cfo、sfo 范围，每组最多8条。
- 源clk500分别到 cfo/observation_front、sfo/initial_estimator 范围，每组最多8条。
合计9查询、上限116条；层次组可能重叠，实际目的时钟以每条原生报告为准。不是所有失败端点的穷举或共同根因证明。输出原生full/input_pins报告以及paths.tsv/queries.tsv；不优化、重综合或布局布线。

150MHz当前最差路径经过频率差/绝对值/常数乘法的一致性判定，再通过CFO fail及跨模块ready链到SFO header RAM使能。静态数学证明：两有符号32位输入之差绝对值最大4294967295；乘4587520最大19703248365158400，小于2^64，无U64溢出；32768000000000除4587520的商7142857、余655360，所以比较可严格等价为abs_difference<=7142857。这里只记录证明，尚未改RTL。
500MHz最差路径为FFT bin寄存器→导频选择/减法→基址相加→系数ROM使能。后续最小流水修复必须对齐IQ、索引、valid、last/错误和取消清空，保持每拍接收能力。具体改动在补充路径证据后单独冻结，再做受影响短等价和更新核心综合。

## 唯一入口、命令、预算和保护
tools/monitor_ota004_a06r2.ps1 仅允许Stage=report，Source精确为tools/vivado/run_ota004_a06r2.tcl并验冻结SHA。Attempt为work/OTA004/report_a06r2（或显式失败阶段新后缀）的直接子目录且启动时为空；launcher stdout/stderr及预检置于Attempt外。拒绝shell元字符、路径穿越/非匹配根、reparse链、错误入口和超限HardSeconds。

具体模板（待新grant填入截止，不能使用旧截止或占位符实际启动）：
C:/Users/lunan/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe -NoProfile -ExecutionPolicy Bypass -File D:/008_MA_Dev/Sync_OTA/tools/monitor_ota004_a06r2.ps1 -Stage report -Attempt D:/008_MA_Dev/Sync_OTA/work/OTA004/report_a06r2 -Source D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota004_a06r2.tcl -AbsoluteDeadlineUtc <新grant绝对截止> -HardSeconds 1800

单Vivado主进程、0MATLAB，general/synth参数8/8在真实报告进程设置/回读，build/IP jobs均0，无xelab。估计10–20分钟，申请阶段上限30分钟，实际受新grant绝对截止较早值约束；报告进程工作集估计10–14GiB（A06R1报告关闭时进程峰值约9GiB），仅告警。小幅不足结合提交/虚拟内存余量继续，监测全树/分页/进展，仅明确分配失败、持续严重压力或确证停滞才干预。不关闭用户应用/修改分页。

监管运行段沿用A06R1累计PID+creation身份、根退出后继续追踪孤儿、实际截止后后代优先受控停止、连续3空树收尾。新grant必须独立明确；不得部署旧guard或因attempt重起预算。

结果：原始报告、实际对象/原pin证据、strict_report_review.json、result.txt和完整进程树/资源记录。若仅Python格式解析失败且原生报告齐全，只做离线适配，不重新读DCP；若只部分原生报告失败，保留成功部分，返回Astra冻结必要缺项，不重跑成功smoke/IP/核心。退出0不是Gray PASS，更不是时序或板测通过。

## 静态验证与参考
reports/OTA004/A06R2_STATIC_FIXTURES.json：15项，使用真实A06R1导出XDC/有效例外/CDC报告和模拟对象API，核对24宏/128位/512原对象证据及拒绝丢scope、错误C/D、未知命令、截断报告等。A06R2_MONITOR_STATIC.json：13项AST/预检。两者均无native。

原生API依据Vivado2021.1官方文档：[report_timing](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/report_timing)、[report_bus_skew](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/report_bus_skew)。实际API/格式以本次原生证据验收，文档和mock不能替代执行。

