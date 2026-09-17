# 把同步前端接入 LabVIEW：从选文件到读回四帧结果

这份指南按实际操作顺序编写。先完成第 1～6 步，把同步前端的端口放进 FPGA VI；再完成第 7～10 步，发送测试数据并读回结果。英文名称对应 NI 英文界面的菜单，中文版或不同版本可能略有差别。

**当前可以开始手工导入和搭建 FPGA VI。核心综合及限定条件下的功能仿真已经完成；LabVIEW 整个 FPGA Target 的编译和板上测试还没有完成。** 本文提供接线方法，不代表已经有搭建好的 Host VI 或 Target VI。

## 1. 先弄清楚需要哪几个文件

| 文件 | 它做什么 | 你把它放在哪里 |
|---|---|---|
| Vivado 工程 .xpr | 打开完整 RTL 工程，用于查看、综合、导出核心 | Vivado |
| 核心 .dcp | 保存已经综合好的同步算法电路 | LabVIEW 的 CLIP 源文件列表 |
| sync_frontend_clip.vhd | VHDL wrapper，负责把核心接口整理成 LabVIEW 容易连接的端口 | 同一个 CLIP 源文件列表，并选为 CLIP 的顶层 VHDL |
| CLIP 声明 .xml | 告诉 LabVIEW 哪个端口是时钟、数据类型是什么、跟随哪个时钟 | 由你在 LabVIEW 向导中填写后生成 |

可以把 wrapper 理解为“接口转接板”：它把四个 U32 输入拼成核心的 128 位输入，再把核心的一整条结果拆成多个输出。算法仍然在核心里。

**Vivado 综合顶层是 sync_frontend_top；LabVIEW 读取的 VHDL 顶层是 sync_frontend_clip。这是两个不同用途的顶层名称。** 不需要先把 wrapper 设为 Vivado 综合顶层，再产生另一个 DCP。

非 VHDL 工程并不是只有 DCP 一条路：NI 也支持相应工具链的 EDIF 等网表。对于本项目已有的 SystemVerilog 核心，本文采用“核心 DCP＋独立 VHDL wrapper”，因为文件依赖更容易核对。NI 要求 CLIP 顶层接口使用明文 VHDL；这是本项目选择该路径的依据，不是说所有非 VHDL 项目只有这一种文件格式。[NI：创建或获取 IP](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/creating-or-acquiring-ip-fpga-module.html)

### 1.1 第一次接入，具体选择这两个文件

**核心 DCP：**

[D:/008_MA_Dev/Sync_Frontend/work/SF003_DCP_check_20260914T223135Z/clip_dcp/sync_frontend_top.dcp](D:/008_MA_Dev/Sync_Frontend/work/SF003_DCP_check_20260914T223135Z/clip_dcp/sync_frontend_top.dcp)

**独立 VHDL wrapper：**

[D:/008_MA_Dev/Sync_Frontend/handoff/Sync_Frontend_20260915_manual/sync_frontend_clip.vhd](D:/008_MA_Dev/Sync_Frontend/handoff/Sync_Frontend_20260915_manual/sync_frontend_clip.vhd)

建议先把这两个文件复制到你准备长期保存的同一个文件夹，例如自己 LabVIEW 工程下的 SyncFrontendIP 文件夹。后面生成的 XML 也放在这里。三个文件要一起保留，避免移动后找不到依赖。

上述 DCP 的核心是 sync_frontend_top，器件是 xcvu11p-flgb2104-2-e。它从已经综合完成的核心网表及依赖重新导出，没有包含 wrapper，也没有重新综合算法；已经用 Vivado 打开检查，没有未解析的内部模块。该版本不携带独立工程的输入输出延迟预算，适合作为这次手工接入的起点。**它通过了核心文件检查，但还没有经过 NI 整个目标的编译验证。**

### 1.2 如果你要自己从 Vivado 综合结果导出

