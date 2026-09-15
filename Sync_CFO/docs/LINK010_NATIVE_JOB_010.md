# CFO-LINK010 原生执行审查包

Astra：01a076f1-ad1b-7d33-a29c-4ea34ae84d01；唯一执行Luna：01a076f0-d8c0-72a0-8371-cb2ff29c1b28。

## 范围与准入

只创建全新 CFO_LINK010.xpr 并执行一次 LINK010 行为仿真。part固定xcvu11p-flgb2104-2-e，top=cfo_estimator_link，simtop=cfo_estimator_link_tb。源列表和字节以LINK010_SOURCE_LOCK.json为准；官方Vivado2021.1 XPM_CDC/XPM_FIFO/XPM_MEMORY依赖单独哈希。不得用同名旧核心代替v2依赖，不修改已冻结001–009源或XPR。

用户已恢复CFO开发；执行仍须共享槽由总管家明确归还T11_T13。每个native阶段前重新读取 D:/007 Dev/OTA_RTL_0829/reports/operations/sync_frontend/resource_slot.json，必须本Astra/原Luna且有效grant，记录字节哈希和grant_id。槽被其他任务占用则不启动，保留已成功检查点。此文不是覆盖槽所有权的授权。

只用1个本任务Vivado计算组、0 MATLAB；全局最多2个Vivado计算组并保留现有T10。用户GUI14300编辑态不计计算槽，其完整子树内存必须计入；必须新鲜核对身份/活动，发现实际新增综合/仿真/实现则重新算计算组并阻止冲突。不得控制、终止、修改GUI或T10。T10 PID34768/28856和GUI14300均按PID、绝对exe与创建FILETIME核实。

预计本任务create10–30秒、simulate30–180秒；内存1.5–3GiB，4GiB仅告警。启动前可用物理内存建议至少6GiB，同时记录全部工具/GUI/子作业内存。general.maxThreads8、synth.maxThreads8，通过真实PRE钩子；xelab16，构建jobs上限16，本任务不启动综合构建。

## 冻结命令与保护

Python：C:/Python314/python.exe -I -B -X utf8 D:/008_MA_Dev/T11_CFO/tools/cfo_link010_guard_v1.py

Vivado：C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/link010_project.tcl -log <attempt>/<stage>.log -journal <attempt>/<stage>.jou -tclargs <create|simulate> <attempt>

每次尝试独立work/CFO_LINK010/attempt_<UTC>_luna。阶段串行。guard先创建暂停进程，绑定KILL_ON_JOB_CLOSE私有Job后才恢复；每秒保存PID列表、Job accounting、私有内存、系统内存与进度。create硬120秒、simulate硬600秒；严重内存<0.25GiB即时、<0.5GiB持续30秒才终止本任务Job，终止后≤5秒确认Job PID空且active accounting0。小幅超过预计不终止。不得按进程名字批量停止，不以runner退出判定全树结束。

## 门限、证据与交接

按LINK010_CONTRACT_V1_ZH.md所有数值/协议门限验收。exit0不等于PASS，需原始CFO_LINK010_PASS、逐条trace验证、实际选源/工程身份一致、XPM实际编译绑定、冻结字节不变、原生Job归零及外部进程保护证据同时成立。需保存EXECUTION_FREEZE、每阶段准入、native logs、actual sources/identity、XPR前后快照、stage result、completion、artifact manifest。

执行包装/路径问题可自行修复，另存修复版本和实际命令/哈希，保留失败证据；不得修改RTL算法、测试含义或门限。成功create不得重做；若simulate准入被阻止或执行包装失败，保留XPR并仅审查/重试必要阶段。wrapper不自动重试或推进下一实验。根本设计结果、不可修复障碍或完成后直接去重唤醒本Astra。普通修复不逐项请示。派单后Astra结束本轮，原Luna负责完整监控，不借人。