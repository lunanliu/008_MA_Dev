# Sync_SFO：LabVIEW时钟配置与Host—FPGA最小实验闭环

2026-09-15。适用当前 `Sync_SFO.xpr` / `sync_sfo_top` / `sync_sfo_manual_wrapper`，默认输出150 MHz，PXIe-7903（xcvu11p-flgb2104-2-e）。依据当前源码、case6001交付资料、本机LabVIEW 2026的CLIP schema和NI官方帮助整理。下面是待用户搭建的VI设计与操作步骤；本说明不是已经生成、编译或板测通过的LabVIEW工程。具体驱动版本、项目基础时钟名称及DRAM节点宽度仍须在实际7903项目中确认。

## 1. 先固定最小实验的边界

目标：Host加载已有测试文件，FPGA独立处理一帧，Host读回并与参考文件比较。

    Host读文件 → H2T DMA → FPGA板载DRAM输入区
                                  ↓ 本地125 MHz回放
                              同步SFO CLIP
                                  ↓ 150 MHz捕获
    Host保存/显示 ← T2H DMA ← FPGA板载DRAM结果区

Host负责文件、按钮、显示；FPGA Target VI负责逐拍握手、回放和捕获。若显示电脑与PXI控制器是两台机器，可在显示电脑与控制器之间另加网络传输；控制器上的Host VI再通过NI-RIO/DMA访问7903。网络链路不负责产生CLIP时钟，也不承担逐拍握手。

第一轮使用本地已存好的case6001，无需先接同步前端或射频输入。输入装完、输出空间准备好以后，才启动算法。不能用Host逐个写前面板控件来代替原始IQ数据流。

## 2. 向导里的MMCM、派生时钟分别怎么填

MMCM是FPGA内部的专用时钟生成/管理电路。时钟端口数量与MMCM实例数量是两件不同的事。

| 页面/项目 | 当前SFO的设置 | 原因 |
|---|---|---|
| CLIP消耗的MMCM数量 | 0 | 当前核心及Wrapper只接收时钟，没有自行生成时钟 |
| CLIP消耗的DCM数量 | 0（若页面显示） | 当前没有DCM实例 |
| CLIP自己实例化的BUFG数量 | 当前自有源码为0；若导入的最终网表增加时钟缓冲，须按网表复核 | 不把平台给输入时钟配置的缓冲重复计入CLIP |
| clk125 / clk150 / clk500 | Signal Type=Clock，Direction=ToCLIP | 由LabVIEW/NI时钟网络提供给核心 |
| 频率/可接受范围 | 分别125 / 150 / 500 MHz；若填Min/Max，两者设同一要求值 | 保持当前核心配置，不自动改成近似频率 |
| CLIP向外提供时钟 | 无 | 当前Wrapper没有FromCLIP时钟端口 |
| Support Derived Clocks | 若指“允许从CLIP输出时钟继续派生”，不启用/不适用 | 当前CLIP没有输出时钟 |
| 时钟门控支持 | 不主动声明支持 | 本轮要求三路时钟连续；不能用停止SCTL或门控模拟暂停 |

本机NI官方schema的注释明确说明MMCM/DCM字段表示用户CLIP实际消耗的资源，见 `C:/Program Files/National Instruments/LabVIEW 2026/FPGA/CLIP/Schema/CLIPDeclaration.xsd` 第319行附近。平台派生时钟所消耗的MMCM由LabVIEW时钟配置处理，不能因为需要三路频率就把此处填3。

“LabVIEW项目创建派生时钟”需要使用；“允许从本CLIP输出时钟再派生”当前不需要。NI对后者要求额外的时钟就绪/有效接口，当前Wrapper没有这些输出时钟接口。[NI：Using CLIP Clocks](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/using-clip-clocks-fpga-module.html)

### 三路输入时钟的实际配置步骤

