# 同步前端：实际架构及 LabVIEW 接线说明

当前更正（2026-09-15）：交付结构为原算法顶层核心 DCP + 独立明文 VHDL wrapper + CLIP XML，由 NI Target 编译关联。自建 read_checkpoint -cell 诊断未完成，但不是 NI 必须步骤，撤回其作为综合交付门槛的判定。原顶层综合已验收；NI 实际导入及整体编译尚未执行。详见 docs/CLIP_NETLIST_INTEGRATION_DECISION_20260915_ZH.md。
更新：2026-09-14，按用户最新要求收束综合交付；不要求新增 BUFG 为零，不为此重实现。本文描述当前 RTL 与建议由用户搭建的 FPGA VI 桥接逻辑，后者尚未实现或板测。

## 当前状态
真实 XPR：vivado/Sync_Frontend/Sync_Frontend.xpr；top=sync_frontend_top；part=xcvu11p-flgb2104-2-e；Vivado 2021.1。34 个硬件 SV 文件、15 个管理 IP，另有 ROM 初始化文件。
SF001 基座短测试通过；SF002 自主连续流限定短测试通过，四帧精TO零样点误差、CFO最大误差23Hz。
SF003 成功综合生成 work/SF003_attempt_20260914T211953Z/sync_frontend_synth.dcp 和 sync_frontend_top.edf，原生综合检查黑盒为0，参考ROM有208个非零INIT字段。综合资源为18770 LUT、18119 FF、58 RAMB36、9 RAMB18、206 DSP、0 URAM。
同次EDF导出附带厂商加密EDN，不能只拿主EDF宣称完整包。EDF+43EDN 的独立核心和 OOC VHDL wrapper 链接已收到回执且零黑盒；发布 XML 静态补齐依赖。原 XML 使用 EDF，不是 DCP 配置。
已有route自然完成：40722/40722 routable nets布完，routing errors=0；WNS=2.087ns，TNS=0，WHS=0.024ns，THS=0；1个8ns时钟、0MMCM/PLL、5BUFG。5BUFG是布局高扇出优化结果，不再作为拒收条件。134个输入没有input delay，其中reset_n按设计异步，另133个同步输入因原XDC命令兼容错误漏约束；OOC端口没有NI实际物理边界路由。因此这些数字仅说明已约束路径，不能说完整IO/NI时序通过。route DCP保留证据，不为本次综合交付重跑。

## 实际数据通路
这是单条复数流的四个连续时间样点并行，不是四路天线。
原始IQ同时进入8192样点历史环和连续S&C检测器。检测器计算间隔1024点的相关度与1024点滚动累计，生成候选。顶层将候选锚点附近[-256,2919]的3176点复制到双快照槽之一，再给粗/精同步核回放。
粗核输出配对的粗TO/CFO；精核用粗CFO在局部窗口旋转IQ，与PS1参考ROM相关搜索精TO。有效结果生成本机rx_frame_id，恢复成epoch内绝对样点坐标。包含候选拒绝、去重、容量drop、会话刷新和结果背压。
原始历史32KiB，双快照总32KiB；还包括检测延迟环、累计历史和既有精核缓存，以综合资源为准。没有整帧输出、整帧缓存读接口或整帧CFO/SFO补偿。

## RTL主层级
以下为模块名主层级，省略算术IP的内部展开。CLIP包装在交付链接检查时加入，并非本次核心综合的top。

    sync_frontend_clip (VHDL，纯连线包装)
    └─ implementation : sync_frontend_top
       ├─ acquisition : sync_continuous_detector
       │  ├─ lag_history : sync_beat_ram
       │  ├─ correlation : coarse_corr_energy_4lane
       │  ├─ rolling : sync_rolling_metric
       │  └─ threshold : coarse_metric_threshold
       ├─ raw_history : sync_beat_ram
       ├─ candidate_snapshots : sync_beat_ram
       ├─ coarse_confirmation : to_coarse_estimator
       │  ├─ coarse_lag1024_beat_ring
       │  ├─ coarse_corr_energy_4lane
       │  ├─ coarse_rolling_sc_accumulator
       │  ├─ coarse_metric_threshold / coarse_plateau_selector
       │  ├─ coarse_safe_phase_replay / cfo_coarse_estimator
       │  └─ coarse_result_pair_fifo
       └─ fine_confirmation : to_fine_estimator
          ├─ u_core : to_fine_core
          │  ├─ sync_coarse_pair_join / fine_local_capture_buffer
          │  ├─ cfo_phase_increment / fine_local_window_reader
          │  ├─ cfo_preamble_rotator / fine_energy_prefix_buffer
          │  ├─ fine_partitioned_corr_engine
          │  │  ├─ fine_corrected_local_buffer / fine_ps1_reference_rom
          │  │  ├─ fine_corr_scheduler / fine_corr_cmpy_array
          │  │  └─ fine_corr_accumulator / fine_corr_metric_controller / fine_peak_selector
          │  └─ fine_quality_controller
          └─ quality denominator / divider vendor adapters

