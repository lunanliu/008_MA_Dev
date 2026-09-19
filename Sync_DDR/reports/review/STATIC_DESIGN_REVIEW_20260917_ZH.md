# DDR 读写控制器静态设计审查

2026-09-17；负责人：当前独立任务 `01a0afdf-cd3a-7e91-afc8-6a947ec3cc71`。
本轮只审查设计和接口；未修改 RTL、TB、XDC、执行脚本或历史，未启动 EDA、仿真或其他原生验证。这是作者自审，不是外部独立复核。

**结论：在现有文档约定的“先装载、后回放，LabVIEW 保存数据，两核各自与 NI 节点同源时钟”的结构下，两模块的核心状态、计数和握手逻辑基本自洽，能够表达所需的 DDR 写入与读取流程。本轮没有发现要求立即改写状态机的明确功能错误。可以继续使用这个设计，但尚不能把实际 LabVIEW 接入、仿真或物理时序标为通过。**

最需要明确的不是更多测试项，而是数据通路的归属：这两个 VHDL 是控制器，DDR/FIFO/40 点数组实际保留在 LabVIEW；读控制器同时包含预取和四点播放器。若 Sync 希望通过 FIFO 取得输入，按现有设计应让四点播放器写入另一个供 Sync 读取的 FIFO。不能让 Sync 与当前控制器同时消费同一个 `FIFO_DDR_Prefetch`。

## 1. 实际结构与适用条件

```text
写侧，150 MHz 同源 SCTL：
Host → H2T FIFO（每次4个U32）→ Pack_Array寄存器（40个U32）
     → NI DDR.Write（每地址40个U32）
       ↑ VHDL提供读使能、打包位置、写地址、写使能和清零控制

读侧，125 MHz 同源 SCTL：
NI DDR.Request → NI DDR.Retrieve → FIFO_DDR_Prefetch（256个40-U32块）
     → Current_Array寄存器（40个U32）→ 每拍最多4个U32
     → 同域Sync输入，或另一个Target-Scoped FIFO → Sync
       ↑ VHDL同时管理请求、返回入队、出队、换块和四点输出
```

以上是代码和已有接线说明中的结构；工程目录没有实际 `.vi/.lvproj`，所以不能据此声称实际框图已按图连接。

| 项目 | 当前合同与代码核对 |
|---|---|
| 器件 | `xcvu11p-flgb2104-2-e`；本轮不运行器件工具 |
| 时钟 | 写侧150 MHz，周期约6.667 ns；读侧125 MHz，周期8 ns；每个控制器仅有一个时钟输入 |
| 数据解释 | 一个U32保存一对I16/Q16的位模式；控制器不做数值换算 |
| 长度 | `N>0`、`N mod 4=0`、`M=ceil(N/40)`、`1≤M≤2048`；代码中的两个64位不等式与该M关系等价，最大N为81920 |
| DDR分配 | 每地址160字节，2048地址共320 KiB；地址是块索引0至M−1，不是U32样本地址或字节地址 |
| 预取FIFO | 实际至少256个40-U32块，共40 KiB数据；启动预取阈值为`min(128,M)` |
| 工作顺序 | 两核没有互相观察busy/done，也没有共同仲裁状态机；先写后读、禁止读取时覆盖波形由外部会话控制保证 |
| 配置/命令 | 先稳定N、M等配置，再发命令上升沿；启动后锁存配置；高电平保持不会重复触发；被拒命令不排队 |

## 2. 写侧：状态与寄存器

对应 `rtl/ddr_upload_ctrl.vhd:74`、`:95`、`:159`。

| 状态/事件 | 允许操作和寄存器更新 | 下一状态 |
|---|---|---|
| WAIT_LOAD，合法load上升沿 | 锁存N/M；清地址、已收样本、组号、pending；generation加1；清Pack_Array | LOADING |
| LOADING，pending=0，FIFO成功读出 | Pack_Array在`4×group_q`位置收4点；`loaded_q+=4`；未满则group加1；满40点或达到N则pending置1 | LOADING |
| LOADING，pending=1但DDR无许可 | 不再读H2T；数组、地址、进度保留 | LOADING |
| LOADING，DDR接受一块 | 使用当前旧数组及旧地址写DDR；`address_q+=1`；group/pending清零；下一拍数组清零 | 最后一块则DONE，否则LOADING |
| LOADING，暂停 | 停止H2T读取与DDR提交，保留进度；暂停不屏蔽abort或DRAM故障 | LOADING或FAULT |
| LOADING，abort或DRAM失去ready | 停止新传输，保留故障；abort与ready丢失同时出现时写侧优先记录code3 | FAULT |
| DONE | 保持完成状态；新的合法load可以直接开始下一次装载 | LOADING或DONE |
| WAIT/DONE/FAULT，合法rearm | 清工作状态和数组，保留generation；不清外部FIFO/DDR | WAIT_LOAD |
| reset | 同步清核心寄存器与数组；命令历史仍采样，解除reset不把保持高的命令当新命令 | WAIT_LOAD |

