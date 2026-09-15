# Host、DMA、DDR与T10：逐步测试说明

本文对应用户计划的LabVIEW 2026Q1 / PXIe-7903。DMA名称、DDR区和配置传输方式是**接线约定，由用户创建**，不是已完成的VI、寄存器地址或NI端点。先读[完整接口表](INTERFACE_ZH.md)。

## 1. 先确认文件格式

全部二进制文件无文件头、无数组维度前缀，按一维U32、小端字节序存储。一个U32代表一个复数点，低16位I、高16位Q，两者按有符号I16解释；归一化幅度为整数除以32768。

| 文件 | 用途 | U32元素数 | 字节数 |
|---|---|---:|---:|
| [raw_input_u32le.bin](../data/raw_input_u32le.bin) | 实际输入 | 1,336,860 | 5,347,440 |
| [expected_e1_iq_u32le.bin](../data/expected_e1_iq_u32le.bin) | 第一遍参考 | 1,336,392 | 5,345,568 |
| [expected_output_iq_u32le.bin](../data/expected_output_iq_u32le.bin) | 最终/E2参考 | 1,336,320 | 5,345,280 |
| [expected_points_u32le.bin](../data/expected_points_u32le.bin) | 每点5个U32，共74点 | 370 | 1,480 |

全部SHA-256、来源和前四个样点见[data_manifest.json](../data/data_manifest.json)。点记录的人类可读表见[expected_points.csv](../data/expected_points.csv)。参考文件只用于比较，不能送进RTL替代估计结果。

原始文件最前四个U32依次为FFA40DE7、FE4B04FE、E51021B9、E9E21B89。第一个点I=3559、Q=−92，最前4字节为E7 0D A4 FF。第一拍s_iq0至s_iq3按上述顺序连接，拼成128位显示值E9E21B89E51021B9FE4B04FEFFA40DE7。MEM高位在左的显示顺序不能当成Host数组顺序。

Host使用Read from Binary File，类型接U32，读取精确元素数，byte order选little-endian。保存读回时Write to Binary File也选little-endian，prepend array or string size设False。DMA元素本身是U32数值，文件字节序与总线位段顺序是两件事。

## 2. 先搭建离线装载与捕获路径

    Host U32数组 → 用户H2T DMA → 外部DDR输入区
                                   ↓ 125 MHz回放，每拍4个U32
                           t10_sfo_manual_wrapper
                                   ↓ 150 MHz按valid/ready接收
                              外部DDR结果区
                                   ↓ 用户T2H DMA按U32读回
                             Host保存文件并比较

DMA可分别命名H2T_RAW_U32、T2H_OUT_U32，但名称仅为示例。配置参数由用户建立的控件、寄存器或配置消息传给Target，在125 MHz域锁存，再按各记录valid/ready提交；Host不承担逐周期送数。

输入DDR至少5,347,440字节。按下文256位结果记录保存时，结果区至少10,690,560字节；可选E1记录另需5,345,568字节，点记录1,480字节。对齐、适配FIFO另计。T10原有片内原始ring、两个中间bank和输出buffer依然存在，外部DDR不会自动取代它们。

回放峰值128位×125 MHz=2.0 GB/s；最终IQ突发128位×150 MHz=2.4 GB/s；连元数据一起按256位保存时，捕获端峰值预算为4.8 GB/s。这是接口带宽计算，不是已测板级性能。必须按DDR控制器宽度、时钟、突发效率核算，并用适当拼宽和FIFO承接；一个每拍仅处理一个U32的节点不能接住每拍8个U32的记录。

建议先把输入完整装进DDR，再启动配置/回放；计算期间由Target的DDR或足够容量的存储接收全部结果，之后再经PCIe慢速读回。虽然有ready，核心含处理期限，不能假设任意长背压都合法，也不能让Host文件I/O停顿直接阻塞核心。

## 3. 本次必需输入值

完整端口见[接口说明](INTERFACE_ZH.md)，结构化输入表见[case6001_settings.json](../data/case6001_settings.json)。

