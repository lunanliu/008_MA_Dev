# CFO-FRONT009 已审查原生作业

依据用户恢复T11/CFO的授权，原配对Luna执行，Astra复核。执行者01a076f0-d8c0-72a0-8371-cb2ff29c1b28；结果直接交Astra 01a076f1-ad1b-7d33-a29c-4ea34ae84d01。禁止借人或经总管家转述。

## 独立工程和冻结入口

D:/008_MA_Dev/T11_CFO/vivado/CFO_FRONT2048/CFO_FRONT2048.xpr；part=xcvu11p-flgb2104-2-e；硬件top=cfo_front2048_window；仿真top=cfo_front2048_tb。

先读取FRONT2048_CONTRACT_V1_ZH.md，核对FRONT009_SOURCE_LOCK.json的全部源、向量、ROM、约束、脚本及13个实际工程成员。明确复用原cfo_fft2048_core.sv和fft2048_twiddle.mem，不修改旧工程。由create/simulate实际导出fileset列表与锁逐项比较，不能递归拼源。

入口：C:/Python314/python.exe -I -B -X utf8 D:/008_MA_Dev/T11_CFO/tools/cfo_front2048_guard_v1.py；先--self-check再本体。冻结实际命令、输入/执行器哈希及运行环境。派发后任何修复另存新文件名与attempt，不原地改冻结输入。

## 资源、并行与保护

0 MATLAB；T11最多1 Vivado主作业，create/simulate串行。全机最多1 MATLAB+2 Vivado，给T10保留1 Vivado槽。不得操作T10、旧runner或其他任务进程。

上个FFT008原始证据：create峰值Job private 1198022656 B、simulate 1197891584 B；全阶段最低空闲16134541312 B（约15.03 GiB，修正Luna文字汇总15.82）。新作业90唯一窗口、98完整事务，预计1.5–3 GiB，告警线4 GiB，推荐启动空闲≥6 GiB；计入全部子作业。预算越线不直接杀进程。

general/synth线程8通过真实PRE钩子，xelab/jobs16。此次不综合，设置回读不冒充综合子进程证据。

create预计5–20秒，硬超时120秒；simulate预计60–240秒，硬超时600秒；总执行/校验/归档预计4–8分钟。逐阶段复用成功检查点，不因日志或包装问题重跑成功native。

启动前及阶段间核对T10 PID34768/28856的路径与创建FILETIME；若现场变化先只读确认归属，不按名字批量kill。原生挂起创建→绑定KILL_ON_JOB_CLOSE Job→恢复，沿用已验监管器，每秒记录PID/创建时间/private/CPU、Job PID表与accounting、系统内存。

真保护条件：可用物理内存<0.25GiB立即，或<0.5GiB持续30秒；明确错误、取消、硬超时收尾本Job；触发后≤5秒Job归零，PID列表与ActiveProcesses必须同时为零。原生数字比较首错即停，不能以exit0判PASS。

## 必过检查

90唯一窗口：82发布来源+8整数边界；其中case001同一帧全部74个window与60680系数地址。98完整事务，8丢弃与恢复（LOAD/FFT/PILOT/Z_HOLD各reset/abort），7协议异常。所有参考文件先检查未知态。

逐导频144位审计包含原FFT S26 IQ、系数S18 IQ、H S28 IQ；逐177位z结果包含元数据、计数、FFT饱和与error。有效导频间隔2拍，两段交界408拍；被清除流水不能泄漏结果。人工输出背压共250拍；输入空拍按案例为0或2047。

每完整事务末输入到z≤13500拍，扣除空拍/背压后的服务≤15600拍，含空拍总周期≤19000拍。TB显式CFO_FRONT2048_PASS后，还须verify_front2048.py --actual --sources --identity、源锁、执行器字节、旧工程指纹、XPR副本、原生Job归零一致。

## 交付与后续

独立work/CFO_FRONT009/attempt目录，交付EXECUTION_FREEZE、原生日志/采样、actual sources/identity、front2048_actual.txt、XPR副本、阶段数值核查、ATTEMPT_COMPLETION及artifact manifest。至少报告实际周期、哈希、Job峰值和真实最低可用内存；保持GB/GiB口径明确。

普通工具/路径/私有环境故障Luna自行修复；RTL、算法、向量意义、门槛变化回Astra。完成或根本阻碍直接唤醒原Astra。

本次不重复旧独立FFT256/phase/backend/rotator/FFT2048仿真；新前端所需的FFT运算属于本次集成验证。没有MATLAB、综合、实现、CDC、估计后端集成、连续全帧、CLIP/LabVIEW或T10操作。PASS后由Astra决定下一步，不自动扩展实验范围。
