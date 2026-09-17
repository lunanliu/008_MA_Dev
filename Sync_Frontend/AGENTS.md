# 同步前端执行规则

用户最新交付范围（2026-09-15）：仅交付完整 Vivado 核心 RTL 工程（top=sync_frontend_top）、独立明文 VHDL wrapper、可复现输入/预期输出及中文手工操作说明。CLIP XML 与 LabVIEW CLIP 配置由用户亲自创建；Agent 不新增/生成/修补 XML，不创建 LabVIEW 项目，不做 wrapper 回填或独立 wrapper 网表验证，不为交付重跑冻结实验。

用户总管家最新授权优先，完整任务书见docs/WORK_ORDER_ZH.md。仅写D:/008_MA_Dev/Sync_Frontend；旧工程及T10/T11只读。Astra拥有设计/源码/正式复核，绑定Luna拥有冻结作业的运行目录；不得同时写同一文件。配对见docs/PAIRING.json（总管家创建后补齐）。

1. 输入仅未同步原始I16/Q16及传输控制，自主检测并生成接收帧标记。禁止把外部frame_id/参考起点/预切前导当成自主同步。
2. 正确器件xcvu11p-flgb2104-2-e，首选125MHz单域，Fs=500MS/s。Vivado真实XPR管理top/RTL/IP/TB/XDC；本地独立Git，功能命名和排版与功能修改分别提交。
3. 重用正式T04/T05已验收算术，来源/哈希/更名映射可查。自己维护的RTL不以T编号命名；厂商生成物不手改。新捕获控制需最小真实验证，不能以原核PASS覆盖。
4. 全机1 MATLAB、2 Vivado主作业；T10长仿真不打断。前端与T11共用非T10槽，按总管家授权文件resource_slot.json所有权执行。缺少grant时不启动Vivado；有grant且资源符合时Astra冻结直接派唯一Luna，无需逐条请示。
5. Vivado general/synth线程8，jobs/xelab默认上限16，传入真实子进程；内存估算告警不直接停任务。MATLAB原唯一串行槽，禁止-singleCompThread。不得改全局环境，不重启电脑。
6. Astra设计/派单/复核；Luna执行/监控并自修执行错误。完成或根本性设计问题才反馈Astra；不重复成功计算，不覆盖冻结/失败证据。Astra派单后结束轮次，等待不空转。
7. Astra High、Luna Max，均Standard禁Fast；用户设置优先。后续消息不带model/thinking/service_tier，禁止全局改设置。无速度控制接口如实记未核实。
8. 工作期间15分钟表格报告，含当前账户周配额；按原模板，末行Ciallo～(∠・ω< )⌒☆。本任务计时器开工启用，空闲停用；任务不足15分钟不补报。总管家统一巡检，不新建值班员。
9. 最终交付为可直接 GUI 打开的完整核心 RTL/XPR（含约束/IP/TB/既有功能验证证据）、匹配的独立明文 VHDL wrapper、输入/预期结果及逐端口和 Host/Target 手工测试说明。XML/CLIP 配置由用户在 LabVIEW 创建；不作为 Agent 必交项或门槛。独立时序与 NI 板级验收分开，用户负责后续 LabVIEW/板测。
