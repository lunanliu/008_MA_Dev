> **新版入口**：容量和顺序会话已改版。请先读[新版端口与顺序控制](LABVIEW_RUNTIME_CONFIG_AND_SESSION_ZH.md)，再按本文搭数据通路。40点数组对应默认1280 bit，其他编译宽度改为K点。实测状态见工程README。

# 现有 DDR1280 工程：LabVIEW Target VI 逐根接线教程

适用起点：用户远端已建好 FPGA Target，确认 DDR 接口宽度为1280位，已有DRAM和FIFO资源。本文教用户核对资源属性和搭建Target VI；不查找远端工程、不生成CLIP文件。菜单文字随LabVIEW版本可能不同，以下以端口名、函数英文名和实际数据类型为准。

对应当前 `rtl/ddr_upload_ctrl.vhd` 与 `rtl/ddr_read_ctrl.vhd`。教程描述现有接口合同，不表示已完成远端接线、编译、仿真或板测。

## 0. 最终搭成什么

同一个FPGA Target下放一个 `DDR_Target.vi`，里面放两个并列的SCTL（Single-Cycle Timed Loop，单周期定时循环），不要互相嵌套。

```text
写循环，150 MHz：
Host → FIFO_H2T.Read → 40点Pack_Array → DDR_Waveform.Write
         ↑                    ↑                 ↑
         └──── UploadCtrl 提供握手、组号、地址和清零 ──┘

读循环，125 MHz：
DDR_Waveform.Request + Retrieve → FIFO_DDR_Prefetch → 40点Current_Array
       ↑                              ↑                    │
       └──────── ReadCtrl 控制 ─────────┘              每次取4点
                                                          │
                                                   FIFO_Sync_Input.Write
                                                          │
后续Sync自己的输入循环：                         FIFO_Sync_Input.Read → Sync
```

`FIFO_DDR_Prefetch`装40点整块，由ReadCtrl独占读取。`FIFO_Sync_Input`装四点小组，由Sync输入侧独占读取。它们是两个不同资源。

当前两个VHDL只提供控制，40点数据在LabVIEW导线上和数组移位寄存器内。状态机、地址计数、组号都已在VHDL中，不必在Target VI再搭同名状态Case或重复计数器。

读写分阶段，由Host先完成装载，再发读取命令。两个循环都持续运行，活动与否由VHDL状态/使能决定。

## 1. 先学会本文的接线写法

- `A → B`：从A输出端拉一根线到B输入端。
- `A → B、C`：A同一根输出线分两支，同时连B和C。不是复制一个A节点，更不是执行两次FIFO.Read。
- `左Pack_Array/左Current_Array`：循环左边移位寄存器在循环内部的输出，本拍旧数据。
- `右Pack_Array/右Current_Array`：循环右边移位寄存器的输入，时钟沿后保存为下一拍数据。
- Select的`s`是布尔条件，`t`在True时选中，`f`在False时选中；只有一个输出。
- VHDL的`in`端口，在LabVIEW端要向CLIP**写入**；VHDL的`out`端口，在LabVIEW端要从CLIP**读取**。本文说“输入/输出”均以VHDL为参照。

实际操作：Ctrl+E切换前面板/程序框图；Ctrl+H打开即时帮助，鼠标移到端子确认名字和类型。框图中可用Ctrl+Space查找英文函数名。若自动工具不好用，从工具选板选择连线工具，在已有线段上单击，再点另一个目的端子，即可产生分支。一个输入端只接一个来源，不能把两个输出硬并在一起。

所有现场会被Host改变的控制量终端应放在所属SCTL**内部**。不要把终端放在循环外再经隧道进入，否则容易只在进循环前读取一次。零数组、固定长度4/40等常量可以放在循环外。

## 2. 核对已有Memory、FIFO和DMA配置

在Project Explorer里右键资源→Properties。下表名称是教程统一称呼，可映射到你现有的名称，不必重复创建资源。

| 名称 | 资源类型 | 一个元素是什么 | FPGA端每次操作 | 深度/容量 | 性质 |
|---|---|---|---|---|---|
| DDR_Waveform | 你已有的1280位DRAM Memory | 40个U32组成的cluster，160字节 | 每次读/写1块 | 建议65536块起；Host上报C不超过实际分配，RTL检查M≤C | 宽度/分块合同必须匹配 |
| FIFO_H2T | Host to Target — DMA | 一个无符号32位样本字 | FPGA Read一次4个元素 | FPGA端建议16384个U32；Host端先65536个U32 | 每次4点必须匹配；两个深度是起始建议 |
| FIFO_DDR_Prefetch | Target-Scoped，非DMA | 与DDR.Data完全相同的40-U32 cluster | Write一次1个cluster；Read一次1个cluster | 请求256，实际容量必须至少256个cluster | 与RTL信用计数直接相关 |
| FIFO_Sync_Input | Target-Scoped，非DMA | 4个U32组成的cluster | Write/Read每次1个cluster | 初始建议1024个cluster，即4096点、16KiB数据 | 新增下游缓冲建议，不是现有RTL固定值 |
| FIFO_T2H_Readback（可选） | Target to Host — DMA | 一个无符号32位样本字 | FPGA Write一次4个元素 | FPGA端4096个元素；Host端65536个元素 | 独立回传Host时替代Sync输出，非必需 |

### 2.1 FIFO_H2T

