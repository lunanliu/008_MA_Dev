# OTA004/A06R1：执行与验收脚本修订包

## 范围与准入
本包落实总管家对 A06 的四项脚本审查。A06 的 285 项冻结输入、4 份 RTL、短 TB、算法、接口、测试场景及已成功的 prepare/45 IP OOC/A05 证据均不改。生产源仍为 rtl/sources_a06.f，128 RTL / 136 定义；核心 75 端口 / Wrapper 111 端口。只使用现有用户分支 V5_Final；原三个工程只读。

固定 Astra 01a0ac17-f298-7201-848c-58d09e90ebb4 与唯一 Luna 01a0ac17-4f21-7be3-8690-540c11497b1e。原 A05 grant 已归还；本冻结包不是资源准入。原绝对截止 2026-09-17T03:44:33.0452158Z 保留历史身份。总管家已说明必要修复/短验证在用户授权内，待本修订复核后另行明确独立修复窗口（预计上限90分钟，尚未授予）。不得复用旧 grant、自动改旧截止或自行开始新计时窗口。

## 1. 启动入口与独立目录
入口 tools/monitor_ota004_a06r1.ps1，Source 必须是 D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota004_a06r1.tcl，且与新 source lock 的字节哈希一致。Stage 只接受区分大小写的 smoke / synth；拒绝 prepare 等其他值。

Attempt 必须是已创建且为空的 work/OTA004 直接子目录，名称仅 smoke_a06r1 或 synth_a06r1，失败阶段重试可加下划线及字母/数字/连字符后缀。拒绝空格、命令元字符、环境变量展开、UNC、设备路径、点路径穿越、非匹配父目录、非匹配阶段名称、任一级祖先 junction/symlink。Luna 的启动器 stdout、准入预检记录必须放在 Attempt 外面；监控器自己写入 Attempt 的 native/wrapper/process 记录。不得重用已非空目录。

AbsoluteDeadlineUtc 必填，由新 grant 给出。有效截止取本阶段实际 native 启动时刻 + HardSeconds 与该绝对截止的较早值；smoke HardSeconds 最大2400，synth 最大3600。A06 已审查的 PID+creation 累计身份、孤儿追踪、后代先收尾及三次空树确认逻辑保持不变。此次验证未启动真实超时/取消探针。

## 2. 45 个成功 IP 只复用
每次阶段开始、核心决定前、reset_run synth_1 之后且 launch_runs 紧前，以及核心返回后，导出 reused_ip_runs_<phase>.tsv。所有45个 IP 必须同时存在对应 run、STATUS 为 synth_design Complete、NEEDS_REFRESH 为明确 false/0、IS_LOCKED 为 false/0。空值、未知值、缺失、过期直接阻塞，绝不让核心依赖调度重建 IP。

实际45个 DCP仍在 A06 继承输入锁中，并由项目审计逐项核对 SHA256。无需 prepare / generate_target / IP launch。若设置 XPM_LIBRARIES 或更新工程导致 IP 被标为 stale，保留回执并上报，不自行清除刷新标记来绕过门禁。

## 3. CDC报告严格完整性
新 verify_ota004_a06r1_synth_result.py 验证 Vivado2021.1 / sync_ota_top / xcvu11p-flgb2104 / report_cdc -details 身份。摘要必须非空且全部规则/严重性/描述可识别；六个实际时钟对必须完整，每块行号连续，全部详细行逐类别计数与摘要完全相等，最后非空行为完整明细。未知规则、未解析行、截断、缺块、计数不符一律 FAIL，绝不以空字典默认零放行。报告没有原生 footer，不伪造 footer 门槛；脚本另写命令完成回执。

完整性通过后，CDC-1 / CDC-13必须为0；已知零计数规则可在原生摘要中省略。CDC-10只接受脚本精确列出的12个源/目的端点对、对应 clk125→clk150 或 clk150→clk500 和深度4。包含 reset 的任意名字、前缀相似源、busy/fault/组合取消译码均不豁免。完整核心 runme 出现 Error/Fatal/Critical Warning即FAIL。

## 4. 实际FIFO Gray约束
在同一次核心综合后的现有报告阶段，打开已完成设计时调用 tools/vivado/audit_ota004_a06r1_gray.tcl。此 helper 不设置任何约束，不新增原生实验。

