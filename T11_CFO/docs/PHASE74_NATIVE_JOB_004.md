# CFO-PHASE004：完整74点相位路径的原生RTL验证

2026-09-14，T11 Astra审查后派给原T11 Luna（01a076f0-d8c0-72a0-8371-cb2ff29c1b28）。在用户直接恢复授权内按既定门槛4推进；本包不启动MATLAB、综合、实现、FFT前端、整帧回放或新信号研究。根D:/008_MA_Dev/T11_CFO，只使用本根已冻结文件，不改T10和旧CFO工程。

## 前置证据与范围

CFO-COORD003已由Astra独立复核通过：373份结果精确一致；完整Job遥测、自动取消时限通过，见reports/CFO_COORD003_REVIEW_20260914/INDEPENDENT_REVIEW.json。不得再跑normal/error/hold监管探针或既有旋转器/坐标仿真。复用经过验证的Job保护实现，适配新命令只能在新包装版本完成，保存实际hash和修复记录。

本包算法定义见docs/PHASE74_CONTRACT_V1_ZH.md，源身份见docs/PHASE004_SOURCE_LOCK.json。19例已发布MATLAB的6156个标量节点与整数参考一致；另有8个单元整数边界，共27个完整74点向量。这里没有复跑MATLAB。RCFO004原JSON缺label/scope，仅是可选上下文，所需相位/拟合字段齐全，不能为此补造或重做实验。

## 冻结与顺序

先用C:/Python314/python.exe -I -B -X utf8分别执行tools/verify_rotator.py、tools/verify_coordinate.py、tools/verify_phase74.py，只核对身份和冻结参考，不运行历史仿真。新工程有12个明确project members，必须核对实际导出。原CFO_SYNC XPR当前hash=8EE3459986419C34B42B4261A0E38B2D5C670B47E25E33D80B46074CD4EE8063；原CFO_COORD XPR当前hash=7605D752B0BB2C0B7BE2841D823E5C0AC3C25EA15D848239E3200AFBC40239A4，原源锁不能变。

每次尝试独立work/CFO_PHASE004/attempt_<UTC>_luna，启动前EXECUTION_FREEZE记录精确命令、所有输入/执行包装/依赖hash、真实解释器及Vivado路径版本、资源和保护、输出目录。只允许以下两个原生阶段，严格串行：

1. C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/phase74_project.tcl -log <attempt>/create.log -journal <attempt>/create.jou -tclargs create <attempt>
2. C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/phase74_project.tcl -log <attempt>/simulate.log -journal <attempt>/simulate.jou -tclargs simulate <attempt>

第1阶段创建独立vivado/CFO_PHASE74/CFO_PHASE74.xpr。运行verify_phase74.py --sources <attempt>/create_actual_sources.csv --identity <attempt>/create_project_identity.txt并保存输出，正确才启动第2阶段。创建成功则保留，不因日志/归档失败重新创建。若先前尝试已经创建，只复用本包成功检查点且hash/实际选源一致的工程，不按mtime混选或覆盖。

第2阶段行为仿真后，运行verify_phase74.py --actual <attempt>/phase74_actual.txt --sources <attempt>/simulate_actual_sources.csv --identity <attempt>/simulate_project_identity.txt。保存native、xvlog、xelab、xsim日志与数据，保存创建后和结束后XPR指纹。真实工具返回0、TB原始PASS行、独立数值检查、完整源集四者缺一不可。

## 验收

TB应完成27个唯一向量及6个复位/取消后的恢复事务，共33个完整结果；另有6个主动丢弃事务、5个协议/输入错误结果。完整事务的74个angle/unwrapped、74个predicted/residual、74个centered及最终234位结果全部精确一致。日志中的P/R/C行也由独立Python逐条核对，不能只看最终频率。

原始PASS行应为CFO_PHASE74_PASS unique=27 completed=33 protocol_errors=5 max_tail=<实际> max_total=<实际> stalled_cycles=150 reset_discards=3 abort_discards=3。末点接受到结果有效≤6000周期，总测试事务≤11000周期；任何fatal/数学/协议不符均不通过。输出反压150周期、复位和取消各3次，旧帧或旧除法结果不得泄漏。输入错误码顺序为1/2/2/3/1，错误结果除帧标识和错误码外均为0。

本包仅验收CORDIC、解缠、相位OLS及相位线性门。不能声称FFT256质量门、模式选择、residual CFO整模块、综合、时序或持续500MS/s已经通过。全零输入必须nonzero=0和phase_linear=0；phase_linear独自不是最终CFO有效性。

## 资源与保护

T10保留原1个Vivado主作业，本包最多1个；全机MATLAB≤1/Vivado主作业≤2，本包MATLAB=0。所有本包子作业计入总内存。general/synth=8，真实run PRE hooks；xelab实际16，默认不降低。2026-09-14 13:38 UTC系统可用10.86GiB，前包完整Job峰值约1.20GB；本小型相位仿真继续预留4GiB估计告警线。启动前重新采样，建议空闲>=6GiB，资源不足先记录并排队，不挤占T10。

4GiB小幅越线只告警，不重跑已成功阶段。严重保护仍为可用物理<0.25GiB即时，或<0.5GiB持续30秒；关键监管失效/明确原生错误按独占Job安全收尾。启动必须suspended→成功AssignProcessToJobObject/KILL_ON_JOB_CLOSE→Resume。每秒记录完整PID/创建身份、BasicAccounting交叉计数、逐进程PrivateUsage、瞬时/峰值Job提交量、系统余量、CPU/阶段进展，监控自身占用另列。瞬时进程退出竞态短重查并记录；不可恢复的漏项不能假称0或PASS。

单调硬限从Resume起：create120秒，simulate300秒；触发后内核活跃数和PID列表共同归零≤5秒。原生预计1–3分钟，包装适配/冻结/归档约10–25分钟。包装自己按deadline执行，不等待模型临时kill，不按名称杀进程，不操作T10。普通执行路径/私有环境/日志修复另存新版本，仅重试必要失败阶段；不得更改RTL、数学、向量或验收阈值。RTL编译/数值或根本设计问题保留证据交回Astra。

完成发布ATTEMPT_COMPLETION.json、全部证据清单、精确实际源/命令/包装指纹、真实耗时/资源及最终XPR核查；原始失败与修复审计保留。只向本Astra去重唤醒一次。这个包结束后不自动启动FFT256、综合或其它实验；下一包由Astra复核后派发。