1. 在 Vivado 2021.1 中选择 **File → Project → Open**，打开 [Sync_Frontend.xpr](D:/008_MA_Dev/Sync_Frontend/vivado/Sync_Frontend/Sync_Frontend.xpr)。整个 Sync_Frontend 工程目录都要保留，单独一个 .xpr 文件不包含所有源文件。
2. 在 Sources 窗口确认顶层为 **sync_frontend_top**；在项目设置中确认器件为 **xcvu11p-flgb2104-2-e**。不要把 sync_frontend_clip.vhd 加进来作为综合顶层。
3. 已有本次综合结果时，点击 **Open Synthesized Design**。只有你修改了源文件、确实需要更新结果时，才重新 **Run Synthesis**。本工程使用供上层集成的 out-of-context 综合方式。
4. 打开综合结果后，选择 **File → Checkpoint → Write**，另存为 sync_frontend_top.dcp。NI 文档给出的导出路径也是从综合结果写出 checkpoint。[NI：为 PXIe-7903 创建 HDL IP](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA0VU000000DK2X0AW&l=en-US)
5. 原综合运行目录里也有 [synth_1/sync_frontend_top.dcp](D:/008_MA_Dev/Sync_Frontend/vivado/Sync_Frontend/Sync_Frontend.runs/synth_1/sync_frontend_top.dcp)。但原独立工程带自己的时钟和输出延迟约束，迁入 NI 前需要核查这些约束的作用范围。第一次按本文操作，请选第 1.1 节指定的版本；不要把原工程的 standalone_io_budget.xdc 一起加入 CLIP。
6. 确认 LabVIEW 安装的 FPGA 编译工具版本与网表生成工具兼容。本核心使用 Vivado 2021.1；若你实际目标使用另一版工具链，应先核对兼容性，不能仅凭后缀相同就认为可用。

选择文件时，可以用下面这张表排除容易拿错的东西：

| 看到的文件 | 这次是否选它 |
|---|---|
| 第 1.1 节指定的 sync_frontend_top.dcp | 选，这是完整算法核心 |
| 各个 IP 子目录里的 .dcp | 不选来替代完整核心，它们只是内部零件 |
| 名称带 stub 的 .v 或 .vhdl | 不选，它只声明接口，没有算法电路 |
| 布局布线后的 route DCP | 不作为本文的 CLIP 导入文件 |
| 以 wrapper 为顶层重新生成的 DCP | 不作为本次交付入口 |
| 单独的主 .edf | 本项目还需要同次 43 个 EDN 依赖；本文不走这条路径 |

同一个核心只添加一份定义；使用 DCP 时，不再把主 EDF 也加入同一个 CLIP。

## 2. 在 LabVIEW 中创建 CLIP 声明

先打开你用于 PXIe-7903 的 LabVIEW 工程，并确认 Project Explorer 中已经存在对应的 **FPGA Target**。

1. 右键 **FPGA Target → Properties（属性）**。
2. 左侧选择 **Component-Level IP**。
3. 点击 **Create File（创建文件）**，进入 **Configure Component-Level IP** 向导。

这里是在 FPGA Target 下操作，不是在 My Computer 下。向导负责生成 XML，你按下面的表填写即可。[NI：定义 CLIP 接口](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/clip-tutorial-part-2-defining-the-interface-fpga-module.html)

## 3. CLIP 向导每一页怎么填

NI 向导包含以下八页。某些版本会根据已选择的信号跳过不适用页面，这是正常的。[NI：CLIP 配置向导](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/using-the-configure-component-level-ip-wizard-fpga-module.html)

### 第 1 页：Name and Source（名称与源文件）

- 名称可以填写 **SyncFrontend125**，便于后面找到它。
- 点击 **Add Synthesis File**，加入 **sync_frontend_clip.vhd**。
- 再加入第 1.1 节选定的 **sync_frontend_top.dcp**。
- 如有“顶层文件”选择，选 **sync_frontend_clip.vhd**。DCP 是它调用的核心。
- 本次不添加独立工程的输入输出预算 XDC。
- 本次先做硬件接入，不添加一个并不存在的 LabVIEW 仿真模型。项目里的 Vivado 测试文件不是直接放进这个源文件列表的硬件文件。

完成后，源文件列表应能看到 **一个 wrapper VHDL 和一个核心 DCP**。

### 第 2 页：Entity, Architecture, FPGA Family and IP Type

| 项目 | 选择或填写 |
|---|---|
| Entity（实体） | sync_frontend_clip |
| Architecture（结构体） | rtl |
| FPGA Family（若需要填写） | 与 PXIe-7903 目标相符的 Virtex UltraScale+ 系列 |
| IP Type | 本次选择普通用户定义 CLIP；不选需要物理接口插槽的 Socketed CLIP |

本次所有输入输出都连接 FPGA VI，没有让该核心直接占用板卡物理引脚，所以使用用户定义 CLIP。不要把核心名 sync_frontend_top 填成 wrapper 的 Entity。

### 第 3 页：Generics（参数）

**本 wrapper 没有需要填写的 generic 参数，直接继续。**

PS1 参考内容已经在核心 ROM 中，Host 不需要每次再传一份参考波形。

### 第 4 页：Basic Signal Settings（基本信号设置）

这里先区分两件事：

