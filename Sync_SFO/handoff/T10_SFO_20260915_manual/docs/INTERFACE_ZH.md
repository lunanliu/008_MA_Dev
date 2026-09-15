# 核心与独立VHDL Wrapper接口

本文件的“入/出”均相对CLIP Wrapper。VHDL明文见[Wrapper](../wrapper/t10_sfo_manual_wrapper.vhd)，可筛选的逐端口表见[ports.csv](../wrapper/ports.csv)，机器映射见[interface_contract.json](../wrapper/interface_contract.json)。

核心有37个端口，Wrapper有102个端口。Wrapper只做连线、拼接、拆分和高位补零，没有时钟发生器、寄存器、FIFO或新增CDC，不改变核心算法。总线拆成Boolean及8/16/32位端口，便于用户手工定义LabVIEW CLIP。实际导入和NI编译尚未执行。

核心唯一参数OUTPUT_CLOCK_MHZ必须为150，与已验RTL默认值一致。Wrapper不声明VHDL generic，源级绑定使用核心默认150；用户导出的固定网表也必须按150综合，不能导入另一个125参数网表。这样固定网表连接时不要求NI对一个已固化模块重新传递参数。

所有多位VHDL端口用std_logic_vector，宽度W时类型为std_logic_vector(W−1 downto 0)，标量为std_logic。负数以二补码原样传送：LabVIEW可以用U32保存位模式，显示物理有符号值时使用位模式重解释为I32，不能将负数经饱和转换变成0。

## 1. 三路时钟和复位

输入、描述符、CFO/fine记录、residual point和debug125属于125 MHz；输出m_*、E1观察、diagnostic、debug150属于150 MHz；FFT服务另需连续500 MHz。三个时钟均由平台提供，不由本Wrapper产生。一个150 MHz SCTL不能直接承担全部接口；建议125 MHz SCTL处理输入/配置/点记录，150 MHz SCTL处理输出/E1观察，平台时钟网络把500 MHz送到clk500。不是要求在500 MHz SCTL中串行运行整个LabVIEW程序。

在用户CLIP定义中把三个输入声明为时钟，并把各组I/O关联到实际所属域。平台必须落实所需时钟源、缓冲、复位/锁定关系、约束及VI与DDR/DMA之间的CDC。本包没有MMCM、PLL、平台clock-locked端口，也没有把150 MHz自动变成500 MHz的功能。频率的整数比本身不构成时钟同步证明。

reset_request高有效，是异步复位请求。核心各低速域经4级异步复位同步器，再保持至少64个本域时钟周期后释放；还存在各FIFO/IP自身复位过程。因此复位请求拉低后，不能立即送数。

最小用例复现测试台：所有时钟稳定后，reset_request=1至少保持80个125 MHz周期（640 ns），所有输入valid=0、abort125=0、m_ready=0；再释放请求，分别观察各自域的ready和m_reset，按握手提交配置。80周期是本用例的复现方式，不替代平台时钟发生器的锁定等待。Wrapper不对输入常量和无效数据自动清零。

abort125是125 MHz同步取消信号，触发粘滞错误，不是暂停键。取消后完整复位再重试。重复frame6001之前也要复位，否则连续递交不递增的帧号会触发错误4。

## 2. 核心37端口的逐项连接

下面的表达式按VHDL从高位到低位拼接；core_*是Wrapper内部连线。拆分输出的完整映射见后面的位段表及VHDL赋值。

