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