1. 在7903的FPGA Target项目中，找到实际可用、稳定的板载基础时钟。使用该目标支持的内部时钟；不能根据其他型号的截图假定其名字或频率，也不要把MGT参考时钟配置当成普通逻辑时钟配置。
2. 右击该基础时钟，选择 `New FPGA Derived Clock`，建立 `SFO_125`、`SFO_150`、`SFO_500` 三个项目时钟。已有正确频率的项目时钟可以复用。最终以工具显示的实际频率和合法性提示为准；不能只改时钟名称。
3. 若对话框用Multiplier/Divisor，频率关系为“输入频率×倍频数÷分频数”；可用的组合由目标和工具决定。无需手工承诺整个设计用了几个MMCM。若500 MHz不能生成或编译不通过，应保留错误并检查时钟方案与核心时序，不能随意降频冒充原配置。
4. 在CLIP向导中把三个时钟端口正确标成Clock/ToCLIP。完成CLIP实例后，右击该实例的Properties，在 `Clock Selections` 中连接：`clk125→SFO_125`、`clk150→SFO_150`、`clk500→SFO_500`。
5. 输入/控制SCTL的Timing Source也选择**同一个SFO_125项目时钟对象**；输出SCTL选择**同一个SFO_150对象**。仅频率相同但来源不同的时钟仍不能直接共用握手。
6. 500 MHz只供核心FFT服务。无需让Host通信、DDR管理或整个Target VI都跑500 MHz。

时钟属性只约束频率，实际时钟由专用硬件网络产生。普通Boolean常量、循环翻转、Wait函数均不能替代Clock绑定。现有独立XDC只声明三个根时钟；不要把其中针对顶层get_ports的约束原封不动当成NI嵌套层级的最终时钟约束。

操作来源：[NI：自定义SCTL频率](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA03q000000YIUMCA4&l=en-US)、[NI：CLIP项目与Clock Selections](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/adding-component-level-ip-to-a-project-fpga-module.html)。频率可配置与实现时序通过须分别确认。

## 3. CLIP的普通I/O设置

入口为 [Wrapper](../wrapper/sync_sfo_manual_wrapper.vhd)；102端口逐项类型见 [ports.csv](../wrapper/ports.csv)。算法核心综合top仍为sync_sfo_top。当前仅完成编译/展开及Wrapper语法，实际导入使用的核心网表仍需综合导出并核对依赖。

| 端口组 | 方向（相对CLIP） | Target放置位置 |
|---|---|---|
| frame/cfo/fine全部字段及valid | ToCLIP | 125 MHz SCTL |
| frame_ready、cfo_ready、fine_ready | FromCLIP | 同一个125 MHz SCTL |
| s_iq0..3、s_valid、s_frame_id、s_absolute_index、s_lane_valid | ToCLIP | 125 MHz SCTL |
| s_ready | FromCLIP | 同一个125 MHz SCTL |
| m_iq0..3、m_valid、m_frame_id、m_generation、m_beat、m_last | FromCLIP | 150 MHz SCTL |
| m_ready | ToCLIP | 同一个150 MHz SCTL |
| m_reset、m_fault、error_code150、diagnostic、debug150 | FromCLIP | 150 MHz采集/快照 |
| abort125、fault、error_code125、debug125、residual_point_valid/point_w0..4 | 对应原端口方向 | 125 MHz；abort正常为False |
| reset_request | ToCLIP Boolean数据，使用本文的手工复位方案 | 125 MHz控制状态机驱动；核心内部异步置位、各域同步释放 |

其中U32端口是位模式容器。s_absolute_index的负数先按I32计算，再保留原32位重解释为U32；不要用有范围限制的数值转换把负数变成0。

### 必须核对的I/O延迟

CLIP I/O默认可能加同步寄存器。本方案的valid/data/ready在**同一项目时钟域**逐拍握手，按NI方法将这些同域信号的附加同步级数设为0，并核查读、写方向的实际节点设置。不能只延迟ready，或让data和valid经过不同级数。若后续为了时序加入流水，需要完整缓冲/握手设计，不能只在某条线上加寄存器。[NI：CLIP与VI之间的数据传递](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/passing-data-between-component-level-ip-and-vis-fpga-module.html)