| 输入 | 本例值 |
|---|---|
| clk125 / clk150 / clk500 | 外部连续125 / 150 / 500 MHz |
| reset_request / abort125 | 初始化复位1，释放后0；正常abort始终0 |
| frame_id / frame_generation | 6001 / 1 |
| frame_raw_first_word_hi / lo | 0 / 0，内部接收流拍地址，不是DDR地址 |
| frame_nominal_absolute / frame_q0_q28 | 0 / 0 |
| cfo_value_hz / quality / status / frame_id | 100000 / 0 / 0x2800 / 6001 |
| fine_start_samples / quality / status / frame_id | 0 / 0 / 0x3800 / 6001 |
| s_frame_id / s_lane_valid | 6001 / 0x0F |
| s_absolute_index | 第b个被接受拍为−172+4b |
| s_iq0..3 | raw数组第4b..4b+3个U32 |
| s/frame/cfo/fine_valid | 初始0，有待接收项时1，仅握手后前进 |
| m_ready | 初始化0，150 MHz接收端有容量时1；冻结测试台为持续1 |

输入场景为无噪声单径、工程SFO −150 ppm、CFO +100 kHz、精定时0。CFO、fine及描述符由外部提供；两次SFO估计由RTL自己完成，没有Host写入SFO正确答案的端口。

## 4. 完整操作顺序

1. **Host装载。** 检查raw长度与SHA，经H2T DMA装入DDR；Target确认已存1,336,860个U32。Host的DMA写成功不等于DDR装载完成，需要Target计数/应答。
2. **准备时钟、复位与结果空间。** 确保三路时钟稳定、平台发生器已锁定，配置结果DDR及可选观察存储区，清零适配器计数/overflow。所有输入valid=0、abort=0、m_ready=0。复现测试台，reset_request高至少80个125 MHz周期（640 ns），再释放并等待各域就绪。内部还有同步器、64周期保持及FIFO/IP复位，不能请求拉低后立即送数。
3. **帧描述符。** 在125 MHz域保持全部frame字段，置frame_valid=1，在frame_valid与frame_ready同一上升沿为1后，下一拍撤销valid；被阻塞时字段不变。
4. **粗CFO，再fine。** 按同样规则分别提交cfo、fine记录。结果接收端已准备好时，在150 MHz域允许m_ready=1。T06有65,024周期处理限制，因此提交fine之前应已经装完DDR，不能之后再等Host搬帧。
5. **raw回放。** DDR适配器准备好4个U32后置s_valid=1。仅s_valid&&s_ready时，输入队列出队、b加1、坐标加4。s_ready=0时保持当前4字、帧号、坐标、valid不变。共334215拍，最后b=334214，首点坐标1,336,684、末点1,336,687；最后拍被接受后撤销s_valid，不额外补零。
6. **同时捕获。** 150 MHz域仅m_valid&&m_ready保存结果并增加计数。125 MHz域每次residual_point_valid捕获point_w0..4；150 MHz域每次debug_e1_valid捕获E1四个IQ字（若启用）。两个观察流没有ready，捕获缓存不足必须记overflow，不能反压它们。
7. **完成并锁存。** 输出共334080拍，末拍m_beat=334079且m_last=1。接受末拍后继续时钟，等待E1/E2/window状态空闲、输出buffer占用0、无故障，再在150 MHz域锁存debug150。在125 MHz域确认已见两次估计、74请求/点，再锁存debug125。跨域传递整个稳定快照，不独立同步跳变中的多位总线。Wrapper没有实现这些平台快照控制器。
8. **读回。** Target捕获完成后经T2H DMA读回，Host按下面格式保存并比较。异常时先保存首错和计数，再复位。重复frame6001前完整复位，否则严格递增帧号检查会报错4。

一个150 MHz SCTL不能直接处理全部接口。125 MHz接口和150 MHz接口分别使用相应域，500 MHz由平台时钟网络送入FFT服务；不需要把整个LabVIEW程序放进500 MHz SCTL。CLIP I/O或适配器引入流水寄存时，valid/data/ready必须保持一致的协议时序，不能只延迟ready而不处理相应在途数据。

## 5. 统一的最终输出文件格式