1. General：Type=Host to Target — DMA，名字采用你现有资源名。
2. Data Type：优先使用U32；若你的接口使用FXP，则设Unsigned、Word Length=32、Integer Word Length=32，即没有小数位。Host数据类型也与它匹配。
3. Requested Number of Elements/Depth：建议16384个U32，即64KiB，不是16384组四点。
4. Interfaces：启用Handshaking；FPGA侧 `Number of Elements Per Read=4`。
5. 若显示FPGA侧Elements Per Write，此方向实际由Host写，保留工具对该方向的有效设置；不要用它来设Host每次发送多少点。Host传数组的长度由Host FIFO.Write的Data决定。
6. 框图Read节点应出现`Ready for Output`输入、`Output Valid`输出、`Element`输出。Element应是固定4元素数组。
7. 若只能看到`Timeout/Timed Out?`，先检查Handshaking配置；不要把Timed Out?原样接到VHDL的valid端。

若该目标/数据类型下不能配置一次读4元素，当前控制器不能直接接一次读1点的节点。不要偷偷把VHDL计数或N除以4；先对齐节点配置。[NI多元素FIFO说明](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z0000019UZ3SAM&l=en-US)指出多元素接口取决于目标支持，配置后Element端接相应长度数组。

### 2.2 FIFO_DDR_Prefetch

1. General：Type=Target-Scoped。
2. Data Type：使用DDR.Data实际的40-U32 cluster类型。不要选“单个U32”，也不要只把depth乘40来代替宽度。
3. Implementation：Block Memory；Control Logic选与当前工程匹配的Slice Fabric选项，避免未经核对更换接口行为。
4. Depth请求256；检查Actual Number of Elements至少256。不要改成64或128。
5. Interfaces：读写都为Handshaking，Elements Per Write=1、Elements Per Read=1。这里的“1”已经包含40点。
6. 该FIFO的Write、Read节点都放在读侧125MHz SCTL内。

如需要建立数据类型控件，可在DDR.Data导线上右键Create→Control得到完全相同的cluster，再由你保存为自定义控件供FIFO属性选择。数组和cluster不是同一种类型，使用下文转换节点，不靠改线颜色或强制类型转换凑宽度。

### 2.3 FIFO_Sync_Input

1. Type=Target-Scoped；Implementation=Block Memory。
2. 一个元素定义为有序的4-U32 cluster，顺序是sample0、sample1、sample2、sample3。可以用Array To Cluster(Size=4)的输出创建对应控件。
3. Handshaking；Read=1个cluster、Write=1个cluster；初始depth=1024个cluster。
4. Write端在125MHz读循环；Read端在后续Sync输入循环。跨时钟时使用NI支持的跨时钟FIFO配置/实现，不另拉一条跨域ready/valid线旁路FIFO。
5. 这是本文主线。若现有Sync输入FIFO已固定为U32并且每次读写4个元素，也能承载四点，但应统一采用那个接口；此时Element接四点数组，省去Size=4的cluster转换。两种配置只能选一种，不能把“一次1个cluster”和“一次4个cluster”混淆。

1024组是方便开始的缓冲建议，不是整帧容量，也不是持续吞吐保证。如果Sync尚未消费，它会填满，播放器随后暂停，read_done不会出现；这是正常背压。独立搭DDR而尚未接Sync时，可采用第8节的Host回读出口。

### 2.4 DMA的Host侧配置

Host VI使用FPGA Interface的Invoke Method对DMA FIFO调用Configure：`Requested Depth=65536`，单位仍是**标量32位元素**。记录返回的Actual Depth，不假设强制等于请求值。配置放在传输前，之后可调用Start。

Project内的16384是FPGA设备端缓冲；Host Configure的65536是主机内存缓冲，它们不能互相替代。Target-Scoped FIFO没有这个Host Configure操作，也不占Host DMA通道。[NI对两种深度的说明](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z0000019KwbSAE&l=en-US)。

## 3. 布置Target VI骨架与CLIP接口

你自行完成CLIP导入，不需要我生成声明文件。将两个实例命名为`UploadCtrl`、`ReadCtrl`，或在笔记中记录实际名字。

1. 在远端已有FPGA Target下新建/打开目标VI，命名如`DDR_Target.vi`。
2. 框图放两个并列Timed Loop。在FPGA VI中它们作为SCTL工作。给它们加标签`WRITE_150M`和`READ_125M`。
3. WRITE选当前合同的150MHz时钟，READ选125MHz时钟。CLIP的clk分别映射到**各自循环的同一个时钟源**；两个名字同为125MHz但源不同也不等于同源。
4. 参与握手的CLIP数据端口配置为SCTL Required，绑定相应时钟域；当前合同不附加输入/输出同步寄存器。clk是Clock，不是Boolean数据端口。
5. 两个SCTL的停止条件接False，保持连续运行。不要把load_done/read_done接到循环停止端。暂停用run_enable，切换会话用命令；不能只停数组所在的SCTL而让CLIP继续运行。
6. 不在SCTL里放等待毫秒、Host文件读取或DMA.Configure。这些属于Host。
7. 使用若干独立FPGA I/O节点访问同一CLIP实例。不要把所有读写端口堆进一个大混合节点。

简单的节点划分：