高速SCTL必须每周期推进握手。使用适用于SCTL的非阻塞FIFO/存储接口，检查数据有效、超时及就绪；若节点支持Timeout，快速循环内采用0并自行处理未就绪。文件、网络、等待整块DMA等阻塞操作留在Host或管理循环。不能让Target循环停住、valid仍为1，而CLIP继续接受同一拍。

跨域的命令和状态使用FIFO或整条快照握手；这一规则不允许把异步信号的同步器一概清零。数据类I/O的Required Clock Domain与所在SCTL一致；需要逐周期运行的流接口设为要求在SCTL中使用。

复位方案必须一致：本文让reset_request作为可写Boolean，由Target主动置高、保持和释放。如果在向导中将它定义成NI专用Reset信号，通常就由平台复位驱动，不能再按本文作为普通I/O写入。若要同时具备NI平台异步复位和用户手工复位，应另外设计并核查两者合并的NI外围层；当前Wrapper没有独立的第二个复位输入。

## 4. Target VI按四个职责搭建

以下模块名、DMA名和状态名称是新建VI时的建议，不是已经存在的VI文件。

### A. 装载/读回管理

在合适的管理时钟域中处理Host命令和DMA，配置两个U32 DMA FIFO：

- `H2T_RAW_U32`：Host→Target。
- `T2H_OUT_U32`：Target→Host。

先用NI的DMA和DRAM示例确定7903的实际节点与数据宽度，再加入SFO外围。FIFO深度设置不是“把整帧存进板载DDR”；真正输入区和输出区应建立DRAM存储及地址控制。

装载阶段，H2T读到的数据只有在有效且写存储被接受后才算已接收；有流水未提交的DDR写不能提前记为LoadDone。装载与计算分阶段，同一个存储端口的写/读所有权明确切换。可采用不同DRAM bank保存输入、结果，以降低计算期间读写争用；具体bank和节点接口按实际7903工程配置。

NI说明7903的DRAM节点可放在可用时钟域，并由平台插入相应CDC FIFO；这不免除用户处理请求、读响应、写接受和延迟的责任。[NI：PXIe-7903 DRAM Clocking](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA0VU0000009x8v0AA&l=en-US)

### B. 125 MHz：配置状态机与原始输入回放

用SCTL＋移位寄存器/反馈节点保存状态、输入拍号b和“当前待发送的四点”。核心并非普通函数调用；CLIP持续运行，Target通过I/O节点喂端口。

建议状态顺序：

    IDLE → LOAD → RESET → WAIT_READY → FRAME → CFO → FINE → REPLAY → DRAIN → DONE
                                                          任意错误 → ERROR

- LOAD必须完整落盘到板载存储并应答；接收端准备好、DDR读响应预取到FIFO后，才提交FINE。
- RESET中valid全部为0，reset_request高至少80个125 MHz周期；随后释放，等待域复位/FIFO就绪和配置ready。运行中时钟保持连续。
- FRAME、CFO、FINE各保持完整字段和valid，直到各自valid与ready同拍为1；只提交一次。
- 回放器持有完整4个U32及全部元信息。`s_valid=当前持有完整拍且处于回放阶段`。只有`s_valid && s_ready`才完成这拍并增加已接受计数b。
- DDR读取有延迟。DDR响应到达→进入预取FIFO/保持寄存器；核心接受→才释放当前保持拍。这两次“接受”是不同边界，分别计数。
- s_ready=0时，s_valid及当前四点、坐标、帧号保持；不能每循环无条件读下一个字或增加坐标。
- 输入结束后s_valid清0，不补额外样点。预取请求计数、DDR返回计数、核心已接受拍数分别保存，以便发现读多、丢数和重复。

### C. 150 MHz：最终结果捕获

另放一个SCTL，读取m_*全部端口，构造一条固定记录。此时m_ready取决于**本地接收缓冲确有可用容量**，不是Host正在读数据。

仅`m_valid && m_ready && !m_reset`的周期保存一次、计数加1。已承诺ready后必须接得住该拍；DDR暂时忙应由中间FIFO吸收。若ready通路增加延迟，须给在途记录留容量。

每条记录8个U32，按以下次序保存：

    frame_id, generation, beat, last, iq0, iq1, iq2, iq3