- **Signal Type** 是信号的用途，例如 Clock 或 Data。
- **Data Type** 是数值怎样表示，例如 Boolean、U32 或 I32。

**clk125 的 Signal Type 必须选 Clock。其余 31 个端口选 Data。** 一根只有 1 位的线也可能是时钟，不能因为它是 1 位就把它配置成普通 Boolean 数据。

方向按 wrapper 来看：

- **Input / To CLIP**：FPGA VI 写给同步前端，例如 input_valid。
- **Output / From CLIP**：FPGA VI 从同步前端读取，例如 input_ready。

**reset_n 在本方案中选 Data、Boolean，而不是自动连接全局复位的 Reset 类型。** 因为本接口需要由 FPGA VI 明确控制低有效复位。False 表示复位，True 表示运行。NI 的 Reset 信号类型可能连接系统复位并不再显示为普通可写 I/O；不要在不知道极性和连接方式时替换。本方案保留用户可写复位，核心内部已有复位释放同步处理。[NI：CLIP 复位信号类型](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA0VU000000AqdF0AS&l=en-US)

### 第 5 页：Additional Clock Signal Settings（时钟设置）

选择 **clk125**，确认它是**输入时钟**，由 LabVIEW FPGA 目标提供。

如果此页要求频率，按字段单位填 **125 MHz** 或 **125000000 Hz**；如果要求支持的最小、最大频率，本次都按 125 MHz 配置。这声明了本次使用的频率。实际接到哪个板上时钟，还要在第 5 节的 Clock Selections 中选择。

这里不是 500 MHz。核心每拍处理四个连续样点，逻辑时钟仍是 125 MHz。

### 第 6 页：Additional Clock Status Signal Settings（时钟状态）

**本 wrapper 没有时钟锁定或时钟状态输出，无需把任何数据口改成时钟状态。**

input_ready 表示能否接收数据，不表示时钟锁定。

### 第 7 页：Additional Data Signal Settings（数据设置）

对除 clk125 外的每个端口，按第 4 节的表设置数值类型，并设置：

| 设置项 | 本项目选择 |
|---|---|
| Required Clock Domain / 所属时钟 | clk125 |
| Single-Cycle Timed Loop 使用规则 | Required：要求在对应时钟的单周期定时循环中访问 |
| 数据宽度及有无符号 | 严格按下一节的表 |

这意味着你后面要把这些 I/O 节点放进使用同一个实际 125 MHz 时钟的 **Single-Cycle Timed Loop，简称 SCTL**。不要把数据口随意留成与时钟无关。

### 第 8 页：XML Export（导出声明）

把声明保存为 **SyncFrontend125.xml**，放进前面保存 DCP 和 VHDL 的文件夹，点击 **Finish**。

向导会检查声明及相应的 VHDL 接口。若报错，先按第 11 节检查文件、实体名和编译工具。这个步骤成功，表示声明建立成功；不代表整个 FPGA 已编译通过。

## 4. 32 个端口照着这张表填

“VI 写入”表示方向选 Input / To CLIP；“VI 读取”表示选 Output / From CLIP。数据口都关联 clk125，并要求在对应的 SCTL 中访问。

| 端口名 | Signal Type | Data Type / 位宽 | 方向 | 所属时钟 |
|---|---|---|---|---|
| clk125 | Clock | 不选普通数据类型 / 1 位 | 时钟输入 | 实例中绑定实际时钟 |
| reset_n | Data | Boolean / 1 位 | VI 写入 | clk125 |
| session_start | Data | Boolean / 1 位 | VI 写入 | clk125 |
| session_abort | Data | Boolean / 1 位 | VI 写入 | clk125 |
| stream_gap | Data | Boolean / 1 位 | VI 写入 | clk125 |
| input_valid | Data | Boolean / 1 位 | VI 写入 | clk125 |
| input_ready | Data | Boolean / 1 位 | VI 读取 | clk125 |
| input_data0 | Data | U32 / 32 位 | VI 写入 | clk125 |
| input_data1 | Data | U32 / 32 位 | VI 写入 | clk125 |
| input_data2 | Data | U32 / 32 位 | VI 写入 | clk125 |
| input_data3 | Data | U32 / 32 位 | VI 写入 | clk125 |
| result_valid | Data | Boolean / 1 位 | VI 读取 | clk125 |
| result_ready | Data | Boolean / 1 位 | VI 写入 | clk125 |
| result_epoch | Data | U32 / 32 位 | VI 读取 | clk125 |
| rx_frame_id | Data | U32 / 32 位 | VI 读取 | clk125 |
| candidate_id | Data | U32 / 32 位 | VI 读取 | clk125 |
| coarse_absolute | Data | U64 / 64 位 | VI 读取 | clk125 |
| fine_absolute | Data | U64 / 64 位 | VI 读取 | clk125 |
| cfo_hz | Data | I32 / 32 位 | VI 读取 | clk125 |
| quality_q1_15 | Data | U16 / 16 位 | VI 读取 | clk125 |
| result_status | Data | U16 / 16 位 | VI 读取 | clk125 |
| accepted_samples | Data | U64 / 64 位 | VI 读取 | clk125 |
| epoch | Data | U32 / 32 位 | VI 读取 | clk125 |
| candidate_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| rejected_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| capture_drop_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| duplicate_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| confirmed_count | Data | U32 / 32 位 | VI 读取 | clk125 |
| snapshot_occupancy | Data | U8 / 8 位 | VI 读取 | clk125 |
| snapshot_peak | Data | U8 / 8 位 | VI 读取 | clk125 |
| max_history_age | Data | U16 / 16 位 | VI 读取 | clk125 |
| error_sticky | Data | U16 / 16 位 | VI 读取 | clk125 |