核心寄存器职责清楚：`loaded_q`是收到的真实样本数，`address_q`是已提交的DDR块数，`group_q`是当前块内四点组号，`pending_q`表示当前数组待提交。接收和提交分别要求pending=0/1，所以同一拍不会既修改Pack_Array又提交该块。

以N=44、M=2静态推演：先收10组组成40点，在下一次写许可时提交地址0；清零数组后再收4点，提交地址1，剩余36点维持零。最后一次写请求被接口接受后进入DONE。`load_done`表示全部写请求已提交，不是本控制器观察到了DDR物理写完成；本控制器没有这种完成输入。

关键连接：DDR.Data必须接**左侧旧Pack_Array**，清零Select只能接右侧下一拍寄存器。否则写使能与清零同拍时会把零块写入DDR；这是接线错误，不是当前状态机要求增加一拍。

## 3. 读侧：状态与寄存器

对应 `rtl/ddr_read_ctrl.vhd:110`、`:126`、`:192`、`:216`、`:257`。

| 状态 | 允许操作和转移 |
|---|---|
| WAIT_READ | 合法read上升沿锁存N/M/check/seed，清工作计数，generation加1，进入PREFETCH |
| PREFETCH | 在请求许可和信用允许时连续请求；独立接收响应并写预取FIFO；正常返回达到`min(128,M)`后进入PRIME |
| PRIME | 等待FIFO真正成功弹出一个块，装入Current_Array，再进入STREAMING；不是只发读使能就认为有数据 |
| STREAMING | 只有`stream_valid AND stream_ready`时才令sent加4、group推进；一块末尾同时尝试装入下一块；没取到则回PRIME；最后四点成功交付后进入DONE |
| DRAIN | 停止新请求和样本输出；取回已请求响应并丢弃，弹出旧FIFO块并丢弃；`requested=returned`且`enqueued=popped`后进入FAULT(code3) |
| DONE | 全部N点已交给当前下游；保持结果，允许新的合法read |
| FAULT | 保留故障，外部清理后合法rearm回WAIT；不自行恢复 |

`requested_q`只在NI请求被提交时加1；`returned_q`只在Retrieve成功返回时加1；`enqueued_q`只在正常返回实际写入FIFO时加1；`popped_q`只在FIFO真正输出一块时加1；`sent_q`只在下游接受四点时加4。多个事件可同拍发生，代码通过各自的next变量累计，不会因if/elsif而漏掉并发事件。

正常工作中有`popped ≤ enqueued = returned ≤ requested ≤ M`。请求条件`requested−popped<256`把“在途响应+FIFO现存块”一起算入容量，不会只看当前FIFO水位而超发。Current_Array已弹出，另占一块寄存器，不占FIFO信用。满256信用当拍即使有pop也暂不发新请求，是保守的一拍等待，不是溢出。

暂停时不再发新请求或输出样本，但允许旧DDR响应继续进入FIFO。Abort当拍禁止新请求、输出和入队，旧响应计入returned后丢弃；DRAIN不依赖run_enable，所以暂停不会阻止排空。DRAM ready丢失优先进入FAULT(code2)，不宣称旧请求已经清完。

换块时，下游取的是左Current_Array中的旧块最后四点；新FIFO块在边沿写入右寄存器，下一拍才输出新块首四点。最后一块只输出N规定的样本，补零尾部不进入下游。`read_done`表示四点流交付完毕，**不是“已经把整段数据写进预取FIFO”**。

`stream_word0..3`是VHDL的输入，仅供可选递增字检查器观察实际数据；它们不是VHDL输出的数据通路。真实波形可关闭`pattern_check_enable`；mismatch只记录诊断，不触发FAULT，也不改变搬运路径。

## 4. 与LabVIEW端口的对应关系

