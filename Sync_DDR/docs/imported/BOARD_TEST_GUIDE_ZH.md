# 独立DDR测试VI：先证明数据正确，再测四点/拍

本指南配套本目录的两个纯VHDL CLIP。测试VI暂时不放同步前端算法，先把“Host→DDR→读回”单独做通。这样出现错误时能够定位存储通路，不会把候选检测算法的行为混进来。

## 1. 新VI最终只需两个SCTL

| SCTL | 建议时钟 | NI节点 | VHDL接管什么 | 留在LabVIEW的数据 |
|---|---|---|---|---|
| Write | 沿用当前截图的150 MHz | H2T.Read、DDR.Write、DRAM Ready | 参数检查、接收/写入状态、组号地址、重复装载、计数 | 40点Pack_Array；Replace；两个Select |
| Read | 125 MHz | DDR.Request、DDR.Retrieve、预取FIFO.Write/Read、可选T2H.Write、DRAM Ready | 请求信用、预取、首块、换块、输出、排空、逐点比较和速率统计 | 40点Current_Array；两个Select；Array Subset |

读控制器已把原先“预取”和“播放器”的状态合在一个125 MHz控制模块中，所以独立测试VI不需要第三个SCTL，也不需要在LabVIEW搭状态Case。两核的时钟分别映射到所在SCTL的实际同源时钟；不能给读核接150 MHz却让它的NI节点放在125 MHz循环。

写和读**分阶段执行**：写完以后才启动读；本测试没有允许一边覆盖DDR一边读取旧波形。不同循环不要拿未经同步的单拍脉冲互相启动，使用Host看到持久DONE后发送下一阶段命令。

## 2. Project Explorer里建立资源

在FPGA Target下面创建VI，确保CLIP/FIFO/Memory引用都有Target上下文。

| 资源 | 配置 |
|---|---|
| FIFO_H2T | Host to Target DMA；每元素Unsigned FXP32/整数32或U32；FPGA每次读4元素；接口Handshaking；设备端深度先4096，不设成150万 |
| DDR_Waveform | 使用DDR1280原生Memory；每元素40个U32的cluster；申请2048元素；不是2048个样本 |
| FIFO_DDR_Prefetch | Target-scoped FIFO；元素类型与DDR.Data相同的40-U32 cluster；深度**256**，实际容量至少256；每次读/写1个cluster；Handshaking；Block Memory、Slice Fabric控制 |
| FIFO_T2H_Test | Target to Host DMA；每元素同H2T的32bit类型；FPGA每次写4元素；Handshaking；设备端深度先4096；只在Host全量读回模式使用 |

读核的信用上限固定256块，启动前等待min(128,DDR_Word_Count)块已经送入预取FIFO。不要把预取FIFO容量改成64，否则硬件信用与容量不匹配。

Host端FIFO.Configure的Requested Depth设置主机缓冲，例如65536元素；它与FPGA设备端深度是两件事。不要为了存整段波形把FPGA DMA FIFO申请成上百万元素，整段波形已经由DDR保存。

## 3. 导入两个VHDL CLIP