几个容易弄错的地方：

- **cfo_hz 用 I32**，因为频偏可以是负数。用 U32 显示负数会变成一个很大的正整数。
- **quality_q1_15 用 U16**。第一次接入保留整数原码，Host 显示时再除以 32768，不必在向导里自行创建定点数类型。
- **input_data0～3 用 U32**。每个 U32 内部装着两个有符号 16 位数，外层仍然按 U32 传输。
- **coarse_absolute、fine_absolute、accepted_samples 用 U64**，不要缩成 U32。
- clk125 是时钟端口，不需要在程序框图上给它写一个 True。

## 5. 把 CLIP 实例加到 FPGA Target，并连接实际时钟

创建“声明”和添加“实例”是两步。声明相当于接口说明，实例才是项目中实际使用的那一份电路。

1. 回到 FPGA Target 的 **Properties → Component-Level IP**。如果列表里没有刚才的声明，点击 **Add**，选择你生成的 SyncFrontend125.xml。
2. 右键 **FPGA Target → New → Component-Level IP**。
3. General 页给实例命名为 **SyncFrontend**，在 **Component-Level IP Declaration** 中选择 **SyncFrontend125**。
4. 打开 **Clock Selections**，把 CLIP 的 **clk125** 连接到 FPGA Target 中实际可用的 **125 MHz 时钟**。
5. 确认后，Project Explorer 中应出现 SyncFrontend 实例及它的数据 I/O。[NI：添加 CLIP 实例](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/clip-tutorial-part-3-adding-clip-to-a-project-fpga-module.html)

若目标里还没有 125 MHz 时钟，先按该目标允许的时钟源创建并验证 FPGA Derived Clock。可用源、倍频和分频范围由目标决定。**把一个 40 MHz 时钟的名字改成“125 MHz”不会改变它的频率。** 不满足目标时钟规则时，应先解决时钟配置，再继续接线。

然后新建或打开该 Target 下的 FPGA VI，放置 **Single-Cycle Timed Loop**：

- 在循环的时钟配置中，选择刚才连接给 clk125 的**同一个时钟对象**。
- 常见入口是在左侧时序输入节点右键 **Configure Input Node**，进入定时循环配置后选择 **Select Timing Source**。
- 仅仅两个时钟都显示“125 MHz”还不够，它们必须确实是同一个时钟来源。[NI：派生时钟和 SCTL 的选择](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA03q000000YIUMCA4&l=en-US)

## 6. 将端口放进 FPGA VI，并检查 I/O 延迟设置

把 SyncFrontend 下的所需数据端口从 Project Explorer 拖到上述 SCTL 中，生成 FPGA I/O 节点。输入口设为写，输出口设为读。

**本项目的 valid、ready 和数据必须对应同一个时钟周期。** 如果数据晚两拍才到，valid 却马上到，核心就可能收错一组样点。

NI 默认可能为 CLIP I/O 加同步寄存器。对本项目这些已确认处在同一实际时钟域的端口，检查 **FPGA I/O Properties → Advanced Code Generation**：

1. 找到 **Number of Synchronizing Registers for Output Data / Output Enable** 等适用设置，按本同域接口设为 **0**。
2. 若界面还提供输入方向的同步寄存器数量，也检查并使这条同域接口不增加额外同步延迟。
3. 对 valid、ready、四个数据口和结果字段保持一致。若某个目标/版本不提供对应设置，不要凭空添加选项；先核实该 I/O 的实际延迟，避免直接套用下面的逐拍握手。
4. 这里说的 0 只适用于本指南已限定的**同一实际时钟域**。跨时钟连接时需要专门的跨域传输结构，不能照搬这项设置。

