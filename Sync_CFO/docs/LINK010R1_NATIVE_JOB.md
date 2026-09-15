# CFO-LINK010R1 最小修订原生审查包

Astra：01a076f1-ad1b-7d33-a29c-4ea34ae84d01；唯一执行Luna：01a076f0-d8c0-72a0-8371-cb2ff29c1b28。用户CFO恢复授权有效，具体启动须总管家给予本新冻结包的共享槽；已退休LINK010 grant不得复用。

## 范围、工程和输入

只创建新的D:/008_MA_Dev/T11_CFO/vivado/CFO_LINK010R1/CFO_LINK010R1.xpr并运行一次修订后的LINK010链接层行为矩阵。part=xcvu11p-flgb2104-2-e，sources_1 top=cfo_estimator_link，sim_1 top=cfo_estimator_link_tb。完整选源/输入/依赖字节见LINK010R1_SOURCE_LOCK.json，修订及验收见LINK010R1_CONTRACT_ZH.md。原LINK010和001–009证据不改，不重跑前端FFT、MATLAB扫描、综合、实现或整链实验。

Python入口：C:/Python314/python.exe -I -B -X utf8 D:/008_MA_Dev/T11_CFO/tools/cfo_link010r1_guard_v1.py。

原生命令：C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/link010r1_project.tcl -log <attempt>/<stage>.log -journal <attempt>/<stage>.jou -tclargs <create|simulate> <attempt>。

独立输出work/CFO_LINK010R1/attempt_<UTC>_luna。两个native阶段串行；每次launch前重新核对源、实际create工程快照、外部进程与共享槽。资源槽须granted_astra/granted_luna准确，authorized_job=CFO-LINK010R1，manifest_sha256为本SOURCE_LOCK哈希，script_sha256为本guard哈希。槽所有权或字节不符则保存检查点，不启动。

## 预算和保护

1个本任务Vivado计算组，0 MATLAB，全局最多2个计算组，保留T10原有组。用户GUI编辑态不计计算槽但计入全部内存；当前身份检查复用冻结link010_admission.py，其T10与GUI的PID/exe/创建时间必须重新核对。不得操作T10或用户GUI；任何新计算活动/归属不清则重新准入。

预计create10–30秒、simulate30–180秒，本任务峰值1.5–3GiB，4GiB告警不强停；每阶段启动前可用物理内存硬门6GiB。general.maxThreads8、synth.maxThreads8经PRE钩子，xelab16；无综合run。私有Job暂停创建、绑定KILL_ON_JOB_CLOSE再恢复；硬create120秒、simulate600秒。系统可用<0.25GiB立即、<0.5GiB持续30秒只终止本Job，随后<=5秒以Job PID列表和active accounting共同确认归零。不得用根进程退出或按名称批量kill代替全树核查。

## 保存、门限与交接

本次对create监管证据作明确修正：READY日志若最后才刷新，允许使用其同一PID/精确exe/创建FILETIME的既有Job采样证明真实native运行；须至少一条保存完好的样本，PID/Job accounting一致且CPU/内存可读，随后READY、DONE、exit0和完整归零仍全部必需。不是删除进程身份门，不修改原LINK010判定。新源码必须创建新项目，不能修改/重复旧成功项目补日志。

stage及completion须保留EXECUTION_FREEZE、每阶段准入、原生日志、实际源/属性/身份、两份XPR快照、数字trace、reset audit、进程采样、Job/内存/时间、冻结字节、旧工程与外部保护、完整artifact manifest。任何原生ERROR/FATAL均阻止PASS。不以修改厂商功能逻辑、关闭全部断言、放宽数值/周期/协议门来处理失败。

普通命令/路径/包装故障由原Luna另存修复版本、实际命令/哈希后仅修受影响阶段；不得改RTL、断言设计、测试含义或门限。成功create仅复用，不重做；无自动重试/下一实验。完成、根本设计问题、重大运行障碍或硬超时直接去重唤醒本Astra。派单后Astra结束轮次，原Luna负责完整监控和15分钟报告，禁止中途无确认交接退出。

交付遵守用户最新边界：核心RTL为综合top的GUI工程，最终完整链验证后再交匹配的独立VHDL Wrapper和端口/Host说明；本次不生成XML、不自动CLIP/LabVIEW工程、不做Wrapper网表资格测试。
