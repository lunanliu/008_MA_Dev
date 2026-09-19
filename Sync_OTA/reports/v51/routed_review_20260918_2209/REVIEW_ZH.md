# Sync OTA 22:09 布线报告：全量失败端点复核

2026-09-18，Europe/Berlin（CEST，UTC+02:00）。分支 V5.1_System_Modify。本轮读取现有报告，并使用 Vivado 2021.1 只读打开用户已完成的 routed DCP 导出路径；没有修改 RTL/约束，没有启动仿真、综合、优化、布局或布线。

## 1. 先明确比较基准

最新 timing 报告生成于22:09:17 CEST，placed utilization生成于20:07:26 CEST，implementation已经完成布线。

| 全设计指标 | 最初3336失败那轮 | 直接上一轮17:48 | 本轮22:09 |
|---|---:|---:|---:|
| WNS / ns | −0.766 | −0.057 | **−0.199** |
| TNS / ns | −647.378 | −0.057 | **−26.125** |
| setup失败端点 | 3336 | 1 | **381** |

相对最初结果，整体负裕量显著减少；但相对最近17:48结果，本轮WNS和TNS均退步，不能将本轮判作全设计时序优化成功。

| 本轮时钟 | WNS / ns | TNS / ns | 失败端点 |
|---|---:|---:|---:|
| clk125 | +0.153 | 0 | 0 |
| clk150 | +0.009 | 0 | 0 |
| clk500 | −0.199 | −26.125 | 381 |

Hold失败0，WHS+0.019 ns；脉宽失败0，WPWS+0.431 ns；50项bus-skew均通过，最低+0.940 ns。716062条需要布线的网络全部布通，路由错误0。当前381个失败全部为同域500 MHz setup，不是DDR背压或跨域例外约束能够消除的问题。

## 2. 全部381端点归因

从本轮已布线DCP导出每个端点的一条最差负裕量路径，max_paths=20000，实际381，无重复端点、未达截断上限。重新生成的summary与用户GUI报告一致。以下分组按最差路径归因，不保证修正一个共同起点后所有相应端点自动通过，因为其次差路径仍可能成为限制。

| 最差路径起因分类 | 端点数 | 量化TNS约/ns | WNS/ns |
|---|---:|---:|---:|
| CFO窗口poison_sync取消控制 | **280** | **−19.466** | −0.199 |
| 其他CFO控制、寻址及FIFO读出 | 59 | −3.549 | -0.151 |
| CFO分页系数ROM读出 | 20 | −2.056 | −0.169 |
| SFO厂商FFT内部及服务握手 | 22 | −0.919 | −0.064 |
| 合计 | 381 | −25.990 | −0.199 |

Vivado导出的单路径SLACK属性量化到0.001 ns，分组求和−25.990与原summary的内部精度TNS−26.125相差0.135 ns，处于381条路径的量化容差内。**权威总TNS仍为−26.125 ns；未按比例修正分组值。**

按目的模块再核对：CFO windows及其FIFO200条；CFO FFT2048 139条；CFO系数前端20条；SFO主FFT服务15条；SFO辅助FFT服务7条。

### 首要问题：窗口取消控制传播，280条

起点全部为 `cfo/windows/poison_sync/syncstages_ff_reg[3]/C`。其中193条终点在窗口队列/FIFO，87条到FFT2048。该共同起点贡献约75%的量化负裕量总量。

最差路径：`poison_sync → fast_stop → issue/credit组合条件 → packed_count[1]/CE`。见原timing第2899–2956行：2.097 ns＝逻辑0.346＋布线1.751 ns，布线占83.5%，4层LUT。poison500自身扇出12，首段连线0.687 ns；因此不能仅笼统解释为超高扇出。

相关源文件：`rtl/buffer/ota_cfo_window_queue.sv` 第26、67–109行；`rtl/cfo/cfo_fft2048_core.sv` 第81–89行。队列宽payload的使能重复包含停止/发出条件；FFT的RAM数据默认清零且整体受valid/abort包围，导致取消控制进入RAM DIN多路选择，而不只是写使能。

优先候选：保持停止对小状态/valid/真实FIFO与credit握手的保护，将无需在无效周期保持的宽payload和RAM数据选择从冗余停止条件中分离。取消当沿必须仍阻止事务提交，不能简单删除保护或仅延迟poison。该方向争取零增拍。

备选：在队列到FFT之间建立完整的局部弹性流水边界，配套数据、元数据、valid、取消及在途容量。不能仅给ready打一拍；如增加每窗服务周期，必须重新核算全链预算。

### 方案A的实际效果：输入侧已保住，读出侧仍失败

本次综合日志1480–1481行确认两份page文件读取成功，8586–8591行确认六个分页BRAM。检查点对象进一步确认：**15个row FDRE＋2个command FDRE均为DONT_TOUCH=1，6个RAMB36E2**。全量381失败集合中，没有这些row/command寄存器作为起终点的失败路径，也没有分页ROM ADDR/EN输入端失败。

但是，20条新失败全部从同一个 `coefficient_page0_data_reg_0_1/CLKARDCLK` 引出，经页选择和8项系数表，到乘法前的FDRE。最差−0.169 ns（原timing3188–3239）：BRAM读出Tco1.020 ns，之后首段布线0.680 ns，再经过LUT3页选择和LUT6查表；总数据延迟2.103 ns。终点名字带pr4/rr3或psdsp，实际单元仍是FDRE，不代表这些路径是乘法器内部运算失败。

