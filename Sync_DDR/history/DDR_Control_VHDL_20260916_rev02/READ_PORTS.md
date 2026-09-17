# DDR 读取控制器端口与接线契约

本文件对应 `rtl/ddr_read_ctrl.vhd`。它是纯 VHDL-93 控制器；1280 位数据不经过 CLIP 端口。数据保留在 NI DDR、NI Target-Scoped FIFO 和 LabVIEW 的 `Current_Array` 中。当前为源码交付与静态设计说明，尚不能代替原生仿真、NI 编译或板上测试。

## 1. 固定配置

- 与 CLIP 同源的 125 MHz SCTL；相关 CLIP I/O 不添加同步寄存器。
- 每个 DDR 地址存40个U32，即1280位。
- `FIFO_DDR_Prefetch` 每个元素也是40个U32的cluster；实际容量至少256个元素。
- 每次向下游提供4个U32。一个U32是一对已经合并的I16/Q16位模式。
- `sample_count=N` 必须为正且能被4整除；`ddr_word_count=M=ceil(N/40)`，1≤M≤2048。
- 自动先预取 `min(128,M)` 块，然后装入第一块并开始播放。无需另加 Prefetch/Play 命令。
- NI Request 和 FIFO Write 的 `Ready for Input` 各自只在 LabVIEW 延迟一拍；反馈初值 False。控制器内部不再延迟。

## 2. LabVIEW 保留的数据接线

按下面顺序搭建，端口方向均以本控制器为参照。

| 控制器端口/节点 | 连接 |
|---|---|
| `request_address` 输出 | DDR.Request Data.Address |
| `request_valid` 输出 | DDR.Request Data.Input Valid |
| DDR.Request.Ready for Input | Feedback Node（初值False）→`ddr_request_ready_now` 输入 |
| `retrieve_ready` 输出 | DDR.Retrieve Data.Ready for Output |
| DDR.Retrieve.Output Valid | `ddr_retrieve_valid` 输入 |
| DDR.Retrieve.Data | FIFO_DDR_Prefetch.Write.Element |
| `prefetch_write_valid` 输出 | FIFO_DDR_Prefetch.Write.Input Valid |
| FIFO.Write.Ready for Input | Feedback Node（初值False）→`prefetch_write_ready_now` 输入 |
| `prefetch_read_enable` 输出 | FIFO_DDR_Prefetch.Read.Ready for Output |
| FIFO.Read.Output Valid | `prefetch_read_valid` 输入 |
| FIFO.Read.Element | Cluster To Array，得到40元素U32数组 |
| `current_load` 输出 | 下述第一个Select的s输入 |
| `current_clear` 输出 | 下述第二个Select的s输入 |

**不能把 Retrieve.Output Valid 直接连到 FIFO.Write.Input Valid。** 正常运行时两者有效事件一致；ABORT/DRAIN时控制器仍取回旧DDR响应，但输出 `prefetch_write_valid=False`，主动丢弃旧返回。必须经过这个控制器输出，才能安全排空旧任务。

只留一个40元素U32数组移位寄存器 `Current_Array`，初值全零。两个Select的所有端子如下：

| 节点 | s | t（True） | f（False） |
|---|---|---|---|
| Select 1 | current_load | 本拍FIFO.Read输出转换的40元素数组 | 左Current_Array |
| Select 2 | current_clear | 40元素全零U32数组常量 | Select 1输出 |

Select 2输出接右Current_Array。不要从右移位寄存器取输出数据。

从**左**Current_Array取 `stream_offset+0`、`+1`、`+2`、`+3` 四项。这四条U32线同时接下游和控制器的 `stream_word0..3` 输入。它们是实际将要被下游接收的数据，也是完整性检查器看到的数据。

- 内部最大速度测试：`stream_ready=True`。
- 下游为NI FIFO Write：把该FIFO的Ready for Input延迟一拍后接 `stream_ready`；该FIFO的Input Valid接 **`stream_fire`**，Element接这四个样本组成的固定数组（FIFO需配置每次写4点）。不要用未限定接受许可的 `stream_valid` 直接驱动NI写节点。
- 下游为同拍valid/ready协议的算法CLIP：`stream_valid`接算法input_valid，算法input_ready接`stream_ready`。