NI 明确说明，CLIP I/O 的同步寄存器会逐级增加时钟延迟；同域传输不需要靠这些寄存器跨域。[NI：CLIP 与 VI 之间传递数据](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/passing-data-between-component-level-ip-and-vis-fpga-module.html)

接线前最后看一遍：clk125 是 Clock；所有数据口关联 clk125；CLIP 和 SCTL 选同一个时钟；reset_n 是低有效 Boolean 数据；数据与握手没有额外错开的延迟。

## 7. FPGA VI 怎么接：先做一个数据回放桥

当前 CLIP 自身没有 DMA FIFO。你需要在 FPGA VI 中连接两个方向：

**Host 的 IQ 数组 → 输入 DMA FIFO → 四样点保持寄存器 → CLIP → 结果保持寄存器 → 输出 DMA FIFO → Host 的结果表。**

### 7.1 创建两条 DMA FIFO

在 Project Explorer 中右键 FPGA Target，选择 **New → FIFO**，分别创建：

| 建议名称 | 类型／方向 | 元素类型 | 用途 |
|---|---|---|---|
| RX_IQ | DMA，Host to Target | U32 | Host 向 FPGA 发送原始复数样点 |
| SYNC_RESULTS | DMA，Target to Host | U32 | FPGA 向 Host 返回同步结果 |

FIFO 深度先选择目标允许的合理值，例如输入 8192 个 U32、输出 1024 个 U32，作为调试起点；这不是吞吐保证。Host 配置的缓冲区和 FPGA 端 FIFO 深度也不是同一个概念。

FPGA 端若支持一次读四个元素，可用它取得一组；若只支持一次一个元素，就用寄存器累计四个后再提交。后者能先验证接线，但输入节奏较慢，不能直接宣称复现了原仿真的周期安排。SCTL 内的 FIFO 操作应使用目标支持的非阻塞接口，不等待操作系统或使用正超时阻塞循环；根据实际读成功/Output Valid 判断数据有效。

### 7.2 四个样点如何交给 CLIP

依时间顺序读到 W0、W1、W2、W3，连接为：

| 寄存器中的样点 | 连接端口 |
|---|---|
| W0，最早的样点 | input_data0 |
| W1 | input_data1 |
| W2 | input_data2 |
| W3，最晚的样点 | input_data3 |

四个 U32 必须先存稳，再令 input_valid=True。使用循环的寄存器保存“这一组尚未交付”的状态。

| 当前情况 | VI 本拍该做什么 |
|---|---|
| 还没有完整的四个新样点 | input_valid=False，继续收集 |
| 四个样点已齐 | 保持四个数据，input_valid=True |
| input_valid=True，但 input_ready=False | 继续保持原数据和 valid，不取下一组覆盖它 |
| 同一个采样沿 input_valid=True 且 input_ready=True | 这一组交付成功；下一拍才可换成下一组 |
| DMA 暂时没数据 | 暂停提供新组，不把上一组再发一次 |

一组交付成功，accepted_samples 增加 **4**。总共应成功提交 **15081 组**，即 **60324 个复数样点**。

FIFO 暂时为空只表示传输停顿；此时不要发 stream_gap。stream_gap 专门表示真实样点丢失、流已经不连续。

若要在一个块内每拍交付一组，需要提前读好下一组，或使用两组寄存器交替保存数据。只用“先读四点、再单独发一次”的简单状态机会插入额外空拍，可以先用于检查接线，但不算精确复现原仿真节奏。

如果要精确复现所附仿真结果，在 FPGA 中数“成功交付的组数”：**每交付 256 组后，将 input_valid 拉低 8000 个 FPGA 时钟周期，再继续。** 125 MHz 下这段暂停为 64 微秒。计数器放在 FPGA VI 中，不能用 Host 的 Wait/Sleep 代替这个周期安排。块内应持续供数；若 DMA 又造成额外停顿，记录实际节奏，再解释诊断计数差异。

### 7.3 复位和会话控制怎么接

第一次回放可在 FPGA VI 中实现一个简单启动状态机：

1. 上电后令 **reset_n=False**，保持至少 4 个时钟；为了贴近现有测试，可保持 8 个时钟。此时 input_valid=False、result_ready=False。
2. 令 **reset_n=True**，继续等待，直到读到 input_ready=True，再开始送数据。释放复位后核心还要完成内部同步和清理，不要立刻假定它已准备好。
3. 本次第一次测试让 **session_start、session_abort、stream_gap 始终为 False**。复位后核心会自动允许接收，这样结果 epoch 从 0 开始。

