# CFO-FFT005：FFT256算术核原生验证包

2026-09-14，T11 Astra在现有恢复授权内派给唯一T11 Luna 01a076f0-d8c0-72a0-8371-cb2ff29c1b28。根D:/008_MA_Dev/T11_CFO，只使用本根明确工程。T10原作业保持独占监控，不操作T10，不使用MATLAB，不启动综合/实现/CLIP/旧runner。当前只验证质量支路的FFT算术依赖，下一包才接归一化、质量和模式。

## 准入和禁止重复范围

PHASE004R1已独立复核PASS_LIMITED_PHASE_PATH，见reports/PHASE004R1_REVIEW_20260914/INDEPENDENT_REVIEW.json。39份原生产物及全部数值核验；27组/33完整/6取消/5错误，tail5272拍。该结果不包含FFT质量门。旧编译失败继续保留。

不得重跑已通过的旋转、坐标、Job正常/错误/取消探针或独立相位测试。只读身份校验不属于重复仿真。不得修改任何已冻结原文件；现有CFO_SYNC、CFO_COORD、CFO_PHASE74工程均不改。新的vivado/CFO_FFT256/CFO_FFT256.xpr用明确10项成员创建，top=cfo_fft256_core，simtop=cfo_fft256_tb，part=xcvu11p-flgb2104-2-e。

## 输入、命令及检查点

冻结契约docs/FFT256_CONTRACT_V1_ZH.md，源锁docs/FFT005_SOURCE_LOCK.json；27个向量（19例已有MATLAB数据+8个整数边界）。先执行C:/Python314/python.exe -I -B -X utf8 tools/verify_fft256.py核对新源、既有参考和整数oracle，保存完整输出。不得调用fft256_reference.py的构建入口重写派单后向量。

新尝试work/CFO_FFT005/attempt_<UTC>_luna；每次独立目录，启动前写EXECUTION_FREEZE，冻结命令、所有选源/向量/参考、工具、控制包装和依赖实际hash、资源/预计时长/保护、输出目录及当前旧工程指纹。允许Luna用已验证cfo_native_guard_v3.py与PHASE004R1包装作为只读依赖，适配新命令和标记另存cfo_fft256_guard_v1.py等新文件；实际执行hash先记录。不要执行旧main或旧三探针；执行修复不得改变RTL/数学/输入/验收阈值。

仅两个原生阶段，串行：

1. C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/fft256_project.tcl -log <attempt>/create.log -journal <attempt>/create.jou -tclargs create <attempt>
2. C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/fft256_project.tcl -log <attempt>/simulate.log -journal <attempt>/simulate.jou -tclargs simulate <attempt>

创建后verify_fft256.py --sources <attempt>/create_actual_sources.csv --identity <attempt>/create_project_identity.txt通过才能仿真。保存创建后XPR和hash。若创建已成功则复用该精确检查点；包装/归档失败不得重新创建或重复已成功仿真。模拟前复查工程指纹及完整实际选源。

模拟后verify_fft256.py --actual <attempt>/fft256_actual.txt --sources <attempt>/simulate_actual_sources.csv --identity <attempt>/simulate_project_identity.txt逐节点验证。保存原始xvlog/xelab/xsim和Vivado日志、创建/结束工程副本。源一致、native exit0、TB原始PASS、独立verifier四者缺一不可。

## 算术与行为验收

预期CFO_FFT256_PASS unique=27 completed=33 protocol_errors=5 max_tail=<实际> max_total=<实际> stalled_cycles=246 reset_discards=3 abort_discards=3。

每个完整事务检查全部1024个蝶形和256个自然序FFT输出，元数据/last/饱和码全部精确；极值例饱和63。B/O逐节点日志独立核对，不能只看peak或最终频率。6次取消分别落在装载/计算/输出，每类reset和abort各一次；5错误顺序1/2/2/1/2。末点至首结果<=5200拍，完整测试事务<=8000拍，TB总周期上限500000。若原生编译/数值/协议错误，保留证据交回Astra，不擅改数学或放宽门槛。

## 资源和进程保护

全机上限1 MATLAB+2 Vivado主作业；本包0 MATLAB、最多1 Vivado，T10保留原1个。2026-09-14 15:11UTC快照可用物理11.91GiB，仅T10的34768/28856在运行。执行前重新核对PID创建身份和资源，不凭固定PID臆断当前占用。

Vivado general.maxThreads=8、synth.maxThreads=8，经真实run PRE钩子传入子进程；xelab默认/上限16，构建jobs默认/上限16。当前行为包不launch synthesis run。记录真实回读和本包全部子进程，不无理由降为2。

近包仿真完整Job峰值约1.12GiB；本新FFT仿真预留4GiB告警预算，建议启动时空闲>=6GiB，资源不足记录后排队。4GiB估计线越过仅告警，禁止因此杀掉并重跑成功计算。严重保护：可用物理<0.25GiB即时，或<0.5GiB持续30秒；不可恢复遥测/明确原生错误按自己的Job收尾。

必须CreateProcess suspended→成功AssignProcessToJobObject(KILL_ON_JOB_CLOSE)→Resume；逐秒记录PID及创建身份、64位正确PID列表、BasicAccounting交叉计数、每进程PrivateUsage/CPU、瞬时及峰值Job提交量、系统余量和进展，监控器自身另列。短命进程退出竞态记录并重查，不把未读取数值写成0；最终Kernel ActiveProcesses和PID列表共同归零，不以runner结束或已知PID为空替代。

单调硬限从Resume起：create120秒，simulate300秒；触发后自己的完整Job归零<=5秒。预计原生1–3分钟，包装适配/冻结/归档10–25分钟。短阶段不要求恰好采到两个READY后稳态样本才承认完成，沿用PHASE004R1已修复的短作业收尾核查。异常包装/路径/私有环境修复新版本另存，仅续必要失败阶段，不杀/接管T10、不改全局环境、不新开MATLAB。

结束完整发布ATTEMPT_COMPLETION.json及artifact manifest、实际选源、全部命令/输入/包装指纹、资源/耗时/Job归零证据。只向原T11 Astra 01a076f1-ad1b-7d33-a29c-4ea34ae84d01去重唤醒一次；正常执行和普通可修复错误不唤醒总管家。完成后不自动开展质量门、模式合并或综合，等待Astra复核和下一份冻结包。