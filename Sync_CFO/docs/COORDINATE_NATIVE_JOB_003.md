# CFO-COORD003：修复后遥测准入 + 坐标控制器原生验证

2026-09-14，T11 Astra 派给唯一原配对 Luna（01a076f0-d8c0-72a0-8371-cb2ff29c1b28）。用户直接恢复授权见 docs/provenance/DIRECT_USER_RESUME_20260914_ZH.md。主根 D:/008_MA_Dev/T11_CFO；不要操作 T10、CLIP、旧 runner、其他任务工作区。MATLAB=0。不得改变算法、RTL、向量、舍入方式或门槛；执行包装/命令/私有环境修复由 Luna 负责，保留每次尝试及 hash。

## 必须先修复的范围

GUARD002 正常/错误退出及自动取消已分别通过；只剩 PID/瞬时资源遥测缺陷，见 reports/CFO_GUARD002_REVIEW_20260914/INDEPENDENT_REVIEW.json。不重跑旧 normal/error，不重跑已通过的旋转器计算。

使用独立新 v3 包装，完整声明 Win32 API argtypes/restype，按 ULONG_PTR/c_size_t 步长和实际结构偏移解析 JobObjectBasicProcessIdList。动态扩容并检查 assigned/list 数，不能漏读；配合 BasicAccounting.ActiveProcesses 校验。每个 PID 获取创建身份、路径、PrivateUsage、CPU；PID 0、打不开、读不全和查询失败不得计零。进程退出造成的采样竞态可短暂重查并如实记录；持续无法恢复的关键监管故障收尾自己的 Job 并阻断后续阶段。最终全树退出须内核 Activity=0 与列表为空共同支持，不能用根进程已退代替。

先完成纯解析/签名检查，保留执行 v3 源码 hash 和检查结果。修复只作用于包装，禁止调整已经冻结的探针。每个原生阶段创建独占 Job，先 CreateProcess suspended，再成功 Assign + KILL_ON_JOB_CLOSE，再 Resume。绑定失败停止；不得无 Job 启动。若包装需适配以下两条新的计算命令，允许 Luna 新版本实现并在原生执行前完整冻结所有实际依赖；不允许扩大命令范围。

## 冻结输入及顺序

开始运行前执行 C:/Python314/python.exe -I -B -X utf8 tools/verify_rotator.py 和 tools/verify_coordinate.py，均须通过。前者只读身份检查，不运行旋转器仿真；后者只核对新源及旧 MATLAB 参数文件。源身份见 docs/COORD003_SOURCE_LOCK.json。旧 CFO_SYNC XPR 预期 SHA256=8EE3459986419C34B42B4261A0E38B2D5C670B47E25E33D80B46074CD4EE8063。禁止同名或 mtime 选源。

本包每次尝试使用 work/CFO_COORD003/attempt_<UTC>_luna，阶段证据可独立子目录；其路径不得复用其他尝试。EXECUTION_FREEZE 必须记录源码/所有依赖、Python/Vivado 真实路径版本、精确命令、输入 hash、保护、资源和输出目录。原生命令只允许以下三条并严格串行，实际 <attempt> 由冻结记录写出：

1. C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/guard_probe_v2.tcl -log <attempt>/hold.log -journal <attempt>/hold.jou -tclargs hold
2. C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/coordinate_project.tcl -log <attempt>/create.log -journal <attempt>/create.jou -tclargs create <attempt>
3. C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/coordinate_project.tcl -log <attempt>/simulate.log -journal <attempt>/simulate.jou -tclargs simulate <attempt>

第 1 阶段保留真实 READY 的原始行（不得把 Tcl 回显注释当标记）。ready→自动触发 3–4.5 秒、触发→Job 实际归零≤5秒、原生启动→归零≤65秒；每秒资源采样且活跃稳定时必须包含 READY 中真正 Vivado PID及其创建身份、有效 PrivateUsage、完整本 Job 进程列表、BasicAccounting 活跃数、瞬时和 Job 峰值提交量、系统可用内存、监控自身占用。短竞态须记录，稳定期仍有漏项为 FAIL。以修复后的计数证明最终归零。该阶段通过才准入第 2 阶段，不需要再等 Astra 消息；失败阻断计算并交回。

