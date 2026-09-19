# LabVIEW 四段数据流与反向逐线接法

对应 DDR_FOUR_STAGE_DESIGN_ZH.md。四个RTL文件均位于rtl/，不生成CLIP XML，用户在远端配置NI资源。本文的Sync.Data[0..3]/Valid/Ready是逻辑接口名称，不声称远端现有模块恰好使用这些端口名。

## 1. 文件、依赖和时钟

| 序号 | 顶层/文件 | 导入时同时包含 | 循环同源时钟 |
|---|---|---|---|
| 1 | ddr_upload_ctrl.vhd | 本文件 | UPLOAD_150M：150 MHz |
| 2 | ddr_read_ctrl.vhd | 本文件 | REPLAY_125M：125 MHz |
| 3 | ddr_capture_ctrl.vhd | ddr_upload_ctrl.vhd | CAPTURE_150M：150 MHz |
| 4 | ddr_download_ctrl.vhd | ddr_read_ctrl.vhd | DOWNLOAD_150M：150 MHz |

新增两文件是明确方向的角色封装，内部各实例化一份原状态机。不能只导入封装文件而遗漏依赖。依赖文件头的125MHz描述是原回放角色的时钟合同；download实例使用同一无时钟生成逻辑的内核，在150MHz同源SCTL下运行，需按150MHz做最终时序验证。VHDL中的clk不会自行产生或选择MHz；LabVIEW时钟资源、CLIP时钟映射和SCTL必须一致。

新GUI入口scripts/create_four_stage_project.tcl，默认顶层capture和constrs_1/150MHz；切换到ddr_read_ctrl时应选择constrs_read_125作为约束集，不能同时向clk施加两个频率。四个sim filesets各自时钟由TB定义。当前没有自动生成集成顶层，LabVIEW Target VI完成资源实例化与会话调度。

## 2. 资源设置：不同FIFO不要混用

默认每个DDR元素1280 bit=40 U32；每次交接四个U32=四个复样点。位宽变化后K=DDR_WIDTH_BITS/32，所有40相关数组和cluster尺寸同步改为K。

| 资源名（可用你现有名称替换） | 配置 | FPGA侧深度起点 | 读写位置 |
|---|---|---|---|
| FIFO_H2T | Host to Target DMA，U32，FPGA每次Read=4 | 16384 U32=64KiB | Host写；UPLOAD_150M读 |
| DDR_Waveform | DRAM Memory，40-U32逻辑元素 | C_in取实际可用元素数 | UPLOAD写；REPLAY读 |
| FIFO_Input_Prefetch | Target-Scoped，40-U32 cluster，每次1个 | 实际至少256块=40KiB | REPLAY_125M内读写 |
| FIFO_Sync_Input（需要时） | Target-Scoped，4-U32 cluster，每次1个 | 1024组=16KiB | REPLAY写；Sync域读 |
| FIFO_Sync_Result | Target-Scoped，4-U32 cluster，每次1个 | 1024组=16KiB | Sync域写；CAPTURE_150M读 |
| DDR_Result | 独立分配的DRAM Memory，40-U32逻辑元素 | C_out取实际可用元素数 | CAPTURE写；DOWNLOAD读 |
| FIFO_Result_Prefetch | Target-Scoped，40-U32 cluster，每次1个 | 实际至少256块=40KiB | DOWNLOAD_150M内读写 |
| FIFO_T2H_Result | Target to Host DMA，U32，FPGA每次Write=4 | 16384 U32=64KiB | DOWNLOAD写；Host读 |

FIFO使用本文约定的Handshaking接口；如果只显示Timeout/Timed Out，先对齐实际节点接口，不能把NOT Timed Out作为valid。跨时钟的两个小组FIFO使用NI支持的独立时钟实现；同频但不同源也按跨域处理。Host对两个DMA分别Configure，Requested Depth起点65536 U32，读取返回Actual Depth；Host缓冲不是FPGA BRAM。

DDR_Waveform与DDR_Result必须实际分配在互不重叠区域。可以是两项Memory资源，不能只是给同一Memory访问节点改标签。二者各自局部地址0。若想改成同一个Memory的不同地址段，当前RTL没有base_address，需要另外修改，不能直接并线。

## 3. Sync输出到结果FIFO：写端位于Sync域