分别用rtl/ddr_upload_ctrl.vhd和rtl/ddr_read_ctrl.vhd建立两个用户定义CLIP。每个只有这一份源文件，entity名与文件名一致。操作细节见[上传指南第2节](UPLOAD_GUIDE_ZH.md#2-手工导入只选一个-vhdl-文件)。

共同要求：

- clk配置为真正的CLIP输入时钟，映射到相应SCTL的时钟。
- 所有数据端口SCTL Required，绑定该时钟域；控制路径不添加同步寄存器。U64指标用64位无符号类型/Unsigned FXP64整数64。
- 完成属性配置后再放新的I/O节点，避免复用过期节点。
- 同一个CLIP可用多只I/O节点分组读写。**输出许可、写入节点反馈、再读取依赖反馈的输出，要分开放**，不把所有端口挤在一个混合大节点。
- NI Request/Write的原始Ready for Input在LabVIEW各延迟一次，Feedback初值False；控制器输入名以_ready_now结尾，不能直连原始Ready，也不能再延迟两次。
- reset高有效，仅复位本控制器及数组；不能与算法reset_n混用。

## 4. 写SCTL怎么接

按[上传指南第4节](UPLOAD_GUIDE_ZH.md#4-labview剩下的接线没有状态case)逐条接。仅一个Pack_Array移位寄存器；不用再搭Group_Index/Load_State等五个寄存器和右下角Case。

本轮新增写侧U64监视输出：

| 输出 | 它在测什么 |
|---|---|
| load_cycles | 接受Load后，到最终块提交为止的全部时钟；包含Host尚未开始送数的等待 |
| data_window_cycles | 第一组四点真正读到后，到最终块提交的时钟；包含中间停顿 |
| receive_cycles | 成功接收四点的拍数，最终应为Sample_Count/4 |
| write_cycles | 提交DDR块的拍数，最终应为DDR_Word_Count |
| fifo_empty_cycles | 已允许读H2T但本拍没有数据 |
| ddr_stall_cycles | 已打好一块但DDR暂不能接收 |
| pause_cycles | 上传任务中run_enable=False的周期 |

指标只需连指示器供Host读取，不参与控制反馈。正常DONE之后指标停止增长。

## 5. 读SCTL怎么接

完整端口见[READ_PORTS.md](READ_PORTS.md)，下面是搭建次序。它接同一个DDR_Waveform，地址单位是一个40点块。

### A. 先接DDR请求和返回

1. 控制器request_valid → DDR.Request.Input Valid。
2. request_address → DDR.Request.Address。
3. DDR.Request.Ready for Input → Feedback(False初值) → ddr_request_ready_now。
4. 控制器retrieve_ready → DDR.Retrieve.Ready for Output。
5. DDR.Retrieve.Output Valid → 控制器ddr_retrieve_valid。
6. DDR.Retrieve.Data → FIFO_DDR_Prefetch.Write.Element。
7. 控制器prefetch_write_valid → FIFO_DDR_Prefetch.Write.Input Valid。
8. FIFO.Write.Ready for Input → Feedback(False初值) → prefetch_write_ready_now。

第7步必须用控制器输出。正常时它传递有效返回；Abort排空期间它会把有效写入关掉，让旧返回直接丢弃。不要始终把Retrieve.Output Valid直接接FIFO.Write.Input Valid。

### B. 再接预取FIFO读取和Current_Array

1. prefetch_read_enable → FIFO_DDR_Prefetch.Read.Ready for Output。
2. FIFO.Read.Output Valid → 控制器prefetch_read_valid。
3. FIFO.Read.Element的40-U32 cluster → Cluster To Array，得到40点Fetched_Array。
4. 放一个Current_Array移位寄存器，初值固定40个U32零。
5. Select一：s=current_load；t=Fetched_Array；f=左Current_Array。
6. Select二：s=current_clear；t=固定40个U32零；f=Select一输出。
7. Select二输出 → 右Current_Array。

不要把Select输出拿去作为当前拍的输出样本；当前拍始终从**左Current_Array**取数，换块的时钟沿之后才使用刚取来的新数组。

### C. 把40点拆成每拍4点

放Array Subset：array=左Current_Array，index=stream_offset，length=常量4。长度固定4，输出是本拍四元素U32数组。

再放Index Array，从这个四元素数组取索引0、1、2、3，分别接控制器stream_word0、stream_word1、stream_word2、stream_word3。检查器比较的是这四条真实导线上的值，不能给这些输入接参考常量来冒充实际数据。

以上反馈I/O节点必须与读取prefetch_read_enable的节点分开；current_load又需在写入prefetch_read_valid的节点之后单独读取。这样避免LabVIEW图形数据流绕成环。

### D. 接两种输出模式，只需要Select和AND

建立Boolean控件Return_To_Host。运行一轮中保持不变。

| 端子 | 接线 |
|---|---|
| FIFO_T2H_Test.Write.Element | Array Subset得到的四元素数组；按FIFO元素类型转Unsigned FXP32/整数32（若需要） |
| T2H.Write.Ready for Input | Feedback(False初值)，输出叫T2H_Ready_Now |
| Select.s | Return_To_Host |
| Select.t | T2H_Ready_Now |
| Select.f | Boolean True |
| Select输出 | 控制器stream_ready |
| AND的两个输入 | Return_To_Host、控制器stream_fire |
| AND输出 | T2H.Write.Input Valid |

- Return_To_Host=False：数据仍送入硬件比较器，但不写T2H；下游永远能收，适合测DDR到四点接口的速率。
- Return_To_Host=True：每次接受四点才写T2H，满了就停住；适合把任意波形完整读回Host。此模式的速率会受PCIe和Host影响，不能直接把变慢归因于DDR。

## 6. Host面板和读取方式

Host控制区分Write和Read两组，例如W_Load、R_Read、W_Reset、R_Reset，避免名字相同接错核。读取以下指标作为一次运行的记录，最好保存CSV/JSON。

| 分组 | 建议显示 |
|---|---|
| 写入 | load_generation、load_busy、load_done、load_fault、fault_code、command_rejected、loaded_samples、ddr_write_address |
| 写入速度 | load_cycles、data_window_cycles、receive_cycles、write_cycles、fifo_empty_cycles、ddr_stall_cycles、pause_cycles |
| 读回 | read_generation、read_state、read_done、read_fault、fault_code、command_rejected、requested_words、returned_words、enqueued_words、popped_words、sent_samples |
| 正确性 | checked_samples、mismatch_count、first_error_index、first_error_expected、first_error_actual |
| 回放速度 | total_cycles、replay_cycles、transfer_cycles、no_data_cycles、sink_stall_cycles、pause_cycles |

错误首位置为零起始索引；只有mismatch_count>0时首错字段有意义。周期/状态指示器不是单拍事件计数：VHDL内一直累计，DONE后保持，因此Host即使每50ms读一次也不会错过事件。Host轮询频率不用于计算FPGA速率。

读取结果时先确认generation是刚启动这一轮，等DONE或FAULT，再一起读取指标；不要启动下一轮后才读上一轮的结果。正常DONE后数值稳定，不需要在Host跟踪125MHz信号。

## 7. 测试一：编号数据，检查全部样本并测500MS/s

### A. 生成两轮不同的数据

在MATLAB进入本包matlab目录，运行：

```matlab
generate_ddr_test('ddr_A', 60324, uint32(hex2dec('FFFFFFF0')));
generate_ddr_test('ddr_B', 60324, uint32(hex2dec('1A2B3C40')));
```

每个目录的input_iq_i16.csv仍是无表头两列：第一列I，第二列Q。合并时I占低16位、Q占高16位；把各自I16的位模式解释为U16后合并，不能用负整数直接做会符号扩展的加法。metadata.json给出Sample_Count、DDR_Word_Count和Pattern_Seed；expected_u32.csv只用于参考比较，不是要求你改变输入CSV格式。

硬件期望第n点为 `(Pattern_Seed+n) mod 2^32`，n从0开始。该模式会跨越低16位和32位边界，能暴露符号、位序、地址顺序等常见问题。

### B. 先上传A

1. 新启动FPGA测试VI。两核命令都False，run_enable=True，abort=False；先对两核reset=True，再False。
2. 确认DRAM Ready=True，所有输入/预取/输出FIFO干净。当前没有正在读DDR。
3. W_new_session_safe=True；N=60324、M=1509；W_Load先False再True。等待write的load_generation加1。
4. Host把A的60324点按既定IQ合并后写入H2T，等待load_done。
5. 必须看到loaded_samples=60324、ddr_write_address=1509、receive_cycles=15081、write_cycles=1509且无fault。

### C. 再读A并在FPGA内比较

1. Return_To_Host=False；pattern_check_enable=True；pattern_seed填A的metadata数值；读核N=60324、M=1509。
2. R_new_session_safe=True（写核DONE，读核尚未工作，预取FIFO为空）；R_Read先False再True。确认read_generation加1。
3. 等read_done，保存下表结果。

| 指标 | 本次要求 |
|---|---|
| requested_words、returned_words、enqueued_words、popped_words | 全部1509 |
| sent_samples、checked_samples | 都为60324 |
| mismatch_count | 0 |
| read_fault | False |
| transfer_cycles | 15081 |
| replay_cycles | 要达到连续四点/拍，应为15081 |
| no_data_cycles、sink_stall_cycles、pause_cycles | 要达到连续四点/拍，全部0 |

不能只看mismatch_count=0。还必须checked_samples=60324、sent_samples=60324和DONE，才能确认全部点都比较过。

### D. 不重新下载FPGA，上传并读B

等A完全读完，确认Host没有新写入、读核DONE、预取已空且计数相等，然后重新上传B，再设置B的pattern_seed读回。两个generation应各加1，指标从新一轮开始计数。

B使用不同内容，可以发现第二轮仍读取A旧数据的问题。不能同时运行写B和读A。这验证的是正常完成后的重复任务，不等同于任意异常中途都可直接重启。

## 8. 测试二：原始波形全部读回Host

1. 用真实I/Q波形上传；不需要编号格式。
2. 读核pattern_check_enable=False，Return_To_Host=True；其他长度/块数按真实波形设置。
3. Host在启动读回前就准备好T2H接收循环，或与启动并行；不要等FPGA读完以后才开始取60324点，否则T2H可能先满。
4. Host每次读min(4096,剩余点数)个32bit元素，直到累计N点；这是缓冲读取块大小，不要求每块加1ms延迟。按FIFO返回顺序拼接，不能每次覆盖掉之前数组。记录超时/错误，失败后不要把重复读取的数据当新数据拼接。
5. 将全部回读32bit值与发送前的合并数组逐点比较，长度和每个元素都必须相同。读回CSV用一列无符号32bit整数，不能用低精度显示文本导出而丢位。
6. 对编号A/B，可用 `analyze_ddr_readback('readback_A.csv','ddr_A/metadata.json')` 做精确比较；真实波形则比较原始发送数组。

此模式硬件checked_samples为0是预期现象，正确性证据来自Host完整逐点比较；不能沿用测试一的硬件比较判据。如果T2H满，sink_stall_cycles会增加，数据应保持正确，只是速率降低。

可选尾零检查：先按N=44、M=2上传编号数据，再把读核配置成N=80、M=2、关闭硬件编号比较、回传Host；期望前44点为真实数据、后36点为零。分析时 `analyze_ddr_readback(file,metadata,true)`。这次是查看DDR补齐区域，不是要求正常播放输出补零。

## 9. 速率怎么算，怎么区分问题

所有频率必须用实际配置且完成时序闭合的SCTL频率。125 MHz不是500 MS/s；每拍成功接收四个IQ复样本才对应500 MS/s。

```text
读回有效速率(MS/s) = sent_samples × Read_Clock_MHz / replay_cycles
回放时间(微秒)      = replay_cycles / Read_Clock_MHz
写入全程速率(MS/s) = loaded_samples × Write_Clock_MHz / load_cycles
写入数据窗口速率   = loaded_samples × Write_Clock_MHz / data_window_cycles
```

本例60324点在125 MHz下，15081拍=120.648微秒，速率500 MS/s。若replay_cycles=16000，速率就是471.28125 MS/s，不能因为循环设置125MHz就说已达500。

正常DONE时读侧应满足：

```text
replay_cycles = transfer_cycles + no_data_cycles + sink_stall_cycles + pause_cycles
sent_samples = 4 × transfer_cycles
```

| 现象 | 优先判断 |
|---|---|
| mismatch_count非0 | 位序/符号合并、数组索引、旧数据、写入或读回内容出错；看首错位置和两个值 |
| checked_samples少于N | 比较没有覆盖全部输出，或没有完成；零错误不能验收 |
| no_data_cycles非0 | 回放中Current无数据，DDR服务/预取补给未跟上；即使内容正确，也未做到连续4点/拍 |
| sink_stall_cycles非0 | 下游暂时不能收；Host回读模式可能被DMA/Host限制 |
| pause_cycles非0 | 用户主动暂停，不应归因于DDR |
| 写侧fifo_empty_cycles很高 | Host/DMA供数间歇，或总计数含了开始发送前的等待；同时看data_window_cycles |
| 写侧ddr_stall_cycles很高 | 已经拼好块但DDR不接收，需要核对Ready与服务压力 |

写侧保留单Pack结构，常规40点要“10拍接收+1拍提交”。150MHz无停顿时上限约545.45 MS/s，125MHz约454.55 MS/s。若要求**写侧也实测至少500**，150MHz只是必要的理论余量之一，最终data_window指标仍须满足门槛；Host过慢不能由控制器凭空补足。该限制与读侧四点/拍回放分开看。

`total_cycles`含预取/首块准备，用于观察启动成本；replay_cycles从首块已准备后的第一拍开始，包含中途停顿，包含最后四点被接受那拍，不含启动预取。

MATLAB可用analyze_ddr_counters.m读Host导出的JSON计算这些数值，字段名按脚本头部。脚本的“本次500MS/s”只描述这一段有限波形；不代表任何长度、任何DDR负载下都永不读空。

## 10. 中止、故障与下一次任务

- 正常完成：读侧全部请求、返回和FIFO块都用完；记录完结果后可直接发下一次合法命令。也可重复读同一段DDR而不重新上传。
- 读侧Abort：停止新请求与输出，进入DRAIN，继续收完已经发出的DDR响应并丢弃，排空预取FIFO；计数对齐后才进入FAULT，fault_code=3。DRAIN期间不要复位/重新开始，不要写新波形覆盖DDR。
- 进入Abort后的FAULT且requested=returned、enqueued=popped，表示读核管理的旧返回和预取FIFO已排空。若开启T2H，还需Host取走/丢弃已传出的旧结果，再声明new_session_safe。
- DRAM Ready丢失：fault_code=2；不能假设DDR还会归还所有旧请求。先恢复Target/Memory服务并确认外部资源干净，必要时重新运行测试VI，再允许rearm。
- 写侧Abort：先停止Host的H2T生产者并处理旧输入FIFO；写核不会自动替你删除旧样本。
- `reset`只清VHDL寄存器，不能取消NI已发的DDR请求或清空FIFO。不要把reset=True当万能的“新会话已干净”。

## 11. 验收记录必须分层

1. **源码/控制仿真**：两TB通过，证明所建握手模型下的控制、字序和计数；不证明NI属性设置正确。
2. **LabVIEW编译**：新VI成功编译、实际150/125 MHz时序通过；不等于数据正确。
3. **板上完整性**：A/B两轮全样本比较和可选Host完整回读通过。
4. **本次吞吐**：在内容正确前提下，记录真实周期数、全部停顿、输入长度，读侧500MS/s门槛满足；写侧单独计算。

以上四层都要有各自证据。当前状态以VALIDATION.md为准，不把尚未运行的测试写成已经通过。