第 2 阶段创建全新独立 CFO_COORD.xpr，FLGB part、硬件/仿真 top 和 7 个显式 project members 必须匹配冻结表。执行 verify_coordinate.py --sources <attempt>/create_actual_sources.csv --identity <attempt>/create_project_identity.txt，保存 JSON 输出并核对成功。记录创建后的 XPR SHA；创建已成功不因后续日志失败重新创建。已有 XPR 须先保留，解释来源及 identity；只复用本包已成功创建且源集完全匹配的工程。

第 3 阶段只跑控制器 behavioral XSim。保存 xvlog/xelab/xsim 原始日志、实际 sources、native/全部子进程退出与 Job 归零、工程 XPR 最终 hash。运行 verify_coordinate.py --actual <attempt>/coordinate_actual.txt --sources <attempt>/simulate_actual_sources.csv --identity <attempt>/simulate_project_identity.txt。不得用包装 exit 0 替代 TB 与数值检查。源集合实际导出不匹配则失败。

## 资源、线程和保护

T10 保留 1 个 Vivado 主作业，本 CFO 最多 1 个，全机最多 2 个；三个重阶段串行，MATLAB 不申请。2026-09-14 12:48 UTC 实测系统 31.421 GiB / 可用15.84 GiB，仅 T10 Vivado 34768/XSim28856 在运行。本包保守估计峰值 4 GiB（包括所启动全部子作业，不拿父进程当总量），留足 T10 增长余量。启动前再次采样，建议空闲>=6GiB；不足则先评估/排队并记录，不挤占 T10。

general.maxThreads=8、synth.maxThreads=8；已有 configure_parallel_jobs.tcl 将 PRE hook 写进真实 run，hook 文件列入 utils_1。xelab 实际设置16，上限16，本包不综合所以不启动 synth runs。若确因新资源证据降低并发，先记录原因，并在 identity 验收中明确本包已批准配置的执行修复差异，不能默改锁/通过条件；常规默认仍为16。

4GiB 是估计告警线，轻微超过只记警告，不因此重跑成功阶段。真正保护：可用物理内存<0.25GiB即时收尾；<0.5GiB持续30秒收尾；关键监管失效/明确工具错误也按本 Job 保守收尾。每秒采样实际 Job 活跃进程、CPU/阶段进展、瞬时私有提交、Job峰值、系统余量；不得接管 T10。

单调时间硬限从各原生进程 Resume 起算：hold 60秒（READY 后3秒优先）；create 120秒；simulate 300秒；触发后全树归零最多5秒。本包原生预计1–3分钟，含准备/归档约10–25分钟。没有自动重启或重跑成功阶段；普通包装修复另存版本/审计，只重试失败阶段。严重无法归零、数值不符、RTL/验收含义问题，停止该阶段并由 Astra 复核。

## 数值和协议门槛

367 个唯一向量（216 组已发布 MATLAB 参数一致 +151 组算术边界），360 个有效/7 个非法。补充6次中途复位/取消后恢复，输出文件应含373条结果，索引顺序为0..366及1/3/5/7/9/11。每条279位完整结果必须匹配；最大有效事务计算延迟≤512周期；TB 中 reset_discards=3、abort_discards=3，不允许旧结果泄漏，输出反压数据/标识稳定，反压周期数必须与向量排程一致。

至少验证真实原始行 CFO_COORD_PASS unique=367 completed=373 invalid=7 max_latency=<实际> stalled_cycles=<实际> reset_discards=3 abort_discards=3；同时独立 Python 逐条通过，且无 $fatal/异常截断。原生包 PASS 只代表该控制器功能，不是 T11/T12/T13整链、综合、布线或500MS/s连续吞吐PASS。

结果完整发布 ATTEMPT_COMPLETION.json 与所有证据清单；全部实际源 hash、原命令、故障修复、阶段耗时和真实资源口径保留。完成或根本障碍时仅向本 Astra 去重唤醒一次。成功保留工程可 GUI 打开；本包不准入下一估计后端、综合或扫描，下一包由 Astra 复核后派发。