这说明只落实ROM输入命令级还不足以完成整个系数读取通路的时序设计。优先候选是重分配现有两级：将原查表寄存级用于每页BRAM输出寄存及页标签延迟，下一原有级完成页选择/查表并进入cr2/ci2及审计流水，保持后续乘法时刻；必须先逐拍证明IQ、索引、气泡和取消对齐，并确认BRAM输出寄存实际被吸收。备选为新增完整输出流水级，同时调整所有标签和全链周期合同。本轮仅给方向，未应用新RTL。

### 另外59条CFO路径

| 路径族 | 数量 | 量化TNS/ns |
|---|---:|---:|
| output_record[80]（generation[9]）→FFT身份检查/状态/input_index使能 | 18 | −1.745 |
| next_output→RAM地址/使能 | 13 | −0.575 |
| offset_in_group→twiddle/数据RAM地址 | 9 | −0.517 |
| stage_index→输出计数控制 | 5 | −0.139 |
| state→RAM数据/地址 | 5 | −0.123 |
| input_index→RAM地址 | 2 | −0.248 |
| packed FIFO BRAM→prefetch head/tail | 5 | −0.111 |
| header_active→header FIFO EN/REGCE | 2 | −0.091 |

因此不能把339条窗口/FFT失败全部归为poison，也不能承诺只修poison就收敛。身份检查与RAM寻址需要分别检查物理邻近关系和已有寄存边界。

### SFO的22条失败

主FFT服务15条：内部sclr复位分发13条/TNS−0.698；外部ready到ingress FIFO 1条/−0.043；内部twiddle数据选择1条/−0.027。

辅助FFT服务7条：内部load_enable经xfft_input_ready到外部ingress FIFO计数4条/−0.134；内部reorder地址到BRAM WE 2条/−0.013；内部butterfly RAM地址1条/−0.004。

当前没有run_time_sel/NFFT源端点，不能继续套用旧NFFT归因。主FFT最差复位路径−0.064 ns，扇出148的网络耗时1.768 ns；零逻辑级的同类路径也显示布线占主导。外部5条握手路径可比较两槽预取与完整寄存接口；其余17条厂商内部路径需要对应的局部物理控制优化或适用IP流水配置，外部FIFO不能一并解决。

## 3. 已通过域的余量与资源背景

150 MHz最差已变为shared_raw URAM读数据→级联输出→六级LUT5选择→XPM doutb_pipe[63]/D，+0.009 ns。数据6.585 ns，含7个URAM级联节点和6级LUT。前10条均为存储路径：raw1、intermediate6、CFO bank3；不再是17:48的SFO输出环取消链，也不涉及最终DDR后级回压。

125 MHz最差变为初始训练读取的fatal/healthy→reader/DDS握手→输出FIFO CE，+0.153 ns，17级，布线6.073/7.742 ns。两域目前无失败，不作为本轮立刻扩大RTL修改的理由，但须在下一版实现中重新检查。

同层级placed资源对比：LUT238616→238678（+62），FF231762→231661（−101），BRAM570、URAM848、DSP2021不变。SLR0 BRAM仍84.82%、DSP65.79%；逻辑仍高度集中SLR0。URAM分布仅由274/286/288变为274/288/286。跨SLR连接总量并未耗尽。

尽管总资源基本不变，Route finalize报告的局部N/S/E/W拥塞等级由1/0/2/2升为3/4/4/4。两次真实运行都采用ExtraTimingOpt / Explore / NoTimingRelaxation，策略未换。因此应结合新逻辑映射与布局重排解释退步，不能把所有变化归因于新增了大量资源或工具策略切换。

本轮另外导出了当前routed分层资源：全设计LUT238758、FF231671、BRAM36为504、BRAM18为132（合570 tile）、URAM848、DSP2021；CFO FFT256为546 LUT、204 FF、2 RAMB36、4 DSP。这是当前routed证据，不与上一版placed数字直接作单模块因果相减。

## 4. 下一步顺序与证据边界

建议：**280条共同取消控制传播 → 20条ROM读出与52条FFT独立身份/地址控制 → 窗口其他7条及SFO22条收敛**。依据每拍组合/布线预算比较零增拍与完整流水两种结构；保留精度、时钟、取消语义及最终无背压合同。同步器最后一级之后是正常同域时序，不能加false_path掩盖。

TIMING-6/7时钟关系、133输入/1536输出缺I/O delay以及OOC HD.CLK_SRC等集成边界仍存在。内部无未约束端点，不代表最终NI时钟/I/O已经验收。新版功能仿真与板测没有由本次报告分析新增证据。

当前129份RTL哈希与方案A交付匹配；新综合日志/实例证实方案A进入本轮，但GUI运行没有完整冻结输入清单，不将当前工作区哈希冒充运行时完整输入证明。

## 5. 复核产物与工具异常说明

- 原始报告及哈希：本目录与 `report_identity.json`。
- 全部381端点、逐条详细路径和分组：`checkpoint_export/failing_endpoints.csv`、`failing_paths_full.rpt`、`endpoint_groups.json`及各分组CSV。
- 实际routed分层资源：`checkpoint_export/utilization_hierarchical_routed.rpt`。
- 分页寄存/BRAM对象：`checkpoint_export/coefficient_mapping.txt`。
- 只读DCP SHA256：590915429ee7d5191726fd0f27e77c85a9ddbbcd40d8ffda9baa225bd007c45a；导出后再次核验未变。

原生脚本完成summary、资源、381条端点及完整路径后，在附加映射数量断言处退出1：名称coefficient_row_reg*同时匹配了15个FDRE和2个CARRY8，故误判row数量。根据已导出的REF_NAME逐项过滤后，确认15+2寄存器和6个BRAM符合预期。错误记录保留，已在export_validation.json说明；无需重复成功导出，未重跑。附加正裕量地址/使能详细报告未生成，故不报告这些端口的具体正裕量数值；完整负裕量集合已证明它们没有失败端点。