1. 四根U32复样点线按时间先后Data0、Data1、Data2、Data3用Bundle形成固定四项cluster，接FIFO_Sync_Result.Write.Element。
2. FIFO.Write.Ready for Input按照当前NI节点“承诺下一拍”的合同，经过一次Feedback Node（False初值），得到本拍ResultReady。反馈必须在Sync所在循环内。
3. ResultReady一分为二：一支接Sync.Ready，一支与Sync.Valid做AND。AND输出接FIFO.Write.Input Valid。四点数据随同这一次交接整体写入。
4. 该FIFO的读节点放在CAPTURE_150M。不要把捕获控制器的result_fifo_read_enable跨域接给Sync.Ready；FIFO负责隔离两个时钟和短时停顿。
5. 此版本按预先给出的N_out计数结束，不依赖Sync.Last。若Sync另外提供Last，可在本地会话逻辑检查其位置是否与N_out吻合，但不能用Last私自缩短本次RTL的sample_count。每段必须产生恰好N_out点，且N_out四点对齐。

如果实际NI接口使用普通同拍ready而非下一拍承诺，应先核对Context Help并按该合同适配，不能机械添加反馈。本文一次Feedback规则沿用项目既有NI接线合同。

## 4. CAPTURE_150M：FIFO -> Pack_Array -> DDR_Result

建一个初值全零的K-U32数组移位寄存器Result_Pack_Array；左端是本拍旧数组，右端是下一拍数组。

| 来自 | 连到 | 分支/说明 |
|---|---|---|
| Capture.result_fifo_read_enable | FIFO_Sync_Result.Read.Ready for Output | 本循环内，不跨域 |
| FIFO_Sync_Result.Read.Output Valid | Capture.result_fifo_output_valid | 再分一支到下文的Select_Receive选择端 |
| FIFO_Sync_Result.Read.Element | Cluster To Array（4 U32） | 供Replace Array Subset的new subarray |
| Result_Pack_Array左端 | Replace Array Subset.array | 另两支：Select_Receive的False端；Array To Cluster K |
| Capture.pack_offset | Replace Array Subset.index | 已经是0、4、8……，不要再乘4 |
| 四点数组 | Replace Array Subset.new subarray | 替换连续四点 |
| Replace Array Subset输出 | Select_Receive.True | False保持旧数组 |
| Select_Receive输出 | Select_Clear.False | Capture.pack_clear接Select_Clear选择端 |
| 全零K-U32数组 | Select_Clear.True | Select_Clear输出仅到Result_Pack_Array右端 |
| Result_Pack_Array左端 -> Array To Cluster K | DDR_Result.Write.Data | 关键：写入消费旧数组，不能接清零后的下一拍数组 |
| Capture.ddr_write_address | DDR_Result.Write.Address | 可分支到本地Written_Words指示器 |
| Capture.ddr_write_valid | DDR_Result.Write.Input Valid | 与清零同拍，DDR使用旧数组 |
| DDR_Result.Write.Ready for Input | Feedback(False) -> Capture.ddr_write_ready_now | 只延迟一次 |

NI Write若带Byte Enables，按实际端子类型使所有字节有效。尾块未使用部分由数组清零提供，Host/Sync不需要发送补齐DDR块的填零样点。捕获完成后capture_done只表示最后请求被接受，读取前还要满足实际NI写后读可见性保证。

## 5. DOWNLOAD_150M：DDR_Result -> 预取 -> Current_Array -> DMA

Request/Retrieve必须选择DDR_Result的同一读接口。新建与输入预取独立的FIFO_Result_Prefetch；新建全零K-U32的Result_Current_Array移位寄存器。

| 来自 | 连到 | 分支/说明 |
|---|---|---|
| Download.request_address | DDR_Result.Request Data.Address | 地址单位为一个K-U32元素 |
| Download.request_valid | DDR_Result.Request Data.Input Valid | 无其他使能门控 |
| Request Data.Ready for Input | Feedback(False) -> Download.ddr_request_ready_now | 一次反馈 |
| Download.retrieve_ready | Retrieve Data.Ready for Output | 暂停期间可能继续收在途数据 |
| Retrieve Data.Output Valid | Download.ddr_retrieve_valid | 不直接接预取Write.Input Valid |
| Retrieve Data.Data | FIFO_Result_Prefetch.Write.Element | 整个K-U32块 |
| Download.prefetch_write_valid | Prefetch.Write.Input Valid | 取消排空时会丢弃旧响应，不入队 |
| Prefetch.Write.Ready for Input | Feedback(False) -> Download.prefetch_write_ready_now | 一次反馈 |
| Download.prefetch_read_enable | Prefetch.Read.Ready for Output | 预取FIFO只能由本下载器读取 |
| Prefetch.Read.Output Valid | Download.prefetch_read_valid | 反映本拍成功读出 |
| Prefetch.Read.Element -> Cluster To Array K | Select_Load.True | Download.current_load接选择端 |
| Result_Current_Array左端 | Select_Load.False | 同时分一支给Array Subset |
| Select_Load输出 | Select_Clear.False | Download.current_clear接选择端 |
| 全零K-U32数组 | Select_Clear.True | Select_Clear输出到Result_Current_Array右端 |
| Result_Current_Array左端 | Array Subset.array | 旧块末四点与下块装载可以同拍 |
| Download.unpack_offset | Array Subset.index | length固定4，不再乘4 |
| Array Subset输出四点U32数组 | FIFO_T2H_Result.Write.Element | DMA配置每次Write=4个标量U32 |
| Download.dma_fire | FIFO_T2H_Result.Write.Input Valid | 表示四点已获许可，不接dma_valid单独冒进 |
| T2H.Write.Ready for Input | Feedback(False) -> Download.dma_ready_now | 许可必须覆盖完整四个元素，一次反馈 |