| 核心端口 | 方向 | 位宽 | Wrapper连接表达式 |
|---|---|---:|---|
| `clk125` | 入 | 1 | `clk125` |
| `clk150` | 入 | 1 | `clk150` |
| `clk500` | 入 | 1 | `clk500` |
| `reset_request` | 入 | 1 | `reset_request` |
| `abort125` | 入 | 1 | `abort125` |
| `s_valid` | 入 | 1 | `s_valid` |
| `s_ready` | 出 | 1 | `s_ready` |
| `s_data` | 入 | 128 | `s_iq3 & s_iq2 & s_iq1 & s_iq0` |
| `s_frame_id` | 入 | 32 | `s_frame_id` |
| `s_absolute_index` | 入 | 32 | `s_absolute_index` |
| `s_lane_valid` | 入 | 4 | `s_lane_valid(3 downto 0)` |
| `frame_valid` | 入 | 1 | `frame_valid` |
| `frame_ready` | 出 | 1 | `frame_ready` |
| `frame_record` | 入 | 188 | `frame_id & frame_generation & frame_raw_first_word_hi & frame_raw_first_word_lo & frame_nominal_absolute & frame_q0_q28(27 downto 0)` |
| `cfo_valid` | 入 | 1 | `cfo_valid` |
| `cfo_ready` | 出 | 1 | `cfo_ready` |
| `cfo_record` | 入 | 96 | `cfo_value_hz & cfo_quality & cfo_status & cfo_frame_id` |
| `fine_valid` | 入 | 1 | `fine_valid` |
| `fine_ready` | 出 | 1 | `fine_ready` |
| `fine_record` | 入 | 96 | `fine_start_samples & fine_quality & fine_status & fine_frame_id` |
| `m_valid` | 出 | 1 | `m_valid` |
| `m_ready` | 入 | 1 | `m_ready` |
| `m_record` | 出 | 225 | `core_m_record` |
| `m_reset` | 出 | 1 | `m_reset` |
| `m_fault` | 出 | 1 | `m_fault` |
| `fault` | 出 | 1 | `fault` |
| `error_code125` | 出 | 8 | `error_code125` |
| `error_code150` | 出 | 8 | `error_code150` |
| `diagnostic` | 出 | 256 | `core_diagnostic` |
| `residual_point_valid` | 出 | 1 | `residual_point_valid` |
| `residual_point_record` | 出 | 129 | `core_residual_point_record` |
| `debug125` | 出 | 512 | `core_debug125` |
| `debug150` | 出 | 512 | `core_debug150` |
| `debug_e1_valid` | 出 | 1 | `debug_e1_valid` |
| `debug_e1_data` | 出 | 128 | `core_debug_e1_data` |
| `debug_e1_beat` | 出 | 32 | `debug_e1_beat` |
| `debug_e1_last` | 出 | 1 | `debug_e1_last` |

## 3. Wrapper全部102端口

输入值由用户Target适配逻辑设置；Host通过用户创建的控件、寄存器或配置消息送给适配逻辑，本包没有固定寄存器地址。表中的预期值只供比较，不是要求驱动输出端口。输出data在valid无效时不保证有意义。