| 节点组 | 内容 |
|---|---|
| W_Command | 向UploadCtrl写入控制量、N/M、DRAM Ready |
| W_Control | 从UploadCtrl读取fifo_read_enable、pack_offset、pack_clear、ddr_write_valid、ddr_write_address |
| W_FIFO_Feedback | 只写fifo_output_valid |
| W_DDR_Feedback | 只写ddr_write_ready_now |
| W_Status | 只读状态与计数，接面板指示器 |
| R_Command | 向ReadCtrl写入控制量、N/M、check/seed、DRAM Ready |
| R_Ready_Feedback | 写延迟后的DDR请求许可、预取写许可、下游许可 |
| R_Request_Stream | 读request_valid/address、retrieve_ready、prefetch_read_enable、stream_offset/valid/fire |
| R_Return_Feedback | 只写ddr_retrieve_valid |
| R_Enqueue | 单独读prefetch_write_valid |
| R_Pop_Feedback | 只写prefetch_read_valid |
| R_Array_Control | 单独读current_load/current_clear |
| R_Check_Data | 写stream_word0..3，来自实际四点线 |
| R_Status | 只读状态、计数与检查结果 |

分组是为了避免LabVIEW把本来可分开的端口强加成图形数据依赖环；**分组不代表增加时钟延迟**。只有明确要求的一拍ready Feedback才插寄存器，FIFO valid、current_load等线路不额外延迟。

### 3.1 控制量名称（新版本由会话状态机驱动）

本表保留信号对应名称；新版本Load/Read、许可及N/M/C由新版补充中的Target会话状态机驱动，Host不能绕过互斥直接启动核。

在所属循环内放下列前面板控制终端。W/R是面板名字前缀，不改变VHDL端口名。Boolean使用保持状态的开关（如Switch When Pressed），不使用Latch机械动作。

| 写侧面板控件 | 类型/初值 | 接UploadCtrl输入 |
|---|---|---|
| W_Reset | Boolean/False | reset |
| W_Run_Enable | Boolean/True | run_enable |
| W_Load | Boolean/False | load_command |
| W_Rearm | Boolean/False | rearm_command |
| W_Abort | Boolean/False | abort_command |
| W_New_Session_Safe | Boolean/False | new_session_safe |
| W_Sample_Count | U32/0 | sample_count |
| W_DDR_Word_Count | U32/0 | ddr_word_count |
| W_DDR_Capacity_Words | U32/0 | ddr_capacity_words |

| 读侧面板控件 | 类型/初值 | 接ReadCtrl输入 |
|---|---|---|
| R_Reset | Boolean/False | reset |
| R_Run_Enable | Boolean/True | run_enable |
| R_Read | Boolean/False | read_command |
| R_Rearm | Boolean/False | rearm_command |
| R_Abort | Boolean/False | abort_command |
| R_New_Session_Safe | Boolean/False | new_session_safe |
| R_Sample_Count | U32/0 | sample_count |
| R_DDR_Word_Count | U32/0 | ddr_word_count |
| R_DDR_Capacity_Words | U32/0 | ddr_capacity_words |
| R_Pattern_Check_Enable | Boolean/False | pattern_check_enable |
| R_Pattern_Seed | U32/0 | pattern_seed |

两边dram_ready接你现有NI资源的DRAM Ready状态，在各自支持的时钟域内读取。该线在每个循环可分支到该控制器dram_ready和本循环的DRAM_Ready指示灯。不要用DDR.Write.Ready for Input代替DRAM Ready，也不要用True常量伪造就绪。

同一个N/M由Host分别写W和R的配置，不把写循环的组合信号直接跨域拉到读循环。首次干净启动可先分别reset=True，再False；这只复位核心和数组，不承诺清掉先前残留NI队列。

## 4. 写循环：一步一步搭线

### 4.1 先放节点与数组寄存器

在WRITE_150M内部放：

- `FIFO_H2T.Read`（从项目FIFO拖入，选择Read）。
- `DDR_Waveform.Write`（同一Memory拖入，选择Write）。
- 一个`Replace Array Subset`，标签`W_Replace`。
- 两个`Select`，标签`W_Select_Keep`、`W_Select_Clear`。
- 一个`Array To Cluster`，右键设置Cluster Size=40，标签`W_ArrayToCluster40`。
- 一个Boolean `Feedback Node`，延迟1次迭代、初始化False，标签`W_Ready_Delay`。
- 前述UploadCtrl的I/O节点。

右键SCTL边框→Add Shift Register，得到一对寄存器，标签`Pack_Array`。在循环外放Initialize Array：element接U32零、dimension size接40；输出命名`W_Zero40`。W_Zero40分两支：一支连左移位寄存器的**外侧初始化输入**，另一支经普通隧道进入循环，供下文清零Select使用。

### 4.2 H2T与DDR握手

| 编号 | 从哪里出线 | 接到哪里 | 分支说明 |
|---|---|---|---|
| W01 | UploadCtrl.fifo_read_enable | FIFO_H2T.Read.Ready for Output | 单一路径 |
| W02 | FIFO_H2T.Read.Output Valid | UploadCtrl.fifo_output_valid | **还分支到W_Select_Keep.s** |
| W03 | FIFO_H2T.Read.Element | W_Replace.new element/subarray | 应为4-U32数组；如果是Unsigned FXP32整数数组，转换成U32数组，值/位模式保持 |
| W04 | UploadCtrl.pack_offset | W_Replace.index | 已是0/4/8…36，不再乘4 |
| W05 | UploadCtrl.ddr_write_address | DDR_Waveform.Write.Address | **还分支到U32指示器W_Written_Words** |
| W06 | UploadCtrl.ddr_write_valid | DDR_Waveform.Write.Input Valid | 单一路径 |
| W07 | DDR_Waveform.Write.Ready for Input | W_Ready_Delay.input | 不是直接接VHDL |
| W08 | W_Ready_Delay.output | UploadCtrl.ddr_write_ready_now | 延迟后才表示本拍许可 |