以后需要重新开始会话时，session_start 才拉高**一个 FPGA 时钟周期**。session_abort 是中止，stream_gap 是声明样点不连续；也都使用单周期脉冲。Host 上点一下 Boolean 可能保持成千上万个 FPGA 周期，不能直接当单拍命令。可让 Host 写命令序号，再由 FPGA 检测新命令产生一拍脉冲。

重新开始时还要清理 VI 自己保存的半组输入、半条输出及旧 DMA 数据，防止把前后两次数据混在一起。

### 7.4 结果如何读出，result_ready 如何控制

当 result_valid=True，CLIP 表示“有一整条结果等你取走”。这一条包括：

result_epoch、rx_frame_id、candidate_id、coarse_absolute、fine_absolute、cfo_hz、quality_q1_15、result_status。

VI 需要在**同一拍保存这八个字段**。可以先做一个本地结果寄存器：有空位、能在该拍保存整条结果时，才把 result_ready=True。在 result_valid 与 result_ready 同时为 True 的沿完成保存，并把本地寄存器标成“占用”。没有空位时 result_ready=False，CLIP 会继续保持原结果。

然后从本地寄存器依次向 SYNC_RESULTS 写九个 U32。写失败或 FIFO 满时，保留当前字和写入序号，下次再试；只在写成功时序号加一。九个字全部成功写完才能释放本地寄存器。

本指南约定以下 **VI 自行实现的 DMA 格式**，它与 wrapper 内部总线的排列不是一回事：

| 每条记录内的字序号，从 0 开始 | 写入内容 |
|---|---|
| 0 | result_epoch |
| 1 | rx_frame_id |
| 2 | candidate_id |
| 3 | coarse_absolute 的低 32 位 |
| 4 | coarse_absolute 的高 32 位 |
| 5 | fine_absolute 的低 32 位 |
| 6 | fine_absolute 的高 32 位 |
| 7 | cfo_hz 的 32 位原始位型 |
| 8 | 高 16 位放 result_status，低 16 位放 quality_q1_15 |

若要复现附带仿真的结果背压测试，每次出现新 result_valid 后，先保持 result_ready=False 共 128 拍，再按上面的规则接收。不要边读一个字段边确认，也不要让 Host 软件直接控制逐拍的 result_ready。

## 8. Host 应该发送什么数据

发送的是**还没有同步的时域复数 IQ**。每个样点一个 U32：

- 低 16 位：I 的二补码位型。
- 高 16 位：Q 的二补码位型。

例如 I=-1、Q=2，对应 U32 为 **0x0002FFFF**。四个数据口是同一条波形相邻的四个时间样点，不是四路天线。

Host 不发送 frame_start、真实帧起点、答案 CFO 或预先切好的前导。前端要从连续输入中自己找出帧。

### 第一次建议使用十六进制文本，容易核对

打开 [input/iq_u32_hex.txt](D:/008_MA_Dev/Sync_Frontend/handoff/Sync_Frontend_20260915_manual/input/iq_u32_hex.txt)。它共有 **60324 行**，每行 8 个十六进制字符，对应一个 U32。

在 Host VI 中：

1. 用 **Read from Text File** 读取文本，按换行拆分，忽略最后可能出现的空行。
2. 用十六进制格式解析每行，例如 **Scan From String** 的 %x；把数值输入/输出类型明确配置为 **U32**。
3. 得到 U32 数组。长度必须为 60324。
4. 将前四个元素的显示格式设为十六进制，核对依次为 **FFFCFFF6、00020000、FFFDFFFA、00040003**。
5. 按原顺序分块写入 RX_IQ，不能按数值大小排序、交换 I/Q 或反转每四个元素的次序。

也提供 [input/iq_u32_le.bin](D:/008_MA_Dev/Sync_Frontend/handoff/Sync_Frontend_20260915_manual/input/iq_u32_le.bin)：这是无文件头的 **241296 字节**原始文件，按小端 U32 读取可得到同样的数组。读二进制文件时要明确小端和 U32，不把它当带 LabVIEW 数组长度头的已展平数据。

原始 autonomous_stream.mem 每行是 128 位、右侧才是最早样点。已经给出的 U32 文件替你完成了拆分，初次接入无需再解析该文件，更不能把整个 128 位数转换成浮点数。

## 9. Host 怎么启动、接收和显示

