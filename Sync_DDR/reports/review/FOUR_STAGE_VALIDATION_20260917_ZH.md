# 四段 DDR 控制器交付与短验证

结论：四个角色RTL文件齐备；新GUI create、capture、download均PASS。原两核/两TB逐字节未改，继承上一轮已通过证据且未重跑。本次没有原生失败/重试，没有改变验收标准。

| 文件 | 作用 | 时钟 | 功能证据 |
|---|---|---|---|
| rtl/ddr_upload_ctrl.vhd | H2T DMA -> 输入DDR | 150MHz | 上一轮PASS，本轮哈希相同 |
| rtl/ddr_read_ctrl.vhd | 输入DDR -> Sync | 125MHz | 上一轮PASS，本轮哈希相同 |
| rtl/ddr_capture_ctrl.vhd | 结果Target FIFO -> 结果DDR | 150MHz | 本轮短测PASS |
| rtl/ddr_download_ctrl.vhd | 结果DDR -> T2H DMA | 150MHz | 本轮短测PASS |

capture/download分别依赖upload/read，四文件一起交付；新增角色不引入额外流水。实际宽数据数组仍在LabVIEW。工程work/four_stage_v1/attempt_01_create/project/DDR_Control.xpr，默认capture顶层；实际4RTL、4TB、2个独立时钟约束集、4个sim filesets与冻结10项源成员及5个top一致。

## 本轮短测证据

- capture原生唯一DDR_CAPTURE_CTRL_TEST_PASS。4000点、100个DDR块、1000个四点接收周期加100个写周期，data_window=1100；另覆盖FIFO/DDR等待、44点尾块补零、84点暂停与配置锁存、非法容量拒绝、取消待提交块及重新启动。
- download原生唯一DDR_DOWNLOAD_CTRL_TEST_PASS。4000点理想回放1000周期无气泡；用8组有限DMA环形队列和独立Host读指针，先停止Host，断言DMA满后播放器保持，再间歇读取，逐点核对无丢失/重复/乱序；604点尾部、N=4首尾同拍、非法容量、取消在途DDR响应及恢复均通过。断言download_done时Host仍未收齐，随后按N接收完整。
- 两次xvhdl/xelab通过，原生xelab命令唯一--mt 16；general.maxThreads=8。所有检查日志无ERROR/FATAL/FAILURE或断言失败。每阶段exit0，所属完整Kernel Job连续三次为空。
- 仿真采用150MHz名义时钟，XSim时间分辨率1ps；周期数是主要服务节拍证据。NI资源/DDR/Host均为行为模型，不是远端真实VI/PCIe实测，也不是四段集成端到端验证。

| 阶段 | 开始（CEST，UTC+02:00） | 收口（CEST） |
|---|---|---|
| create | 2026-09-17T20:46:37.940136+02:00 | 2026-09-17T20:46:58.589388+02:00 |
| capture | 2026-09-17T20:47:20.274920+02:00 | 2026-09-17T20:47:48.664465+02:00 |
| download | 2026-09-17T20:48:11.827680+02:00 | 2026-09-17T20:48:41.264664+02:00 |

固定预算起点20:46:37.9312527，整体截止21:01:37.9312527；真实首次根PID5864创建于20:46:37.9786848，二者分别记录。本轮最后作业20:48:41.2646649收口，不再启动EDA。工具环境有HLS路径缺失/.gen目录不存在等提示，详见JSON逐项原文；本轮未使用HLS或生成IP。create另提示threads_pre.tcl是外部synth钩子、未加入utils_1；当前路径存在且未运行综合，Vivado Archive不能假定包含此钩子，应保留项目scripts目录或用本工程Tcl重建。报告整理时本机Python缺tzdata，已按当天明确的CEST UTC+02:00转换显示，内部UTC日志不改，没有重跑计算。

## 速率与尚未验证项

默认1280bit写入10拍接收+1拍提交，因此150MHz理想545.45MSample/s，大于500但只有约9%服务裕量；平均每40点额外停顿达到1拍就降至500。不能称为每拍永不间断接收四点。125MHz回放端口500MSample/s，150MHz下载端口600MSample/s，都可能受背压/缺数据限制。物理时序、共享DDR持续约4GB/s服务、PCIe实际吞吐、NI编译、跨域FIFO和板测均未验证。

结果N_out需在启动前给出且四点对齐，不能默认等于N_in。输入和结果Memory独立分配，原始输入与结果不能同地址覆盖。capture_done到NI写可见性、download_done到Host实际收齐分别需要会话层条件。Sync必须能够承受结果FIFO背压；若无法暂停，须另给最大突发合同并核算容量。

## 交付入口

- docs/DDR_FOUR_STAGE_DESIGN_ZH.md：编码前架构/资源/时钟预算。
- docs/tutorial/LABVIEW_FOUR_STAGE_WIRING_ZH.md：四个文件依赖、FIFO/DMA配置、分支接线及全部新增端口。
- reports/review/FOUR_STAGE_SELF_REVIEW_ZH.md与FOUR_STAGE_STATIC_AUDIT.json：单任务设计自审。
- reports/operations/FOUR_STAGE_VALIDATION_RESULT_20260917.json：冻结校验、阶段结果、原生标志、进程身份/三空及限制。
- work/four_stage_v1/attempt_02_capture/native_logs/simulate.log；attempt_03_download/native_logs/simulate.log：原始行为证据。

本轮只改既有README和PROJECT_SPEC以标注新范围，原两核/两TB、history、imported、matlab和失败证据保持不变。未修改其他四个Sync项目、未新建任务/worktree、未改变模型配置、未推送远端。总管家于20:51:39.146387 CEST完成资源归还，中央owner=NONE、grant=null、usable=false；所有旧grant不能复用。