Feedback的初始化端接False，不是把False接到正常数据输入上。不要再在W08后加第二个Feedback。

### 4.3 三条最重要的数据分支

从**左Pack_Array在循环内部的输出端**拉出一根主线，分成下面三支：

```text
左Pack_Array ─┬→ W_Replace.array
             ├→ W_Select_Keep.f
             └→ W_ArrayToCluster40.array → DDR_Waveform.Write.Data
```

然后接Select的全部端子：

| 节点 | s（条件） | t（True） | f（False） | 唯一输出接到 |
|---|---|---|---|---|
| W_Select_Keep | H2T.Read.Output Valid，即W02的分支 | W_Replace.output | 左Pack_Array的第二分支 | W_Select_Clear.f |
| W_Select_Clear | UploadCtrl.pack_clear | W_Zero40的循环内分支 | W_Select_Keep.output | **右Pack_Array** |

再确认H2T的有效线是这样分叉的：

```text
H2T.Read.Output Valid ─┬→ UploadCtrl.fifo_output_valid
                      └→ W_Select_Keep.s
```

DDR.Write.Data来自旧数组的cluster。W_Select_Clear输出只去右寄存器；如果把它接DDR.Data，在写入与清零同拍时就可能提交零数组。

如果DDR.Write还有Byte Enables端子，按它实际类型创建常量，使全部160字节有效；若是Boolean数组则长度160且各项True。不要把一个Boolean True硬接到一个160元素数组端子。可选错误输出接单独错误指示器，不代替VHDL的fault_code。

## 5. 读循环：先请求，再接返回入FIFO

在READ_125M内放同一个`DDR_Waveform`的`Request Data`与`Retrieve Data`两个节点。放`FIFO_DDR_Prefetch.Write`和`.Read`两个节点；它们指向同一预取FIFO资源。

放两个独立Boolean Feedback，都是1拍、初值False：`R_Request_Ready_Delay`和`R_Prefetch_Ready_Delay`。

| 编号 | 来源 | 目的 |
|---|---|---|
| R01 | ReadCtrl.request_address | DDR.Request Data.Address |
| R02 | ReadCtrl.request_valid | DDR.Request Data.Input Valid |
| R03 | DDR.Request Data.Ready for Input | R_Request_Ready_Delay.input |
| R04 | R_Request_Ready_Delay.output | ReadCtrl.ddr_request_ready_now |
| R05 | ReadCtrl.retrieve_ready | DDR.Retrieve Data.Ready for Output |
| R06 | DDR.Retrieve Data.Output Valid | ReadCtrl.ddr_retrieve_valid，使用R_Return_Feedback节点 |
| R07 | DDR.Retrieve Data.Data | FIFO_DDR_Prefetch.Write.Element |
| R08 | ReadCtrl.prefetch_write_valid，使用R_Enqueue节点 | FIFO_DDR_Prefetch.Write.Input Valid |
| R09 | FIFO_DDR_Prefetch.Write.Ready for Input | R_Prefetch_Ready_Delay.input |
| R10 | R_Prefetch_Ready_Delay.output | ReadCtrl.prefetch_write_ready_now |

**R06不分支到FIFO.Write.Input Valid。** 这个使能必须由R08提供，因为Abort排空时DDR仍会返回旧数据，但控制器要把它丢弃。

Request/Retrieve方法必须对应同一个Memory和匹配的读接口，并位于同一个125MHz读循环中；不要误选另一块同名或不同bank的Memory。

## 6. 从预取FIFO取出40点，并保存在Current_Array

在READ_125M里再放：`Cluster To Array`（R_ClusterToArray40）、两个Select（R_Select_Load、R_Select_Clear）、一对`Current_Array`移位寄存器。

同样在该循环外建立独立的`R_Zero40`：Initialize Array，U32零，长度40。分支1接左Current_Array外侧初始化端；分支2进入循环，接R_Select_Clear.t。

| 编号 | 来源 | 目的 |
|---|---|---|
| R11 | ReadCtrl.prefetch_read_enable | FIFO_DDR_Prefetch.Read.Ready for Output |
| R12 | FIFO_DDR_Prefetch.Read.Output Valid | ReadCtrl.prefetch_read_valid，使用R_Pop_Feedback节点 |
| R13 | FIFO_DDR_Prefetch.Read.Element | R_ClusterToArray40.cluster |
| R14 | R_ClusterToArray40.array | R_Select_Load.t |
| R15 | ReadCtrl.current_load，使用R_Array_Control节点 | R_Select_Load.s |
| R16 | 左Current_Array内部输出 | R_Select_Load.f；**还分支到第7节Array Subset.array** |
| R17 | R_Select_Load.output | R_Select_Clear.f |
| R18 | ReadCtrl.current_clear | R_Select_Clear.s |
| R19 | R_Zero40的循环内分支 | R_Select_Clear.t |
| R20 | R_Select_Clear.output | **右Current_Array** |