| 名称 | 方向/位宽 | 数值解释 | 所属时钟 | 用途 | 本用例设值/预期 | 有效时刻 | 复位或空闲 |
|---|---|---|---|---|---|---|---|
| `clk125` | 入 / 1 | Clock | Clock | 外部连续时钟 125 MHz | 125 MHz | 复位前稳定并持续运行 | 不得使用布尔软件翻转代替时钟 |
| `clk150` | 入 / 1 | Clock | Clock | 外部连续时钟 150 MHz | 150 MHz | 复位前稳定并持续运行 | 不得使用布尔软件翻转代替时钟 |
| `clk500` | 入 / 1 | Clock | Clock | 外部连续时钟 500 MHz | 500 MHz | 复位前稳定并持续运行 | 不得使用布尔软件翻转代替时钟 |
| `reset_request` | 入 / 1 | Boolean | 异步请求→各域内部同步释放 | 高有效总复位 | 1 | 稳定时钟后保持高；释放后等各域就绪 | 开机/异常恢复=1；运行=0 |
| `abort125` | 入 / 1 | Boolean | 125 MHz | 取消，触发粘滞故障 | 0 | 125 MHz同步；停止后必须总复位恢复 | 正常=0 |
| `s_valid` | 入 / 1 | Boolean | 125 MHz | 原始数据有效 | 0 | 与ready同拍为1时接收；被阻塞时保持有效及全部字段 | 复位/空闲=0 |
| `s_ready` | 出 / 1 | Boolean | 125 MHz | 原始数据可接收 | 由核心产生 | 与valid同拍解释 | 复位期间0；不能固定为1 |
| `frame_valid` | 入 / 1 | Boolean | 125 MHz | 帧描述符有效 | 0 | 与ready同拍为1时接收；被阻塞时保持有效及全部字段 | 复位/空闲=0 |
| `frame_ready` | 出 / 1 | Boolean | 125 MHz | 帧描述符可接收 | 由核心产生 | 与valid同拍解释 | 复位期间0；不能固定为1 |
| `cfo_valid` | 入 / 1 | Boolean | 125 MHz | 粗CFO记录有效 | 0 | 与ready同拍为1时接收；被阻塞时保持有效及全部字段 | 复位/空闲=0 |
| `cfo_ready` | 出 / 1 | Boolean | 125 MHz | 粗CFO记录可接收 | 由核心产生 | 与valid同拍解释 | 复位期间0；不能固定为1 |
| `fine_valid` | 入 / 1 | Boolean | 125 MHz | 精定时记录有效 | 0 | 与ready同拍为1时接收；被阻塞时保持有效及全部字段 | 复位/空闲=0 |
| `fine_ready` | 出 / 1 | Boolean | 125 MHz | 精定时记录可接收 | 由核心产生 | 与valid同拍解释 | 复位期间0；不能固定为1 |
| `s_iq0` | 入 / 32 | U32容器；两个I16 Q1.15 | 125 MHz | 第4b+0个复数点，Q在高16位I在低16位 | raw_input_u32le.bin | s_valid && s_ready | valid=0时可置0 |
| `s_iq1` | 入 / 32 | U32容器；两个I16 Q1.15 | 125 MHz | 第4b+1个复数点，Q在高16位I在低16位 | raw_input_u32le.bin | s_valid && s_ready | valid=0时可置0 |
| `s_iq2` | 入 / 32 | U32容器；两个I16 Q1.15 | 125 MHz | 第4b+2个复数点，Q在高16位I在低16位 | raw_input_u32le.bin | s_valid && s_ready | valid=0时可置0 |
| `s_iq3` | 入 / 32 | U32容器；两个I16 Q1.15 | 125 MHz | 第4b+3个复数点，Q在高16位I在低16位 | raw_input_u32le.bin | s_valid && s_ready | valid=0时可置0 |
| `s_frame_id` | 入 / 32 | U32 | 125 MHz | 本拍所属帧号 | 6001 | s_valid && s_ready | 6001 |
| `s_absolute_index` | 入 / 32 | I32二补码，单位复数样点 | 125 MHz | 本拍第一个样点相对采样坐标 | -172+4*b | s_valid && s_ready | 起点-172；只在接受时加4 |
| `s_lane_valid` | 入 / 8 | U8 | 125 MHz | 低4位通道掩码，高4位必须0 | 0x0F | s_valid && s_ready | 0x0F |
| `frame_id` | 入 / 32 | U32 | 125 MHz | 描述符帧号 | 6001 | frame_valid && frame_ready | 6001 |
| `frame_generation` | 入 / 32 | U32 | 125 MHz | 本次生成编号 | 1 | frame_valid && frame_ready | 1 |
| `frame_raw_first_word_lo` | 入 / 32 | U32 | 125 MHz | 内部接收流128位拍地址低32位；不是DDR地址 | 0 | frame_valid && frame_ready | 0 |
| `frame_raw_first_word_hi` | 入 / 32 | U32 | 125 MHz | 内部拍地址高32位 | 0 | frame_valid && frame_ready | 0 |
| `frame_nominal_absolute` | 入 / 32 | I32二补码，样点 | 125 MHz | 名义帧原点采样坐标 | 0 | frame_valid && frame_ready | 0 |
| `frame_q0_q28` | 入 / 32 | U32，低28位Q0.28 | 125 MHz | 初始小数相位；高4位必须0 | 0 | frame_valid && frame_ready | 0 |
| `cfo_value_hz` | 入 / 32 | I32二补码，Hz | 125 MHz | 外部粗CFO估计 | 100000 | cfo_valid && cfo_ready | 100000 |
| `cfo_quality` | 入 / 16 | U16 | 125 MHz | 质量字段 | 0 | cfo_valid && cfo_ready | 0 |
| `cfo_status` | 入 / 16 | U16 | 125 MHz | 类型/有效状态字段 | 0x2800 | cfo_valid && cfo_ready | 0x2800 |
| `cfo_frame_id` | 入 / 32 | U32 | 125 MHz | 所属帧号 | 6001 | cfo_valid && cfo_ready | 6001 |
| `fine_start_samples` | 入 / 32 | I32二补码，样点 | 125 MHz | 外部精定时帧起点 | 0 | fine_valid && fine_ready | 0 |
| `fine_quality` | 入 / 16 | U16 | 125 MHz | 质量字段 | 0 | fine_valid && fine_ready | 0 |
| `fine_status` | 入 / 16 | U16 | 125 MHz | 类型/有效状态字段 | 0x3800 | fine_valid && fine_ready | 0x3800 |
| `fine_frame_id` | 入 / 32 | U32 | 125 MHz | 所属帧号 | 6001 | fine_valid && fine_ready | 6001 |
| `m_valid` | 出 / 1 | Boolean | 150 MHz | 最终输出有效 | 核心产生 | 仅在150 MHz域采样/驱动 | 复位时m_ready=0；其它由核心产生 |
| `m_ready` | 入 / 1 | Boolean | 150 MHz | 接收端有容量 | 连续接收路径就绪时1 | 仅在150 MHz域采样/驱动 | 复位时m_ready=0；其它由核心产生 |
| `m_reset` | 出 / 1 | Boolean | 150 MHz | 150 MHz域内部复位状态 | 运行时0 | 仅在150 MHz域采样/驱动 | 复位时m_ready=0；其它由核心产生 |
| `m_fault` | 出 / 1 | Boolean | 150 MHz | 150 MHz域故障 | 成功时0 | 仅在150 MHz域采样/驱动 | 复位时m_ready=0；其它由核心产生 |
| `m_iq0` | 出 / 32 | U32容器；两个I16 Q1.15 | 150 MHz | 输出第4b+0点 | expected_output_iq_u32le.bin | m_valid && m_ready | 无有效数据时不解释 |
| `m_iq1` | 出 / 32 | U32容器；两个I16 Q1.15 | 150 MHz | 输出第4b+1点 | expected_output_iq_u32le.bin | m_valid && m_ready | 无有效数据时不解释 |
| `m_iq2` | 出 / 32 | U32容器；两个I16 Q1.15 | 150 MHz | 输出第4b+2点 | expected_output_iq_u32le.bin | m_valid && m_ready | 无有效数据时不解释 |
| `m_iq3` | 出 / 32 | U32容器；两个I16 Q1.15 | 150 MHz | 输出第4b+3点 | expected_output_iq_u32le.bin | m_valid && m_ready | 无有效数据时不解释 |
| `m_frame_id` | 出 / 32 | U32位模式 | 150 MHz | 输出帧号 | 6001 | m_valid && m_ready | 见有效条件；无独立Wrapper复位逻辑 |
| `m_generation` | 出 / 32 | U32位模式 | 150 MHz | 输出生成编号 | 1 | m_valid && m_ready | 见有效条件；无独立Wrapper复位逻辑 |
| `m_beat` | 出 / 32 | U32位模式 | 150 MHz | 输出拍号 | 0..334079 | m_valid && m_ready | 见有效条件；无独立Wrapper复位逻辑 |
| `m_last` | 出 / 1 | Boolean | 150 MHz | 名义帧最后一拍 | 仅拍334079为1 | m_valid && m_ready | 见有效条件；无独立Wrapper复位逻辑 |
| `fault` | 出 / 1 | Boolean | 125 MHz | 控制域综合故障 | 成功时0 | 125 MHz采样 | 复位期间0 |
| `error_code125` | 出 / 8 | U8 | 125 MHz | 该域第一个错误码 | 成功时0 | 所在域采样；粘滞直到复位 | 复位=0 |
| `error_code150` | 出 / 8 | U8 | 150 MHz | 该域第一个错误码 | 成功时0 | 所在域采样；粘滞直到复位 | 复位=0 |
| `diag_w00` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | diagnostic[31:0]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `diag_w01` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | diagnostic[63:32]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `diag_w02` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | diagnostic[95:64]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `diag_w03` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | diagnostic[127:96]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `diag_w04` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | diagnostic[159:128]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `diag_w05` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | diagnostic[191:160]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `diag_w06` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | diagnostic[223:192]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `diag_w07` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | diagnostic[255:224]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w00` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[31:0]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w01` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[63:32]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w02` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[95:64]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w03` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[127:96]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w04` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[159:128]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w05` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[191:160]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w06` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[223:192]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w07` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[255:224]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w08` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[287:256]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w09` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[319:288]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w10` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[351:320]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w11` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[383:352]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w12` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[415:384]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w13` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[447:416]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w14` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[479:448]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug125_w15` | 出 / 32 | U32位模式；部分字段为I32 | 125 MHz | debug125[511:480]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w00` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[31:0]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w01` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[63:32]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w02` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[95:64]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w03` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[127:96]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w04` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[159:128]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w05` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[191:160]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w06` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[223:192]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w07` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[255:224]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w08` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[287:256]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w09` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[319:288]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w10` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[351:320]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w11` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[383:352]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w12` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[415:384]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w13` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[447:416]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w14` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[479:448]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `debug150_w15` | 出 / 32 | U32位模式；部分字段为I32 | 150 MHz | debug150[511:480]；逐字释义见调试表 | 见调试表 | 所在域快照；跨域整体握手后读 | 计数复位清零；状态按表 |
| `residual_point_valid` | 出 / 1 | Boolean | 125 MHz | T09点记录观察脉冲 | 共74次 | 每个高电平周期捕获整条point；没有ready | 复位/空闲无事件 |
| `point_w0` | 出 / 32 | U32原始位模式 | 125 MHz | point记录第0个低位优先U32字；w4仅bit0有定义 | expected_points_u32le.bin | residual_point_valid=1 | 无valid不解释 |
| `point_w1` | 出 / 32 | U32原始位模式 | 125 MHz | point记录第1个低位优先U32字；w4仅bit0有定义 | expected_points_u32le.bin | residual_point_valid=1 | 无valid不解释 |
| `point_w2` | 出 / 32 | U32原始位模式 | 125 MHz | point记录第2个低位优先U32字；w4仅bit0有定义 | expected_points_u32le.bin | residual_point_valid=1 | 无valid不解释 |
| `point_w3` | 出 / 32 | U32原始位模式 | 125 MHz | point记录第3个低位优先U32字；w4仅bit0有定义 | expected_points_u32le.bin | residual_point_valid=1 | 无valid不解释 |
| `point_w4` | 出 / 32 | U32原始位模式 | 125 MHz | point记录第4个低位优先U32字；w4仅bit0有定义 | expected_points_u32le.bin | residual_point_valid=1 | 无valid不解释 |
| `debug_e1_valid` | 出 / 1 | Boolean | 150 MHz | E1已接受数据的观察脉冲，无ready | 共334098拍；末拍334097 | debug_e1_valid=1 | 无valid不解释 |
| `debug_e1_beat` | 出 / 32 | U32 | 150 MHz | E1拍号0..334097 | 共334098拍；末拍334097 | debug_e1_valid=1 | 无valid不解释 |
| `debug_e1_last` | 出 / 1 | Boolean | 150 MHz | 仅E1末拍为1 | 共334098拍；末拍334097 | debug_e1_valid=1 | 无valid不解释 |
| `debug_e1_iq0` | 出 / 32 | U32容器；两个I16 Q1.15 | 150 MHz | E1观察第4b+0点 | expected_e1_iq_u32le.bin | debug_e1_valid=1；不能施加背压 | 见有效条件；无独立Wrapper复位逻辑 |
| `debug_e1_iq1` | 出 / 32 | U32容器；两个I16 Q1.15 | 150 MHz | E1观察第4b+1点 | expected_e1_iq_u32le.bin | debug_e1_valid=1；不能施加背压 | 见有效条件；无独立Wrapper复位逻辑 |
| `debug_e1_iq2` | 出 / 32 | U32容器；两个I16 Q1.15 | 150 MHz | E1观察第4b+2点 | expected_e1_iq_u32le.bin | debug_e1_valid=1；不能施加背压 | 见有效条件；无独立Wrapper复位逻辑 |
| `debug_e1_iq3` | 出 / 32 | U32容器；两个I16 Q1.15 | 150 MHz | E1观察第4b+3点 | expected_e1_iq_u32le.bin | debug_e1_valid=1；不能施加背压 | 见有效条件；无独立Wrapper复位逻辑 |

## 4. 打包位段与地址

| 核心记录 | 从高到低的字段 |
|---|---|
| frame_record[187:0] | [187:156]frame_id；[155:124]generation；[123:60]raw_first_word；[59:28]nominal_absolute；[27:0]q0Q28 |
| cfo/fine_record[95:0] | [95:64]有符号值；[63:48]quality；[47:32]status；[31:0]frame_id |
| m_record[224:0] | [224:193]frame；[192:161]generation；[160:129]beat；[128]last；[127:0]IQ |
| s_data / IQ[127:0] | [31:0]最早复数点；其低16位I、高16位Q；之后每32位一个点 |
| residual_point_record[128:0] | [128:97]frame；[96:65]generation；[64:58]slot；[57:47]peak bin；[46:29]有符号delta-bin Q16；[28:5]有符号delay Q16；[4:1]quality flags；[0]point valid |

s_absolute_index是本拍第一个样点坐标，从−172开始，每次真正接受后增加4。frame_nominal_absolute=0、fine_start_samples=0，二者之差是核心用于后续提取的定时偏移；当前允许范围检查为−101至101样点。

frame_raw_first_word是T10内部原始接收流的128位拍编号，复位后第一拍地址为0。本次两部分均设0。外部DDR基地址由用户DDR适配器另行选择，不能填入这个字段。frame_q0_q28只用低28位；s_lane_valid只用低4位，分别要求高4位清零，通道掩码为0x0F。

point_w0是记录最低32位，point_w3是[127:96]，point_w4只有bit0对应记录bit128，其余31位补零。delta和delay要分别按18位、24位有符号二补码扩展，再除以65536；不能先当U32除法而丢失负号。

## 5. 调试字的具体含义

所有wNN均是原总线[32*NN+31:32*NN]。只读观察没有背压能力；跨域读多个字时不能逐位打两级寄存器后当成同一时刻。应在原域整体锁存，用请求/应答跨域传递；稳定快照后再让Host读取。Wrapper没有实现这个快照控制器。

| debug125字 | 含义 | 本例结束时的重要预期 |
|---|---|---|
| w00 | 原始接受拍数 | 334215 |
| w01 | bit0见到T06结果，bit1见到T09结果，bit2 T06halt，bit3 T09busy，bit4 fault | 结束稳定后低5位=3 |
| w02 | 第一次估计，有符号Q18 ppm | −39303835；U32模式0xFDA84565 |
| w03 | 高16位quality、低16位status | status=0x4800 |
| w04 | 第一次估计帧号 | 6001 |
| w05 | 第二次残余估计，有符号Q18 ppm | −12945 |
| w06 | 第二次步长Q28 | 268435443 |
| w07 / w08 | 第二次估计帧号 / generation | 6001 / 1 |
| w09 | T06 elapsed周期数 | 诊断用，非跨平台固定延迟门槛 |
| w10 | 低13位FFT输入计数，[28:16]FFT输出计数 | 各4096 |
| w11 | 低13位观测计数，[28:16]权重计数 | 各6560 |
| w12 | T09结果原始[95:64]；[31:25]总槽数、[24:18]有效槽数、[17:6]质量字段，[5:0]ppm编码的高6位 | 两个槽数各74；不要把整字当ppm |
| w13 / w14 | 点记录数 / 窗口请求数 | 各74 |
| w15 | [7:0]error_code125；[15:8]T06错误阶段；[21:16]T09结果最低6位（bit16为结果有效） | 低16位0；其它按T09结果解释 |

| debug150字 | 含义 | 本例结束时的重要预期 |
|---|---|---|
| w00 / w01 / w02 | E1 / E2 / 顶层接受拍数 | 334098 / 334080 / 334080 |
| w03 / w04 | E1 / E2步长Q28 | 268395209 / 268435443 |
| w05 / w06 | E1 / E2 processing cycles | 实际记录，不作为新增固定周期门槛 |
| w07 | [7:0]raw、[15:8]E1、[23:16]E2、[31:24]output-buffer错误码 | 0 |
| w08 | [7:0]first_error150、[15:8]bank0错误、[23:16]bank1错误 | 0 |
| w09 / w10 | raw-ring / output-buffer高水位 | 单位128位拍 |
| w11 | [1:0]E1状态、[3:2]E2状态、[5:4]窗口状态、[7:6]两bank committed、bit8 halted | 等三状态均0且halted=0后锁存；bank状态不冒充错误 |
| w12 | raw_written低32位 | 复位后单帧为334215 |
| w13 / w14 | 两个中间bank读取消费计数 | 诊断值；含T09及E2读取 |
| w15 | 输出buffer当前占用拍数 | 排空后0 |

| diagnostic拆分字 | 含义（全部150 MHz域） |
|---|---|
| diag_w00 / w01 | bank0 / bank1写停顿周期计数 |
| diag_w02 / w03 | E1 / E2处理周期数 |
| diag_w04 / w05 | bank0 / bank1未完成读取数高水位 |
| diag_w06 / w07 | 输出buffer / 原始ring占用高水位，单位128位拍 |

## 6. 错误定位

| error_code125 | 含义 |
|---:|---|
| 1 | abort125触发取消 |
| 2 | 描述符或fine绑定FIFO错误 |
| 3 | 已接受数据的lane_valid不是0xF |
| 4 | 后续描述符帧号没有严格递增 |
| 5 | 描述符、T06结果、fine结果帧号不一致 |
| 6 | T06/fine状态或定时偏移范围无效 |
| 7 | T06 halted；再看debug125_w15[15:8] |

| error_code150 | 含义 |
|---:|---|
| 1 | 内部CDC FIFO错误 |
| 2 / 3 / 4 | 原始ring / 中间bank / 输出buffer故障 |
| 5 / 6 | E1 / E2失败或halt |
| 7 | T09窗口请求几何或bank匹配错误 |
| 8 | 残余估计结果无效或bank匹配错误 |
| 9 | 同一bank的窗口/E2读调度冲突 |
| 10 | 原始窗口已退休或地址加法溢出 |

首次故障后先锁存两域状态、输入接受拍号与DDR/DMA计数，再停止新输入并执行复位。不要先清零错误再询问发生了什么。故障会阻止数据推进；不能仅等待最后一拍而不监测fault。
