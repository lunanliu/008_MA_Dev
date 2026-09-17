# CLIP 端口填写与接线速查

第一次导入请从[逐步操作指南](D:/008_MA_Dev/Sync_Frontend/handoff/Sync_Frontend_20260915_manual/README_ZH.md)开始。下面是同一套设置，方便在向导旁边逐项核对。

Signal Type 表示信号用途，Data Type 表示数值类型。clk125 选 Clock，其余 31 个端口选 Data。所有数据端口的 Required Clock Domain 选 clk125，SCTL 使用规则选 Required。VI 写入对应 Input / To CLIP，VI 读取对应 Output / From CLIP。

| 端口名 | Signal Type | Data Type / 位宽 | 方向 | 所属时钟 |
|---|---|---|---|---|
| clk125 | Clock | 不选普通数据类型 / 1 位 | 时钟输入 | 实例中绑定实际时钟 |
| reset_n | Data | Boolean / 1 位 | VI 写入 | clk125 |
| session_start | Data | Boolean / 1 位 | VI 写入 | clk125 |
| session_abort | Data | Boolean / 1 位 | VI 写入 | clk125 |
| stream_gap | Data | Boolean / 1 位 | VI 写入 | clk125 |
| input_valid | Data | Boolean / 1 位 | VI 写入 | clk125 |
| input_ready | Data | Boolean / 1 位 | VI 读取 | clk125 |
| input_data0 | Data | U32 / 32 位 | VI 写入 | clk125 |
| input_data1 | Data | U32 / 32 位 | VI 写入 | clk125 |
| input_data2 | Data | U32 / 32 位 | VI 写入 | clk125 |
| input_data3 | Data | U32 / 32 位 | VI 写入 | clk125 |
| result_valid | Data | Boolean / 1 位 | VI 读取 | clk125 |
| result_ready | Data | Boolean / 1 位 | VI 写入 | clk125 |
| result_epoch | Data | U32 / 32 位 | VI 读取 | clk125 |
| rx_frame_id | Data | U32 / 32 位 | VI 读取 | clk125 |
| candidate_id | Data | U32 / 32 位 | VI 读取 | clk125 |
| coarse_absolute | Data | U64 / 64 位 | VI 读取 | clk125 |
| fine_absolute | Data | U64 / 64 位 | VI 读取 | clk125 |
| cfo_hz | Data | I32 / 32 位 | VI 读取 | clk125 |
| quality_q1_15 | Data | U16 / 16 位 | VI 读取 | clk125 |
| result_status | Data | U16 / 16 位 | VI 读取 | clk125 |
| accepted_samples | Data | U64 / 64 位 | VI 读取 | clk125 |
| epoch | Data | U32 / 32 位 | VI 读取 | clk125 |
| candidate_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| rejected_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| capture_drop_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| duplicate_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| confirmed_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| snapshot_occupancy | Data | U8 / 8 位 | VI 读取 | clk125 |
| snapshot_peak | Data | U8 / 8 位 | VI 读取 | clk125 |
| max_history_age | Data | U16 / 16 位 | VI 读取 | clk125 |
| error_sticky | Data | U16 / 16 位 | VI 读取 | clk125 |

## 每个端口实际连接什么

| 端口 | 用途和接法 |
|---|---|
| clk125 | 提供核心运行时钟，在实例 Clock Selections 连接实际 125 MHz 时钟 |
| reset_n | 低有效复位：False 复位，True 运行；释放后等待 input_ready |
| session_start | 新会话命令，只拉高一个 FPGA 周期；第一次参考回放保持 False |
| session_abort | 中止当前会话，只拉高一个 FPGA 周期；正常回放保持 False |
| stream_gap | 确有样点丢失时的一拍通知；DMA 暂时为空时保持 False |
| input_valid | 四个新样点已经存稳，保持 True 直到该组被接受 |
| input_ready | 核心能够接收；与 input_valid 同拍为 True 才算交付一组 |
| input_data0 | 本组第一个、时间最早的复数样点 |
| input_data1 | 本组第二个复数样点 |
| input_data2 | 本组第三个复数样点 |
| input_data3 | 本组第四个、时间最晚的复数样点 |
| result_valid | 核心有一整条结果等待读取 |
| result_ready | VI 能在本拍保存整条结果时才置 True |
| result_epoch | 这条结果属于哪个连续数据段 |
| rx_frame_id | 接收端确认的帧编号，在连续数据段内从 0 开始 |
| candidate_id | 这条结果来自检测器的第几个候选 |
| coarse_absolute | 粗时间位置，单位为从本段起点计数的样点 |
| fine_absolute | 精确时间位置，单位样点，从 0 开始 |
| cfo_hz | 有正负号的频偏估计，单位 Hz |
| quality_q1_15 | 质量整数原码，Host 显示时除以 32768 |
| result_status | 结果状态位；所给有效参考结果为 0x3800 |
| accepted_samples | 当前连续段已成功接收的样点总数，每组加 4 |
| epoch | 当前连续数据段编号 |
| candidate_count | 检测器提出的候选总数 |
| rejected_count | 局部检查没有通过的候选数 |
| capture_drop_count | 因窗口缓存或服务条件而放弃的候选数 |
| duplicate_count | 与已确认帧重复、被去掉的候选数 |
| confirmed_count | 已确认并提交到结果保持寄存器的帧数 |
| snapshot_occupancy | 当前占用的局部窗口槽数，范围 0～2 |
| snapshot_peak | 局部窗口槽占用的历史峰值，范围 0～2 |
| max_history_age | 复制窗口时所需最旧样点的最大年龄，单位样点 |
| error_sticky | 本连续段中累计记录的诊断错误位，正常参考为 0 |

## 填完后再确认五件事

1. clk125 在实例的 Clock Selections 中连接真实 125 MHz 时钟；访问这些端口的 SCTL 选择同一个时钟对象。
2. reset_n 选 Data / Boolean，False 表示复位。没有把它误配成自动接全局复位的 Reset 信号。
3. cfo_hz 选 I32；quality_q1_15 选 U16；三个样点计数/位置口保留 U64。
4. 同域 I/O 的附加同步寄存器及访问延迟已经核查，valid、ready 与数据没有错拍；具体入口和适用条件见逐步指南第 6 节。
5. 输入四个 U32 按先后时间连接 data0 到 data3；结果的八个字段同时保存后才确认 result_ready。DMA 打包由 FPGA VI 实现，CLIP 自身没有 DMA 端口。
