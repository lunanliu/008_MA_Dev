# DDR 上传控制器：纯 VHDL，替代 R2.1 第8节的状态 Case

本模块只接管截图中的**上传 SCTL 控制**，不改变同步前端算法，不直接驱动 DDR 引脚，不替代 NI 的 DDR 控制器。源文件为 VHDL-93，标准 IEEE 库，无厂商 IP；可直接加入用户定义 CLIP，由 LabVIEW 的 FPGA 编译流程综合，不需要先导出 DCP。用户现有 R2.1 指南和 VI 保留。

**先打开：** [RTL源文件](rtl/ddr_upload_ctrl.vhd)。导入 CLIP 只需要这一份文件。sim、scripts、constraints 和验证工程都不是 CLIP 的导入文件。

## 1. 你现在画好的哪些东西还用得到

| 现有部分 | 本模块接入后 |
|---|---|
| FIFO_H2T.Read，每次4点 | 保留 |
| DDR_Waveform.Write | 保留，1280位/40个U32，地址从0开始 |
| DRAM Ready | 保留 |
| DDR Write Ready for Input的一拍Feedback，初值False | **保留一次**，输出连ddr_write_ready_now |
| Pack_Array，40个U32零初值 | 保留，仍是LabVIEW移位寄存器 |
| Replace Array Subset、Array To Cluster(Size=40) | 保留 |
| Group_Index、Loaded_Samples、Write_Address、Block_Pending、Load_State移位寄存器 | 改由VHDL内部保存 |
| Params_OK、Block_Finished、Start_Load及控制AND | 改由VHDL内部计算 |
| 右下角整个嵌套Case | 由VHDL替代 |
| 预取SCTL、播放器SCTL、CLIP算法和结果FIFO | 本次不改；不能因此宣称整套回放已可重复启动 |

40点数组留在LabVIEW是为了少连线。普通CLIP端口支持的标量类型不能直接表示1280位；把数组一起搬进CLIP需拆成很多数据端口，再在LabVIEW合并，反而增加工作量。

## 2. 手工导入：只选一个 VHDL 文件

1. 在副本VI里集成，先保留已经搭好的上传VI，方便对照。
2. FPGA Target的Properties → Component-Level IP → Create File。
3. Add Synthesis File选择 `rtl/ddr_upload_ctrl.vhd`，实体/top选择 `ddr_upload_ctrl`。不添加测试台，不添加原Sync_Frontend的DCP。
4. 时钟端口 `clk` 配置为输入时钟，映射到**上传SCTL实际使用的同一个时钟源**。你最新截图是150 MHz，就先使用这个同源150 MHz，不拿播放器的125 MHz替代。
5. 其余端口全部是数据。按下表设Boolean/U32/U8；若向导使用FXP映射，U32选Unsigned、Word length=32、Integer word length=32；U8对应8/8。
6. 本控制器的数据端口设为SCTL Required，Required Clock Domain选上述上传时钟；参与控制握手的I/O不添加同步寄存器，读/写高级选项若提供寄存器数则设0。它不是跨时钟接口。
7. 完成CLIP声明并在Target下添加新实例。**先完成属性设置，再从项目树放新I/O节点**，不要复制曾经失效的旧CLIP节点。
8. 控制器读取输出的节点，与给控制器写入反馈的节点分开摆放，见第4节；不要把所有端口一次塞进一个既读又写的大I/O节点形成图形数据流环。

这是纯VHDL直接导入，因此无需独立VHDL Wrapper：本文件的entity已经是std_logic/std_logic_vector接口。FPGA完整VI仍需重新编译；“不需要先综合DCP”不表示“无需LabVIEW FPGA编译”。

## 3. 端口表：方向均以VHDL为准

本表所有数据端口都跟随上传时钟；Boolean为高有效，除非明确说明。

| 输入 | 类型 | LabVIEW接什么/含义 |
|---|---|---|
| clk | Clock | 与上传SCTL同源时钟 |
| reset | Boolean | 高=True复位此上传控制器和Pack_Array；平时False；**不是算法的reset_n** |
| run_enable | Boolean | 正常运行True；False暂停读写，保留进度；停SCTL前先置False |
| load_command | Boolean | False→True申请一次装载；保持True不会自动再次启动 |
| rearm_command | Boolean | False→True申请清故障/回WAIT；LOAD期间拒绝 |
| abort_command | Boolean | True中止当前上传到FAULT；平时False |
| new_session_safe | Boolean | 外部确认旧输入/DDR读者/预取等已处理好，允许开始或清理控制状态；见第6节 |
| dram_ready | Boolean | NI的DRAM Ready直接接入 |
| sample_count | U32 | 本轮真实IQ复样本数；如60324；每点I16+Q16共32bit |
| ddr_word_count | U32 | 本轮DDR块数；如1509；必须是ceil(sample_count/40)且1～2048 |
| fifo_output_valid | Boolean | FIFO_H2T.Read.Output Valid直接接入 |
| ddr_write_ready_now | Boolean | DDR.Write.Ready for Input经过现有一拍Feedback的输出；不是原始Ready |