候选复制、双槽调度、RESET_ESTIMATORS/REPLAY/WAIT_RESULT状态机、坐标转换与结果保持寄存器直接写在sync_frontend_top中，不能误画成已经存在的另一个RTL模块。

## DCP与LabVIEW
NI文档列出Vivado CLIP支持.dcp，使用综合DCP作为子模块，在VHDL包装里实例化sync_frontend_top，由XML描述端口与依赖。不能只将DCP当VI节点直接调用，也不能把独立route DCP当完整NI bitfile。
当前原算法顶层 DCP 和独立 VHDL wrapper 已存在，可按标准方式准备 CLIP 导入和 Target VI 桥接。无需先生成 wrapper 顶层 DCP；自建回填诊断失败不能代表 NI 导入失败。实际 NI 导入及整个 Target 编译尚未执行，不能宣称平台集成已通过。
选择DCP分支时XML应引用综合DCP；选择EDF分支时要带同次所有必要EDN。同一核心不要同时加入DCP和EDF两份定义。NI编译使用平台真实时钟/接口约束，不把standalone_io_budget.xdc搬入。
依据：
- https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/integrating-third-party-ip-fpga-module.html
- https://knowledge.ni.com/KnowledgeArticleDetails?id=kA0VU000000DK2X0AW&l=en-US
- https://knowledge.ni.com/KnowledgeArticleDetails?id=kA03q000000x0jiCAA&l=en-US

## 建议Target VI结构（尚需用户搭建）
Host U32样点数组 → Host-to-Target DMA FIFO RX_IQ → 四点组装/保持寄存器 → CLIP输入。
CLIP结果 → 原子结果快照/串行打包 → Target-to-Host DMA FIFO SYNC_RESULTS → Host。
所有CLIP读写与握手逻辑放在同一125MHz SCTL；clk125绑定NI提供的同一个时钟。DMA控制器处理Host/FPGA传输，若另有不同FPGA时钟域，使用真正跨域FIFO/消息握手，不逐位同步多位总线。
建议RX_IQ元素U32，FPGA端支持时每次读4元素。若目标只支持每次1元素，先在VI中收集4个再送入，不能把不完整的beat送DUT；此方式吞吐较低。
FIFO读成功的4个样点先存保持寄存器，再令input_valid=1；只在input_valid && input_ready的采样沿释放这组数据。ready=0时valid和4个数据保持。FIFO暂时为空令valid=0，不重复旧数据，不发stream_gap。
若使用带Output Valid/Ready的FIFO接口，将数据有效与保持状态机对齐；超时/读取失败绝不能作为新数据。不要仅用“剩余元素数”推断本拍已读成功。
四点握手一次accepted_samples加4。加载最后不足4点时，本接口没有lane_valid；必须明确填充真实时间序列及其额外样点计数，或使用4的倍数长度，不能悄悄丢尾点。已给测试向量恰为60324点。

## 输入与控制接线
| CLIP端口 | 方向/类型 | FPGA VI连接 |
|---|---|---|
| clk125 | 输入 clock | NI同一125MHz时钟，SCTL选同源 |
| reset_n | 输入Bool | 复位控制器，低至少4拍；释放后等input_ready |
| session_start | 输入Bool | VI将Host新会话命令转成单拍脉冲；普通DMA分块不触发 |
| session_abort | 输入Bool | 中止命令单拍，丢弃在途状态并关闭接收 |
| stream_gap | 输入Bool | 实际样本丢失/不连续时单拍；回放FIFO空不触发 |
| input_data0..3 | 输入U32各1 | 时间依次为x[4b]..x[4b+3] |
| input_valid | 输入Bool | 四点已齐、当前beat有效 |
| input_ready | 输出Bool | 送入输入保持状态机，握手前不覆盖数据 |
| result_valid | 输出Bool | 结果快照状态机的新记录标志 |
| result_ready | 输入Bool | VI已能原子保存整条记录时确认，不能由Host软件直接逐拍驱动 |

控制命令需要由FPGA VI产生单拍。Host前面板写True可能持续很多FPGA周期，不能直接作为start/abort/gap；可用命令FIFO或请求/应答序号加FPGA边沿脉冲。reset与会话切换还要丢弃VI内残留输入beat和未完成结果包，并避免DMA中旧数据混入新会话。正常首次复位后armed自动置1，不额外发送start即可得到参考epoch0；若发送start则epoch递增，Host应按实际epoch比较。

