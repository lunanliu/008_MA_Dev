# Sync Frontend：第一次通过 Host 做波形回放

这份资料用于你已经编译好的 125 MHz FPGA VI。Host 从 CSV 读取一段数字基带波形，经 FIFO_H2T 送入 CLIP，再从 FIFO_T2H 保存检测结果。首次测试使用随包提供的 baseline，不需要信号源、天线或射频连线。

本次测试检查有限长度输入的传输、捕获、定时和频偏结果。它不等同于连续 ADC 数据流的持续吞吐验收。

## 1. 先选对文件

| 文件 | 用途 |
|---|---|
| data/baseline/input_dma_u32.csv | **Host 真正要发送的文件**，单列、无表头、60324 行 |
| data/baseline/input_iq_view.csv | 观察 I/Q 波形；有表头，不能直接送 DMA |
| data/baseline/input_four_lanes_view.csv | 每行四个连续样点，便于核对 lane 顺序 |
| data/baseline/expected_truth.csv | 四条真实结果应有的精定时与频偏 |
| data/baseline/host_chunks.csv | Host 分块发送清单，包括每块起点、长度、等待的累计接收数 |
| generate_frontend_csv.m | 生成 CSV；baseline 原样重建已验证输入，custom 改变噪声与间隔 |
| analyze_frontend_waveform.m | 查看输入波形、重复前导特征与频偏 |
| analyze_frontend_readback.m | 解析板卡返回的九字记录并对照真值 |
| reference/example_SIMULATION_readback_u32.csv | **仿真结果构造的分析示例，不是板卡实测数据** |

MATLAB R2024a 可运行这些脚本，不需要专门的通信工具箱。输出目录应使用新名字；脚本会拒绝覆盖已有结果。

## 2. 输入到底是什么信号

每个复数样点是 I16 + jQ16，I、Q 都是有符号 16 位整数。一个样点打包成一个无符号 32 位数：

- 低 16 位存 I 的二补码位型。
- 高 16 位存 Q 的二补码位型。

例如 I=-1、Q=0 时，发送值是 65535；I=0、Q=-1 时，发送值是 4294901760。不要把这列数归一化到 -1～1，也不要把它当成单独的实数幅度。

你目前 DMA 的 unsigned FXP、word length=32、integer word length=32 可以精确表示这些打包值。Host 可先把 CSV 读成 DBL，再转换成 FIFO 要求的这一种 FXP 类型；所有 U32 整数都能被 DBL 精确表示。不能经过 SGL，SGL 会丢低位。

baseline 共 60324 个复数样点，包含背景噪声、用来干扰捕获的假重复前导，以及四段真实前导附近的 IQ 数据。四段真实片段每段 3176 个样点，**不是四个含完整负载的 OFDM 帧**。

信号采样率为 500 MS/s，样点间隔 2 ns。FPGA 每个 125 MHz 时钟最多接收四个连续样点。因此：

| FIFO 一次读取的数组元素 | CLIP 端口 |
|---|---|
| 元素 0（最早的样点） | input_data0 |
| 元素 1 | input_data1 |
| 元素 2 | input_data2 |
| 元素 3（最晚的样点） | input_data3 |

60324 是 4 的整数倍，共 15081 次四元素读取。主输入文件故意只放一列，可以避免把四列表格按列展开而打乱时间顺序。

波形中的 500 MS/s 描述样点时间坐标。Host 在两块数据之间等待，不会增加波形里的样点，也不应插入零或触发 stream_gap。

## 3. 首次测试的控制值

| 信号 | 本次如何设置 | 含义 |
|---|---|---|
| reset_n | 开始时 False，等待 1 ms，再改 True | 低电平复位 CLIP，之后释放 |
| session_start | 始终 False | 这份核心在复位后已经自动允许接收，不需要再发 start |
| session_abort | 始终 False | 本次不中途终止 |
| stream_gap | 始终 False | DMA 暂时没数据不是波形断点 |
| stop | 测试中 False，收完结果后再 True | 不要送完输入就立即停 FPGA |
| input_valid | 保持由 FIFO_H2T 的 Output Valid 驱动 | Host 不手动控制这个握手信号 |
| input_ready | 保持连接到 FIFO_H2T 的 Ready for Output | CLIP 决定何时可以接收 |
| result_ready | 保持你现有内部 FIFO 写入侧的背压逻辑 | Host 不把它强行写成 True |

