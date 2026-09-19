# 四段 DDR 控制器：设计与接线合同

2026-09-17。用户本轮明确授权补齐反向 RTL；唯一修改根 Sync_DDR，保持单任务，原配对停止。旧原生资源窗口已关闭，新测试必须重新冻结和申请。

## 编码前架构与自审

器件 xcvu11p-flgb2104-2-e；Vivado/XSim 2021.1。复样点按 I16/Q16 的原始位模式打包 U32，每批四点共128 bit，不做数值运算或精度变更。

| 文件 / entity | 数据方向 | 同源 SCTL 时钟 | 每次成功交接 |
|---|---|---|---|
| ddr_upload_ctrl.vhd | H2T DMA FIFO -> 输入 DDR | 150 MHz / 6.666667 ns | 4 U32 |
| ddr_read_ctrl.vhd | 输入 DDR -> Sync | 125 MHz / 8 ns | 4 U32 |
| ddr_capture_ctrl.vhd | Sync -> Target-Scoped FIFO -> 结果 DDR | 150 MHz / 6.666667 ns | 4 U32 |
| ddr_download_ctrl.vhd | 结果 DDR -> 预取 FIFO -> T2H DMA FIFO | 150 MHz / 6.666667 ns | 4 U32 |

四个文件是四个可选择的顶层。新增capture实例化upload内核，新增download实例化read内核，具名端口映射不增加寄存器或ready延迟；导入CLIP必须包含依赖的原内核文件。四实例拥有各自独立状态，不是把同一实例接到两路数据。原两核源文件与已通过测试保持不变。

数据通路仍由LabVIEW持有：两个写侧各有一个K-U32 Pack_Array；两个读侧各有一个K-U32 Current_Array及独立256块预取FIFO。VHDL不内置NI Memory或DMA，不新增整帧片上RAM。下载角色关闭已有自检pattern功能，实际数据不经过该检查器；外部TB仍独立检查实际数据。

DDR_WIDTH_BITS是编译参数，默认1280；K=width/32=40，G=K/4=10。每段开始前提供U32 N/M/C，M=ceil(N/K)，N>0且四点对齐，0<M<=C，Host填写实际分配容量。容量可大于65536；位宽改变要重编译并同步改LabVIEW类型。结果N_out独立于N_in；当前明确采用已知长度，不新增未知长度last驱动捕获。

### 每拍预算及吞吐

写内核WAIT -> CONFIG_CALC -> CONFIG_CHECK -> LOADING -> DONE/FAULT。配置乘法与界限比较分两拍，不进入稳态读/写使能路径。单打包数组在G拍内逐批接收，再占1拍提交DDR，提交时不同时读FIFO。理想服务拍数N/4+M，DDR等待、FIFO空及暂停另计，命令初始化另有固定拍数。默认1280位，150 MHz下理想稳态40/11*150=545.45 MSample/s，即2.182 GB/s；不是每个物理时钟都能接四点。超过500 MSample/s要求平均额外停顿小于1拍/40点，且源有足够数据。640位只达500 MSample/s，不能承诺超过500；更窄需另作硬件架构预算。

读内核WAIT -> CONFIG_CALC -> CONFIG_CHECK -> PREFETCH -> PRIME -> STREAMING -> DONE，异常DRAIN/FAULT。预取min(128,M)块后开始发送；block边界允许旧Current_Array发末组与下一块装入同时发生。读125 MHz端口峰值500 MSample/s，下载150 MHz端口峰值600 MSample/s/2.4GB/s；缺数据或接收方停顿会降低实际速率。吞吐统计用成功交接点数/窗口时间，不把时钟设置当实现或PCIe证据。

时序风险保持显式：宽数组动态写/选四点、NI ready反馈到局部使能、32位信用差值比较、配置乘法与64位比较均需以后真实平台STA验证。新增角色映射不添加组合层或跨核ready链。不得给ready任意再加拍。当前不获综合/实现/NI编译授权，因此物理时序和持续DDR带宽均未验证。

### 缓冲、资源、跨域

固定分配输入区DDR_Waveform与结果区DDR_Result，互不重叠。两区各自地址从0开始且不允许同区同时写读。处理时允许读取输入区并写入结果区，DDR仲裁和共享带宽必须预算；500 MSample/s双向同时服务约需4 GB/s有效DDR载荷。没有输入区/结果区交换机制。

建议起点：H2T 16384 U32=64KiB；输入预取256x1280=40KiB；可选Sync输入1024x128=16KiB；结果FIFO 1024x128=16KiB；结果预取256x1280=40KiB；T2H FPGA端16384 U32=64KiB。总有效载荷240KiB，Host端两DMA各65536 U32属于Host内存。两预取FIFO配置实际深度至少256。以上不含NI平台、Sync内部RAM及FIFO实现碎片；片上保留128个BRAM36作为规划额度、URAM计划新增0，非综合利用率。控制核自身不描述BRAM/URAM，FF/LUT须实测，不编造精确数。

结果FIFO 4096点在500 MSample/s下仅容纳约8.192us输入，须扣除占用及在途量，不能吸收无限DDR停顿。Sync必须响应本地FIFO写入许可；若Sync不能暂停，尚缺其最大突发/停顿合同，不能承诺无丢数。

Sync输出不是150MHz同源时使用NI支持的独立时钟FIFO，四点与需保留的元信息原子入队。捕获模块端只见150MHz的FIFO.Read接口；不从另一时钟域直接拉valid/data或多位N/M/C。三个150MHz循环须明确同一时钟来源，不能只凭频率相同认定同步。125MHz supervisor与150MHz命令/状态仍用原子消息FIFO；每域同步释放reset。

### 所有权与异常

先启动结果capture并确认capture_busy/合法配置，再启动输入回放和Sync；输入读完不代表Sync输出完。等待结果capture_done以及真实NI写后读可见性，再启动download。download期间Host持续排空T2H。download_done仅代表最后四点交给FPGA侧DMA，Host按N_out实际读齐并核对session tag后结束。

结果区不能在旧download未完成/旧数据未处理时重写；new_session_safe由Target会话状态机生成，不能接恒True。abort、DDR失效、run暂停、命令冲突、reset沿、旧响应排空继承现有内核优先级。reset不清NI FIFO/Memory，跨域旧数据清理和session tag由Target管理。

### 受影响短验证

原upload/read两核及两TB不改，不重跑既有成功测试。新增capture短测：四点接收、地址顺序、尾块补零、FIFO/DDR暂停、配置锁存/非法容量、取消恢复、理想4000点/1100拍。新增download短测：150MHz四点拆分、真实有限DMA FIFO和Host间歇读取、停顿保持/尾组、精确N_out、完成后Host尚有FIFO数据、取消排空和非法容量。仅两条短XSim，无扫描、整帧/超65536重跑。

新GUI工程明确4 RTL、4 TB、150/125MHz两约束集、4 sim filesets，默认capture/150MHz。125MHz约束单独集，不与150同时施加同一clk。功能测试使用TB实际时钟，完整集成时序仍未做。资源窗口获准后才create/xvhdl/xelab/XSim。
