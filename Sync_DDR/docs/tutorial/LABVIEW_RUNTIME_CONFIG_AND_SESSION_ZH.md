# DDR新版端口与顺序Target VI接线补充（2026-09-17）

本文件对应本次修改后的两份VHDL，替代旧教程的容量、Host直接命令和会话控制部分。数据通路继续参考[逐根接线教程](LABVIEW_TARGET_VI_STEP_BY_STEP_ZH.md)。远端VI/CLIP由用户创建，本地不生成XML。

## 1. 单位、编译参数和Host配置

两个实例都用同一个DDR_WIDTH_BITS，默认1280，必须是128的正整数倍。K=DDR_WIDTH_BITS/32。默认Pack_Array、Current_Array及DDR/FIFO元素均40个U32；640配置全部改为20个。每拍输出始终4个U32。
NI规格列每bank LabVIEW DRAM总线640 bit；用户的1280 bit逻辑元素仍需核对Memory数据类型和聚合方式，不把1280称为已确认的单bank原生端口。[NI规格](https://www.ni.com/docs/en-US/bundle/pxie-7903-specs/page/specs.html)

| 配置 | 类型 | 单位/规则 | 完整窗口示例 |
|---|---|---|---|
| C / DDR_Capacity_Words | U32 | 允许寻址的DDR逻辑元素，不超过实际分配 | 65536 |
| N / Sample_Count | U32 | 有效复样点，含真实前后保护数据；正数且4对齐 | 1336860 |
| M / DDR_Word_Count | U32 | ceil(N/K)，不是字节或128bit组数 | 33422 |
| Word_Bits（Host记录） | U32常量 | 等于两个实例编译参数，非运行时宽度开关 | 1280 |
| Segment_Tag（会话管理使用） | U32 | 装载版本，防止旧完成事件误认新任务 | 每次装载递增 |

Host用U64临时量计算(N+K-1)/K并检查后转换U32，避免加法溢出。N最大0xFFFFFFFC；C可大于65536，但一段长度仍受N端口约束。更大C不增加FIFO深度，也不会实际重新分配Memory。
当前SFO窗口已含前后保护，不重复添加201点。默认完整窗口最后一块20点有效、20点填零；Host只传N点。泛化完整采集段还需满足Sync对检测位置和保护范围的要求。

## 2. 新端口与分支

| 端口 | 方向（以VHDL为参照） | 来源/去向 |
|---|---|---|
| UploadCtrl.ddr_capacity_words | U32输入 | 写循环锁存的W_Descriptor.C |
| ReadCtrl.ddr_capacity_words | U32输入 | 已成功装载的Valid_Descriptor.C |
| ReadCtrl.stream_first | Boolean输出 | 当前首组四点的段首边带 |
| ReadCtrl.stream_last | Boolean输出 | 当前末组四点的段尾边带 |

N/M从同一描述符分支，不能分别读取运行中改变的Host控件。new_session_safe为本域启动/清理许可，不是Memory.Ready。首尾以stream_valid限定，N=4时first/last同时True；read_done不能当作last。

### 同域直接接Sync

1. 当前四点数据分两支：到Sync数据输入，以及ReadCtrl.stream_word0..3自检观察端。
2. stream_valid到Sync有效输入；Sync.ready回stream_ready。此同域同拍ready不额外延迟。
3. stream_first/last分别接Sync段首/段尾。它们不是同步算法检测的OFDM帧边界。
4. Sync若无边带接口，通过其现有段命令设置长度并等准备完成，不修改其他Sync工程。

### 通过FIFO接Sync

若需要传首尾，FIFO单元素改为cluster {Data:4-U32 cluster, First:Boolean, Last:Boolean}，每次读写一个，深度1024。四点和first/last进同一个Bundle，其唯一输出连FIFO.Write.Element；Input Valid接stream_fire。
FIFO.Write.Ready for Input按NI合同经过一次Feedback（初值False）接stream_ready。读端一次Unbundle取得对齐的数据与标志；跨域使用NI支持的独立时钟FIFO，标志不能绕过FIFO直连。
额外2bit边带使净容量成为16640字节（16.25KiB）。实际资源以NI编译为准，单向64块BRAM36仍仅规划额度。
若现有Sync只接受数据并按配置N计数，可保持原FIFO，首尾只在播放器边界观察；不能跨域单独采样标志来恢复对齐。

## 3. Target VI唯一会话控制者

将会话Case Structure和状态移位寄存器放在READ_125M，与ReadCtrl同域；WRITE_150M保留独立循环，两循环始终运行。
只保留一个Host提交入口。旧W_Load/R_Read等控件不能继续直接驱动核，否则可绕过互斥。DDR容量始终只有一段，不做双缓冲。

两条小型独立时钟控制FIFO：

| FIFO | 方向 | 原子元素 | 建议深度 |
|---|---|---|---|
| FIFO_Write_Command | 125写、150读 | cluster {Operation U32, Tag U32, N U32, M U32, C U32} | 4 |
| FIFO_Write_Status | 150写、125读 | cluster {Tag U32, Code U32, Loaded U32, Submitted U32} | 4 |

Code区分WRITE_ACCEPTED_ALL、FAULT、CLEANUP_ACK；WRITE_ACCEPTED_ALL不是物理DDR写完成。控制FIFO资源纳入既有规划余量，本地行为测试不验证NI跨域实现。
ReadCtrl在125MHz本地，不需要跨域读命令FIFO。Host先稳定配置，再提交请求序号；Target获取快照并确认，确认前Host不改变参数。多次Host寄存器写必须保证先参数后提交的执行顺序，多位配置不能逐位同步。

| 状态 | 事件/动作 | 下一状态 |
|---|---|---|
| EMPTY | 合法Load：撤销旧有效段，锁存描述符，成功发送装载消息 | LOADING |
| LOADING | 同Tag的WRITE_ACCEPTED_ALL，且Loaded=N、Submitted=M | WRITE_DRAIN |
| WRITE_DRAIN | NI实际写后读顺序/完成条件成立 | AVAILABLE |
| AVAILABLE | 只Read：复用有效描述符，Sync准备完成后启动读核 | REPLAYING |
| AVAILABLE | 只Load：撤销旧描述符，发送新装载消息 | LOADING |
| REPLAYING | 本次generation已确认；read_done及N/M计数吻合 | AVAILABLE |
| 任一状态 | 同时Load/Read，或忙时新请求 | 拒绝，不排队、不改变活动状态 |
| 活动状态 | 取消/错误 | 有效段失效，进入FAULT，清理后才可回EMPTY |

read_done允许释放DDR读取占用，但不自动复位Sync或清下游FIFO；下一次回放仍须等待Sync允许新段。重复回放不改变段Tag。
new_session_safe只有本域拥有许可且旧事务清理后才能置True，不能用异步的not other_busy替代。

### 写循环适配步骤

1. IDLE时从Command FIFO取一条消息，完整锁存到W_Descriptor；检查Operation和Tag。
2. 下一迭代将N/M/C分支到UploadCtrl三个配置端，load_command保持False。
3. 再下一迭代在本地许可成立时拉高load_command一拍后恢复False，进入WAIT_RESULT。
4. 先观察本次busy/响应，再识别done/fault，避免旧done被误认。初始化新增CALC/CHECK两拍；generation仅参数通过后增加。
5. 无错完成且Loaded=N、Submitted=M时，把同Tag结果放进消息寄存器；valid保持直到Status FIFO成功接收，不使用易丢失的单拍完成脉冲。
6. 故障保留fault_code并发FAULT状态。Abort/Rearm也走控制消息，不从125MHz直拉异步脉冲；未清理旧事务不接收下一装载。

### 读循环启动步骤

1. AVAILABLE中的Valid_Descriptor.N/M/C同时连ReadCtrl和诊断显示，Host不能独立修改这份读配置。
2. 根据Sync现有协议设置新段长度、准备内部状态，等待ReadyForSegment。
3. 在本地许可成立时使read_command先False再True一拍；记录原generation，等待新generation或fault，期间拒绝Load。
4. 回放时SCTL、NI响应和FIFO持续运行；ready控制常规背压，run_enable为独立暂停。
5. read_done且计数吻合后回AVAILABLE；错误进入FAULT。旧响应必须排空或经平台实际清理后才能恢复。

## 4. 写后读平台保证

[NI DRAM说明](https://www.ni.com/en/support/documentation/supplemental/13/introduction-to-using-dram-with-ni-fpga-devices.html)说明Write握手提交请求，读请求和响应分离。“按接收顺序处理”的文字针对读取请求，不能据此证明两个异步访问器的全部写已经物理完成。
当前未找到足以给7903这组150/125MHz访问器直接背书的写完成保证。远端实际Memory帮助/接口说明需确认：后发读请求是否保证看到已接受写入；若有完成/排空机制，应使用真实机制产生WriteVisible。
确认前WRITE_DRAIN不接常数True，也不用任意固定等待代替。此平台条件不妨碍控制器行为短测，但完整Target VI集成不能宣称通过。

## 5. 状态与计数

| 核 | 原状态码保持 | 新状态 |
|---|---|---|
| Upload | 00等待、01装载、02写请求全提交、03故障 | 04 CONFIG_CALC、05 CONFIG_CHECK |
| Read | 00等待、01预取、02当前块装入、03回放、04排空、05完成、06故障 | 07 CONFIG_CALC、08 CONFIG_CHECK |

命令接受沿锁存参数，后两拍计算和验证；busy包括配置状态，非法配置无外部传输。暂停可延后，取消/DDR失效优先。generation只在合法配置后增加，高电平保持不重复启动。
load_cycles统计LOADING，读total_cycles统计预取/装入/回放/排空，不包括两拍配置。首结果延迟另含预取等待，不能固定承诺。
故障码01参数、02DDR失效、03取消；写核取消优先于DDR失效，读核DDR失效优先于取消，均优先于暂停。Reset仅清核心，不能替代NI资源清理。