`current_clear`为True时清零优先；否则current_load为True装新块；否则保持旧块。无需再加一个Reset Case，清零条件已由控制器给出。

不要把FIFO.Read.Output Valid直接当current_load替代R15。正常弹出和Abort丢弃都会有Output Valid，只有控制器知道本拍应装入还是丢弃。


## 7. 四点播放器：接到后续Sync的专用FIFO

这里的数据路径在LabVIEW里。VHDL的stream_word0～3是**输入**，用于检查已发送的数据；它们不是四个数据输出口。

本节选用第2节的FIFO_Sync_Input：每个元素是4个U32组成的cluster，写一次/读一次都是一个cluster。若你已有的Sync输入FIFO采用U32、每次4元素，保留它的结构，并按本节末尾的等价改法接线。

### 7.1 先拿出本拍的四点

在READ_125M内部放：

1. Array Subset，命名R_Subset4。
2. Index Array，展开到4个输出，索引分别接常量0、1、2、3。
3. Array To Cluster，右键设置Cluster Size为**4**。
4. FIFO_Sync_Input的Write方法。
5. 一个Boolean Feedback，命名R_Sink_Ready_Delay，延迟1拍、初始化False。

接线如下：

| 编号 | 来源 | 目的 |
|---|---|---|
| R21 | 左Current_Array内部输出，即R16的分支 | R_Subset4.array |
| R22 | ReadCtrl.stream_offset | R_Subset4.index |
| R23 | 整数常量4 | R_Subset4.length |
| R24 | R_Subset4输出的4-U32数组 | **分两支**：Index Array.array、Array To Cluster.array |
| R25 | Index Array索引0的数据 | ReadCtrl.stream_word0 |
| R26 | Index Array索引1的数据 | ReadCtrl.stream_word1 |
| R27 | Index Array索引2的数据 | ReadCtrl.stream_word2 |
| R28 | Index Array索引3的数据 | ReadCtrl.stream_word3 |
| R29 | Array To Cluster输出的4-U32 cluster | FIFO_Sync_Input.Write.Element |
| R30 | ReadCtrl.stream_fire | FIFO_Sync_Input.Write.Input Valid |
| R31 | FIFO_Sync_Input.Write.Ready for Input | R_Sink_Ready_Delay.input |
| R32 | R_Sink_Ready_Delay.output | ReadCtrl.stream_ready |

请把分支画成下面这样：

```text
左Current_Array ─┬→ R_Select_Load.f
                └→ Array Subset（index=stream_offset，length=4）
                       │
                       ├→ Index Array[0] → ReadCtrl.stream_word0
                       │              [1] → ReadCtrl.stream_word1
                       │              [2] → ReadCtrl.stream_word2
                       │              [3] → ReadCtrl.stream_word3
                       │
                       └→ Array To Cluster，Size=4 → FIFO_Sync_Input.Write.Element

ReadCtrl.stream_fire ────────────────────────────→ FIFO_Sync_Input.Write.Input Valid
ReadCtrl.stream_ready ← Feedback，1拍、初值False ← FIFO_Sync_Input.Write.Ready for Input
```

stream_offset已经是0、4、8……36，不要再乘4。这里同样取**左侧旧Current_Array**：一个块最后四点输出的同时，右Current_Array可能装入下一块，两者不会混用。

R30必须用stream_fire，不能换成stream_valid。当前VHDL定义stream_fire=stream_valid AND stream_ready；它在输出FIFO已承诺接收的拍上才推进样本计数和偏移。stream_valid可接一个监视指示器，不参与这个NI FIFO的写使能。

### 7.2 Sync在另一个循环怎样取

在后续Sync自己的循环内放**同一个FIFO_Sync_Input资源**的Read节点：

| 来源 | 目的 | 说明 |
|---|---|---|
| Sync本拍确实能接收一组4点的许可 | FIFO_Sync_Input.Read.Ready for Output | 这是消费许可；Sync会暂停时不能接常量True |
| FIFO_Sync_Input.Read.Output Valid | Sync的输入有效端 | 只有这拍有效，Sync才处理本组 |
| FIFO_Sync_Input.Read.Element | Unbundle拆成4个U32，再接Sync的4路数据输入 | 顺序必须是word0、word1、word2、word3 |

如果Sync数据输入是128位总线而非4个U32，须按Sync实际位序装配；当前DDR模块不定义Sync的高低位拼接方式。如果Sync接收I16/Q16，也要按已有Sync合同拆分U32中的I/Q，不做额外数值缩放。

这里没有冒充已核对过远端Sync端口名：“Sync输入有效”“Sync接收许可”描述的是端口作用，最终名称及帧开始/结束等边带，要以你实际Sync入口为准。新版ReadCtrl提供stream_first/last，按新版说明与数据原子传递，不能用read_done替代last。

如果Sync使用普通“本拍ready、本拍valid”的RTL握手，接收许可直接来自本拍ready；如果它也是NI“Ready for Input承诺下一拍”的节点，则在**Sync所在循环内**先延迟一次该Ready，再用作FIFO.Read.Ready for Output。不要把NI下一拍许可与普通RTL同拍ready混用。

若两个循环不同钟，使用支持这两个时钟域的NI Target-Scoped FIFO及其跨域配置；数据、valid和ready不能用普通线直接跨时钟域。若相同钟，也只能放一个读取该FIFO的消费者。