Download.dma_valid描述当前有四点可送，dma_fire=dma_valid AND dma_ready_now才会推进。普通背压不改变当前数据/偏移/首尾；run_enable是另一种会撤销valid的暂停控制，不用它代替正常背压。dma_first/last是本地四点边带，本U32 DMA数据通道不自动携带这两个Boolean，不能把它们混入IQ数组。Host通过原子结果描述符里的N_out和Tag识别边界。

## 6. 参数与会话步骤

前向参数N_in/M_in/C_in和反向N_out/M_out/C_out独立。M=ceil(N/K)，正整数N必须四点对齐。捕获与下载使用同一结果描述符快照；操作中Host改控件不会修改该段。DDR实际容量由LabVIEW分配，不是写C就能扩大物理内存。

1. 初始化/清理对应FIFO及旧事务，取得本地new_session_safe；各循环继续运行，不停止循环来模拟暂停。
2. Host按现有流程完整上传输入；等待写请求接受与实际写后读可见性，输入描述符标记有效。
3. Target为结果区登记新的Tag和N_out/M_out/C_out，先启动capture并确认配置合法、capture_busy有效。
4. 启动输入回放和Sync。读输入区、写结果区可能重叠；同一区域不同时写读。Sync必须尊重结果FIFO背压。
5. 等capture_done、captured_samples=N_out以及结果区实际WriteVisible条件；输入read_done不代替Sync结果完成。
6. Host启动/保持FIFO_T2H_Result.Read消费循环，然后Target启动download；Host每次读一段，累计恰好N_out。有限超时/部分读按实际已读数续读，不盲目重发或丢弃整个段。
7. download_done后DMA可能仍有数据，Host继续收齐并核对Tag/数量/错误。新帧启动前确认旧FIFO数据已处理。可重复下载结果，但每轮必须重新登记Host接收会话并保持结果DDR不被重写。

建议沿用125MHz supervisor，通过原子命令/状态FIFO控制150MHz三个角色。消息要含Role/Operation/Tag/N/M/C；发送方保持描述符完整，接收方锁存后才打本域命令沿。三个角色各有独立busy/done，不允许Host用多个无互锁按钮绕过状态机。具体跨域FIFO与复位清理仍由远端Target VI实现。

## 7. 全部新增端口去向

Clock=对应150MHz SCTL同源时钟；Boolean/U8/U32/U64均按表类型，不使用有符号转换。各状态输出可接本地指示器，同时由会话逻辑采集为含Tag的状态消息；跨域不要直接拉多位线。

### ddr_capture_ctrl

| 端口 | 方向/类型 | 接线或用途 |
|---|---|---|
| clk | in/Clock | 对应150MHz SCTL同一时钟源 |
| reset | in/Boolean | 本时钟域同步高有效复位；不等于清空NI FIFO |
| run_enable | in/Boolean | 本域运行/暂停许可；正常运行True |
| capture_command | in/Boolean | 本域启动捕获命令沿 |
| rearm_command | in/Boolean | 会话逻辑产生的本域重新就绪命令沿 |
| abort_command | in/Boolean | 本域取消；暂停时也必须能处理 |
| new_session_safe | in/Boolean | 本域会话许可：区域所有权与旧事务清理完成；禁止常True |
| dram_ready | in/Boolean | 本域实际NI DRAM Ready |
| sample_count | in/U32 | 锁存的结果总样点数N_out |
| ddr_word_count | in/U32 | 结果DDR元素数M_out=ceil(N_out/K) |
| ddr_capacity_words | in/U32 | 结果区实际允许容量C_out |
| result_fifo_output_valid | in/Boolean | FIFO_Sync_Result.Read.Output Valid |
| ddr_write_ready_now | in/Boolean | DDR_Result.Write.Ready for Input经一次反馈 |
| result_fifo_read_enable | out/Boolean | FIFO_Sync_Result.Read.Ready for Output |
| pack_offset | out/U32 | Replace Array Subset.index |
| pack_clear | out/Boolean | Select_Clear选择端 |
| ddr_write_valid | out/Boolean | DDR_Result.Write.Input Valid |
| ddr_write_address | out/U32 | DDR_Result.Write.Address，同时可到本地计数显示 |
| captured_samples | out/U32 | 实际接收结果点数，完成时核对N_out |
| capture_state | out/U8 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| capture_busy | out/Boolean | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| capture_done | out/Boolean | 会话的写请求提交完成；还需WriteVisible才允许下载 |
| capture_fault | out/Boolean | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| fault_code | out/U8 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| capture_generation | out/U32 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| command_rejected | out/Boolean | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| capture_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| data_window_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| receive_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| write_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| fifo_empty_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| ddr_stall_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| pause_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |

### ddr_download_ctrl

| 端口 | 方向/类型 | 接线或用途 |
|---|---|---|
| clk | in/Clock | 对应150MHz SCTL同一时钟源 |
| reset | in/Boolean | 本时钟域同步高有效复位；不等于清空NI FIFO |
| run_enable | in/Boolean | 本域运行/暂停许可；正常运行True |
| download_command | in/Boolean | 本域启动下载命令沿 |
| rearm_command | in/Boolean | 会话逻辑产生的本域重新就绪命令沿 |
| abort_command | in/Boolean | 本域取消；暂停时也必须能处理 |
| new_session_safe | in/Boolean | 本域会话许可：区域所有权与旧事务清理完成；禁止常True |
| dram_ready | in/Boolean | 本域实际NI DRAM Ready |
| sample_count | in/U32 | 锁存的结果总样点数N_out |
| ddr_word_count | in/U32 | 结果DDR元素数M_out=ceil(N_out/K) |
| ddr_capacity_words | in/U32 | 结果区实际允许容量C_out |
| ddr_request_ready_now | in/Boolean | Request.Ready for Input经一次反馈 |
| prefetch_write_ready_now | in/Boolean | Prefetch.Write.Ready for Input经一次反馈 |
| ddr_retrieve_valid | in/Boolean | Retrieve.Output Valid |
| prefetch_read_valid | in/Boolean | Prefetch.Read.Output Valid |
| dma_ready_now | in/Boolean | T2H.Write.Ready for Input经一次反馈 |
| request_valid | out/Boolean | Request.Input Valid |
| request_address | out/U32 | Request.Address |
| retrieve_ready | out/Boolean | Retrieve.Ready for Output |
| prefetch_write_valid | out/Boolean | Prefetch.Write.Input Valid |
| prefetch_read_enable | out/Boolean | Prefetch.Read.Ready for Output |
| current_load | out/Boolean | Current_Array的Select_Load选择端 |
| current_clear | out/Boolean | Current_Array的Select_Clear选择端 |
| unpack_offset | out/U32 | Array Subset.index |
| dma_valid | out/Boolean | 本地可发送状态指示；不单独触发NI写入 |
| dma_fire | out/Boolean | T2H.Write.Input Valid |
| dma_first | out/Boolean | 本地首组指示；如需跨域元信息必须随同数据原子传递 |
| dma_last | out/Boolean | 本地末组指示；Host用N_out/Tag识别段尾 |
| download_state | out/U8 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| download_busy | out/Boolean | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| download_done | out/Boolean | 提交到FPGA侧DMA完成；不能代替Host收齐 |
| download_fault | out/Boolean | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| fault_code | out/U8 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| download_generation | out/U32 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| command_rejected | out/Boolean | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| requested_words | out/U32 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| returned_words | out/U32 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| enqueued_words | out/U32 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| popped_words | out/U32 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| downloaded_samples | out/U32 | 实际交给DMA的点数，完成时核对N_out |
| total_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| download_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| transfer_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| no_data_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| sink_stall_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |
| pause_cycles | out/U64 | 本地同名状态/统计指示器，并由会话逻辑打包上传；不接数据使能 |

## 8. 当前验证边界

两个原内核已有功能行为证据；新角色与150MHz下载须以本轮短测试结果为准。行为时钟不证明NI平台150MHz实现时序或PCIe持续2GB/s。实际DDR写后读可见性、四点NI FIFO接口、跨域配置、外部Sync结果长度/背压及完整平台资源尚需远端对齐。