把控制器“输出读取”节点与“反馈输入写入”节点分开摆放，避免一个混合巨大I/O节点构成LabVIEW数据流依赖环。

## 3. 控制和状态

| 输入 | 类型及含义 |
|---|---|
| clk | 与本SCTL同源的时钟 |
| reset | Boolean，高有效同步复位；它只清控制器和Current_Array，不能自行清NI的FIFO/请求 |
| run_enable | Boolean，True运行；False暂停新DDR请求与播放，旧DDR响应仍可进入预取FIFO |
| read_command | Boolean，上升沿申请一次读取；保持True不会重复启动 |
| rearm_command | Boolean，上升沿清状态回WAIT；仅WAIT/DONE/FAULT可接受 |
| abort_command | Boolean，高电平中止当前任务并进入DRAIN；不会凭空取消已发出的DDR请求 |
| new_session_safe | Boolean，外部确认旧NI请求/FIFO已清理且DDR写入已停止的许可 |
| dram_ready | NI DRAM Ready信号 |
| sample_count/ddr_word_count | U32；新任务接受时锁存 |
| pattern_check_enable | Boolean；接受任务时锁存；开启后按下述递增字测试模式检查 |
| pattern_seed | U32；接受任务时锁存 |

`read_command`只能在WAIT或DONE、`run_enable=True`、`new_session_safe=True`、DRAM已就绪、无abort及无同时rearm上升沿时接受。参数无效时进入FAULT。其余不满足条件的命令被拒绝，不排队。准备好后必须先把按钮拉低，再重新给上升沿。

命令拒绝时 `command_rejected=True` 并保持；下一次成功read或rearm会清除。正常新任务令 `read_generation` 加1，reset归零，rearm保留。Host可用generation变化确认本次命令被接受。

| read_state (U8) | 名称 | 行为 |
|---|---|---|
| 0 | WAIT | 等待合法read命令 |
| 1 | PREFETCH | 请求DDR并将返回放入预取FIFO；等待128块或全部小文件 |
| 2 | PRIME | 从预取FIFO取一块装入Current_Array；首次及缺块恢复都使用此状态 |
| 3 | RUN | 每次被下游接受后推进4点 |
| 4 | DRAIN | 中止后的排空阶段；不发新请求、不播放、旧返回丢弃、旧FIFO元素丢弃 |
| 5 | DONE | 已接受全部N点，等待下一次合法命令 |
| 6 | FAULT | 保留故障，清理后接受rearm回WAIT |

`read_busy` 在PREFETCH/PRIME/RUN/DRAIN为True。`read_done` 仅DONE为True。`read_fault` 仅FAULT为True；DRAIN时fault_code已为3，但busy保持True，表示还不能安全重启。

| fault_code | 含义 |
|---|---|
| 0 | 无控制故障 |
| 1 | 输入参数不合法 |
| 2 | 活动期间DRAM Ready丢失；旧请求状态不能假定已被清掉 |
| 3 | 用户abort，正常情况下排空后进入FAULT |

检查到错误样本不会把状态改为FAULT；它会记录mismatch计数和首错信息，让整段数据检查完成。

## 4. 为什么不会覆盖正在播放的块

Current_Array每块40点，`stream_offset`依次为0、4、8……36。只有 `stream_fire=True`，即本拍四点实际被下游接收，才推进偏移和 `sent_samples`。

在旧块最后四点被接受的同一拍，控制器尝试从预取FIFO取下一块：本拍下游看到的是左Current_Array中的旧块尾部，新FIFO数据在时钟沿存入右移位寄存器，下一拍才成为新的左Current_Array。因此不需要第二个Next数组。

若没有取到下一块，控制器进入PRIME，拉低stream_valid，等待真实数据，并累计no_data_cycles；不会补零冒充连续播放。最后一块只输出N规定的真实样本，DDR补零尾部不送给下游。

