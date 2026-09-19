# Sync_DDR 接管任务书

用户最新要求：独立新任务在 D:/008_MA_Dev/Sync_DDR 负责现有 VHDL DDR 读取/写入功能的设计、执行、复核及验证。与其他 Sync 项目平级；停止原同步前端配对继续本工作。不拆分为 Astra/Luna 两个任务。

目标是在现有两控制器和测试台基础上，得到可打开且包含完整层级/两测试源集的 GUI 工程、清晰端口/Host-Target指南和有证据的功能验证结果。器件 xcvu11p-flgb2104-2-e，Vivado/XSim 2021.1。原用户功能验证授权保留；当前不包含综合、实现、NI编译、上板或 MATLAB 执行。

接手顺序：
1. 对照 COPY_MANIFEST 核对工作源、冻结历史和原暂停交接。先读现有端口/测试台，确认频率、接口吞吐和存储协议假设；不猜 DDR 控制器外部服务保证。
2. 修复工作目录内 Tcl/PowerShell 入口，使其只使用本工程文件。已知 add_files 需要把含空格单路径写成 Tcl list；set_property 的 {-mt 16} 应用已准备的 -dict [list ...] 形式再核查。rev05只是无进程预检通过的候选，完整复核尚未结束且从未执行。
3. 发布最小当前执行包，冻结新源清单/脚本身份、完整sources_1/sim_write/sim_read/constrs_1、唯一top、绝对预算和全Job监管，向总管家申请新窗口。本任务同时负责设计/执行/复核，不需要再找配对审批。
4. 获得本任务新grant后依次create、write、read，核对真实5源（2RTL/2TB/1XDC）、编译/展开、原始仿真日志唯一PASS、无ERROR/Fatal/断言失败、完整Job结束。遇普通工具适配错误自行收口修复，不擅自扩大实验。
5. 结果及未验证边界写入本工程 README、验证报告和端口/使用指南。原失败XPR不能作为最终GUI工程，旧通过声明不能套到新目录版本。

不更换用户模型、推理强度或速度，不推送新增Sync_DDR到远程（已有四工程发布由另一任务负责；本任务发布范围需用户另定）。
## 2026-09-17 用户批准的当前修改

两核加入运行时容量C、编译时DDR_WIDTH_BITS、启动配置流水和回放first/last。采用整段上传后回放，Target VI负责段描述符及跨域互斥。实施依据见DDR_RUNTIME_CONFIG_DESIGN_ZH.md，新接线见tutorial/LABVIEW_RUNTIME_CONFIG_AND_SESSION_ZH.md。无双缓冲及反向链路扩展。当前工程已成功create；原历史create失败记录不改变，最终功能结果以本轮验证报告为准。

## 2026-09-17 最新：四段正反向数据流授权

用户本轮明确要求补齐Sync结果FIFO->DDR以及DDR->T2H DMA->Host，交付四个不同VHDL控制器。时钟固定为upload150/read125/capture150/download150 MHz，每组四个32位复样点；目标捕获服务能力超过500MSample/s。此条覆盖上文旧“无反向链路扩展”范围，但不扩大综合/实现/NI/板测/MATLAB授权。

先行设计见DDR_FOUR_STAGE_DESIGN_ZH.md，新增角色复用原两核，无额外组合/流水；保持旧两核、两TB及其成功证据不变。新四源GUI入口及两条反向短测冻结在FROZEN_FOUR_STAGE_V1.json，资源申请RESOURCE_REQUEST_FOUR_STAGE_V1.json，由当前唯一负责人向总管家申请全新窗口。不能将上一轮已关闭grant用于新作业。

已知长度结果N_out与原始输入N_in独立，按Host/Target描述符预设；输入和结果Memory分配互不重叠，不实现同区边写边读。平台写后读可见性、跨域FIFO及实际DDR并行带宽仍需远端NI条件，不用任意延时或假ready替代。

## 2026-09-17 用户继续要求：运行既定方案并交付零基础回环教程

四RTL不变，新增一条604点四核透明回环行为短测与输入/期望/实际仿真接收文件、CLIP导入及全流程连线教程。先行设计DDR_ROUNDTRIP_DESIGN_ZH.md，冻结FROZEN_ROUNDTRIP_V1.json。新资源窗口下仅新create及roundtrip一次XSim，均已PASS；旧成功阶段不重跑。真实Sync/CDC/NI/板测和持续吞吐保持未验证，远端VI/XML由用户实现。