释放 reset_n 后，核心还有内部复位同步和 16 个时钟的清理时间。Host 等待 1 ms 已经足够宽松；如果 input_ready 被暴露为 Host 指示器，也可同时检查它为 True。本次预期 epoch=0。

session_start、session_abort、stream_gap 在核心中按“每一个为 True 的 FPGA 时钟”处理。以后如果要用它们，应该由 FPGA 产生单时钟脉冲。Host 把按钮保持 True 几毫秒会覆盖很多 FPGA 时钟。本次把三者保持 False，避免引入这个问题。

## 4. Host 初始化，按这个顺序做

1. Open FPGA VI Reference，选择本次编译产生的 bitfile。关闭自动运行选项，先完成初始化。
2. 在没有发送数据时，调用 FPGA 的 Reset 方法。对两个 DMA FIFO 调用 FIFO.Stop，结束上一次 Host 传输，再做后续配置。**只拉低 CLIP 的 reset_n 不能代替整个 FPGA VI 的 Reset**：你的内部 FIFO、串行发送用的移位寄存器也需要回到初始状态。
3. 在 Host 调用 FIFO.Configure：H2T 的 Depth 可先用 65536，T2H 可先用 4096。记录返回的实际深度。这两个数是电脑内存里的缓冲深度，不是 Project Explorer 里消耗 FPGA BRAM 的深度。
4. 写入控制值：stop=False，reset_n=False，session_start=False，session_abort=False，stream_gap=False。
5. 对两个 DMA 调用 FIFO.Start，然后 Run FPGA VI；Run 应设为不等待 FPGA VI 执行结束。
6. 等待 1 ms，把 reset_n 改为 True，再等待 1 ms。确认 accepted_samples=0、epoch=0、error_sticky=0，然后开始下面的两个 Host 循环。

每次重新测这段文件都从步骤 1～6 的初始化状态开始。不要把上次残留的 DMA 字和新结果拼接起来。NI 对 Reset/Run/FIFO.Start 的说明见文末；Reset 会恢复 FPGA VI 默认状态并清空 FIFO，Run 本身不是清空操作。

如果你没有把 input_ready 暴露给 Host，不必为了这个指示器重新编译；固定等待之后，以 accepted_samples 的实际增长检查送数即可。

## 5. Host 发送循环：每块 1024 个样点

不要一开始就把全部波形灌进 FIFO。首次测试先用下面的慢速分块方式，把接线和功能确认清楚。这个节奏可以只在 Host 实现，不必为了节流修改已编译的 FPGA VI。

1. Read Delimited Spreadsheet 读取 input_dma_u32.csv，得到一列数；取出这一列成为一维数组。
2. 转成与 H2T FIFO 一致的 unsigned FXP 32/32 数组。
3. 从数组起点 0 取 1024 个元素，调用 FIFO_H2T.Write，Timeout 可设 2000 ms。
4. 写入成功后，通过 Read/Write Control 读取 accepted_samples。等它达到本块的累计目标：第一块是 1024，第二块是 2048，依次增加。可在轮询之间 Wait 1 ms，最多等 2 s。
5. 达到目标后，再 Wait 1 ms，然后发送下一块。**先确认 FPGA 已接收这一块，再等待和发送下一块**，这样不会在 Host 队列中积压整段波形。
6. 最后一块只有 932 个样点。最终累计目标为 60324。精确分块表在 host_chunks.csv 中。

如果 Write 或累计接收等待超时，保存当时的块号和计数并结束本次测试；不要不检查传输状态就重发整块，以免重复输入。

原 RTL 参考测试采用“每 256 次四样点接收后，空闲 8000 个 FPGA 时钟”，约 64 μs。这里采用 Host 等待至少 1 ms，调度不完全相同。因此精定时和频偏可以对照真值，但 candidate_id、粗定时、质量及丢弃候选计数不能一概要求与原仿真逐项相同。

这份前端在候选缓存忙时可能丢弃候选，input_ready 不是全链无限背压的保证。先用此节奏验证有限回放，再另行评估持续实时输入。

## 6. Host 接收循环：与发送循环并行

在另一个 Host While Loop 中读取 FIFO_T2H。两个循环共用 FPGA reference，但不要用错误线把“发送完全部数据”串在“开始读取结果”之前。