1. 保存 FPGA VI，在 FPGA Target 的 Build Specifications 中建立/选择 FPGA 编译项，指定这个 VI，完成目标编译。只有这一步成功，才会得到可下载运行的 NI bitfile。
2. Host VI 使用 **Open FPGA VI Reference** 打开对应的编译结果，配置 DMA FIFO，启动 FPGA VI。让 FPGA 自己执行第 7.3 节的复位时序。
3. Host 放两个并行循环：一个向 RX_IQ 写输入数组，一个持续从 SYNC_RESULTS 读结果。避免输入写入等待和输出读回等待互相堵住。
4. 记录 FIFO 的实际成功读写数量及超时。遇到超时，按相应 FIFO 方法报告的实际传输状态处理，不能未经核实就把整块输入重复发送。
5. 输出每凑齐 **9 个 U32**，解析为一条记录。一次 DMA 读取末尾不足 9 个时，留下这些字，和下次读到的内容拼接。
6. 用两个 U32 合成 U64 位置：先把高字扩成 U64，再左移 32 位，与低字合并。
7. 第 7 字按原位型解释成 **I32**，可使用适当的 Type Cast；不要使用可能把大 U32 饱和成最大 I32 的数值转换。这样负 CFO 才能正确恢复。
8. 第 8 字：右移 16 位取出 status；与 0xFFFF 按位与取出 quality。quality/32768 是便于显示的质量数值。

前面板建议放一张结果表，列出“接收帧号、精确位置、频偏 Hz、质量、状态”。再放几个诊断指示器：accepted_samples、confirmed_count、error_sticky、capture_drop_count，以及 DMA 超时次数。

诊断指示器可由 FPGA VI 从 CLIP 读取后送到前面板，Host 通过 FPGA Reference 的 Read/Write Control 低频读取。若要一次比较多个计数，让 FPGA 先同时保存一份快照；不要把 Host 分别读到的不同时刻数据当作同一拍状态。

输入发完不等于运算结束。继续读结果，等待四条记录到齐、accepted_samples=60324、snapshot_occupancy=0，再记录最终计数。超时未到齐时保存计数和接线状态用于排查，不要立刻复位把证据清掉。

## 10. 第一次应该看到什么结果

使用所给输入、首次复位后不额外发 session_start，并按第 7 节的仿真节奏回放，对照表如下。status 一列使用十六进制。

| 接收帧号 rx_frame_id | 候选编号 | 粗位置，样点 | 精确位置，样点 | CFO，Hz | 质量原码 | status |
|---|---|---|---|---|---|---|
| 0 | 2 | 15056 | 15004 | -150022 | 29212 | 0x3800 |
| 1 | 6 | 26428 | 26373 | 0 | 32768 | 0x3800 |
| 2 | 9 | 37912 | 37842 | 150022 | 28791 | 0x3800 |
| 3 | 12 | 49396 | 49311 | -149977 | 28348 | 0x3800 |

四条记录的 result_epoch 都为 0。完整参考见 [autonomous_results.csv](D:/008_MA_Dev/Sync_Frontend/handoff/Sync_Frontend_20260915_manual/expected/autonomous_results.csv)，按本文九字格式打包后的 36 个 U32 见 [results_u32_hex.txt](D:/008_MA_Dev/Sync_Frontend/handoff/Sync_Frontend_20260915_manual/expected/results_u32_hex.txt)。

fine_absolute 是从当前连续数据段的第一个被接受样点开始、**从 0 计数的样点位置**。它不是字节地址，也不是 125 MHz 的循环次数。rx_frame_id 是接收端自己确认出来的帧号，不是从发射端解码得到的协议编号。

先检查三件事：

1. 输入完整：accepted_samples=60324，没有重复发送、丢弃或调换样点。
2. 返回四条有效记录，帧号依次为 0、1、2、3，精确位置与上表一致。
3. 频偏与注入值 -150000、0、150000、-150000 Hz 比较，现有精度门为误差不超过 1000 Hz；所附仿真结果最大误差为 23 Hz。

完全复现原仿真传输节奏时，最终诊断还应为：

| 指标 | 参考值 | 人话解释 |
|---|---|---|
| confirmed_count | 4 | 已确认四帧 |
| candidate_count | 13 | 检测器一共提出十三个待检查位置 |
| rejected_count | 1 | 有一个候选检查后不符合条件 |
| capture_drop_count | 4 | 有四个候选因缓存/服务条件没有进入处理 |
| duplicate_count | 4 | 有四个候选与已确认帧重复，被去掉 |
| snapshot_peak | 2 | 两个局部窗口缓存曾同时占用 |
| max_history_age | 4336 | 开始复制窗口时，所需最旧样点的最大年龄，单位样点 |
| error_sticky | 0 | 没有记录到硬件诊断错误 |