| 输出 | 类型 | LabVIEW接什么/含义 |
|---|---|---|
| fifo_read_enable | Boolean | FIFO_H2T.Read.Ready for Output |
| pack_offset | U32 | Replace Array Subset.index，直接接；**不再乘4**，值已经是0、4…36 |
| pack_clear | Boolean | 第4节第二个Select的条件；True清空下一拍的Pack_Array |
| ddr_write_valid | Boolean | DDR_Waveform.Write.Input Valid |
| ddr_write_address | U32 | DDR_Waveform.Write.Address；也可分支到Written_Words指示器 |
| loaded_samples | U32 | 已接收的真实样本数；最终60324 |
| load_state | U8 | 0=WAIT，1=LOAD，2=DONE，3=FAULT，供指示器看 |
| load_busy | Boolean | LOAD时True；暂停期间也保持True |
| load_done | Boolean | 所有块的写请求被NI Memory接口接受后True；保持到下次任务或rearm/reset |
| load_fault | Boolean | FAULT时True，保持到合法rearm/reset |
| fault_code | U8 | 0无故障，1参数错，2上传中DRAM Ready丢失，3上传中Abort |
| load_generation | U32 | 每次接受新装载加1；Host用它确认命令确实被接受；reset清0，rearm不清 |
| command_rejected | Boolean | 命令被拒后保持True；成功load、rearm或reset清除 |

容量2048是本版本RTL内的固定限制，对应现有Memory申请容量。减少或扩大实际Memory容量时应匹配修改并复核此限制，不能只改Host参数。有效参数在命令接受时锁存；Host中途修改输入不改变正在进行的任务。

## 4. LabVIEW剩下的接线：没有状态Case

### A. 控制节点和NI节点

先放一组只读取控制器输出的I/O节点：fifo_read_enable、pack_offset、pack_clear、ddr_write_valid、ddr_write_address。

- fifo_read_enable → FIFO_H2T.Read.Ready for Output。
- pack_offset → Replace Array Subset.index。
- ddr_write_valid → DDR_Waveform.Write.Input Valid。
- ddr_write_address → DDR_Waveform.Write.Address。
- DDR_Waveform.Write.Data始终来自**左Pack_Array → Array To Cluster(Size=40)**。

再放写入控制器输入的I/O节点：

- FIFO_H2T.Read.Output Valid → 控制器fifo_output_valid。
- DDR.Write.Ready for Input → 现有Feedback(初值False) → 控制器ddr_write_ready_now。
- DRAM Ready → 控制器dram_ready。
- Host控制布尔/数字 → 对应控制器输入。

时钟由CLIP时钟配置提供，不是普通Boolean数据线。当前控制器没有再给Ready添加寄存器，因此原有Feedback只保留一个即可。

### B. 数组处理，只有一个Replace和两个Select

保留固定40元素的U32数组移位寄存器。FIFO四元素数组若为Unsigned FXP32/整数32，先转为U32数组，再接Replace Array Subset。

| 节点/端子 | 连接 |
|---|---|
| Replace Array Subset.array | 左Pack_Array |
| Replace Array Subset.index | 控制器pack_offset |
| Replace Array Subset.new element/subarray | FIFO本次输出的四个U32 |
| Replace输出 | 命名Pack_After_Read |
| 第一个Select.s | FIFO Output Valid |
| 第一个Select.t | Pack_After_Read |
| 第一个Select.f | 左Pack_Array |
| 第二个Select.s | 控制器pack_clear |
| 第二个Select.t | 固定40个U32零数组 |
| 第二个Select.f | 第一个Select的输出 |
| 第二个Select输出 | 右Pack_Array |

关键：DDR.Data用左Pack_Array；第二个Select的输出只接右寄存器。写DDR的那一拍，DDR接收旧数组的完整40点，寄存器在边沿后清零，为下一块准备。

没有读到数据且不清零时，第一个Select保留旧数组，第二个Select也保留它；所有False端都有明确来源。不要把旧Case输出也接到同一右寄存器。

## 5. 第一次运行与正常再次装载

这里先只测试上传，不启用预取/播放器。

