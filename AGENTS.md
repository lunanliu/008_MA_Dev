# 2026-09-17：Sync_DDR 独立单任务（最新 DDR 归属）
用户要求把同步前端的 VHDL DDR 读写工作迁入 D:/008_MA_Dev/Sync_DDR，与其他 Sync 工程平级。唯一新任务为“同步 DDR｜设计、执行、复核与验证”，ID 01a0afdf-cd3a-7e91-afc8-6a947ec3cc71，工作目录 D:/008_MA_Dev；该任务自己负责设计、执行、监控、自审和验证，不建立第二个执行任务，不派给原前端或 OTA 的 Luna。这是仅针对 Sync_DDR 的单任务例外，覆盖下方历史配对规则。
入口见 Sync_DDR/README_ZH.md 和 Sync_DDR/AGENTS.md。原 DDR 配对已停止，旧 grant 已关闭；新任务先静态接管/修入口/冻结输入，再申请自己的新资源窗口。现有功能验证授权承接，write/read 仍未验证，迁移不等于功能验收。其余四个 Sync 工程保持各自当前范围，OTA 设计/测试继续暂停。Sync_DDR 尚未加入本次四工程远程发布，不自动推送。

# 2026-09-17 用户新增硬规则：先按真实硬件指标设计RTL

凡RTL/FPGA设计、修改或集成，先明确器件/时钟周期、持续吞吐、延迟与背压、存储带宽和器件资源预算，再规划每级运算、流水寄存器、弹性握手、扇出、CDC/复位及同时事件优先级，完成设计自审后编写RTL。不得把长ready链、复杂地址/判定逻辑直接连成一拍，再等最终综合或板测发现问题。模块边界不是寄存器边界，功能仿真/IP OOC不等于整链时序或持续吞吐通过。

设计前必读 [RTL硬件设计前置规范](<D:/007 Dev/OTA_RTL_0829/docs/engineering/RTL_HARDWARE_DESIGN_STANDARD_ZH.md>)；设计依据写入已有模块文档/任务书，简单变更只记录受影响项，不新增逐项审批。高速结构成形后按已有授权尽早综合/检查真实路径，禁止无依据false_path、降频或放宽指标掩盖问题。原配对、资源准入、安全审批及既有只读/暂停边界保持。

# 2026-09-16 Sync OTA集成授权

用户最新直接要求新增Sync_OTA，与本目录Sync_Frontend、Sync_SFO、Sync_CFO并列。其独立任务书在Sync_OTA/docs/PROJECT_SPEC_ZH.md；Astra 01a0ac17-f298-7201-848c-58d09e90ebb4 与Luna 01a0ac17-4f21-7be3-8690-540c11497b1e唯一配对，负责集成设计、必要短测与真实核心综合交付。原三个工程保持原位只读；Sync_OTA使用本父目录Git，只提交本任务文件。该范围覆盖下方旧“仅三模块整理”的限制，不自动恢复其他配对或旧作业；原生运行仍须总管家具体验证资源准入。模型Astra High/Luna Max、要求Standard禁Fast，后续由用户控制。


# 2026-09-15 目录映射补充（原规则全文保留）

本轮用户批准的三模块入口与路径整理按 D:/007 Dev/OTA_RTL_0829/docs/operations/SYNC_SFO_DIRECTORY_REORGANIZATION_AUTHORIZATION_20260915_ZH.md 执行。新增位置见 [PATH_MAPPING_ZH.md](PATH_MAPPING_ZH.md)。下方旧规则中的根目录 docs、tools、rtl、ip、constraints、sim、matlab、vivado、handoff、work 均已归入 Sync_SFO；T11_CFO 对应 Sync_CFO。Sync_Frontend 保持原位，I16 示例在其 examples 内且保持独立身份。

本补充只解释搬迁后的路径，不扩大算法、实验、配对或交付授权。用户打开的旧前端 GUI 状态保持；旧规则原文和已有用户修改均保留如下。

---

# 本工程执行规则

1. 用户总管家任务最新要求优先。当前T10完整帧仿真与 T11_CFO 内T11～T13的CFO RTL独立并行，器件只用 `xcvu11p-flgb2104-2-e`。旧CFO暂停已解除，范围见[授权说明](docs/operations/T11_CFO_RTL_AUTHORIZATION_20260914_ZH.md)；新增Sync_Frontend专属配对开发自主原始流同步前端核心工程及VHDL Wrapper，授权见D:/007 Dev/OTA_RTL_0829/docs/operations/SYNC_FRONTEND_CLIP_AUTHORIZATION_20260914_ZH.md；用户负责LabVIEW工程/板测，不恢复旧T10 CLIP及旧runner。
2. 开工先读 `README_ZH.md`、`docs/PROJECT_SPEC_ZH.md` 和 `docs/AGENT_GUIDE_ZH.md`。本目录是独立副本，禁止引用或修改旧工作区来完成构建。
3. 唯一硬件顶层、仿真顶层及准确源集由Vivado工程和原生Tcl共同定义。禁止递归收集整个目录、按mtime挑选同名源码、静默替换IP/参数/参考答案。
4. T10与T11各自保持原Astra/Luna配对：Astra设计、冻结作业和复核，自己的Luna执行、监控及自修执行问题。模型/强度/速度由用户控制，Astra禁Fast；单写者，不跨任务借人或接管进程。
5. 原生作业先固定输入、预算、异常保护及结果目录；全机最多1 MATLAB＋2 Vivado主作业，每对最多1个；T10保留原槽，Sync_Frontend与T11共享另一槽，前端优先、不中断既有阶段，按总管家reports/operations/sync_frontend/resource_slot.json所有权执行，启动前核算总资源。T10正常仿真不设墙钟截止，T11按具体作业的阶段保护执行。按[性能规范](docs/TOOL_PERFORMANCE_ZH.md)充分使用本机：Vivado general/synth线程请求均8，必须经run的PRE钩子传入子进程；构建jobs和xelab子编译默认/上限16。实际并行数按总内存、现有进程及历史峰值选取，资源不足可下调并记录理由，禁止无理由固定2线程。MATLAB新入口不用 `-singleCompThread`，使用自动计算线程；串行槽只限制进程数。保留冻结历史脚本，不直接复用其旧限速参数。先查数据加载/首错再长跑，不因交接问题重跑成功计算。
6. 运行产物留在 `work/` 或Vivado自身运行目录。禁止改全局环境；Python用独立解释器，避免继承Vivado的Python库路径。正常GUI仿真不依赖旧Python监管器。
   内存预估是告警线，不直接作硬终止条件；小幅越线继续监控并完成，事后复核峰值。真正停止条件按系统严重内存压力、明确错误或无进展另行定义；续跑复用成功检查点，不重做已成功阶段。
7. 工作中的任务每15分钟报告进展、耗时、进程/队列和当前账户周配额；空闲停报。沿用总管家已有调度，不新建重复唤醒链。
8. 原件及失败证据保留。修改前确认Git状态、来源和依赖；仅提交已审阅的本次文件。本项目仅本地Git，不设置或推送云端remote。
9. 按[交付规范](docs/RTL_HANDOFF_MANUAL_LABVIEW_ZH.md)只交付算法核心为综合top的GUI工程、独立VHDL Wrapper、测试输入/预期输出及端口/Host操作说明；不生成CLIP XML/配置包，由用户手工创建CLIP。工程能打开、仿真通过、实现时序通过是不同验收。旧FLGC结果保留历史身份；任何新FLGB通过声明必须对应实际工具证据。


