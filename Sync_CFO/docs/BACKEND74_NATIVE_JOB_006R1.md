# CFO-BACKEND006R1：仅拆分wire声明并续跑既定后端验证

2026-09-14 T11 Astra审查，派给原T11 Luna 01a076f0-d8c0-72a0-8371-cb2ff29c1b28。当前T11/CFO恢复授权内的最小RTL修复；0 MATLAB、最多1个T11 Vivado，不操作T10，不启动综合/实现/旧独立单元/新算法试验。

## 已确认失败与修复

原尝试work/CFO_BACKEND006/attempt_20260914T161238733030Z_luna：create PASS（13.127秒、21实际成员/41冻结文件/79参考一致）；simulate于15.210秒exit1，首错VRFC 10-292，cfo_fft74_quality.sv第74行。没有进入XSim，没有backend74_actual.txt，不能声称数学通过。完成SHA CACA6C5D3C64643848C65F5A0A422A3286A5E2D9379D3CCC3ACB302AC6964318；清单SHA 170E701301344FEBB2348DD536E2E11ED383BFA3377BCF8FFD7DA936D9F7BF49。

Astra只将带赋值的div_s_valid声明与不带赋值的div_s_ready/div_m_valid/div_error拆成两条wire声明，另存rtl/cfo_fft74_quality_v2.sv，模块名保持cfo_fft74_quality。旧SHA=38AAE8B4C6DD7FC8BD5B57F1512192A3AE4C726DC74C14485C8EBD2716956430；新SHA=84B39001F074DFB2C08951221A5E801A02457EE7826C7813229F2478068EE3AF。将这一个精确替换反向还原后全文一致，运算、位宽、常数、TB、向量和验收不变。失败日志与XPR归档在reports/BACKEND006_COMPILE_REVIEW_20260914。

新checker tools/verify_backend74_fix01.py只将源锁文件名改为BACKEND006R1_SOURCE_LOCK.json；其余MEM/算术/逐节点/计数/门限逻辑与原checker完全相同。原quality、原锁、原入口、原checker保持原字节，不覆盖。

## 唯一入口与检查点

首轮重试前，现有vivado/CFO_BACKEND74/CFO_BACKEND74.xpr SHA应为9653AF12054CC39EBCF697515A7D56C277C9E0FCF0DB21CCC8A4CB7160A75E04，与归档CFO_BACKEND74_before_fix.xpr相同。不得重跑create，也不运行旧phase/FFT/旋转/坐标/Job探针。

先用C:/Python314/python.exe -I -B -X utf8分别执行tools/verify_backend74.py和tools/verify_backend74_fix01.py，只做源和参考只读校验。每次尝试独立work/CFO_BACKEND006R1/attempt_<UTC>_luna，启动前冻结本次命令/工具/输入/源/执行包装及依赖hash、资源/时长/保护、输出目录和实际XPR。包装使用新cfo_backend74_fix01_guard_v1.py等版本，原字节另存到attempt；不能修改已冻结旧入口。任何后续修复用新文件名与新发布文件，不覆盖旧completion/manifest。

唯一原生命令：

C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/backend74_fix01.tcl -log <attempt>/simulate.log -journal <attempt>/simulate.jou -tclargs <attempt>

新Tcl仅打开已建工程，核对旧21项实际成员，将唯一quality文件替换成v2（其余20项不变），保存、关闭并重开，核对新21项成员后launch_simulation。part=xcvu11p-flgb2104-2-e，top=cfo_estimate74_backend，simtop=cfo_estimate74_backend_tb。严禁旧/new quality同时混入。若该入口已成功完成换源，必须以该次发布的XPR/hash和实际新源集作为检查点复用，不能按mtime或同名猜选。

入口保留before_fix、updated、simulate_actual_sources.csv，更新前/后/最终XPR及simulate_project_identity.txt。失败后如更新已保存，不重建项目；仅续失败阶段。保留独立原生xvlog/xelab/xsim日志和首错，不只引用下次会覆写的工具缓存。

## 验收完整保持原包

运行tools/verify_backend74_fix01.py --actual <attempt>/backend74_actual.txt --sources <attempt>/simulate_actual_sources.csv --identity <attempt>/simulate_project_identity.txt。

CFO_BACKEND74_PASS unique=28 completed=38 protocol_errors=5 max_tail=<实际> max_total=<实际> stalled_cycles=154 reset_discards=5 abort_discards=5 divider_cases=14。

28组覆盖MAIN22/DEGRADED1/INVALID4/ZERO1，10个取消及其恢复，5错误顺序1/2/2/3/1；14个新宽分母除法边界。逐N归一化IQ、P的FFT IQ及功率和499位最终结果全部精确。末点至结果<=7600拍，完整事务<=12000拍，TB总<=750000拍；所有阈值沿用原包，不因失败调整。原始PASS、native exit0、新21实际源集、独立checker通过和完整Job收尾共同支持限定验收。

范围仍只是74个已提取导频观测的后端质量/模式集成；不包括FFT2048前端、整帧、持续500MS/s、综合、时序或T11/T12/T13整体验收。编译/展开失败或没有实际输出时，明确没有数值结果。

## 资源与保护

沿用原包0 MATLAB、T11最多1 Vivado，与T10合计最多2主作业；全部子进程记入总内存。启动前重新核对T10创建身份和当前物理余量，建议可用>=6GiB。前包峰值约1.12GiB，本包4GiB为估计告警，越线不等于终止；资源不足先记录排队，不干预T10。

general/synth各8，真实run PRE钩子；xelab默认/上限16。唯一阶段Resume起300秒单调保护，触发后本包完整Job归零<=5秒。预计原生1–3分钟，包装适配/冻结/归档10–20分钟。必须suspended→绑定KILL_ON_JOB_CLOSE成功→Resume；每秒正确64位PID/BasicAccounting交叉、创建身份、PrivateUsage/CPU、Job瞬时/峰值和系统余量，监控器另列。

真正严重条件仍为可用物理<0.25GiB即时、<0.5GiB持续30秒、持久关键遥测失败或明确原生错误。短命进程退出竞态保留并重查，不把仍存活进程的缺失读数填0；最终两内核查询确认归零，不用runner结束替代。不因非持久累计unstable计数或READY后样本少而重复成功计算。只操作本包Job，禁止按名字批量kill或接管T10。

普通路径/私有环境/包装修复由Luna另存版本完成；新的RTL/数值/验收问题交Astra。完整发布本尝试证据，只向原T11 Astra 01a076f1-ad1b-7d33-a29c-4ea34ae84d01去重唤醒一次，不经过总管家中转，不自动启动后续工作。