| VHDL端口/数据 | LabVIEW对应端子或节点 |
|---|---|
| 写侧`fifo_read_enable` →，`fifo_output_valid` ← | H2T.Read的Ready for Output、Output Valid；H2T每次读4个U32 |
| `pack_offset`、`pack_clear` | Replace Array Subset的index（已经乘4）、下一拍Pack_Array清零选择 |
| `ddr_write_address`、`ddr_write_valid` | DDR.Write的Address、Input Valid；Data另接左Pack_Array的40-U32 cluster |
| `ddr_write_ready_now` ← | DDR.Write.Ready for Input经过**一次**Feedback，初值False |
| `request_address`、`request_valid` | DDR.Request Data的Address、Input Valid |
| `ddr_request_ready_now` ← | Request.Ready for Input经过一次Feedback，初值False |
| `retrieve_ready` →，`ddr_retrieve_valid` ← | DDR.Retrieve Data的Ready for Output、Output Valid |
| DDR.Retrieve.Data | 直接连接预取FIFO.Write.Element；数据不经过VHDL |
| `prefetch_write_valid` → | 预取FIFO.Write.Input Valid；不能直接用Retrieve.Output Valid替代，否则Abort时旧响应仍会入队 |
| `prefetch_write_ready_now` ← | 预取FIFO.Write.Ready for Input经过一次Feedback，初值False |
| `prefetch_read_enable` →，`prefetch_read_valid` ← | 预取FIFO.Read的Ready for Output、Output Valid |
| `current_load`、`current_clear` | Current_Array下一拍装入/清零；清零优先于装入 |
| `stream_offset` | 从左Current_Array取offset至offset+3，四点同时接下游和`stream_word0..3` |
| 下游为NI FIFO | FIFO的Ready for Input延迟一次后接`stream_ready`；FIFO.Input Valid接`stream_fire` |
| 下游为同域同拍valid/ready模块 | `stream_valid`接下游valid；下游ready接`stream_ready`；数据来自LabVIEW四点线 |
| `new_session_safe` | 外部会话控制许可，不是DDR硬件端口；确认旧事务/相关FIFO已清理、读写占用互斥后才给True |