## Host要发送的数据
Host发送未同步的时域原始复数IQ，I16和Q16均二补码，每样点打包为U32：
W[15:0]=I的16位位型，W[31:16]=Q的16位位型。
例如I=-1、Q=2，则W=0x0002FFFF。必须保留符号的位型，不使用会饱和/裁剪的数值类型转换。
发送顺序W0,W1,W2,W3,W4...；不包含frame_id、frame_start、真实TO/CFO、样点索引或truth答案。PS1参考已进入ROM，Host不需要逐次发送参考表。
测试文件sim/data/autonomous_stream.mem共有15081行，每行128bit十六进制，显示顺序data3:data2:data1:data0，最右8个十六进制字符才是data0；先拆成4个U32按data0到3发送。不要把整128bit通过浮点数解析。
以500MS/s连续四点/拍送满需要原始数据2.0GB/s，不含协议开销；这只是输入字节率，当前未证明Host DMA或前端无限候选持续能力。最初按已验证节奏：每256次四点握手后由FPGA停8000拍，再继续；Host分块可以不同，但不能改变样点顺序。固定暂停应在FPGA计数实现，不能用Host sleep模拟64us精确节奏。

## Host接收与监视
结果字段在result_valid且ready未确认时保持，VI在一个125MHz拍中将全部字段存入一条本地快照；快照保存成功才确认result_ready。之后序列化到DMA，FIFO满则保留未写元素，不丢包或重复确认。
建议SYNC_RESULTS用U32 FIFO，每条9字，以下是建议由VI实现的打包协议，当前CLIP本身没有DMA端口：
| 字号 | 内容 |
|---|---|
| 0 | result_epoch |
| 1 | rx_frame_id |
| 2 | candidate_id |
| 3、4 | coarse_absolute低32、高32 |
| 5、6 | fine_absolute低32、高32 |
| 7 | cfo_hz的I32位型 |
| 8 | result_status高16、quality_q1_15低16 |

Host按9字组包（跨DMA读取块保留不足9字的尾部）；CFO重解释为I32，位置合成为U64，质量=原码/32768。结果对应(epoch,rx_frame_id)，不是发射端协议帧号。位置单位为epoch内已接受样点，lane=fine_absolute mod4、beat=floor(fine_absolute/4)。
清DMA或重置时不能留下半条记录；更复杂连续运行可由VI另加包头/长度/序号，但不改CLIP结果含义。

| 结果端口 | 类型 | Host用途 |
|---|---|---|
| result_epoch / rx_frame_id / candidate_id | 各U32 | 数据连续代次、有效接收帧号、候选追溯 |
| coarse_absolute / fine_absolute | 各U64 | 粗/精位置，单位样点 |
| cfo_hz | I32 | 估计粗频偏，Hz；不是补偿后的IQ |
| quality_q1_15 / result_status | 各U16 | 质量及有效标志；参考有效status=0x3800 |
| accepted_samples | U64 | 实际输入点数是否完整 |
| epoch | U32 | 当前会话/中断代次 |
| candidate_count / rejected_count | 各U32 | 候选量及局部确认拒绝数 |
| capture_drop_count / duplicate_count / confirmed_count | 各U32 | 容量拒绝、去重、已确认数 |
| snapshot_occupancy / snapshot_peak | 各U8 | 双快照占用及峰值，0..2 |
| max_history_age | U16 | 捕获开始时最旧所需样点的最大龄期 |
| error_sticky | U16 | bit0检测运算/IP，1核deadline，2协议/服务，3核运算/IP，4历史容量，5历史读过期/读未来，6worker超时 |

诊断量是live状态，不与result记录自动同拍。Host可低频读取统一快照的指标，或让VI发独立诊断DMA；跨域时整包握手，不逐个异步读后假定同时。还应监视两条DMA的超时/溢出、VI实际送入beat数、结果序列化丢包数。

## 第一次对照的预期
保持参考节奏、首次reset后不额外start：
| rx_frame_id | fine_absolute | CFO仿真实际Hz | CFO注入真值Hz |
|---|---|---|---|
| 0 | 15004 | -150022 | -150000 |
| 1 | 26373 | 0 | 0 |
| 2 | 37842 | 150022 | 150000 |
| 3 | 49311 | -149977 | -150000 |

最终accepted_samples=60324、confirmed_count=4、候选13、局部拒绝1、容量drop4、去重4、snapshot_peak2、max_history_age4336、error_sticky0。四条参考结果CSV在reports/reference/autonomous_results.csv；同输入同传输节奏按其逐项比较。科学精度门为精TO零样点误差、CFO对注入真值误差<=1000Hz。传输节奏改变可能改变候选服务/drop计数，不能把原计数机械用于任意实时条件。
整帧后续处理需要在CLIP外保留同一epoch的原始IQ，按fine_absolute取帧。当前前端没有整帧缓存导出接口，不能只凭TO数值从已覆盖的历史环取出整个帧。
当前完整发布：release/Sync_Frontend_SF003_20260915_rev02；唯一 CLIP 导入入口 clip/sync_frontend_clip.xml。rev01 为保留的旧快照，新的三项实现依赖已配齐。NI Target 编译仍未执行。