**等价配置**：如果FIFO_Sync_Input已经配置为单元素U32、每次Write/Read为4元素，那么R_Subset4数组直接接Write.Element，去掉第7.1节的Array To Cluster；读取侧得到4-U32数组，改用Index Array拆分。其余握手和分支不变。不要把这两种FIFO配置的Element端类型混着接。

## 8. 还没接Sync时，可以选择DMA回读出口

这一节是可选替代出口，不是主链必须新增的FIFO。如果你当前只想在Host查看DDR读出的波形，使用FIFO_T2H_Readback替代第7节的FIFO_Sync_Input.Write：

- FIFO类型：Target to Host DMA。
- 单元素类型：U32；若你的目标属性只提供FXP，则无符号、Word Length=32、Integer Word Length=32。
- FPGA端Number of Elements Per Write=4。
- FPGA端Requested Depth=4096个U32；Host端Configure请求65536个U32。这两个深度是建议起点，不是RTL常量。
- FIFO接口启用握手。

接线只改三处：

| 原来的连接 | DMA替代连接 |
|---|---|
| 四点数组→Array To Cluster4→Sync FIFO.Write.Element | 四点数组→T2H.Write.Element，Element必须是4元素数组 |
| stream_fire→Sync FIFO.Write.Input Valid | stream_fire→T2H.Write.Input Valid |
| Sync FIFO.Write.Ready for Input→R_Sink_Ready_Delay | T2H.Write.Ready for Input→同一个R_Sink_Ready_Delay |

四点数组到stream_word0～3的检查分支保持原样。Host侧使用同一个DMA资源的Read方法，读取结果是U32数组。

不要把一个stream_fire同时扇出到两个可独立堵塞的FIFO，然后只接其中一个Ready；那不能保证两边都收到同一组数据。当前教程在“送Sync”与“DMA回Host”中选择一个出口。真正双路同时广播需要单独设计接收确认与缓存。

Host应在读任务运行期间持续读取T2H，不能等read_done后才开始读。如果帧长大于缓冲容量，等完成才读会形成相互等待。Sync出口同理，必须有实际消费者；只放FIFO.Write不放Read，FIFO满后播放器会正常停住。

## 9. 状态输出逐个接哪里

VHDL输入必须按本教程接好；只用于监视的输出可以不放对应I/O节点。若放了，就分别接前面板指示器，不要接回控制端。状态指示器的终端放在对应SCTL内。多个CLIP的fault_code、command_rejected同名，指示器用W_/R_前缀区分。

### 9.1 UploadCtrl监视输出

| VHDL输出 | 指示器建议名 | 类型/意义 |
|---|---|---|
| loaded_samples | W_Loaded_Samples | U32，已从H2T消费的样本数 |
| load_state | W_Load_State | U8，状态编号 |
| load_busy | W_Busy | Boolean |
| load_done | W_Done | Boolean，本轮DDR提交完成 |
| load_fault | W_Fault | Boolean |
| fault_code | W_Fault_Code | U8 |
| load_generation | W_Generation | U32，已接受装载命令代号 |
| command_rejected | W_Command_Rejected | Boolean |
| load_cycles | W_Load_Cycles | U64 |
| data_window_cycles | W_Data_Window_Cycles | U64 |
| receive_cycles | W_Receive_Cycles | U64 |
| write_cycles | W_Write_Cycles | U64 |
| fifo_empty_cycles | W_FIFO_Empty_Cycles | U64 |
| ddr_stall_cycles | W_DDR_Stall_Cycles | U64 |
| pause_cycles | W_Pause_Cycles | U64 |

ddr_write_address已在W05分支到W_Written_Words。装载过程中它是下一写地址；完成时它等于累计提交的DDR块数，因此不要把“写入过程中显示的地址”误当成当前拍已经提交的块数。

fifo_read_enable、pack_offset、pack_clear、ddr_write_valid、ddr_write_address五个控制输出已经在第4节全部接完，无需再建立另一组控制线。

### 9.2 ReadCtrl监视输出

| VHDL输出 | 指示器建议名 | 类型 |
|---|---|---|
| read_state | R_Read_State | U8 |
| read_busy | R_Busy | Boolean |
| read_done | R_Done | Boolean |
| read_fault | R_Fault | Boolean |
| fault_code | R_Fault_Code | U8 |
| read_generation | R_Generation | U32 |
| command_rejected | R_Command_Rejected | Boolean |
| requested_words | R_Requested_Words | U32 |
| returned_words | R_Returned_Words | U32 |
| enqueued_words | R_Enqueued_Words | U32 |
| popped_words | R_Popped_Words | U32 |
| sent_samples | R_Sent_Samples | U32 |
| total_cycles | R_Total_Cycles | U64 |
| replay_cycles | R_Replay_Cycles | U64 |
| transfer_cycles | R_Transfer_Cycles | U64 |
| no_data_cycles | R_No_Data_Cycles | U64 |
| sink_stall_cycles | R_Sink_Stall_Cycles | U64 |
| pause_cycles | R_Pause_Cycles | U64 |
| checked_samples | R_Checked_Samples | U32 |
| mismatch_count | R_Mismatch_Count | U32 |
| first_error_index | R_First_Error_Index | U32 |
| first_error_expected | R_First_Error_Expected | U32 |
| first_error_actual | R_First_Error_Actual | U32 |
| stream_valid | R_Stream_Valid | Boolean，仅观察播放器是否有待发送数据 |