NI官方[高性能FPGA开发指南](https://download.ni.com/pub/gdc/tut/labview_high-perf_fpga_v1.1.pdf)印刷页38–40说明：Output Valid针对当前输出，Ready for Output表示当前接收能力，Ready for Input提供下一迭代许可，需用Feedback传回上游。当前“一次延迟”的合同与此一致，不能把普通同拍ready任意延迟后代入。

NI官方[DRAM访问说明](https://www.ni.com/en/support/documentation/supplemental/13/introduction-to-using-dram-with-ni-fpga-devices.html)说明Write使用地址/数据/输入有效，读操作分Request与Retrieve，响应受ready和非确定延迟影响。代码按这一接口组织。文档确认的是通用接口语义，不是当前PXIe/LabVIEW工程配置已经验证。

## 5. 硬件可实现性：本轮应看到的边界

没有数据位宽转换或复杂数值算法；关键工作是计数、比较、使能和外部寄存器控制。所有内部状态在同一上升沿更新；未见内部锁存、多驱动、组合门控时钟或内部组合握手环。组合路径跨越LabVIEW节点时仍须按真实寄存器端点评估。

- 写侧理想服务周期为`N/4+M`拍，不含命令/外部等待；满块为收10拍、写1拍。150 MHz下满块理想上限约545.45 M个U32/s，仅为调度上界。
- 读侧理想回放为`N/4`拍；125 MHz下四点端口对应500 M个U32/s，需要平均2 GB/s有效数据供给，即每10拍至少补足一个160字节块。真实DDR服务间隔没有冻结，所以不能承诺持续无间断输出；缺数据时进入PRIME并拉低valid，功能上允许停顿。
- DDR首响应和预取时间不确定，首样本必须等预取条件满足、PRIME成功装入后才出现；没有固定端到端延迟承诺。任意长下游背压会使完成时间任意延长；容量信用保证的是不超发，不保证deadline。
- 预取的128块含5120点：在全部已经驻留、下游每拍收4点且期间没有新返回的理想情况下，提供1280个读时钟周期（10.24 us）数据。不能把256信用误当成始终驻留256块的保证。
- 按声明位宽和二进制状态编码估算，写核约627位、读核约885位状态/计数寄存器，实际综合可能优化或改编码；其中13个U64计数器占832位。两核没有显式DSP/BRAM/URAM实例；LabVIEW两组40-U32数组另占2560位，预取FIFO另需40 KiB存储。这些是结构核算，不是工具资源报告，平台外壳/LUT总预算尚无实测。
- 需留意的路径只有少数：写侧64位参数运算/比较到start/pack_clear；读侧32位信用差值到request；块尾`stream_ready→stream_fire→FIFO.Read→current_load`；可选检查器的32位加法/比较、四路错误累加和首错选择；U64计数器及复位/使能扇出。检查器写在for循环内不等于四拍流水。不能仅凭状态数少断言150/125 MHz物理时序通过，也没有证据把问题归因于高扇出。
- 当前唯一XDC约束写顶层clk为6.666667 ns；它不能证明读顶层125 MHz或LabVIEW I/O约束。写TB时钟为10 ns、读TB为8 ns，均不构成物理时序证据。

## 6. 审查后的处理建议

| 项目 | 本轮判断 | 下一步最小动作 |
|---|---|---|
| 状态转移、地址/计数推进、尾部处理 | 在接口合同成立时，静态逻辑自洽；未发现明确需改RTL的问题 | 保留核心结构，无需先扩大测试矩阵 |
| 下游数据通路归属 | 读核已消费预取FIFO并产生四点流；不能再有第二个消费者 | 按第1节接Sync；若要求Sync直接消费40点预取FIFO，需先调整读核职责，此事仿真无法代替设计选择 |
| 实际NI节点参数与CLIP寄存器属性 | 只有接线文档，没有当前VI/项目供核查 | 接入时核对40-U32内存、256块FIFO、每次4点、同源时钟、握手只延迟一次；VHDL仿真不能确认实际框图属性 |
| 跨模块会话控制 | 两核不自动互斥；reset/rearm不清NI队列；写DONE不提供物理flush回执 | 外部采用先写后读，Host稳定配置后发命令；150/125 MHz控制交接须有实际同步/握手，不直连异步控制。读写顺序保证以实际NI接口配置为准，不凭空添加固定等待拍数 |
| 核心逐拍数据对齐 | 旧数组/新数组、块尾换块、暂停/恢复可以解释，但纯阅读不是执行证据 | 后续确需功能确认时，只做下述写/读短场景，不开展新的边角测试清单 |
| 真实时序/持续吞吐 | 未验证；短功能仿真也不能解决物理路径和DDR服务保证 | 本轮不运行，不能以功能通过替代 |

后续建议的最小功能场景（本轮仅建议，未启动）：

1. **写侧一条短场景**：84点分3块，加入一次FIFO空和一次DDR不接收，检查地址0/1/2、数据顺序、最后36点补零和DONE；再发一次正常新命令确认从地址0开始。重点是数组/寄存器与写许可的逐拍对应。
2. **读侧一条短场景**：对应3块，加入响应延迟和块尾下游暂停，检查预取→PRIME→STREAMING→DONE、块尾换块、只交付84点以及四个块计数一致；在同一短场景中再做一次有未决请求的abort，确认DRAIN期间不把旧数据写回FIFO、排空后才能恢复。

这些已经覆盖用户关心的主要状态和接口事件；不新增大规模随机、性能、边界组合验证。实际VI连接和物理时序的不确定项不能通过这两条行为测试解决。是否执行后续短测留待用户决定；原资源grant/deadline仍不可复用。

## 7. 本轮证据身份

审查源码与迁入版本一致，SHA-256：

| 文件 | SHA-256 |
|---|---|
| rtl/ddr_upload_ctrl.vhd | DC2804BD120FCB3F9D1CCFD9767756E1E510E89980F437AB9E2CB390D2E53BD1 |
| rtl/ddr_read_ctrl.vhd | D75A88072AE909D4D34E843DD0EA99C82F82379EEAD80CCA55CCEBFBFC32965A |
| sim/tb_ddr_upload_ctrl.vhd | 51418FA2A7CC32E457825C3956852468FFE546DED7EFCB6058E2A2CAE501BEE2 |
| sim/tb_ddr_read_ctrl.vhd | A7120FFEE8A7308A3764790AAF78E44143939BBB283E68FC69A006980589A853 |
| constraints/upload_150mhz.xdc | 53E720A13C1E45FF0F2A195A7166A62420DBB7B0CBA189D7913D724C03D4389D |

本轮状态：STATIC_REVIEW_COMPLETED_WITH_INTEGRATION_CONDITIONS。写/读仿真仍NOT_RUN；综合、实现、持续吞吐、NI编译和板测均未验证。历史两次create失败保持原归因，不能据此称RTL功能失败。