1. Host使load_command、rearm_command、abort_command=False，run_enable=True。
2. reset=True保持到FPGA至少经过一个上传时钟，再设False。Host可以先写True再单独写False，不需要精确制造一个FPGA时钟宽度的脉冲。
3. 在第一次、输入FIFO已知为空且没有DDR读取的测试中，new_session_safe=True。
4. 设置sample_count=60324，ddr_word_count=1509。读取当前load_generation记作G。
5. load_command先False再True；等待load_generation变为G+1。若command_rejected=True而generation未变，检查就绪/状态/安全许可，不继续盲目发送。
6. Host向H2T写入恰好60324个已合并IQ32元素；不需要每1024点固定等1ms。数据的实际搬运由原FIFO背压控制。
7. 最终应见loaded_samples=60324，ddr_write_address=1509，load_done=True，fault_code=0。
8. 再次上传前，确认上一轮H2T没有残留、DDR没有读者占用，保持new_session_safe=True。更改波形参数后，让load_command再次False→True；generation再加1，并从地址0装载新波形。**不需要重启FPGA VI，也不需要先rearm或reset。**

DONE保持完成标志是正常的；新VHDL允许DONE收到合法新命令后进入LOAD。若load_command一直True，不会因为进入DONE就自动重复装载。Host应确认generation变化，不能依赖一个只有单拍宽的确认脉冲。

## 6. 故障恢复与整套回放的边界

FAULT不自动重启，保留原因供Host读取。rearm仅清上传控制状态和数组，不会清空NI的DMA FIFO、DDR内容或播放器缓冲。

- **仅上传且上一轮成功**：Host严格只写N点，上传计数等于N，且没有预取/回放；可直接允许下一轮。
- **中途Abort/FAULT**：先停止Host发送，处理H2T内未消费的旧样本；若已启用预取/回放，还要停止新读请求、收完在途返回、排空旧预取/结果数据并复位相应读侧计数。完成这些后才能new_session_safe=True。
- 清理完成，rearm_command False→True，控制器回WAIT且故障清除；然后另发load_command False→True。两命令不能同时产生上升沿。
- new_session_safe是你完成外部清理后的许可，**不能直接用NOT Play_Command或LoadDone代替**。这个上传控制器没有观察全部外部队列，无法自行证明它们已经清空。

因此本交付实现的是“可重复装载的上传控制器”；整套三SCTL可重复回放仍需要读侧统一的停止/排空/重新开始设计，本版本未冒充完成那一部分。

命令规则：LOAD时load/rearm被拒绝而原任务继续；run_enable=False时的新load/rearm被拒绝且不排队；两命令同拍上升沿都拒绝。reset期间已经保持高的命令在解除reset后不会自动触发，必须先拉低。Abort和DRAM就绪丢失即使在暂停期间仍把正在上传的任务置FAULT。

reset=True仅复位此控制器，不等于NI Target Reset，不会改变算法CLIP的reset_n或清空NI FIFO。请避免用同一个名字混淆三种复位。

## 7. 性能与验证

本版本保持R2.1单数组调度：通常收十拍四点，再用一拍写一块。理想无停顿上传上限为40×时钟频率/11；150 MHz约545.5 MS/s，真实DMA/DDR停顿会降低它。纯RTL改写主要减少图形开发工作，不自动增加持续吞吐。先完整装载、再独立回放时，上传无需与播放同时达到500 MS/s。

[测试台](sim/tb_ddr_upload_ctrl.vhd)用同拍LabVIEW数组模型逐字核对DDR提交的数据，覆盖参数错误、DDR/FIFO停顿、尾零、DONE重新启动、命令保持高、暂停、参数锁存、忙时命令、Abort、重装许可、FAULT恢复、DRAM掉Ready和容量边界。它不模拟真实NI DDR PHY，也不能证明CLIP属性正确、NI整合编译或150 MHz实现时序。

原生验证结果见同目录VALIDATION.md；若尚未生成，表示原生验证尚未完成，不能据代码存在声称通过。

可选的独立Vivado验证工程由scripts/create_project.tcl生成，器件xcvu11p-flgb2104-2-e，唯一综合top=ddr_upload_ctrl，唯一TB=tb_ddr_upload_ctrl。工程不是LabVIEW导入的必要步骤；没有要求把Wrapper当综合top，也没有要求生成DCP。

## 官方接口依据

- [NI：Importing External IP Into LabVIEW FPGA](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA03q000000x0jiCAA&l=en-US)：纯VHDL CLIP输入、LabVIEW与VHDL标量端口映射。
- [NI High-Performance FPGA Guide](https://download.ni.com/pub/gdc/tut/labview_high-perf_fpga_v1.1.pdf)，印刷页39～40：Ready for Input表示下一迭代许可，本模块保留图中的一拍反馈。

本模块由R2.1第8节的控制契约重新用VHDL实现，并增加正常重复装载、命令边沿、参数锁存、暂停及明确故障恢复。未修改原指南或任何VI。