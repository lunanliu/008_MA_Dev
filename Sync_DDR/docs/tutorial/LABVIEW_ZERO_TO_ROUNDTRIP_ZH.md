# 从零搭建四模块 DDR 回环：LabVIEW 操作手册

适用工程：Sync_DDR；FPGA目标已由用户在远端创建。四份生产VHDL不变，时钟150/125/150/150 MHz。本文从导入开始，先把604点透明回环搭通，再说明接回真实Sync的位置。图表是接线说明，不是远端工程截图。本地不生成CLIP XML、不替用户运行NI编译或板测。

## 0. 先知道最后应看到什么

本次把Sync处理位置暂时接成直通，数据不变。完整路径：

Host数据 -> H2T DMA -> Upload(150) -> DDR_Waveform
-> Read(125) -> FIFO_Sync_Result(125写/150读)
-> Capture(150) -> DDR_Result
-> Download(150) -> T2H DMA -> Host比较。

发送604个U32，收回604个U32，顺序和位值逐项相同；每段151组四点、16个DDR元素，最后一块4点有效、36点补零。Host不能收到这些36点填零。此例只验证搬运，不能用它验证OFDM同步或SFO校正。

## 1. 下载包内的文件怎么放

在远端任选一个固定工程目录，例如 D:/FPGA_Work/DDR_Roundtrip，把整个接入包解压。不要让CLIP引用浏览器临时下载目录。rtl/里正好四个文件：

| 角色/实例建议名 | 选择的顶层entity | 同时加入的源文件 | 时钟 |
|---|---|---|---|
| UploadCtrl | ddr_upload_ctrl | ddr_upload_ctrl.vhd | 150MHz |
| ReadCtrl | ddr_read_ctrl | ddr_read_ctrl.vhd | 125MHz |
| CaptureCtrl | ddr_capture_ctrl | ddr_upload_ctrl.vhd + ddr_capture_ctrl.vhd | 150MHz |
| DownloadCtrl | ddr_download_ctrl | ddr_read_ctrl.vhd + ddr_download_ctrl.vhd | 150MHz |

四个CLIP实例各自独立。Capture/Download复用内核源码，不会共用原实例的寄存器状态。不要把sim/中的tb文件当成CLIP顶层；它们只能仿真。

默认DDR_WIDTH_BITS=1280，每个DDR逻辑元素等于40个U32。Host运行时修改的是N/M/C，不能用Host变量改变端口物理位宽。

## 2. 第一次使用LabVIEW先认识这几个东西

- Project Explorer是资源树：FPGA Target下面放时钟、Memory、FIFO、CLIP和Target VI。My Computer下面放Host VI。
- Front Panel是控件/指示器面板；Block Diagram是程序框图。Ctrl+E通常用于二者切换，Ctrl+H打开Context Help，鼠标悬停端口查看类型与说明。
- 控件给程序输入值；指示器显示程序输出。绿色通常是Boolean；蓝色通常是整数，要进一步核对U8/U32/U64。颜色相同不代表位宽相同。
- VHDL的in：LabVIEW向CLIP写；VHDL的out：LabVIEW从CLIP读。时钟clk是Clock类型，不是前面板True/False控件。
- 从一根已有线的中间拉到第二个端口就是分支；一个输出可以分支，两个输出不能硬接成一根线。
- Select有True、False和选择端；选择端=True时输出True支路。下文均显式写True/False，不靠图标上下位置判断。
- 移位寄存器左端表示当前拍旧值，右端表示下一拍存入值。右击循环边框添加Shift Register；给左侧外部端子连初始化常量。
- Array是同类型有序数组；Cluster是固定成员集合。Array To Cluster需配置固定size=4或40；不是把一个U32强制转成1280位。

## 3. 在已有FPGA Target内导入四个CLIP

在FPGA Target右键Properties -> Component-Level IP -> Create File，打开CLIP声明向导。Add Synthesis File加入上表该角色所需源文件，选择相应entity作为top，按向导验证语法并保存声明。声明创建后，再在Target右键New -> Component-Level IP，选择声明、填写实例名并映射clk。声明和实例是两个步骤。[NI导入说明](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA03q000000x0jiCAA)