这表示逻辑上256位的原子捕获。不能在一个150 MHz循环中通过单元素U32存储口连续写8次，却假设仍可每周期接收一整拍。应按实际DRAM端口做多元素并行访问或更宽的拼包/FIFO，保证捕获端吞吐；具体宽度不能脱离驱动节点假定。

看到最后一拍不立即置Host可读完成：还要确认该拍已接受、捕获FIFO排空、DDR写提交完成，再发布CaptureDone和记录数。仅拍数相等仍须检查beat、last、frame、generation及fault。

### D. 状态、命令与可选观察

命令通过稳定负载＋请求/应答或命令FIFO送往相应域。第一轮可把case6001参数固定在125 MHz状态机内，Host只发Load、Run、Readback、Reset/Abort，先减少动态配置接口。

Host状态至少包含：工作状态、LoadDone/已提交U32数、已接受输入拍数、已接受输出拍数、CaptureDone、overflow、两域错误码、最近beat/last。新增的这些平台指标由Target自己实现；不是当前Wrapper已经具备的控制接口。

debug125与debug150分别在本域锁存整条稳定快照，再跨域回传。当前Wrapper不提供快照握手。`fault`总汇信号也不能用来省略各域错误源的同步采集。

74条residual_point是125 MHz无ready观察流；debug_e1是150 MHz无ready观察流。第一轮可先实现最终结果闭环，再增补这些观察；若启用，使用足够的本地记录缓存并报告溢出。未采集的观察项在报告中写“未验证”。

## 5. case6001的固定设值与容量

来源：[case设置](../handoff/T10_SFO_20260915_manual/data/case6001_settings.json)、[数据清单](../handoff/T10_SFO_20260915_manual/data/data_manifest.json)、[原Host测试说明](../handoff/T10_SFO_20260915_manual/docs/HOST_TEST_ZH.md)。旧文档的t10顶层名称以当前sync_sfo名称替换，数据和端口含义保持。

| 项目 | 本次固定值 |
|---|---|
| frame_id / generation | 6001 / 1 |
| raw_first_word高/低、nominal_absolute、q0 | 均0；raw_first_word不是DDR地址 |
| CFO value / quality / status / frame | 100000 / 0 / 0x2800 / 6001 |
| fine value / quality / status / frame | 0 / 0 / 0x3800 / 6001 |
| raw帧号、lane mask | 6001、0x0F |
| 第b个已接受输入拍的坐标 | −172 + 4b |
| 输入 | 1,336,860个U32＝334,215拍＝5,347,440字节 |
| 最终结果 | 334,080拍＝1,336,320个复数点 |
| 每拍含元信息的结果 | 8个U32，整帧10,690,560字节 |
| 可选E1 / point容量 | 5,345,568字节 / 1,480字节 |

输入区和结果区可分别规划8 MiB与16 MiB（工程预留建议，非既有地址表）；对齐和FIFO另计。不要把core已有的ring/bank简单算成可以随意复用的外部存储。

输入回放接口峰值2.0 GB/s；最终IQ峰值2.4 GB/s；采用8个U32记录时捕获端峰值4.8 GB/s。这里是按宽度×频率计算的**瞬时需求**，没有证明板级可持续达到。输入DDR读、结果DDR写及FIFO深度必须结合各阶段重叠核算。

核心含处理期限，首次估计器的65,024个125 MHz周期约为520.192 μs。它不是整个帧的结束时限，但意味着提交fine后不能再等Host慢慢装数据。valid/ready允许协议层停顿，不代表停顿可以任意长。首轮尽量复现已验用例的本地连续供数与接收条件。

## 6. Host VI逐步搭建