pattern_check_enable=False时，检查器统计不能用于判断真实波形正确。当前真实波形先用False；只有明确发送与RTL所定义的递增模式一致的数据时才启用。

request_valid、request_address、retrieve_ready、prefetch_write_valid、prefetch_read_enable、current_load、current_clear、stream_offset、stream_fire已在第5～7节接完。

Host轮询看不到125MHz的每个瞬时变化；以generation变化以及保持的Done/Fault和结果计数判断一轮任务。单拍控制脉冲即使接LED，也不保证人眼或Host轮询能看到。

## 10. Host VI按什么顺序操作

这一节是将来在你远端工程运行时的操作说明，本轮没有进行NI编译、仿真或板测。

本节仅保留手工观察步骤；正式启动、互斥及跨域以[会话补充](LABVIEW_RUNTIME_CONFIG_AND_SESSION_ZH.md)为准。不能同时连接旧Host直接W/R命令和新会话控制；60324是短示例，不是生产帧。

### 10.1 明确样本数和DDR块数

一个U32是当前DDR合同中的一个样本。它可以携带已经打包的I/Q位模式；Host应保持现有位序，不把一个复样本擅自拆成两个U32。

两模块都设置：

- sample_count=N：实际有用的U32样本数，必须大于0且是4的倍数。
- ddr_capacity_words=C：允许使用的DDR逻辑元素，不超过实际分配。
- ddr_word_count=M=ceil(N/K)：必须在1～C，默认K=40。
- 写入端和读取端的N、M必须一致。

例如N=60324，则M=1509。最后一个DDR块只有4个有用U32，其余由Pack_Array清零；Host只发送N个U32，不需要发送补到M×40的零。读播放器也只输出N个U32。

### 10.2 正常首次装载

1. Host打开FPGA VI引用。使用该引用配置FIFO_H2T的Host侧深度为65536个元素，并检查Configure返回的实际深度。若选择T2H出口，对T2H也配置Host深度。DMA配置、启动和Host读写都在Host VI，不在FPGA的SCTL里。
2. 将命令Load/Read/Rearm/Abort全部置False；W_Run_Enable、R_Run_Enable置True。若需要复位两个控制器，先置W_Reset、R_Reset=True，再置False；控制器复位不清理NI FIFO/DRAM未完成访问。
3. 确认是一个外部队列已干净、没有旧DDR读响应的会话；同时等两个时钟域内的dram_ready有效。首次启动也必须依据实际资源初始化状态，不能仅凭Reset=true就认定队列已清空。
4. Host分别写W_Sample_Count=N、W_DDR_Word_Count=M，以及R_Sample_Count=N、R_DDR_Word_Count=M。用Host执行顺序保证参数写入先于命令上升沿；不要通过150MHz循环到125MHz循环的普通多位连线传这些参数。
5. 将R_Pattern_Check_Enable=False；R_Pattern_Seed=0。真实波形模式不启用递增模式检查。
6. 在确认没有DDR读任务、旧响应或残留FIFO数据后，将W_New_Session_Safe=True。它是外部确认，不是控制器替你检测出的状态；不能简单接NOT W_Busy，也不能用它当清空FIFO的命令。
7. 先记录W_Generation。让W_Load从False变True。观察W_Generation增加说明该轮命令被接受；随后把W_Load恢复False，供下一次产生新的上升沿。不能同时给Rearm上升沿。
8. Host调用FIFO_H2T.Write，发送恰好N个U32。可以分块发送，例如每块4096个、最后一块发送剩余；本例最后2980个。Host一批发送的长度不等于FPGA每拍读取数量，FPGA仍每次取4个。
9. 不要先等待W_Done再发送Host数据；没有输入数据，装载自然不能结束。Host各DMA调用使用有限超时并检查返回错误，发生部分传输/超时时保留计数与状态，不盲目把整帧重发到非空FIFO。
10. 等待本轮W_Done且无W_Fault，核对W_Loaded_Samples=N、W_Written_Words=M。写入完成前不开始读取同一片DDR地址。

若write fault发生在Host尚未发送完时，先停止继续送新数据。重新开始之前必须处理残留DMA数据，不能靠控制器Reset把新旧帧分开。

### 10.3 启动读取

1. 确认这一轮DDR装载已经完成，而且整个读取过程中Host不会启动覆盖同一区域的新装载。
2. 确认FIFO_DDR_Prefetch为空、没有旧请求/响应；输出FIFO中也没有会被下游误认成新帧的旧数据。
3. Sync消费者准备好；若选T2H出口，则准备好Host持续读取。可以用Host并行分支接收数据，控制分支监视Done/Fault。
4. 将R_New_Session_Safe=True。记录R_Generation，然后R_Read从False变True；generation增加后把R_Read恢复False。
5. 正常无故障完成时核对：R_Requested_Words、R_Returned_Words、R_Enqueued_Words、R_Popped_Words均为M，R_Sent_Samples=N。
6. R_Done只表示DDR读模块已经把N个样本交给输出接口。它不表示FIFO_Sync_Input已被读空，不表示Sync计算结束，也不表示T2H数据已经全部到达Host。
7. 下一个会话必须根据下游自己的完成/排空状态来决定。不能把R_Done直接当作整个系统可复位或下一帧可任意覆盖的许可。