- 每条检测结果占 9 个 U32 字，先用 FIFO_T2H.Read 每次读取 9 个元素、Timeout=100 ms。
- 正常等待期间超时表示这次没有凑齐一条记录，不是一个全零结果。不要把默认值或无效输出写进结果文件，也不要吞掉其他类型错误。
- 将成功读取的数据按收到的顺序追加到一维数组中。
- 发送结束后继续读取，给最后一条结果留下处理时间。首次测试可在发送结束后留最多 2 s；同时观察 confirmed_count 是否为 4、snapshot_occupancy 是否回到 0。
- 正常应收到 4 条结果，即 36 个字。收满后仍检查是否有额外结果；若超时结束时还剩不足 9 字，按实际剩余数量读出并保存，这样分析脚本能指出不完整记录。
- 保存原始文件为 readback_u32.csv：**单列、无表头、无空行，每行一个无符号十进制整数**。用 Write Delimited Spreadsheet 时将格式设为 %.0f，不要沿用只有少量有效位的默认浮点格式。

完成读取和保存后，再停止 FPGA VI 与 DMA，关闭 reference。

下面是分析器采用的九字顺序，与原交付手册一致：

| 字编号（从 0 起） | 内容 |
|---|---|
| 0 | result_epoch |
| 1 | rx_frame_id |
| 2 | candidate_id |
| 3 | coarse_absolute 的低 32 位 |
| 4 | coarse_absolute 的高 32 位 |
| 5 | fine_absolute 的低 32 位 |
| 6 | fine_absolute 的高 32 位 |
| 7 | cfo_hz 的 I32 二补码位型 |
| 8 | 高 16 位为 result_status，低 16 位为 quality_q1_15 |

尤其注意：LabVIEW 的 Join Numbers 必须按实际高/低半字端子接线，不能只看线条上下位置猜测。这里是明确的传输约定；如果你已编译的 VI 使用其他顺序，分析器也必须按那个顺序调整。编译成功不会检查这种应用层位序。

CFO 为负时，原始 U32 字会是很大的正数，这是正常现象；MATLAB 会按 I32 位型解码。64 位定时也是先拼接高低位再解释，不经过浮点截断。

## 7. 应该看到什么结果

下面位置是“从整段输入第 0 个样点开始计数”的精定时真值。它不是 Host 上的毫秒时间。

| rx_frame_id | fine_absolute 真值 | CFO 真值 |
|---|---:|---:|
| 0 | 15004 | -150000 Hz |
| 1 | 26373 | 0 Hz |
| 2 | 37842 | +150000 Hz |
| 3 | 49311 | -150000 Hz |

首次回放检查：四条记录按 0、1、2、3 排列，epoch 都为 0，精定时等于上表，CFO 与真值偏差不超过 1000 Hz，status 的有效位 bit11 为 1。candidate_id 应递增，但不必连续。

Host 同时保存这些指示器：

| 指示器 | 本次观察重点 |
|---|---|
| accepted_samples | 最终为 60324，说明输入样点已被核心接收 |
| confirmed_count | 预期 4，与收到的完整记录数核对 |
| error_sticky | 预期 0；非零时保存原值 |
| epoch | 预期 0；意外变化通常要检查三个边界控制信号 |
| snapshot_occupancy | 处理结束后回到 0 |
| candidate_count、rejected_count、capture_drop_count、duplicate_count、snapshot_peak、max_history_age | 保存用于定位；含假前导和重复候选，不能统统要求为 0 |

原 RTL 参考结果的 CFO 为 -150022、0、150022、-149977 Hz；有效状态均为 0x3800。完整参考在 reference/autonomous_results.csv，里面 status 这一列是十六进制文本。该文件是对照资料，不是原始 DMA 返回文件。

## 8. MATLAB 怎么用

先在 MATLAB 执行：

```matlab
cd('D:/008_MA_Dev/Sync_Frontend/handoff/Sync_Frontend_BoardTest_20260915')
```

现成 baseline 已可直接发送，不必先运行生成器。要重新生成同一波形到新目录：

```matlab
generate_frontend_csv('my_baseline', 'baseline');
```

查看输入波形：

```matlab
analyze_frontend_waveform('data/baseline', 'my_waveform_analysis');
```

它输出 I/Q 波形及重复前导相关曲线，使用 1024 样点间隔和 1024 样点窗口估计重复特征与频偏。它用于解释这段波形，**不替代自主检测算法或 RTL 验证**；已知位置上的频偏估计只是辅助查看。