逐个按上表完成，先Upload、Read，再Capture、Download。若提示找不到work.ddr_upload_ctrl或work.ddr_read_ctrl，优先检查对应依赖文件是否遗漏以及top是否选错，不要复制代码改名字来掩盖依赖问题。

本工程端口设置：

| VHDL类型/端口 | 向导中的含义 | 本工程选择 |
|---|---|---|
| clk | Clock输入 | 绑定该CLIP所在SCTL的真实时钟源 |
| reset | Boolean数据输入 | 同步高有效复位；保留可由Target VI控制，不映射为平台异步Reset特殊端口 |
| 其他std_logic | Boolean数据 | 方向按VHDL in/out |
| 7 downto 0 | 无符号8位 | U8 |
| 31 downto 0 | 无符号32位 | U32 |
| 63 downto 0 | 无符号64位整数 | U64；若向导使用FXP，选Unsigned、word length64、integer word length64 |
| 数据/握手/状态端口 | 所属时钟域 | Required Clock Domain=clk，SCTL Required |
| 附加同步寄存器 | CLIP I/O附加拍数 | 本合同同域连接为0；跨域由外部独立时钟FIFO承担 |

不要把这些同域握手端口设成任意时钟域后直接跨域连接；也不要为消除错误随意添加同步拍。[NI关于SCTL Required和时钟域](https://www.ni.com/en/support/documentation/bugs/17/archived--labview-8-6-1-fpga-module-known-issues.html)解释了这些选项的作用；页面版本较旧，菜单标签以远端版本为准。

声明完成后，展开CLIP实例能看见各端口。把所需I/O点从树拖入FPGA VI的框图，形成FPGA I/O节点。控制输入、输出使能、反馈、状态分开放，不要把所有端口挤进一个混合节点。此分组本身不增加流水拍数。

本包的独立Vivado时钟XDC不要原样挂到NI工程顶层clk；NI工程应使用实际CLIP/SCTL时钟映射和平台约束。本地行为测试不能替代远端编译。

## 4. 核对时钟与数据资源

使用远端Target支持的时钟资源/派生时钟，准备Clk150和Clk125。三个150MHz循环及其CLIP选择同一个实际Clk150，Read循环及其CLIP都选择同一个Clk125。不要只把循环标签改成150MHz；确认Timing Source属性实际选择了该资源。目标不支持的时钟不能靠改名字得到。

右击FPGA Target -> New -> Memory，Implementation选择DRAM。建立两项独立资源DDR_Waveform和DDR_Result，分别记录Actual number of elements为C_in和C_out。多Memory可以分配同一DRAM bank的不同区域，由NI仲裁；不是把同一Memory节点换个显示名称就得到独立存储。[NI DRAM资源说明](https://www.ni.com/en/support/documentation/supplemental/13/introduction-to-using-dram-with-ni-fpga-devices.html)

每项Memory的数据类型必须与你确认的1280位逻辑元素一致：40个U32的固定cluster，总160字节。内存容量C的单位是这样的一个逻辑元素。604点只需16个元素；若属性窗口实际6554，则该资源C填6554。以后实际分配65536或更大时再用对应Actual值，不把Requested值或“Allocated MB”直接当成C。

建立/核对以下FIFO，均使用匹配的Handshaking接口：

| 名称 | 类型/元素 | 每次FPGA操作 | FPGA深度起点 | 所在循环 |
|---|---|---|---|---|
| FIFO_H2T | Host to Target DMA，标量U32 | Read=4个元素 | 16384个U32 | Upload读 |
| FIFO_Input_Prefetch | Target-Scoped，40-U32 cluster | Read/Write=1个cluster | 实际至少256个cluster | Read125内 |
| FIFO_Sync_Result | Target-Scoped，4-U32 cluster，Independent Clocks | Read/Write=1个cluster | 1024个cluster | 回环时125写、Capture150读 |
| FIFO_Result_Prefetch | Target-Scoped，40-U32 cluster | Read/Write=1个cluster | 实际至少256个cluster | Download150内 |
| FIFO_T2H_Result | Target to Host DMA，标量U32 | Write=4个元素 | 16384个U32 | Download写 |

透明回环不额外添加FIFO_Sync_Input；真实Sync需要输入FIFO时，按其接口另外接入。两组预取FIFO名字相似但必须是不同资源。不要把一个40点cluster误配置成“每次读4个cluster”。

Host对H2T/T2H各调用Configure FIFO，Host Requested Depth起点65536个U32并记录Actual。它们属于Host内存，与表中FPGA深度是两套配置。不要让Host Configure把Target-Scoped FIFO当成DMA。

NI的四线握手中Ready for Input表示下一周期能否接收；本文对这种接口用一次Feedback把它转换为当前周期许可。[NI高性能FPGA指南](https://download.ni.com/pub/gdc/tut/labview_high-perf_fpga_v1.1.pdf)说明此约定。如果当前节点只显示Timeout/Timed Out，先核对接口属性，不把NOT Timed Out接成valid。

## 5. 创建Target VI的四个循环

在FPGA Target下面New VI，命名DDR_Roundtrip_Target.vi。在框图放四个并列的Single-Cycle Timed Loop（有的版本由Timed Loop配置得到），命名UPLOAD_150M、REPLAY_125M、CAPTURE_150M、DOWNLOAD_150M，按第4节选择时钟。

四个循环持续运行，Stop条件为False；done不接循环Stop。前面板停止应用应走取消与清理流程，不能停数组循环后让CLIP仍运行。每个CLIP只在所属循环访问。

每个角色放本域配置寄存器N/M/C以及控制寄存器，run_enable正常=True、abort/rearm/启动命令初值=False。reset是本域同步复位。new_session_safe初值False，由第9节会话逻辑在拥有区域且旧事务已清理时授权；不能用常True。

建议节点分组如下；从树拖同一CLIP的不同I/O，不是新增CLIP实例：

| 分组 | 写侧Upload/Capture | 读侧Read/Download |
|---|---|---|
| Command | 写reset/run/命令/许可/DRAM Ready/N/M/C | 同左，Read另写pattern_check_enable/seed |
| Ready Feedback | 写DDR写许可 | 写DDR请求许可、预取写许可、下游许可 |
| Control | 读FIFO读使能/pack偏移/clear/DDR写地址valid | 读request地址valid/retrieve_ready/FIFO读使能/四点偏移及fire |
| Returned Valid | 写FIFO输出valid | 分别写DDR输出valid和预取FIFO输出valid |
| Array Control | 已含于Control | 单独读current_load/current_clear |
| Status | 读done/fault/计数 | 同左；Read另写四点checker观察输入，单独读检查结果 |

输出使能→NI节点→返回valid→CLIP→依赖该valid的输出，必须按依赖拆成节点。对FIFO返回valid和current_load不要另插Feedback；只有已明确的Ready反馈插一拍。

## 6. 两个写侧：先照着搭Upload，再搭Capture

两个循环各放一个40-U32数组移位寄存器，初值全零。创建方法：Initialize Array，element连U32零，dimension size连40；数组连左移位寄存器初值。

| 项目 | UPLOAD_150M | CAPTURE_150M |
|---|---|---|
| 控制器W | UploadCtrl | CaptureCtrl |
| 源FIFO.Read | FIFO_H2T.Read（4-U32数组） | FIFO_Sync_Result.Read（4-U32 cluster） |
| FIFO读使能 | fifo_read_enable | result_fifo_read_enable |
| FIFO反馈输入 | fifo_output_valid | result_fifo_output_valid |
| 打包寄存器 | Input_Pack_Array | Result_Pack_Array |
| DDR.Write | DDR_Waveform.Write | DDR_Result.Write |
| 段参数 | N_in/M_in/C_in | N_out/M_out/C_out |

逐根接线（W表示该列控制器）：

1. W的FIFO读使能接源FIFO.Read.Ready for Output。
2. FIFO.Read.Output Valid分两支：到W的FIFO反馈输入；到Select_Receive的选择端。
3. Upload的Read.Element已是4-U32数组，直接用；Capture的Read.Element先Cluster To Array得到4-U32数组。
4. Pack_Array左端旧数组分三支：Replace Array Subset.array；Select_Receive.False；Array To Cluster(size40)输入。
5. W.pack_offset接Replace Array Subset.index；第3步四点数组接new subarray。offset已经是0/4/.../36，不再乘4。
6. Replace Array Subset输出接Select_Receive.True。Select_Receive输出接Select_Clear.False。
7. W.pack_clear接Select_Clear选择端；40点全零数组接Select_Clear.True；Select_Clear输出只接Pack_Array右移位寄存器。
8. 第4步Array To Cluster40输出接DDR.Write.Data。不能从右移位寄存器或Select_Clear输出取DDR.Data，否则写与清零同拍可能把零写出去。
9. W.ddr_write_address接DDR.Write.Address，另可分支给Written_Words指示器。
10. W.ddr_write_valid接DDR.Write.Input Valid。
11. DDR.Write.Ready for Input接一只Feedback Node，初值False，其输出接W.ddr_write_ready_now。不再加第二个寄存器。
12. 如果Write显示Byte Enables，按端子类型创建全部字节有效常量；若Boolean数组则160项True。错误输出接错误指示器，不代替控制器fault_code。
13. W.dram_ready接本域实际DRAM Ready，可另分支到本地灯。它不同于Write.Ready for Input。

两个150MHz写入器在默认1280位下接收10批后用1拍提交整块；源FIFO需要接受该停顿，不能按永远每拍四点硬推。

## 7. 两个读侧：预取、当前块和四点输出

Read放在125MHz，Download放在150MHz。各自资源如下：

| 项目 | ReadCtrl | DownloadCtrl |
|---|---|---|
| Memory | DDR_Waveform | DDR_Result |
| 预取FIFO | FIFO_Input_Prefetch | FIFO_Result_Prefetch |
| 数组寄存器 | Input_Current_Array | Result_Current_Array |
| 四点偏移输出 | stream_offset | unpack_offset |
| 下游当前许可输入 | stream_ready | dma_ready_now |
| 当前有效/实际交接 | stream_valid/stream_fire | dma_valid/dma_fire |
| 目的Write | 回环时FIFO_Sync_Result.Write | FIFO_T2H_Result.Write |

每个读循环先放Memory的Request Data、Retrieve Data，确保是同一资源和匹配读接口；再放本列Prefetch.Write和Prefetch.Read。

| 来自 | 连到 | 备注 |
|---|---|---|
| 控制器.request_address | Request Data.Address | DDR元素地址 |
| 控制器.request_valid | Request Data.Input Valid | 不额外再打一拍 |
| Request Data.Ready for Input | Feedback(False) -> ddr_request_ready_now | 一次 |
| 控制器.retrieve_ready | Retrieve Data.Ready for Output | 允许接受在途响应 |
| Retrieve Data.Output Valid | 控制器.ddr_retrieve_valid | 不直接去Prefetch.Write有效端 |
| Retrieve Data.Data | Prefetch.Write.Element | 整块40-U32 cluster |
| 控制器.prefetch_write_valid | Prefetch.Write.Input Valid | Abort时可能取回并丢弃，必须用此输出 |
| Prefetch.Write.Ready for Input | Feedback(False) -> prefetch_write_ready_now | 一次 |
| 控制器.prefetch_read_enable | Prefetch.Read.Ready for Output | 独占此预取FIFO |
| Prefetch.Read.Output Valid | 控制器.prefetch_read_valid | 本拍反馈 |
| Prefetch.Read.Element | Cluster To Array40 -> Select_Load.True | 本拍取出的新块 |

再放Current_Array移位寄存器，初值40点全零，以及Select_Load、Select_Clear、Array Subset：

1. Current_Array左端分两支：Select_Load.False和Array Subset.array。
2. 控制器.current_load接Select_Load选择端；新块接True（见上表）。
3. Select_Load输出接Select_Clear.False；零数组接Select_Clear.True；current_clear接选择端。
4. Select_Clear输出接Current_Array右端。
5. 控制器的四点偏移接Array Subset.index，length常量4。Array Subset输出就是本拍四点。仍从左旧数组取，不取下一拍数组。

### 7A. Read125的透明回环接法

- 四点数组分两路：一路Array To Cluster(size4)后到FIFO_Sync_Result.Write.Element；另一路Index Array取0/1/2/3，分别到ReadCtrl.stream_word0/1/2/3。
- ReadCtrl.stream_fire到FIFO_Sync_Result.Write.Input Valid。
- FIFO_Sync_Result.Write.Ready for Input经一次Feedback(False)到ReadCtrl.stream_ready。
- ReadCtrl.pattern_check_enable=True；pattern_seed=U32十六进制12340000（十进制305397760）。
- stream_first、stream_last可以分支到本地监视/计数。当前测试按N计数，不把它们插入U32数据数组。
- 此时没有真实Sync模块，也不新增旁路到DMA。不要把同一fire同时广播到两个会独立堵塞的FIFO。

### 7B. Download150接DMA

- 四点数组直接到FIFO_T2H_Result.Write.Element，该DMA每次Write=4个U32；这里不转4-U32 cluster。
- DownloadCtrl.dma_fire到T2H.Write.Input Valid；dma_valid仅表示有数据可送，不单独触发写入。
- T2H.Write.Ready for Input经一次Feedback(False)到DownloadCtrl.dma_ready_now。
- Download没有四点checker输入；数据只经过LabVIEW数组和DMA。
- dma_first/last可监视，不混入IQ数据。Host按N_out与Tag确定段界。

## 8. Capture的FIFO读端已经连接，中间回环就完整了

第7A节是FIFO_Sync_Result的125MHz写端，第6节Capture列是同一个FIFO的150MHz读端。两者之间没有额外直接数据/ready线。跨域由Independent Clocks FIFO实现。

这一步很容易误接：Input_Prefetch只供Read取40点块；Result_Prefetch只供Download取40点块；Sync_Result只供Capture取四点组。三个FIFO的元素尺寸和所有者不同。

本地短测故意使用8组容量以快速触发回压，远端起始配置使用1024组；不要为了复制短测就擅自把生产FIFO缩到8。

## 9. 启动顺序：用一个会话状态机控制四核

四个VHDL是数据流控制器，不包含整个Target VI的会话管理。不能摆四个按钮让Host随意并发启动同一DDR区的读写。

将总会话Case Structure及Enum状态移位寄存器放在REPLAY_125M。Read在本域直接启动；其余三个150MHz角色通过命令/状态FIFO通信，避免从循环出口硬拉跨域线：

| FIFO | 方向 | 原子cluster | 深度 |
|---|---|---|---|
| U_Command / C_Command / D_Command | 125写 -> 150读，各角色独立 | {Operation U32, Tag U32, N U32, M U32, C U32} | 每个4条 |
| U_Status / C_Status / D_Status | 150写 -> 125读，各角色独立 | {Tag U32, Code U32, Samples U32, Words U32} | 每个4条 |

这些小FIFO有效载荷合计432字节，实际NI实现有存储粒度和控制开销；不能直接按432字节换算精确BRAM。它们都是NI支持的独立时钟Target-Scoped FIFO，消息整体Bundle/Unbundle，不把多位N/M/C拆成逐位同步。

对小FIFO的Read：只有本地消息寄存器空/本地状态可接收时Ready for Output=True，Output Valid时锁存整个cluster。对Write：消息寄存器valid保持到下一拍许可有效，Input Valid=消息valid AND延迟后的Ready；成功后清valid。

150MHz的每个角色适配器在本循环按以下Case执行：

1. IDLE收一条命令并锁存Tag/N/M/C，保存命令前generation。
2. CONFIG把寄存器N/M/C接CLIP并让启动命令False。
3. START在本域合法许可成立时让启动命令True一拍；下一拍恢复False。
4. WAIT_ARMED等generation变成旧值+1且状态已进入实际LOADING/PREFETCH，而不把配置阶段busy当成“参数已合法”。若fault，发同Tag的FAULT消息。
5. 发ARMED消息，Code=1。保持消息直到状态FIFO成功接收，不能只发一个易丢失脉冲。
6. WAIT_DONE观察本次done/fault。完成发Code=2，Samples/Words来自该核实际计数；故障Code=3并另保存fault_code。上一条ARMED未发完时先保存完成状态，不能覆盖尚未发送的消息。
7. 回IDLE前仍保留区域所有权，直到总会话释放。全局初始化清理后才允许Rearm；Abort/Rearm同样走命令消息，不跨域拉单拍线。

全局状态表：

| 状态 | 做什么 | 何时进入下一步 |
|---|---|---|
| IDLE_CLEAN | 确认资源初始化、旧FIFO与事务清理、参数合法 | 接受新Tag和整段描述符 |
| START_UPLOAD | 发U启动消息；通知Host可继续向H2T送N_in点 | U已ARMED |
| WAIT_UPLOAD | Host正在送数，U正在装载 | 同Tag完成且Samples=N_in、Words=M_in |
| WAIT_INPUT_VISIBLE | 等实际NI写后读可见性条件 | 输入区可以读 |
| ARM_CAPTURE | 发C启动消息，结果区保留给此Tag | C已ARMED |
| START_REPLAY | Read输入N_in/M_in/C_in、许可；read_command一拍 | Read generation递增或fault |
| RUN_REPLAY_CAPTURE | 读取输入区并捕获结果区 | Read完成且C同Tag完成、各计数吻合 |
| WAIT_RESULT_VISIBLE | 等结果区NI写后读可见性 | 允许下载 |
| START_DOWNLOAD | 发D启动消息；Host消费循环已准备 | D已ARMED |
| WAIT_HOST | D输出，Host持续读T2H；D完成只代表提交完 | Host按同Tag确认收齐N_out |
| COMPLETE | 锁存总结果，保持指示器 | 清理与新会话请求 |
| FAULT | 记录角色/Tag/fault；停止新数据提交、按各核协议排空 | 外部清理确认后重新就绪 |

**平台待对齐点：**现有RTL的load_done/capture_done表示“写请求全被接受”。真实NI Memory的写后读可见性需要按远端接口保证实现。这里的WAIT_INPUT_VISIBLE/WAIT_RESULT_VISIBLE不是可以接常True的虚构完成端口，也不能用任意等1ms代替。若接口没有显式完成端口，应确认同Memory的后发读是否保证看到已接受写；在确认前只能完成连线/行为验证，不能宣称真实板卡回环已验收。Error端口并不自动代表写入完成。

### Host参数怎样进入这个状态机

沿用工程的“先稳定参数，再提交Tag；收到确认前保持不变”合同。若不熟悉Host控件的原子交接，建议用额外一条小型Host-to-Target命令DMA代替多个直接启动按钮：

- FIFO_Control_H2T，U32，每次FPGA Read=1，FPGA深度128个U32；读端在125MHz会话循环，低速控制不要求4元素。
- Host一次发送8个U32：[Operation, Tag, N_in, M_in, C_in, N_out, M_out, C_out]。Operation=1表示启动完整透明回环，Operation=2表示Host已收齐本Tag。
- 会话侧有8-U32消息数组和0..7索引，仅Output Valid时存一个字；第8个字到齐后才原子锁存描述符并处理。没收齐不能启动任何核。处理期间暂停接收下一条消息，忙时新启动不排队。
- Host确认消息也发足8字，Tag必须一致，其余字段保持原值；清理时丢弃未完整命令，避免半条消息拼到下一轮。
- Host读取的Session_Tag、Session_State、Fault等前面板指示器由125MHz会话逻辑保持稳定，仅供Host低速轮询；不能把这些Host监控值拿来替代内部跨域握手。

这条控制DMA额外有效载荷512字节，Host数据DMA仍是每次FPGA四点。它属于LabVIEW会话适配，不是第五个VHDL。

## 10. Host VI：生成604点、发送、接收、比较

在My Computer下面New VI，命名DDR_Roundtrip_Host.vi。前面板放N_In/N_Out/M_In/M_Out/C_In/C_Out（U32）、Tag（U32）、Received_Count（U32）、Mismatch_Count（U32）、First_Error_Index（I32，初值-1）、Pass（Boolean）、输入/输出数组指示器。

输入取本包examples/roundtrip_604/input_u32.csv：无表头、一行一个十进制U32。也可在Host用For Loop次数604自动索引生成：U32常量305397760加迭代索引i（转U32），得到数组。不要用浮点波形类型发送DMA。

如果从input_iq_i16.csv读两列：I低16位、Q高16位。先保留I16/Q16位模式并Type Cast成U16，再提升U32；U32=I_bits OR (Q_bits左移16)。负I/Q不能直接有符号加法拼接。本例I=0..603，Q=4660。

Host框图使用Open FPGA VI Reference、Read/Write Control和FIFO Invoke Method等节点连接同一FPGA引用；error线按顺序串接初始化步骤，避免配置与运行无序。具体Method名称以当前FPGA接口菜单为准。

1. 打开对应Target VI/已生成bitfile引用，配置H2T/T2H（及选择使用的Control DMA）。先确认平台启动、FIFO清理和Target Session=IDLE_CLEAN。
2. 准备Tag，例如1；N_in=N_out=604；M_in=M_out=16；C分别填两个Memory真实Actual容量，至少16。
3. 先提交完整回环命令/描述符；然后H2T FIFO.Write发送604个U32。不能先等Upload done再发送数据。
4. Host主循环持续检查错误和Target状态，并读取T2H。初始没有数据时有限超时并按实际接口的有效返回长度处理；不要把“尚未产生结果”当作收到零数组。不可将Timed Out当作数据valid。
5. 本例可每次请求4个U32，累计151次，便于看每组数据；后续长帧改用较大批次，并让最后一次请求min(批次大小,N_out-已收到数)。不要最后还请求固定大批次而一直等不存在的数据。
6. 收到的数据按先后追加到Host数组。Received_Count增加实际收到的U32个数，不是读调用次数。超时/部分返回时保留已收数据，依据该API返回结果续读，不能盲目从头发送新一帧。
7. 先用Array Size分别核对两个数组都是604。再把输入与接收数组同时送入一个For Loop的自动索引隧道，循环内每次取同一下标的两个U32，用Not Equal?比较；Boolean To(0,1)后累计得到Mismatch_Count。First_Error_Index移位寄存器初值-1，遇到不等且旧值仍为-1时存迭代索引i，否则保持旧值。不要让数组比较函数默认的“整体比较”输出替代逐点统计。
8. Data_Pass = (Received_Count=604) AND (Mismatch_Count=0) AND (四核无fault) AND (本Tag四核均done)。这里检查四个控制器完成，不先等待总会话COMPLETE，因为总会话还在等待下一步的Host确认。单独看Download done不够。
9. Data_Pass成立后发本Tag的Host收齐确认，Target转COMPLETE；最终Pass = Data_Pass AND (Session_State=COMPLETE且Tag一致)。检查是否存在非预期多余点，再结束这轮；未处理的旧DMA数据不能留给下一轮。
10. 将实际接收U32数组保存为无表头单列十进制CSV，命名host_received_u32.csv。用附带scripts/compare_roundtrip.py也能独立比较。

Python可选用法：python scripts/compare_roundtrip.py 你的接收文件.csv。它不控制板卡，只检查实际文件；不要把expected文件改名冒充received。

Host不会按150MHz执行软件循环；FPGA侧循环150MHz，DMA缓冲把两种节拍隔离。Host持续吞吐受实际PCIe/驱动/主机链路限制。

## 11. 正确结果长什么样

| 观察项 | 604点透明回环的预期 |
|---|---|
| 输入/输出U32长度 | 都为604 |
| 输入/输出总字节 | 都为2416 |
| 第一组四点（十六进制） | 12340000、12340001、12340002、12340003 |
| 最后一组四点 | 12340258、12340259、1234025A、1234025B |
| I分量图 | 按样点索引从0升到603 |
| Q分量图 | 恒为4660 |
| 输入与回收I/Q曲线 | 以样点索引对齐后重合；不是按Host墙钟时间对齐 |
| Upload.loaded_samples / Capture.captured_samples | 各604 |
| Upload/Capture.ddr_write_address（完成后） | 各16；最后实际写地址是15 |
| Read.sent_samples / Download.downloaded_samples | 各604 |
| 两个读核requested/returned/enqueued/popped_words | 都为16 |
| 两个读核transfer_cycles | 都为151 |
| Read.checked_samples / mismatch_count | 604 / 0（checker已按本例开启） |
| Host Received_Count / Mismatch_Count / First_Error_Index | 604 / 0 / -1 |
| 四核fault / fault_code | False / 0 |
| done | 每核完成后保持True，下一合法会话清除 |
| 两个DDR最后一块 | 前4点为最后四点，后36项零；零不送Host |

完成后写地址输出16是“下一个地址/已提交块数”，不是写越界。state码：Upload/Capture完成0x02；Read/Download完成0x05。暂停或Host停读时总周期可能增加，不要求total_cycles等于151，也不按这个小例子宣称持续吞吐合格。

604点小例子小于16384点的FPGA DMA深度，暂停Host接收通常不会让DMA填满，不能据此判断背压失效。以后使用足够长的数据段且Host及FPGA侧缓冲确实耗尽时，downloaded_samples才应停止增加，恢复读取后继续。普通ready背压期间当前四点与首尾保持，已发出的DDR请求仍可能返回预取FIFO，这属于正常在途响应。

本地行为测试额外让Capture暂停，验证结果FIFO满时Read也会停住。远端正常配置深度更大，604点小段未必能把1024组FIFO填满；因此不要要求你的小例子一定出现相同stall计数。

## 12. 从透明回环切换到真实Sync

先保存可工作的透明回环VI副本。在Read125输出位置接Sync输入（同域直接握手，异域经过适配FIFO），把Sync输出四点接FIFO_Sync_Result.Write；其写端位于Sync实际输出域，读端仍150MHz。

真实Sync的Ready接到对应本域源许可，不从Capture150跨域直拉。四点必须按实际Sync I/Q位序拼接，附带First/Last若需要跨域，应与数据装入同一FIFO元素；不要单独跨域拉标志。

N_out必须是Sync本轮实际输出合同的点数，可能小于或不同于N_in。捕获器当前按预设N_out完成，不能只在结束时才告诉它长度。真实Sync会搜索、截取、校正或改变样点，正确比较对象是同一输入条件下的Sync参考输出；本例的“逐位等于输入”只适用于透明回环。

## 13. 常见问题按现象查

| 现象 | 先检查 |
|---|---|
| Import找不到entity | 顶层名字及Capture/Download依赖源文件 |
| CLIP Clock端口不能接Boolean | 时钟在CLIP实例属性映射，不用前面板线造时钟 |
| 编译出现数据依赖环 | 把请求输出、NI返回valid、依赖反馈输出拆成不同I/O节点；不盲目插拍 |
| Upload/Capture一直busy | 源FIFO是否有足够N点；N_out是否填成输入长度；DDR Ready是否真实 |
| Read/Download一直预取 | Request/Retrieve是不是同一个Memory接口，返回valid和预取Write有没有接错 |
| 每40点少4点或重复4点 | 使用了右Current_Array、offset重复乘4、current_load或ready多打一拍 |
| 读回几乎全0 | DDR.Data误接Select_Clear输出；未等待真实写可见性；Memory资源选错 |
| 结果尾部多36个0 | Host按M*40读而非N；末组处理或计数单位错 |
| 所有I/Q看起来交换 | I低16/Q高16是否一致，使用位模式拼接而非有符号相加 |
| Download停在一半 | Host尚未开始消费或DMA满；不能等done才开始FIFO.Read |
| 上一轮尾数据混入下一轮 | 会话Tag、Host已收齐确认及NI FIFO清理缺失 |
| 只有done灯通过，数组不一致 | 仍需逐点比较，done只表示对应控制阶段完成 |
| WAIT_*_VISIBLE一直不走 | 缺少真实NI写后读保证，不能改成True消除这个现象 |

## 14. 本地验证和远端操作的边界

四个角色各自已有通过证据；本轮四核串联604点行为回环也已通过，实际仿真接收文件位于examples/roundtrip_604/simulated_host_received_u32.csv，报告为reports/review/DDR_ROUNDTRIP_VALIDATION_ZH.md。所有NI FIFO/DRAM/Host在本地是模型，没有连接远端硬件；真实NI编译、物理时序、CDC电路、持续DDR/PCIe速率及Sync算法不由这条测试证明。

远端界面版本、具体DVM/Memory接口的写可见性保证仍需对齐。当前教程不提供假的“已完成远端VI”或板测截图，也不生成CLIP XML。代码导入后实际NI编译/下载/板测由用户在远端执行并记录结果。