精确范围为 metadata/fifo、completion/fifo、ddr/requests/fifo、ddr/responses/fifo、cfo/window_samples/fifo、cfo/observation_backend/observation_fifo。每个检查 wr/rd 的普通指针与计数指针，共24个 Gray 宏；发现缺失或额外宏均FAIL。逐位导出实际 src_gray_ff 和 dest_graysync_ff[0]，核对当前钟名、周期、位宽及两方向。

最大延迟来自 report_exceptions -write_valid_exceptions 的实际有效例外；bus-skew来自 write_xdc 的实际约束。安全 Tcl 子解释器仅允许只读对象解析及捕获命令，不执行 set_max_delay/set_bus_skew，不加载完整XDC。约束必须准确覆盖本实例全部源/目的位集合。max_delay -datapath_only 数值必须为源周期，bus_skew 必须为源/目的周期较小值，与冻结厂商 xpm_cdc_gray.tcl 一致。

每个目的位还必须有真实 get_timing_paths 路径且 REQUIREMENT 符合源周期，防止被 false path / clock group 覆盖。每个 Gray 宏另导出 report_bus_skew -cells <实际宏>，要求原生报告身份、对应 From/To 和可解析数值 Requirement 闭合。空报告、缺字段、未知格式都FAIL；普通 SFO 其他实例有约束不能满足本检查。所有原始导出、TSV、报告及SHA进入 strict_synth_review.json。

这是综合阶段的约束存在/适用性核查，不是布线时序或 bus-skew 实现收敛证明。负时序值如实保留。成功核心复用还必须在实际生成的 run Tcl 中包含全部4份A06源，并把 read_verilog 实际127份生产源及顺序（工程128份登记源中，to_coarse_ports.sv为唯一未引用的独立前端端口Wrapper）与当前已审计的精确源集/compile order逐项比较，导出复用回执。出现部分A06身份或NEEDS_REFRESH时保留核心并阻塞，不能误复用或盲目重综合。若核心成功后仅报告导出/解析失败，保留已完成核心/DCP，另开失败阶段恢复目录，仅恢复报告；禁止重新综合成功核心。格式修复必须保留原报告、另存修复脚本及哈希，不降低完整性或约束门槛。

## 输出、预算与收尾
获准后先同一 A06 smoke（包含既有4方向真实FIFO复位探针），严格通过才核心 synth。预期 smoke 10–20分钟；复用45 IP后的核心与报告 25–45分钟；总35–65分钟。全机最多2主Vivado、本对1、MATLAB0；general/synth8经PRE回读、xelab/core jobs16、IP jobs0。内存20–24GiB工作集估计仅告警，依据实际提交余量/分页/全树资源和工具进度判断。

命令模板（仅由唯一Luna在明确新grant后填入实际截止执行）：
私有pwsh.exe -NoProfile -ExecutionPolicy Bypass -File D:/008_MA_Dev/Sync_OTA/tools/monitor_ota004_a06r1.ps1 -Stage smoke -Attempt D:/008_MA_Dev/Sync_OTA/work/OTA004/smoke_a06r1 -Source D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota004_a06r1.tcl -AbsoluteDeadlineUtc <新准入截止> -HardSeconds 2400
synth改Stage/Attempt并设HardSeconds3600，其余入口和绝对截止保持准入身份。

离线证据 reports/OTA004/A06R1_AUDITOR_STATIC_TESTS.json（27项）、A06R1_MONITOR_STATIC_TESTS.json（17项）；A05真实报告2444行闭合，24个目标宏及位宽/时钟方向逐项相符。静态 Tcl 使用 Python附带解释器，只证明语法/模拟API路径，不代替Vivado2021.1原生API执行。原生报表格式适配还未实跑。

最终交付仍须更新核心网表/GUI工程依赖、独立VHDL Wrapper、上板波形及比较脚本、Host/Target指南；不生成CLIP XML/NI工程。整链算法、实现时序、持续吞吐和板测分别保留未验证状态。Astra派原生包后结束本轮并停表，由Luna负责监控至全树关闭，再回Astra复核。