这是**用户Target适配器需要构建的记录**，并非核心自带DMA协议。每拍8个U32、32字节：

| U32序号 | 内容 |
|---:|---|
| 0 | m_frame_id，6001 |
| 1 | m_generation，1 |
| 2 | m_beat，0..334079 |
| 3 | m_last，只允许0或1 |
| 4 / 5 / 6 / 7 | m_iq0 / m_iq1 / m_iq2 / m_iq3 |

Host应得到2,672,640个U32、10,690,560字节，例如out_records_u32le.bin。无数组头、时间戳或文本前缀。若内部用256位DDR字，最低32位是序号0，U32 DMA也按0至7发送。无valid或没有ready的周期不能保存占位或重复记录。

首条IQ四字为0117FDCA、16230603、187703AD、0F00E8FB。point文件每条point_w0至w4，共74条、1480字节；w4高31位必须0。E1文件按debug_e1_iq0至3保存，共334098拍，同时在Target检查debug_e1_beat连续、last只在末拍。

## 6. 用LabVIEW或附带工具比较

在LabVIEW拆出有符号I16的I/Q后，用I32做减法及绝对值，避免I16差值溢出。拍数、帧号、generation、beat和last必须正确；逐分量误差不超过1 LSB，已验RTL实际最大0 LSB。

[compare_capture.py](../tools/compare_capture.py)只使用Python标准库，读取保存文件，不访问硬件、不启动MATLAB或Vivado。在交付目录用本机已确认的Python执行：

    python tools/compare_capture.py --capture out_records_u32le.bin --report capture_review_01.json

提供全部可选观察和状态时：

    python tools/compare_capture.py --capture out_records_u32le.bin --e1 e1_iq_u32le.bin --points points_u32le.bin --status actual_status.json --report capture_review_02.json

报告用新文件名，不覆盖旧结果。actual_status.json按[空白模板](../data/capture_status_template.json)填入实际Target锁存值；null表示未取得，不能用参考答案填充。debug125/debug150按w00至w15存U32，负ppm编码也保存为二补码U32位模式。

比较器检查输出元信息、逐I/Q差及74个OUT有效窗口EVM。有E1、point、status文件才检查对应项，并明确列出未提供项。完整2048频点的参考差异EVM与时域能量比由Parseval等式等价，无需安装FFT库。OUT窗口起点25984+17920*slot；E1数组还加36点；各74窗口、2048点、门槛低于−45 dB，无增益或相位对齐。

返回码0表示提供文件的检查通过；1是数值/元信息/状态失败；2是文件/格式错误。CAPTURE_CHECKS_PASS不等于时序或持续吞吐通过。未捕获E1时不能声称已逐点比较板上E1结果。

## 7. 出错后先定位哪一层

| 现象 | 优先检查 |
|---|---|
| 第一拍完全不对 | 小端、数组头、I/Q位段、四点顺序 |
| 重复或丢拍 | DDR/FIFO是否只在valid&&ready出队，阻塞期间是否保持 |
| 运行一段后无输出 | fault、错误码、T06期限、输出容量、DDR停顿 |
| ppm显示巨大正数 | U32未重解释为I32；再除以2^18 |
| 输出正确但点/E1记录短 | 无ready观察接口的捕获溢出 |
| 原始窗口地址异常 | 是否把外部DDR地址填进raw_first_word |
| 第二次运行错误4 | 同帧号重复使用前没有复位 |

保存首次错误、最近输入/输出接受拍号、两域状态、DDR/DMA计数，再恢复；Host等待超时不能单独证明RTL错误。本例无背压仿真从零到排空为8.725104 ms，Host装载/读回时间另计，不要把桌面仿真约26小时当成FPGA处理时延。

用户仍需完成NI时钟选择及CDC、CLIP定义、DDR/DMA适配、捕获和状态快照、NI编译及板测。本包未实现这些平台逻辑。

参考：[NI外部IP导入](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA03q000000x0jiCAA&l=en-US)、[NI数组文件头](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z0000019PvJSAU&l=en-US)、[NI字节序说明](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z000000PAE9SAO&l=en-US)。