要改变背景噪声种子、前置噪声长度和段间隔：

```matlab
generate_frontend_csv('my_custom', 'custom', struct( ...
    'Seed', 7, 'LeadingNoiseSamples', 8192, 'GapSamples', 12288));
```

custom 会保留四段经过验证的前导 IQ 片段，重新组合背景与间隔，并生成新的 expected_truth.csv。它不是任意 OFDM 帧/任意信道生成器，也没有因为生成成功就自动通过 RTL 或板级验证。首次板测用 baseline。

收到真实板卡文件后，执行：

```matlab
report = analyze_frontend_readback( ...
    'D:/你的实际目录/readback_u32.csv', ...
    'data/baseline', 'my_readback_analysis');
```

如果测试的是 my_custom，则第二个参数改成 my_custom。输出包括 decoded_results.csv（还原后的结果）、comparison.csv（误差）、analysis_summary.txt/json（判定）和 readback_comparison.png。

若另外记录了实际诊断计数，把真实读值传进去。例如，确实读到 accepted_samples=60324、error_sticky=0 时：

```matlab
report = analyze_frontend_readback( ...
    'D:/你的实际目录/readback_u32.csv', ...
    'data/baseline', 'my_readback_analysis_with_counts', ...
    struct('ExpectedEpoch', 0, 'AcceptedSamples', 60324, 'ErrorSticky', 0));
```

不要为了得到 PASS 而直接照抄两个诊断值；没有读取就省略它们。对应判定：

- FINITE_REPLAY_CHECKS_PASS：本次有限回放的所检查结果和输入计数/错误标志通过。
- RESULT_FIELDS_PASS_DIAGNOSTICS_NOT_CHECKED：结果字段通过，但未提供诊断计数。
- FAIL_OR_INCOMPLETE_CAPTURE：结果、数量、有效位或诊断有异常，或者最后一条记录缺字。

StrictRtl 默认关闭，Host 1 ms 分块方案不要打开它。只有复现原来精确 FPGA 周期节奏时，才能对照所有原 RTL 字段。

如想先熟悉分析器，可把 readback 路径换成 reference/example_SIMULATION_readback_u32.csv，并选新输出目录。得到的图是仿真示例，不代表已完成板测。

## 9. 依据与文件来源

本包 baseline 原始流的 SHA256：

98fffec3b2773996e54aa7608b1c2e112bc9f97fd3672f7d27bdc1b614c550d4

接口和控制依据为当前 Sync_Frontend/rtl/frontend/sync_frontend_top.sv、wrapper/sync_frontend_clip.vhd、sim/tb/sync_frontend_tb.sv 及原手工交付说明。这里没有更改它们。

NI 官方说明：

- [DMA 由 FPGA 与 Host 两端缓冲组成](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/how-dma-transfers-work-fpga-module.html)
- [Host 缓冲深度与 FPGA 缓冲深度的区别](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z0000019KwbSAE&l=en-US)
- [Reset、Run、Start 对 FIFO 和 FPGA VI 状态的作用](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z000000kGSNSA2)
- [Host 一次读写的元素数与缓冲深度限制](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA0VU000000CQ1x0AG&l=en-US)

本次新脚本验证记录见 validation 下的独立目录。真实板卡结果尚未提供；脚本自测与仿真参考不能代替你的板卡读回。

## 10. 本次实际完成的检查

2026-09-15，MATLAB R2024a 的第二次新脚本验证正常结束（exit code 0）。第一次验证发现分析脚本状态半字移位方向写反，已修正；旧脚本和失败输出保存在 validation/attempt_01，没有删除。

已检查：60324 样点的 I/Q 打包与四路顺序、分块长度、四条仿真参考记录的完整还原、缺字、重复帧、错误 CFO、错误精定时、无效状态、空输入、多列输入拒绝、缺少诊断时不报完整 PASS、epoch 选择、超过 double 精度范围的 U64 拼接，以及 custom 片段保持一致。

验证摘要：validation/attempt_02/validation_summary.json。输入波形分析：validation/waveform_analysis_01/waveform_analysis.png。后者在四个真实位置给出的浮点频偏为约 -150016.56、0、150022.24、-149985.88 Hz。

这些是新 CSV/MATLAB 工具的离线检查。没有运行新的 RTL 仿真，也没有把仿真示例标记成板卡实测。你的真实板卡回放结果需要另行保存后分析。