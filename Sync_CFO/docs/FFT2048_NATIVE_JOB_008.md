# CFO-FFT008 已审查原生作业

派发即冻结。执行者仅原 T11 Luna（01a076f0-d8c0-72a0-8371-cb2ff29c1b28），完成/根本性问题直接唤醒 T11 Astra（01a076f1-ad1b-7d33-a29c-4ea34ae84d01）。不经总管家转述。

## 本作业准入

按用户最新恢复授权，创建独立 D:/008_MA_Dev/T11_CFO/vivado/CFO_FFT2048/CFO_FFT2048.xpr，并串行运行一次行为仿真。part固定xcvu11p-flgb2104-2-e，硬件top=cfo_fft2048_core，仿真top=cfo_fft2048_tb。确切fileset见FFT008_SOURCE_LOCK.json；从真实工程导出create/simulate source list逐项比较，不能递归加源。

唯一入口：C:/Python314/python.exe -I -B -X utf8 D:/008_MA_Dev/T11_CFO/tools/cfo_fft2048_guard_v1.py。先--self-check（不启动native），再入口本体。入口及本次实际执行器复制、哈希冻结；禁止派发后原地修改。执行修复用新文件名、独立attempt，并保留成功检查点。

## 资源和阶段

- 0 MATLAB；不占MATLAB串行槽。T11最多1 Vivado主作业，create和simulate串行。T10保留1槽；全机上限1 MATLAB+2 Vivado，现有其他作业冲突则等待，不能接管。
- 当前保护的T10 Vivado PID34768、XSim PID28856；启动前用PID+绝对路径+创建FILETIME核对和冻结，阶段间再核对。若现场变化，先只读确认归属并记录，不按旧PID或名称杀进程。
- 历史同类阶段约1.2 GiB Job峰值。本次仿真向量扩大，预计1.5–3 GiB，告警线4 GiB；推荐启动时物理空闲≥6 GiB。估计越线只告警。所有本次子进程的私有提交和Job峰值都记入预算。
- general.maxThreads=8，synth.maxThreads=8，通过真实run PRE钩子设置；xelab/jobs=16。实际工程属性须回读。此次不启动综合，不能声称已观察综合子进程。
- create预计5–20秒，硬超时120秒；simulate预计30–180秒，硬超时300秒；常规监控/收集总计约3–6分钟。CPU或末次打印时间不能冒充算法进度。
- 使用已验证cfo_native_guard_v3.py及cfo_phase74_guard_v1.py的阶段监管：挂起创建→绑定KILL_ON_JOB_CLOSE Job→恢复；每秒记录PID、创建时间、private/CPU、Job PID表与accounting交叉核对、系统可用内存。结束必须PID表为空且ActiveProcesses=0。
- 真正保护：物理空闲<0.25 GiB立即，或<0.5 GiB持续30秒；明确错误、取消、阶段硬超时终止本Job；触发后≤5秒归零。不碰T10。不能按名字批量kill。

## 验证门槛

20组唯一输入：12个发布来源窗口+8个整数边界。26次完整事务（包括6次清除后恢复）、6次丢弃（LOAD/RUN/OUTPUT各reset、abort一次）、7种协议异常。

逐蝶形107位数据含4个S26及饱和增量；逐输出155位包包括全部元数据/索引/last/IQ/饱和/error。连续蝶形发出、各级排空、连续输出II=1均由TB检查。所有2048点IQ及11264蝶形参考文件先检查未知态。明确注入输出背压共210拍，输入空拍按案例选择0或2047。完整事务首输出≤11450拍，扣除输入空拍/输出背压后的总服务≤15550，总周期≤19000。

必须TB显式PASS和只读verify_fft2048.py --actual --sources --identity通过，再检查源锁、XPR副本、真实执行器字节不变、原生退出和整个Job归零。exit0不能代替上述门槛。

## 交付和边界

每次尝试写work/CFO_FFT008/独立目录；保存EXECUTION_FREEZE、create/simulate日志与采样、实际fileset/identity、fft2048_actual.txt、阶段核查、XPR创建后/最终副本、ATTEMPT_COMPLETION和完整artifact manifest。报告模型结果、资源统计和工具缺陷分别列出。

只复用本作业已成功create检查点，不重复旧FFT256/phase/rotator/backend试验。普通路径/私有环境修复Luna自行处理；RTL、算法、向量语义或门槛变化必须回Astra。首个数值/协议不一致停止本仿真并保留证据。

不自动启动综合、实现、74窗连续全前端、整帧、CLIP/LabVIEW或T10。单元PASS后由Astra独立复核决定下一步；本作业不授予T11/T12/T13完整验收。
