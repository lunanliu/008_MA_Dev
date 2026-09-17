# OTA004/A06：最小CDC控制修订与核心综合更新

## 授权与时间门禁
原A05 grant已归还，当前无新原生启动授权。固定Astra 01a0ac17-f298-7201-848c-58d09e90ebb4 / 唯一Luna 01a0ac17-4f21-7be3-8690-540c11497b1e；根D:/008_MA_Dev/Sync_OTA、现有用户V5_Final分支、Vivado2021.1、Sync_OTA.xpr、sync_ota_top、xcvu11p-flgb2104-2-e。

原包首native为2026-09-17T00:44:33.0452158Z，原绝对截止2026-09-17T03:44:33.0452158Z（05:44:33 CEST）不自动改变。A06预计短smoke10–20分钟、复用IP后的核心综合/报告25–45分钟，总35–65分钟；冻结时原窗口已不足容纳此估计。须总管家明确新的具体grant及时间预算处理；无明确时间授权时不能启动、不能用新attempt编号重起180分钟。若仍沿用原截止，必须有可完成本阶段的预算，不以必然撞限的启动代替准入。后续任何批准的截止作为显式AbsoluteDeadlineUtc传入监管器并完整记录，不通过修改默认值隐式延时。

## A05结论与保留
A05真实核心OOC已完成，0黑盒，DCP/EDIF和报告均完整，352已记录进程身份全树关闭；45个IP OOC均成功。A05源码216项、prepare、smoke、DCP/EDIF和全部报告保持原位。复核reports/OTA004/A05_SYNTH_ASTRA_REVIEW.json：资源未超器件；WNS -2.357ns非时序通过；CDC控制毛刺/原始复位旁路使最终交付暂缓。不得重复prepare、45个成功IP OOC、原全帧或implementation。

## 准确变更边界
四份RTL另存新名、旧文件不动，rtl/sources_a06.f仍128生产RTL/136定义，核心75端口和Wrapper111端口不变，数值算法/波形/IP参数/时钟不变：
1. sync_ota_top_a06.sv：125MHz取消状态译码先寄存再进异步复位同步器；150MHz busy/fault启用XPM SRC_INPUT_REG=1。控制取消数据门原本即时阻断不变，跨域控制增加一个源时钟周期，完成/再次接收仍按原握手排空。
2. ota_cfo_chain_a06.sv：150MHz取消/取消排空状态译码先寄存，统一给500MHz复位、窗口FIFO复位及观测链abort；同域停止喂数与存储排空不变。
3. ota_async_fifo_a06.sv：wr_busy/rd_busy使用已有本域异步断言、同步释放的rw/rr尾链，移除raw reset_request对握手/同步复位/CE的旁路。
4. cfo_estimator_link_a06.sv：同理移除fast/slow busy中的raw common_reset旁路；真实74观测数学、数据/信用/复位完成双向握手不变。

生产XPM统一通过XPM_LIBRARIES={XPM_CDC XPM_FIFO XPM_MEMORY}自动加载安装版官方源及实例范围约束；工程内3份官方拷贝保持记录但USED_IN_SYNTHESIS/SIMULATION均false，避免与自动加载的同字节memory重复。私有仿真3份仍只用于simulation且实际绑定严格核对。安装版3 SV及全部Tcl运行依赖已逐字节复制并锁定；不手工新增clock-group/宽泛false path，不修改厂商断言。烟测保留已验证仿真库顺序。

## 具体入口与复用
入口tools/vivado/run_ota004_a06.tcl，仅smoke/synth。新work/OTA004/smoke_a06、synth_a06，重试失败阶段用新独立目录。smoke替换5个源成员（4RTL+TB）并保存变更前XPR；实际sources/headers/include/IP/MIF/compile order审计必须通过。45个原IP OOC DCP作为冻结输入，清单docs/provenance/OTA004_A06_REUSED_IP_DCP_LOCK.json；任一缺失/变更/未完成直接阻塞，禁止launch IP。

更新核心前将原synth_1完整目录复制到本次attempt/previous_core_run并逐文件校验，才reset_run synth_1；原A05导出DCP/EDIF不动。只更新受影响的核心综合。如A06核心已成功而仅报告/导出失败，则确认完成标记/NEEDS_REFRESH/实际A06脚本后复用，不能重新综合成功核心。