1. 放置Open FPGA VI Reference，选择**已成功编译的Target VI bitfile**及实际7903资源；根据项目运行方式调用Run，不能同时重复启动。核心综合/NI目标编译完成前不能直接运行SFO硬件试验。
2. 配置并启动H2T/T2H DMA FIFO，Host缓冲按分块传输设置。读取raw_input_u32le.bin：类型U32、小端、无数组维度前缀，要求1,336,860元素并核对清单SHA。
3. 下发LOAD命令；分块FIFO Write。每块记录实际成功写入数量并处理超时，避免把超时当作完整发送成功。Target同时消费DMA并写DDR；不能让Host等Target“装完”才允许Target开始消费。
4. Host等待Target报告LoadDone且已提交1,336,860个U32；DMA Write成功只证明传输层推进，不代替DDR完成。
5. 下发RUN，Target自动完成复位、frame/CFO/fine、回放与捕获。Host只低频轮询状态，不逐拍操作valid、ready或时钟。
6. 等CaptureDone且记录数334,080、无捕获溢出。下发READBACK，Target将结果存储按每条8个U32序列化到T2H。
7. Host分块FIFO Read，累计精确2,672,640个U32；读取与显示分开，先把数据存入数组/队列，再刷新图。不要用Elements Remaining短暂为0作为整帧完成条件。
8. 保存为小端无头二进制，关闭Write to Binary File的prepend array/string size。保留输入身份、构建身份、错误码和各接受计数。
9. 将每条记录的4个IQ字还原为复数样点，再绘图/比较。完成后停止FIFO并关闭引用；重复case6001前让Target完成一次总复位。

数据类型：一个U32的低16位是I，高16位是Q，均应按二补码I16解释，再转DBL并除以32768。显示的时间轴使用算法约定采样率（此例复数网格500 MS/s），不能用Host DMA读回速度或150 MHz输出时钟当成每点采样率。

## 7. 最先看哪些显示与验收结果

- 数量：输入334,215接受拍；输出334,080接受拍；Host最终读回2,672,640个U32。
- 元信息：frame=6001、generation=1、beat连续0…334079，只有最后一条last=1。
- 完整性：Target适配FIFO/DDR overflow=0、无重复/漏拍、各域错误码无故障。
- 波形：分窗口显示输出I/Q与参考I/Q叠加，另画I/Q差值；先用前4096点等小窗口观察，保存全量数据。
- 数值：先把I/Q升到I32再相减，逐分量绝对误差≤1 LSB；已有RTL完整帧基线实际最大0 LSB。无需只看“曲线差不多”。
- 频谱/EVM：先完成逐点和帧结构检查，再用原比较器检查74个有效窗口，保持原先低于−45 dB且不做额外增益/相位对齐的定义。

第一个输入U32为FFA40DE7，即I=3559、Q=−92；第一输入拍四字为FFA40DE7、FE4B04FE、E51021B9、E9E21B89。最终输出参考首拍IQ四字为0117FDCA、16230603、187703AD、0F00E8FB，可用于快速确认打包顺序。

现有 [compare_capture.py](../handoff/T10_SFO_20260915_manual/tools/compare_capture.py)读取捕获文件、核对元信息和IQ，不启动MATLAB/Vivado。结果报告写新文件；未提供E1/point/status时，只判定实际提供的数据范围。

## 8. 按顺序推进的三个小阶段

| 阶段 | 做什么 | 通过标志 |
|---|---|---|
| 1. DMA往返 | Target本地FIFO缓存后回送递增U32序列；先用4096等小数据集 | Host逐元素相等，数量一致，无overflow；这仅验证传输 |
| 2. 板载存储回放与捕获 | 装载已有raw，回读原样；再在125/150 MHz外围测试跨域与宽记录缓存 | 位模式/顺序正确，DDR提交计数正确，适配路径可承接计划突发；只回读相等不等于吞吐通过 |
| 3. 一帧SFO闭环 | 使用相同Target外壳接入当前CLIP，执行case6001 | 数量、帧身份、最后拍、故障和IQ误差均符合上节 |

每一阶段保留成功结果和第一处失败信息。阶段1、2不需要截短case6001送进估计器；阶段3使用完整冻结输入。当前已有FN01只是源码等价、工程打开、编译展开与Wrapper语法证据，尚无本说明所列NI编译或新板测PASS。

接下来实际需完成的工程工作就是：当前核心综合/网表准备，用户CLIP配置，Target的时钟/复位/DRAM与握手外壳，Host加载/显示，最后NI编译与上述板上验证。