本教程先采用“写完一帧，再读这一帧”的外部调度。两个SCTL同时运行，不代表允许它们同时访问同一段数据进行覆盖写和读取。

### 10.4 暂停、取消和重新开始

正常接线中SCTL继续运行，只用run_enable暂停控制器；不要为了暂停数据流而停时钟或停止SCTL。ReadCtrl暂停后仍可能接收已发出的DDR响应，这是设计要求。

Abort后的读控制器需要排空旧请求响应及预取FIFO；不要立刻停止READ_125M。已经进入下游Sync FIFO的数据归下游处理，读控制器不会回收它。两个控制器的reset也不会清空NI资源。

如出现故障，保留fault_code和计数，按实际资源支持的停止/清理流程处理完旧数据，再提供new_session_safe并Rearm。这里不编造远端资源的FIFO清空方法，也不把循环停止/Reset当作通用清理手段。

## 11. 最后按这张表检查接线

| 检查项 | 正确结果 |
|---|---|
| H2T每次FPGA读取 | 4个U32，不是1个，不是40个 |
| Prefetch每个元素 | 40个U32组成的1280位cluster；一次读写1个cluster |
| Prefetch深度 | 实际至少256个1280位元素；不是256个U32 |
| Array To Cluster | DDR处Size=40，Sync FIFO处Size=4；不是默认值 |
| DDR.Write.Data | 来自左Pack_Array，经Array To Cluster40 |
| 四点数组 | 来自左Current_Array，经Subset(index=stream_offset,length=4) |
| Pack/Current右侧寄存器 | 只接相应Select_Clear输出，保存下一拍值 |
| 写入FIFO有效的来源 | H2T.Output Valid分支到核心与W_Select_Keep |
| 返回预取FIFO写使能 | prefetch_write_valid，不是裸Retrieve.Output Valid |
| 下游FIFO写使能 | stream_fire，不是stream_valid |
| Ready Feedback | DDR.Write、DDR.Request、Prefetch.Write、输出FIFO.Write各自延迟一次，初值False |
| 偏移 | pack_offset与stream_offset都已经以U32元素为单位，不再乘4 |
| CLIP与对应SCTL | 同一个实际时钟源；本接口约定没有额外I/O同步拍 |
| Reset与FIFO | 控制器Reset不是FIFO清空 |
| FIFO消费者 | Prefetch只有ReadCtrl这一条消费路径；Sync读另一只输出FIFO |
| 状态 | W_Done/R_Done保持的模块结果，不等于全链路处理完毕 |

当前结构含40-U32数组的动态写入和4点选择，以及NI节点到CLIP的组合控制路径。上述连线描述的是现有RTL的逻辑接口合同，尚未证明远端工程在150MHz/125MHz下能通过实现时序；不能随意在中间加一拍“修时序”，因为数据、许可、偏移和计数会失去对齐。后续若工具暴露真实路径问题，应一并设计相应流水与缓存。

## 12. 依据、适用范围与后续对齐

本说明逐项依据本工程的ddr_upload_ctrl.vhd、ddr_read_ctrl.vhd和静态审查报告整理。DDR宽1280、远端已有Target/DRAM/FIFO，是用户本轮明确提供的事实；远端LabVIEW版本、节点截图及Sync实际输入合同尚未查看。

当前接线要求NI节点确实提供本文的握手端子。如果你打开的节点只显示Timeout/Timed Out，先核对FIFO Interface/Handshaking及节点所在循环类型；不要把NOT Timed Out直接替代本文Output Valid。菜单措辞随版本变化，应以Context Help显示的端口作用与类型对齐。

NI官方参考（用于LabVIEW通用节点/资源行为，不是本项目运行通过的证据）：

- [NI：FIFO多元素接口设置](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z0000019UZ3SAM&l=en-US)：Interfaces设置每次元素数，具体支持取决于目标。
- [NI：DMA的Host端与FPGA端缓冲](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z0000019KwbSAE&l=en-US)：两个深度分开配置。
- [NI：High-Performance FPGA Developer’s Guide](https://download.ni.com/pub/gdc/tut/labview_high-perf_fpga_v1.1.pdf)：印刷页38～40的四线握手与Ready for Input下一拍许可说明。
- [NI：LabVIEW FPGA DRAM使用介绍](https://www.ni.com/en/support/documentation/supplemental/13/introduction-to-using-dram-with-ni-fpga-devices.html)：DRAM资源及访问方法。
- [NI：自定义类型DRAM的示例说明](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA03q000000YSChCAO&l=en-US)：DRAM数据类型与缓冲资源配置参考。

相关本地文件：

- [Upload RTL](D:/008_MA_Dev/Sync_DDR/rtl/ddr_upload_ctrl.vhd)
- [Read RTL](D:/008_MA_Dev/Sync_DDR/rtl/ddr_read_ctrl.vhd)
- [静态设计审查](D:/008_MA_Dev/Sync_DDR/reports/review/STATIC_DESIGN_REVIEW_20260917_ZH.md)

本轮仅新增说明文档，未修改RTL、TB、XDC或历史证据，没有启动EDA/NI编译/板测。写入和读取行为仿真仍未验证。

对齐时优先确认三件事：H2T属性中的单元素类型与Elements Per Read；Prefetch的1280位元素类型、实际深度和单元素读写；Sync入口接收的是4-U32数组、4-U32 cluster还是128位总线，以及是否支持背压。完成这三项就能确定本文哪些转换节点直接适用。