## 受影响同一短smoke
保留A05全部真实核心展开、RAW第三响应待定取消、禁止提前done、单次完成、非法配置、两个done ACK后的80拍迟到观察、16/128拍reset guard和4个真实SFO FIFO极早取消探针；不缩短既有门槛。

新增4个真实ota_async_fifo探针覆盖125→150、150→125、150→500、500→150。每探针先写入两个旧epoch数据并对读口施加背压，取消/复位保持16个写时钟，等双域复位完成，再写入两个新epoch数据；仅可读回这两个新值，旧值/重复/乱序/overflow/underflow均FAIL。全部4探针完成才允许主TBfinish，marker为OTA004_LOCAL_RESET_FIFO_PASS。仍是同一200us超时短TB，未改变算法观察长度。

verify_ota004_a06_sim_result.py严格扫描完整日志，任何Error/Fatal/Critical Warning、运行期XPM复位错误均FAIL；保留A05已批准的唯一20ns特定FPO启动warning及4点公开复位保持证明。不能仅靠exit0或自有marker放行综合。

## 综合与CDC门槛
smoke严格通过才运行核心synth_1，general/synth8由真实PRE回读，xelab16、core jobs16、IP jobs0（只复用45项）。固定out_of_context、flatten_hierarchy=none，frontend/sfo/cfo/control/ddr/两旋转/真实前后端及源域控制寄存器存在，黑盒0。输出DCP/EDIF、资源/层次/时序/时钟/CDC/check_timing、report_exceptions及write_xdc完整生效约束。

新增verify_ota004_a06_synth_result.py要求核心完整runme无Error/Fatal/Critical Warning，CDC-1和CDC-13计数均0；CDC-10仅允许已明确的algorithm_reset_guard/reset_active_reg或cfo/compute_cancel150_reg到已有复位同步器的协调全局/会话复位组合，任何数据/busy/fault/状态译码源或其他端点均FAIL。必须在实际导出XDC看到厂商Gray指针max_delay/bus_skew与同步级范围约束，不允许全时钟异步group。不因剩余预算放宽门槛。

负的同域综合估计如实保留，不启动实现优化循环；本包不承诺物理时序、持续速率、完整帧算法闭环、NI集成或板测通过。

## 监管与资源
监管另存tools/monitor_ota004_a06.ps1：必填AbsoluteDeadlineUtc，实际生效截止为启动时刻+HardSeconds与批准绝对截止之小者，直接消除预检到启动偏移；累计PID+creation身份作为树种子，父子归属需当前父身份和创建时间顺序，根退出不能代替全树退出。截止时逐次核对当前创建时间，按后代优先顺序受控停止；继续追踪已记录孤儿，连续3个空树采样才收尾。该取消路径只有静态审查/AST检查，不虚称实测。Luna必须保持责任至完整收尾，重大监管异常主动接管并反馈。

命令模板：私有pwsh.exe -NoProfile -ExecutionPolicy Bypass -File D:/008_MA_Dev/Sync_OTA/tools/monitor_ota004_a06.ps1 -Stage smoke或synth -Attempt 本次新目录 -Source D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota004_a06.tcl -AbsoluteDeadlineUtc 准入回执明确值 -HardSeconds smoke2400或synth3600（实际仍受绝对截止约束）。具体命令/输入SHA/准入/预计耗时在启动前留证。

A05核心整树工作集曾约21GiB、系统空闲最低557944KiB、提交余量仍约61.99GB；A06预算按20–24GiB工作集估计，真实余量/提交/分页/工具进展共同判断。12GiB仅告警，小幅不足不硬拒；不因估算自动杀，不改系统分页或关闭其他应用。全机最多2主Vivado、本对1，本包0MATLAB。

普通执行环境/命令问题Luna自主另存修复并记录哈希；不改算法/RTL/输入含义/通过门槛。仅完成、实质设计问题、重大障碍或硬超时回对应Astra；普通采样留本线程15分钟报告。执行/监控时启用自己的计时器，空闲停表，不更改模型/强度/速度。
