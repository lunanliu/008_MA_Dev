# CFO-BACKEND006：74点估计后端集成原生验证

T11 Astra于2026-09-14在当前恢复授权内派给原T11 Luna 01a076f0-d8c0-72a0-8371-cb2ff29c1b28。根D:/008_MA_Dev/T11_CFO，正确器件xcvu11p-flgb2104-2-e。本包是实现门槛4的归一化、FFT质量和相位/FFT最终模式集成，不启动MATLAB、综合、实现、FFT2048前端、整帧或CLIP，不修改/接管T10。

## 前置验收及本包范围

PHASE004R1相位支路已独立通过。FFT005已复核全部52份发布产物、27冻结文件/58参考、10实际成员，B36642/O8474逐点一致，33完整/6取消/5错误，tail5121/total6163/停顿246/饱和63。FFT005的同名执行脚本原地修复违反冻结规则，现已精确恢复原启动字节并另存两版本，缺陷继续保留，见reports/FFT005_REVIEW_20260914/INDEPENDENT_REVIEW.json。没有重复成功原生计算。

本次不运行旧独立相位、FFT、旋转、坐标或Job探针。后端实例化已通过相位v2与FFT256核是新集成验证的一部分；新输入必须由真实RTL同时产生两种估计，再合并，不能给RTL喂参考估计值。算法契约见docs/BACKEND74_CONTRACT_V1_ZH.md，源锁docs/BACKEND006_SOURCE_LOCK.json。

准确工程vivado/CFO_BACKEND74/CFO_BACKEND74.xpr；硬件top cfo_estimate74_backend，仿真top cfo_estimate74_backend_tb；21项明确成员。6份RTL只有cfo_estimate74_backend.sv、cfo_fft74_quality.sv、cfo_divide_rne64wide.sv、cfo_fft256_core.sv、cfo_phase74_core_v2.sv、cfo_divide_rne64.sv；严禁同名旧core混入。

## 启动冻结、命令与检查点

每次新尝试work/CFO_BACKEND006/attempt_<UTC>_luna。启动前记录EXECUTION_FREEZE：准确工具/命令、所有输入/源/参考/执行脚本及依赖hash、旧工程身份、本包资源、预计时长、硬保护和输出目录。

先用C:/Python314/python.exe -I -B -X utf8 tools/verify_backend74.py只读校验源及参考；严禁调用backend74_reference.py构建入口改写已派向量。允许Luna以已验证guard v3与前包包装为只读参考编写新cfo_backend74_guard_v1.py；真正运行前冻结并另存一份执行脚本原字节。执行后任何修复必须v2/v3新文件，不改旧路径来加入resume函数，不修改已发布completion或manifest。普通工具路径/私有环境/包装故障可自行修，RTL/算法/验收变更交Astra。

两个原生阶段严格串行：

1. C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/backend74_project.tcl -log <attempt>/create.log -journal <attempt>/create.jou -tclargs create <attempt>
2. C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/backend74_project.tcl -log <attempt>/simulate.log -journal <attempt>/simulate.jou -tclargs simulate <attempt>

create结束保存XPR及hash，执行verify_backend74.py --sources <attempt>/create_actual_sources.csv --identity <attempt>/create_project_identity.txt，通过才启动simulate。若成功创建则沿用相同源锁和精确检查点，不因交接/报告问题重建。模拟前核对XPR与实际成员；不得扫描目录挑源。

simulate结束执行verify_backend74.py --actual <attempt>/backend74_actual.txt --sources <attempt>/simulate_actual_sources.csv --identity <attempt>/simulate_project_identity.txt。保存全部原生日志xvlog/xelab/xsim、数据、源集和最终XPR。native exit0、原始TB PASS、独立逐点verifier、源身份全部符合才是本包通过。

## 验收数值和行为

预期原始PASS：CFO_BACKEND74_PASS unique=28 completed=38 protocol_errors=5 max_tail=<实际> max_total=<实际> stalled_cycles=154 reset_discards=5 abort_discards=5 divider_cases=14。

28组唯一向量覆盖MAIN22/DEGRADED1/INVALID4/ZERO1；10次取消后的恢复也完整完成。N行检查每个归一化IQ，P行检查每个FFT IQ与功率；F行完整499位含元数据、最终频率、两种候选、质量、相位诊断，全部精确一致。ZERO例N/P均0。5错误码顺序1/2/2/3/1。V行14例新宽分母除法必须精确，含零分母error。

rst/abort各覆盖收集、归一化、FFT输出、除法执行中、合并结果待收5处，丢弃数据不能进入下一帧。末输入至结果<=7600周期、完整测试事务<=12000周期、TB总<=750000周期。正常结果停顿154拍，错误和V结果另有保持检查。数学/协议/编译失败不准改阈值或参考来通过，保留首错交回Astra。

## 资源、性能与异常保护

全机最多1 MATLAB+2 Vivado主作业；本包0 MATLAB、T11最多1 Vivado，T10保留原1个。2026-09-14 15:55UTC快照可用物理7.71GiB，只有原T10 Vivado/XSim；启动前重新核对完整PID创建身份和当前总余量。前包完整Job峰值约1.12GiB，本新包继续4GiB告警预算，建议启动时空闲>=6GiB。资源不足记录并排队，不操作T10或其它任务释放内存。

general.maxThreads和synth.maxThreads均8，真实run PRE钩子；xelab默认/上限16，build jobs默认/上限16，本包不启动综合run。实际回读与所有子进程/总内存一起记录，禁止无理由固定2线程。

4GiB是估计告警线，不能因小幅越线杀掉或重复成功运算。真正保护：可用物理<0.25GiB即时，或<0.5GiB持续30秒；持久关键遥测失败、明确错误按本包独占Job安全收尾。启动必须suspended→Assign Job(KILL_ON_JOB_CLOSE)成功→Resume。逐秒记录64位PID列表、BasicAccounting交叉数、每进程创建身份/PrivateUsage/CPU、瞬时及峰值Job提交量、系统余量、阶段进展，监控器自身另列。

短命进程OpenProcess竞态需保留失败记录和后续重查证据；若PID后续已退出且最终两内核查询归零，没有持久关键遥测缺失，则不因通用累计unstable计数超过阈值把已成功原生阶段当数学失败。不可把仍存活进程的未读内存填0或忽略持续故障。READY后短作业样本少也用完成/源/Job证据核查，不为凑样本重跑。

单调硬限从Resume起：create120秒、simulate300秒；触发后本包完整Job归零<=5秒。预计原生1–3分钟，包装/冻结/归档10–25分钟。只按本包Job取消，不按名称批量kill，不以runner/PID列表静态缓存为空证明子树全退。修复仅重试失败阶段，成功计算检查点只读复用。

完成后发布新ATTEMPT_COMPLETION.json/manifest（若有失败，原发布保留，新修复结果另名/另目录并引用原件），含实际hash、命令、源集、资源/耗时、全Job归零及未操作T10证据。仅向本T11 Astra 01a076f1-ad1b-7d33-a29c-4ea34ae84d01去重唤醒一次，普通可修复问题自行收尾。不要通过总管家中转；不自动启动后续前端、整帧、综合或时序。即使本包通过，也只是74点后端行为验证，不是T11/T12/T13整体验收。