请求信用使用 `requested_words-popped_words<256`。它同时计算“还在DDR路上的块”和“已回到FIFO但还没弹出的块”，防止未决请求和FIFO容量一起溢出。Current_Array已从FIFO弹出，另外占一个块的位置。

## 5. 安全中止和重复任务

ABORT当拍禁止新Request及新样本输出，并开始DRAIN：

1. 已发出的DDR请求仍要取回，returned_words继续增加。
2. 这些旧返回被直接丢弃，不再增加enqueued_words。
3. 已经写入预取FIFO的旧块全部读出丢弃，popped_words继续增加。
4. 只有 `requested_words=returned_words` 且 `enqueued_words=popped_words` 才进入FAULT(code3)。DRAIN期间不清这些计数。
5. Host释放abort，确认外部输入/输出FIFO等也处理完毕后，给new_session_safe及rearm上升沿，回到WAIT。

若DRAM Ready丢失，模块直接FAULT(code2)，**不声称已经drained**。必须由外部完成NI接口/队列恢复并确认安全后才能rearm。不能把new_session_safe永久接True来掩盖旧返回；单独reset本CLIP也不会清掉NI请求或FIFO。

正常DONE说明本任务所有M块已请求、返回、入队、弹出，全部N点已被下游接受。若下游是T2H DMA，Host还可能没有读走所有旧样本，必须在下一任务前处理结果归属和剩余FIFO数据。

## 6. 计数与验收

| 输出 | 类型 | 计数事件 |
|---|---|---|
| requested_words | U32 | NI Request Input Valid提交1次，加1 |
| returned_words | U32 | NI Retrieve成功输出1块，加1，包括DRAIN丢弃 |
| enqueued_words | U32 | 向预取FIFO成功提交1块，加1；DRAIN返回不计 |
| popped_words | U32 | 预取FIFO成功输出1块，加1，包括DRAIN丢弃 |
| sent_samples | U32 | stream_fire一次，加4 |
| checked_samples | U32 | 检查开启且stream_fire一次，加4 |
| mismatch_count | U32 | 每个不符合期望的U32样本字加1；一次fire最多加4 |
| first_error_index | U32 | 首个错误样本的位置，从0开始；mismatch_count=0时无意义 |
| first_error_expected/actual | U32 | 首错的期望值/实际值 |

测试模式要求Host提供：`word[k]=(pattern_seed+k) mod 2^32`，k从0开始。这是验证DDR和数据通路的测试字，不是有物理意义的IQ波形。pattern_check关闭时可以传任意原始波形，但零mismatch不能证明检查通过。

完整性结论至少要求DONE、sent_samples=N、**checked_samples=N且mismatch_count=0**，以及四个块计数均为M。回读任意真实波形的逐点比较由Host执行。

所有时间计数均为U64，每个新任务/rearm/reset清零：

| 输出 | 定义 |
|---|---|
| total_cycles | 从接受read后的下一拍开始，PREFETCH/PRIME/RUN/DRAIN每拍计1；最后活动拍也计 |
| replay_cycles | 首次PRIME装好块之后，从RUN第一拍到最后四点被接受，包含中途PRIME等待；不含首次预取/PRIME、不含DRAIN |
| transfer_cycles | replay期间真正stream_fire的拍数 |
| pause_cycles | replay期间run_enable=False的拍数 |
| sink_stall_cycles | 未暂停、已有有效四点但下游stream_ready=False的拍数 |
| no_data_cycles | 未暂停且没有可输出块的拍数，包括缺块恢复PRIME装入那拍 |

正常完成时应满足：

```text
replay_cycles = transfer_cycles + no_data_cycles + sink_stall_cycles + pause_cycles
sent_samples = 4 * transfer_cycles
```

若时钟实际为125MHz，平均回放速率为 `sent_samples / replay_cycles * 125e6` 样本/秒。最大速率测试接stream_ready=True，正常完成且no_data_cycles、sink_stall_cycles、pause_cycles均为0时，计数应为replay_cycles=N/4，说明本次回放阶段每拍接受四点，对应500MS/s。不把源代码结构或行为仿真当成板上持续吞吐证据；还需NI编译时序及真实板测计数。