这里 capture_drop_count=4 不等于丢了四个真实帧，四个真实帧已经全部确认。改变输入停顿、DMA 供数或结果读取速度，可能改变候选服务和这些诊断计数；不能把任意节奏下计数不同直接判成算法错误。先记录实际节奏并核对四条有效结果。

## 11. 导入或运行出问题，先查哪里

| 现象 | 先检查 |
|---|---|
| 找不到 VHDL entity | 顶层 VHDL 是否是 sync_frontend_clip.vhd；Entity 是否为 sync_frontend_clip，Architecture 是否为 rtl |
| 提示 sync_frontend_top 未解析或黑盒 | 核心 DCP 是否加入同一个 CLIP 源文件列表；是否误选了 stub、单个 IP DCP；器件和工具链是否匹配 |
| clk125 出现在普通 Boolean 数据列表 | Signal Type 选错，应改成 Clock，并在实例 Clock Selections 中绑定时钟 |
| 时钟列表没有需要的 125 MHz | 检查目标实际可用时钟及派生时钟配置，不要只改时钟名称 |
| 数据 I/O 不能放进当前循环 | 检查 Required Clock Domain、SCTL 规则，以及循环是否选了与 clk125 同一个时钟 |
| reset_n 不见了，无法自己控制 | 检查是否误选成了系统 Reset 信号类型；本文方案使用 Data/Boolean |
| input_ready 一直 False | reset_n 是否一直 False；是否持续发送 abort；复位释放后是否等待内部清理 |
| accepted_samples 不对 | 检查四点是否齐全、valid/ready 同拍握手、FIFO 读失败时是否重复发送，以及 I/O 同步寄存器延迟 |
| CFO 是四十多亿的正数 | 检查 cfo_hz 是否 I32，以及 Host 是否把 DMA 的原始 U32 位型正确解释成 I32 |
| 只收到半条或少几条结果 | 检查是否同拍保存整条结果；FIFO 满时是否保留未写字；Host 是否跨块保留不足九字的尾部 |
| NI 目标编译不满足时序 | 查看 NI 整个目标的真实时序路径，不能用独立核心已有的 WNS 数字替代 |

## 12. 这个核心内部在做什么，现在验收到哪一步

输入 IQ 一边进入历史缓存，一边寻找前导特征。找到可疑位置后，它复制附近的一小段数据，先估计粗时间位置和粗频偏，再用局部频偏补偿后的数据寻找精确时间位置，最后返回一条同步结果。

主要 RTL 层级如下。括号是它解决的问题，细小算术模块在这里省略。

~~~
sync_frontend_top                         ← Vivado 综合顶层
├─ acquisition : sync_continuous_detector  连续寻找前导候选
├─ raw_history : sync_beat_ram             保存检测之前的原始样点
├─ candidate_snapshots : sync_beat_ram     保存候选附近的局部窗口
├─ coarse_confirmation : to_coarse_estimator
│  └─ 粗时间定位、粗频偏估计和结果配对
└─ fine_confirmation : to_fine_estimator
   └─ to_fine_core
      ├─ 局部数据读取与 CFO 旋转
      ├─ PS1 参考相关搜索
      └─ 峰值选择和质量计算

LabVIEW CLIP 的接口层：
sync_frontend_clip.vhd → 调用上述 sync_frontend_top 核心
~~~

历史缓存保存 8192 个复数样点；候选局部窗口是 3176 点，使用两个快照槽交替处理。当前输出是“帧在哪里、估计频偏是多少及诊断状态”，**没有整帧补偿后的 IQ 输出端口**。后续需要整帧数据时，必须在 CLIP 外保存同一数据段的原始 IQ，再按 fine_absolute 找到对应位置。

现有工程包含 34 个硬件 SystemVerilog 文件和 15 个受工程管理的 IP。自主四帧仿真及核心综合已完成。已有独立布局布线的已约束路径满足其时序要求，但原独立输入约束不完整，不能据此判定 NI 整个目标已通过时序。5 个 BUFG 已记录，不把“新增 BUFG 必须为零”作为本次拒收条件。

125 MHz × 每拍四样点说明接口满速时可接收 500 MS/s 的样点排列，**尚未证明 Host DMA、候选处理和整板能长期持续达到该速率**。本指南先帮助你完成可核对的四帧接入测试。

如果你只想在 Vivado 中查看已有自主前端仿真，右键 **sim_autonomous → Make Active**，确认测试顶层为 **sync_frontend_tb**。工程默认的 sim_1 是较早的粗同步基座测试，不是这里的完整自主前端测试。
