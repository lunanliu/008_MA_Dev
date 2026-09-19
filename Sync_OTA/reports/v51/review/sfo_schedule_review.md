# SFO 原始环、训练与多帧调度独立静态审查

日期：2026-09-17（Europe/Berlin，CEST）。
对象：D:/008_MA_Dev/Sync_OTA 当前生产源集与 XPR。
审查范围：只读源代码、现用 XCI/生成包装及已发布历史证据；未运行仿真、综合、实现、MATLAB 或任何数值实验。仅本报告获准写入。用户最新规定最终输出没有后级背压；本文仍保留内部 SFO/CFO 流水容量与握手约束。

## 1. 结论与证据边界

首选保留两套重采样器和两块 SFO 中间 bank，重构共享原始输入、训练回读、逐窗准入和所有权记录。上述结构调整无需更改现有 FIR/Farrow/FFT、缩放、舍入和窗口坐标。

当前存在明确的设计缺口，不能宣称静态风险已清零：

1. 顶层仍是 DDR 捕获完成后扫描，再重放给 SFO；没有连续输入与算法处理并行的结构。
2. 原始 ring 仅在 E1 顺序读 issue 时退休，无候选时不会释放历史，长无帧输入约 3.145728 ms 后耗尽。
3. 当前 T09 配置、bank sparse read 和源完整性合同均要求整帧 committed；提前窗口必须同时修改，不能只提前 publish 或伪造 source_complete。
4. T06 等待训练 capture 时已经计入 watchdog 且可能已经占有 FFT lease。
5. 新结构每个合法配置的端到端无背压周期尚缺官方 FIR AXI 固定接口延迟和 FFT/IFFT 精确延迟的可引用静态依据。已找到 IP 算术延迟、所有可见 RTL 固定循环，以及旧单例事件；不能把旧单例或 watchdog 当作普遍上界。
6. 核心在真实 150/500 MHz 下的逻辑可运行性仍需未来获准的综合/实现报告。固定拍数推导不构成物理时序证据。

## 2. 实际生产身份

- Sync_OTA.xpr:10 指定 xcvu11p-flgb2104-2-e。
- Sync_OTA.xpr:1213 指定算法 top=sync_ota_top，定义来自 rtl/control/sync_ota_top_a07.sv。
- rtl/sources_a07.f 与 XPR 均选入 sync_sfo_top、sfo_two_pass_transport、sfo_raw_frame_ring、sfo_intermediate_frame_bank。
- Sync_OTA.xpr:1827、1843 实际 FFT XCI 路径是 Sync_OTA.srcs/sources_1/ip/.../*.xci；ImportPath 只是导入来源，不能按同名选 ip/config_a04 或其他历史副本。
- 主 FFT actual XCI:119 为 pipelined_streaming_io，:120 为16 bit，:126为natural_order，:129为convergent_rounding，:131为scaled，:134为realtime，:135为2048。
- 辅 FFT maximum transform=16384，runtime configurable；residual_ifft_service4.sv:51 使用 24'h0D560B 将本服务实际变换长度配置为2048。不能将其每窗工作量写成16384点。
- sync_ota_top_a07.sv:145 实际 PROCESSING_LIMIT_CYCLES=536870912，不是 sync_sfo_top 默认400896；该保护值不是实时性能合同。

## 3. 确定的数据量、时钟预算与窗口坐标

| 项目 | 数值 |
|---|---:|
| 名义帧复样点 | 1336320 |
| 名义帧时间 | 2.67264 ms |
| 125 MHz帧预算 | 334080拍 |
| 150 MHz帧预算 | 400896拍 |
| 500 MHz帧预算 | 1336320拍 |
| E1原始输入 | 334215字，1336860复样点 |
| E1输出/E2输入 | 334098字，1336392复样点 |
| E2最终输出 | 334080字 |
| E1 Farrow/降采样物理请求 | 334106组 |
| E2 Farrow/降采样物理请求 | 334088组 |
| T09输入窗口 | 74×512=37888字 |
| 原始ring | 393216×128 bit=6 MiB |
| 每块SFO bank | 335872×128 bit |
| T06训练暂存 | 5172×128 bit=82752 Byte |

来源：sfo_two_pass_transport.sv:60,398-404,550-556；first_resampler:69；first_frame_scheduler:48-49；guarded_resampling_core:27。

T09窗口坐标由 residual_nominal_window_reader4.sv:70 确定：

- start_sample(j)=25984+17920*j，j=0..73；
- bank_first(j)=start_sample/4+9=6505+4480*j；
- 完整窗口要求 bank_written_exclusive >= 7017+4480*j；
- 最后一窗水位334057，完整bank334098；最后一窗后尚有41字；
- E1连续一字/150MHz时，窗口产生间隔4480拍=29.866667微秒，相当于3733又1/3个125MHz周期。

## 4. 原始ring和训练回读

### 4.1 当前阻塞点

sfo_raw_frame_ring.sv:52 在occupancy达到DEPTH后撤销输入ready。:189-194 只在读issue时推进retired_words；不存在外部无帧历史回收接口。连续125MHz四点输入充满容量的时间为393216/125MHz=3.145728ms。

sfo_two_pass_transport.sv:320-322 必须 raw_written >= ctxraw+WIN 才能配置E1，即原始窗口完整后启动。保守剩余空间：

393216-334215-256=58745字，连续输入只能支持469.96微秒额外启动滞后。

该余量还须覆盖检测/描述符等待、训练服务、bank等待和原始CDC暂存；不能把它全部分给任意一个阶段。

### 4.2 两种结构选择

| 候选 | 收益 | 代价与边界 | 建议 |
|---|---|---|---|
| 原始ring增加非破坏性训练读，复用原训练BRAM | 不新增整帧副本，保留T06数值路径 | 读端口仲裁、独立训练身份、退休前沿 | 首选 |
| 独立连续训练历史BRAM环 | 与E1读端口完全独立 | 额外容量；仍要证明最迟定位与覆盖边界 | 备选 |

实际训练范围是5272..25959，来自 initial_raw_reader_local_capture.sv:44,64-67,89-99。不要采用训练buffer模块默认的152..2919。

以raw窗口相对位置-172为基准，训练读从 raw_first_word+1361 开始5172字；转成tap_abs=5272+4*i，并附该frame id和全lane-valid，可保持旧T06局部捕获与不对齐读取数学行为。

E1每帧334215次RAM读，加训练5172次，共339387个读拍，占400896拍的84.657118%。理想余量61509拍；尚未扣交接、仲裁、CDC、响应和内部暂停。

仲裁两个候选：

- 有界整段训练burst：理想150MHz占口34.48微秒，125MHz消费5172字至少41.376微秒；必须依据CDC可用信用限制发读。易于给出服务界。
- 固定配额交错：减小E1突发暂停，但增加读请求身份/响应路由与暂停计数。只有前者不能满足峰值空间时才采用。

训练读不得推进E1的破坏性退休指针。回收边界必须综合最早候选、训练任务、E1读任务和在途响应。未检测到帧的历史按检测最大回看距离释放；不能无限保留整个段。

### 4.3 避免训练与初始估计循环依赖

sync_sfo_top.sv:161-177 只有frame context、fine record和initial_result全部存在才形成transport context。训练回读必须由独立的早期frame任务启动，不能等该context。

T06可以等待capture，但等待计入计算保护：

- initial_raw_to_fft_frontend.sv:97 的service_active包含WAIT_CAPTURE；:283-286执行8拍FLUSH后等待lease；:346用MAX_CYCLES检查全部等待。
- initial_estimation_service.sv:105,283,287-315,394 从coarse/fine join后的ACQUIRE/START/RUN持续计时，并可能先占FFT lease。
- local capture的rst连接外部rst，而不是FLUSH local_rst，见 raw_to_fft_frontend.sv:124-126。因此预填训练不会被后续8拍FLUSH清掉。

首选先提交早期frame任务用于训练回读，5172字完整并校验后再向T06发布该帧coarse/fine。备选增加capture_ready准入并调整内部计时起点；这会扩大T06控制修改面。不能默认增加34-42微秒训练等待后原65024拍保护仍够用。

## 5. SFO A/B生命周期和逐窗启动

### 5.1 现有bank不是普通等待清空的双缓冲

intermediate_frame_bank.sv:69-72 支持旧帧sequential读取时新帧写入，但要求write_next<issued。:204-217 在sequential请求接受后取消committed，读身份独立保留。响应信用和FIFO在:67,86-87保留。

因此“旧单例E1+T09+E2约6.05ms，大于2Tf=5.34528ms”只能否定整bank释放后才能重用的简单模式，不能单独否定现有受保护交叠。

两种选项：

- 首选逐窗提前估计，使bank整块退役尽量在2Tf内完成，再开始下一次占用；所有权简单。
- 备选保留旧读/新写交叠，需要同时证明地址前沿、响应捕获、旧新身份和单读口仲裁。不得将仅有committed=0当作写许可。

### 5.2 提前窗口的必要改动

当前阻塞条件：

- transport.sv:324-325：E1 done后才发T09配置；
- transport.sv:474-475：窗口定位仅匹配bcomm；
- bank.sv:101-105：稀疏读要求committed；
- residual_estimator4.sv:309-315 和 nominal_window_reader4.sv:162-176：检查完整源和整帧范围；
- estimator4.sv:104-105：当前仅按front空闲和队列信用启动窗口。

首选已写水位确认窗口完整后再发front cfg；备选E1旁路截窗进入独立BRAM窗口队列。首选存储更省且沿用旧74窗数据访问和数学路径；备选端口隔离更强但需额外队列峰值证明。

应新设独立writer identity及written_exclusive；不能直接用write_next，因为bank.sv:186-189在最后一字后把它清零。提前稀疏读仍是非破坏性读取。最终E2配置必须同时具备74点成功结果和完整E1成功提交，避免半帧产生成功输出。

如果新帧写入时旧帧仍在同bank sequential读，新帧提前稀疏读不能抢占未完成的旧读事务；当前每块bank只有一个读事务端口。首选方案应尽量通过提前估计消除此种同bank交叠需求。

### 5.3 计时语义

不得提前发配置后任由reader等待未来窗口：

- residual frame watchdog332999拍@125MHz；
- grid front watchdog4999拍@125MHz；
- nominal reader watchdog20000拍。

这些计数从状态进入开始，含源等待。首选将窗口未齐备的等待放在front启动之前，计算watchdog继续覆盖真实计算；生产等待单独记录并与E1进度绑定。备选更改多个子核的暂停计时，影响更大。不得简单拉大watchdog然后视为吞吐已闭合。

## 6. FIR/Farrow的静态周期证据

actual XCI目录：Sync_OTA.srcs/sources_1/ip。

| 生产IP | C_LATENCY | C_INPUT_RATE | C_OUTPUT_RATE | SV wrapper |
|---|---:|---:|---:|---:|
| t07_g3_up47 | 18 | 1 | 1 | +1拍clip弹性寄存 |
| t07_g3_up15 | 10 | 1 | 1 | +1拍clip弹性寄存 |
| t07_g3_down15 | 14 | 1 | 1 | +1拍clip弹性寄存 |
| t07_g3_down47 | 30 | 1 | 1 | +1拍clip弹性寄存 |

前三列分别在各XCI约115-135行；up47/up15/down47 C_LATENCY:118，down15:119；生成synth VHDL同值。四个生成的C_LATENCY参数合计72；四个clip寄存再加4拍。所有IP启用C_S_DATA_HAS_FIFO=1。公开元数据尚未明确C_LATENCY与完整AXI最小延迟的映射，因此既不能把它直接命名为纯算术延迟，也不能确认其已包含或排除了FIFO固定延迟。不能把76拍直接宣称为完整接口总延迟；见第10节进一步核查。

Farrow arithmetic.sv:480-493为23级valid/tag；input_ready=!reset。实际乘法farrow_mul_t16/h16为3拍，加法18/28/32为1拍。guarded_farrow_stream.sv:188-210先把返回结果写入64深FIFO，因此issue至下游接受还至少增加1拍。

Farrow启动时初始化15个剩余lane phase，:162-175；scheduler已经留16拍INIT_PHASE覆盖它。一个accepted input包含16个上采样点，每拍可发16个Farrow请求。

合法E1步长268395191..268475721，E2步长268434651..268436261。相对Q=268435456：

- E1全帧坐标漂移对应的16点组增减，ceil(334106*40265/Q)=51组；
- E2相应ceil(334088*805/Q)=2组。

这是坐标消费/产生差额上界，不是完整管线stall上界。完整stall上界还必须证明上游FIR的elastic控制和Farrow信用不会引入额外周期性空拍。

首组所需输入的几何上界：E1允许to±101、q0为0或0.5，对16lane的四点插值窗口，最多需前60组上采样输入；E2固定坐标相位约126，需前9组。严格公式为ceil((max_rounded_base_lane15+3)/16)。该启动预读不是每帧都额外产生60个存储读字；它包含在固定输入总数中，做保守周期预算时可以显式计入并标注重复计算的安全余量。

### 6.1 完整周期表达式

E1/E2描述符合法路径从cfg接受到HOLD有96个后续时钟边沿：30步除法、29步初相位乘法、29步末相位乘法以及8个固定状态。scheduler固定阶段为32 CLEAR+1 START+16 INIT+101 QUIET_TAIL=150拍。

准确服务表达式为：

Cservice = 96 + Cwrapper/launch/context_ack + 150 + Crun + Ccompletion/bank_publish

其中Crun从RUN_FRAME进入到确认所有输入、六个stage计数、请求输出、pack和Farrow信用均排空为止。它取决于最后输入进入上采样链、最后Farrow请求、最后物理输出与pack交接中最晚的事件，不能只用输出字数。

可用条件性保守模型为：

Crun <= I + D + H + Lup + Lfarrow_response + Ldown + Cpack/edge

I为固定输入总字数；D为坐标速差导致的额外服务差额；H为启动窗口几何预算；Lup/Ldown必须含官方AXI接口FIFO附加延迟；Lfarrow_response至少24。只有证明FIR为无外背压的一组/拍elastic流水、64信用不耗尽、ring每次循环只产生坐标差额所允许的阻塞，才可将D取51/2。当前不把这个条件模型冒充已完成的形式证明或普遍最坏值。

缺失依据明确为：(a) FIR完整AXI固定延迟/恢复；(b)所有合法step/phase下ring和FIR组合的严格pause界；(c)新训练仲裁及CFO内部服务的最坏暂停数。新代码完成后应先静态补齐这些条件，不以反复仿真猜参数。

## 7. residual74固定工作量、精确尾部与剩余未知

### 7.1 可直接确定的阶段

- 每窗source capture512拍@125MHz；完整窗口后本地BRAM replay第一字需3个后续边沿（reader.sv:202-219）。
- FFT ingress为132到33位异步FIFO，prefill32个窄样点，CDC_SYNC_STAGES=2，FFT每拍一复样点@500MHz；输出预留4096窄项，避免实时FFT因下游被截断。
- 导频selector1拍+rotate3拍，共4拍，pilot_front2.sv:1-2。
- pilot_grid接收512拍后GAIN从+12逐拍探测至-2，合法输入幅度<=46341保证至迟-2可取，故GAIN=1..15拍；随后512字读取及2拍流水。
- 从最后一个FFT四点字被pilot_front接受，到最后grid字被下游接受，连续ready时为518+G拍，最大533拍。若官方FFT status尚未观察到，front commit还必须额外等待status；不能只看最后data。
- 两个完整grid packet slot只解决front/aux重叠。aux必须等point完成才可启动下一窗，不能只依据最后IFFT输入已送完认定空闲。

### 7.2 最后IFFT数据到point的精确成功路径

以最后IFFT四点字接受边沿为t=0：

1. t=2：功率最后一字写入bank，进入SCAN；
2. t=3..514：发512次扫描RAM读；
3. t=515：消费最后扫描结果，peak DONE；
4. t=516：interpolator接受peak；
5. t=517：MATH；
6. t=518：请求80步除法；
7. t=519..598：80步除法；
8. t=599：消费除法结果；
9. t=600：FINALIZE；
10. t=601：point_event被LS接受。

依据：power4的两级寄存；peak_triplet4.sv:187-218；peak_interpolate.sv:149-177；div_u80_u49_rne.sv:69-86。因此最后IFFT字到point_event为601拍（无异常、valid interpolation、无内部反压）。

### 7.3 最后point到最终result的精确成功路径

以第74个point_event被LS接受为t=0：

- t=1 ACCUM，t=2..8执行SSE与PPM准备；
- t=9 PPM除法请求，t=10..89执行80步，t=90消费；
- t=91 PREP_STEP，t=92第二次除法请求，t=93..172执行80步；
- t=173 LS进入DONE；
- t=174 backend捕获LS；
- t=175顶层residual捕获backend；
- t=176外层接受result。

所以最后point到result交接=176拍=1.408微秒。最后IFFT四点字到result=777拍=6.216微秒。输出result不被反压时该尾部固定；重构若新增结果寄存或提交闸门，应显式加拍。

### 7.4 不能消去的FFT延迟变量

实际XCI和生成包装没有提供主2048 FFT以及最大16384、实际2048 IFFT的完整accept-to-result延迟数字；厂商主体HDL加密。当前没有启动IP工具去重新求值。

定义Fm、Fa分别为第一宽输入字接受到最后宽输出字返回的完整主FFT/辅助IFFT服务时间，均换算到125MHz并含输入prefill、串行化、CDC相位以及status同步。定义Cs为每窗请求/原始bank到local cache填满的服务时间。则逐窗启动模型为：

front_j_start = max(window_j_ready, front_previous_free, packet_credit_ready)
front_j_commit = front_j_start + Cdispatch + Cs + 3 + Fm + (518+Gj) + Cstatus_commit
aux_j_first_input = max(front_j_commit + Cqueue, aux_previous_free)
point_j = aux_j_first_input + Fa + 601
result_last = point_73 + 176

其中Gj<=15；同一窗口的front与aux串行，不同窗口可并行。不能把Fm/Fa归零，不能用watchdog代替。

在无窗口积压条件下，应证明front和aux各自的启动间隔小于等于4480/150MHz，而不是要求同一窗口front+aux延迟小于窗口间隔。

## 8. 已发布RUN03可支持的数字及限制

引用现存 Sync_SFO/docs/verification/T10_RUN03_INDEPENDENT_REVIEW_20260915.json；它是旧单帧无外背压、无噪声单径、SFO约-150ppm的记录，不是新结构或全参数最坏证据。

- E1 accepted output连续334098字，first_cycle401599、last_cycle735696；
- E2 accepted output连续334080字，first_cycle974620、last_cycle1308699；
- T09相邻point_event间隔2652..2654拍@125MHz，平均2653.20548；
- 第一point相对T09 cfg为4852拍；
- 最后point到result为176拍，与上述静态推导一致；
- 不同窗间隔的数据相关变化与GAIN逐拍选择一致，但本轮未证明仅此一种变化来源，不能据此直接把2654当所有输入上界。

历史tb时钟为timescale1ns/1ps下的#3.333333333，实际半周期截取为3.333ns，周期6.666ns。由已发布事件差值除以6666ps，E1 cfg到publish为334551拍，E2 cfg到complete为334461拍。不要除以6667ps或理想20/3ns后四舍五入冒称整数周期。E1 cfg到第一输出302拍、最后输出到publish152拍；E2相应277和105拍。这些拆分来自同一历史counter/time口径，仍不是全参数性能界。

## 9. 每个修改点的二选一摘要

| 修改点 | 首选 | 备选 | 首选理由 |
|---|---|---|---|
| 原始训练供数 | ring非破坏性回读到既有训练BRAM | 独立历史BRAM | 不复制整帧，保留数学 |
| T06启动 | 训练完整后发布coarse/fine | 增加capture准入/暂停计时 | 不侵占既有watchdog，不提前占FFT |
| 无帧回收 | 多读者最早保留绝对水位 | 分段固定容量捕获 | 符合连续变长段，容量有界 |
| residual提前窗口 | bank水位齐备后front启动 | 输出旁路窗口BRAM队列 | 改动小，维持原顺序和坐标 |
| bank复用 | 提前估计后整bank释放 | 旧sequential读前沿保护下覆盖 | 所有权更简单 |
| source等待 | front启动前等水位 | 多层watchdog暂停语义 | 不让生产等待侵入计算保护 |
| FIR/FFT/Farrow | 保留现有数值结构 | 待实际瓶颈后专项替换 | 第一轮无需改变定点参考 |

下一步应先冻结窗口水位记录、bank身份/提交/取消合同、原始回收公式以及内部CFO读取服务上界，再由唯一开发者修改。静态资料仍不足的项目如实标注；仅在用户另行批准后进行必要的数值对比、真实核心仿真与物理时序检查。

## 10. Vivado 2021.1 本地 IP 与官方接口合同复核

本节仅查阅文件与官方文档，未启动 Vivado、仿真器、综合器、C model 或任何实验。核查日期仍为2026-09-17（CEST）。

### 10.1 本地版本和可读性

安装根为 C:/NIFPGA/programs/Vivado2021_1。data/ip/xilinx/fir_compiler_v7_2/doc/fir_compiler_v7_2_changelog.txt:1-4 为2021.1、v7.2 rev.16；xfft_v9_1/doc/xfft_v9_1_changelog.txt:1-3 为2021.1、v9.1 rev.6，与生产生成包装的版本一致。

本地xgui中的延迟计算Tcl（包括xfft_v9_1_utils_timing.tcl）为Xilinx加密格式；厂商HDL同样受保护。现有生产IP目录虽然已有 *_sim_netlist.v，但仅顶层参数与端口可读：up47文件:157起、main FFT文件:166起为pragma protect加密区，不能从文本追踪内部FIFO/valid级数。没有尝试解密或绕过保护。component.xml仅保存C_LATENCY的生成参数，并没有可读的计算公式。

### 10.2 官方文档版本边界

- [PG149 v7.2，2022-10-26](https://www.xilinx.com/support/documents/ip_documentation/fir_compiler/v7_2/pg149-fir-compiler.pdf)：p.133修订表说明较2021-01-21只更新Answer Record，故本文引用其中未标为新改动的接口和采样率规则；这不是将2022版IP替换为2021.1版的授权。
- [PG109 v9.1，2022-05-04](https://www.xilinx.com/support/documents/ip_documentation/xfft/v9_1/pg109-xfft.pdf)：p.97记录2021-08对SCALE_SCH/配置TDATA的文档修订，2022-05为C model资料；吞吐及latency定义未列改动。生产仍锁定2021.1 rev.6。
- [UG958，2020.2 FIR Compiler 7.2](https://docs.amd.com/r/en-US/ug958-vivado-sysgen-ref/FIR-Compiler-7.2)交叉确认输入FIFO默认16项及复位至少两拍；该资料用于合同交叉核对，不补造延迟数值。

### 10.3 C_INPUT_RATE=1能够支持什么结论

PG149 p.69说明SSR一次处理一拍中的多个并行样点；p.69-70说明整数速率配置按固定样点周期消费，启用FIFO后仍按该周期从FIFO消费。四个生产IP均C_INPUT_RATE=C_OUTPUT_RATE=1、C_NUM_CHANNELS=1、无CONFIG/RELOAD、无ACLKEN。将总线beat视为处理单位，能据此采用稳态每拍一个输入beat、每拍一个输出beat的服务能力合同；输入输出beat内部样点数量按各级倍率变化。

这不是无条件的s_axis_tready常高证明。合同前提是复位/清空完成、对应IP的m_axis_tready持续许可、输入遵循握手、没有旧阻塞造成的在途积压。在当前整链中，最终输出无外背压不等于每一个FIR的m_ready恒真；Farrow窗口/信用仍可能产生内部暂停，必须由整链设计单独上界化。首个ready边沿、从历史阻塞恢复的控制延迟也不能只从rate=1推出。

PG149 p.124将blocking接口latency解释为可变、GUI只给minimum；p.125只有关闭输出TREADY才承诺固定延迟。本轮不建议为取得固定延迟而直接关闭现有握手，原因是Farrow前后仍需真实弹性流控。

### 10.4 可给出的保守排队项与不可给出的常数

定义Lempty为厂商确认的“FIFO初始为空、复位释放完成、无上下游等待”的实际AXI首输入接受至其相应首输出接受延迟。输入FIFO为16项且消费间隔I=1时，已接受数据在输入队列中最多有15个先行beat。对队列等待加一个服务边沿作保守取整，可以预算额外16拍；这是排队项，不是FIFO空转固定延迟。

在处理能力持续一拍一个beat、无其他额外停顿时，可使用：

Laxi <= Lempty + 16
sum_four_fir_and_clips <= sum(Lempty_i) + 64 + 4

若后续通过同版本厂商元数据确认Lempty_i确实等于当前C_LATENCY_i，才可把右侧代入72+64+4=140拍。140是该条件下的保守预算，不是本轮已证明的无条件端到端上界。空FIFO持续满速运行通常不会产生最大排队项，故这里有意保守。

如果给定额外阻塞总数B，还须证明阻塞传播/恢复不会制造未计入的空拍，才能将B加到公式。不能把B只统计在最终输出口，也不能从FIFO深度16猜测其固定接口延迟等于16。

本轮没有得到Lempty与C_LATENCY的权威映射，不能给出可信的无条件额外延迟数值。第6节将72误称为纯算术延迟的表述已更正。

### 10.5 FFT已有明确的完整延迟定义，缺少具体表值

PG109 p.64-65的GUI Latency定义为：核心初始idle且上下游不插入waitstate时，从首输入到末输出的完整时钟数；该值包含该配置实际核心执行，而非仅算术流水。若取得生产配置在NFFT=11时的GUI表值，可以直接形成500MHz服务预算，再添加项目RTL的预填充、宽窄转换、CDC、状态返回及握手边界项。GUI数据结束点不等于项目status已同步返回，后者须独立计入。

PG109 p.43、53支持pipelined streaming连续帧吞吐，但明确要求仍遵守输入TREADY；p.59指出运行中切换NFFT可能等待旧流水清空。本工程aux最大16384不应误用为每窗16384，实际residual配置2048；若aux与其他不同NFFT使用者共享，必须计入排空/切换，否则不能照搬固定2048预算。

生产XCI/XML未保存GUI Latency表，本地计算Tcl又加密。不能凭N=2048断言总latency=N、2N、3N或4N，也不能以旧RUN03的2654拍窗口周期代替表值。

### 10.6 两种补齐路径及首选

首选对现有生产XCI作一次只读的Vivado 2021.1 IP参数/GUI Latency读取，冻结四个FIR minimum latency及主/辅助FFT在2048点的完整latency表；不生成目标、不改配置、不运行综合/仿真。这是厂商设计元数据提取，与功能实验不同，但本子任务未启动工具，应由父任务按本轮授权统一安排。

备选向AMD获取相同IP修订的正式接口延迟说明，或者提供已冻结的同配置GUI截图/导出表。更换FIR为无FIFO/无backpressure或自写FIR也能建立自主可审查的流水，但会改变接口与实现范围，不应只为填一个预算常数而提前采用。
## 11. 可执行的逐窗水位接口设计（待主开发者实施）

本节是静态接口规范，不表示RTL已修改。只读核对当前生产代码；不启动Vivado、综合或仿真。保留74窗坐标、每窗2048点、FFT缩放、pilot选择、归一化、peak/LS运算、定点位宽和结果顺序。

### 11.1 结构选择及边界

首选“bank持有单调写水位，在完整窗口可读后发送授权事件”。150MHz域只在本窗512字实际写入完成后发WINDOW事件，125MHz域消费该事件时才启动front stage。整帧成功提交另发COMMIT事件。数据仍通过原请求/响应CDC读取原bank，不复制数值路径。

备选为跨域发送可合并的累积窗口数/水位快照。它能减少事件数，但需为两个bank保存不同身份的最新快照、处理配置先后顺序、旧epoch快照和终态不被合并丢失。首选事件流总共仅150条在途上限，更容易证明顺序、容量和授权有效性。

本轮首选同时关闭同bank的“旧帧sequential读、新帧writer追赶”重叠，仅在旧读最后响应已被消费后复用整个bank。另一块bank仍可与其并行。备选保留旧覆盖前沿协议，但新帧sparse窗口会与旧帧sequential事务争用唯一读端口，必须再做事务抢占/仲裁与服务上界；第一轮不建议同时引入。整bank复用能否在2Tf内完成仍需全局周期模型确认，不能因所有权更简单便宣称性能通过。

### 11.2 单位、窗口界限与事件布局

所有bank地址、水位均按128bit字计数，每字4个复样点。名义sample0位于bank word9，bank word0对应名义sample-36。

S(j) = 25984 + 17920*j                  // 名义复样点，j=0..73
B(j) = 6505 + 4480*j                   // bank首字
W(j) = B(j) + 512 = 7017 + 4480*j       // bank排他末字
W(73) = 334057; FRAME_BEATS = 334098

授权不需要发送快速变化的真实最大水位。WINDOW事件的watermark固定为W(j)，表示截至该排他地址的连续数据已可读，是实际已写水位的保守快照。收到该授权的reader可使用available_first=-36、available_last=4*W(j)-37；后者恰好为S(j)+2047。

新记录宽100bit，建议固定如下，所有域作为一条记录经过sfo_record_cdc_fifo：

| 位段 | 字段 | WINDOW | COMMIT |
|---|---|---|---|
| [99:98] | kind | 2'b00 | 2'b01 |
| [97:66] | frame | 源frame | 同frame |
| [65:34] | generation | 源generation | 同generation |
| [33:27] | slot | 0..73 | 74 |
| [26:8] | written_exclusive | W(slot) | 334098 |
| [7:0] | source_error | 0 | 0 |

kind=2/3保留并视为协议错误；本轮任何生产错误继续使用已有sticky fault/全链poison路径，不另发可能被排在数据后面的错误事件来延迟取消。

事件CDC深度建议256。采用整bank释放且仅两bank时，每个所有者最多有74个WINDOW+1个COMMIT，总数不超过150条；pending寄存器若另计，保守151条，仍低于256。该证明要求bank直到对应所有者所有事件已发、T09已成功、E2读完才可复用，不允许描述符队列在无bank所有权时提前生成事件。256*100=25600bit是逻辑存储量，实际BRAM因端口宽度/深度映射另计，不假称恰好一个BRAM。

### 11.3 精确端口变更

| 模块 | 新增/调整端口 | 时钟与含义 |
|---|---|---|
| sfo_intermediate_frame_bank | output source_valid; output [31:0] source_frame, source_generation; output [18:0] source_written_exclusive | 全为clk150；当前不可变所有者及已实际写入排他水位 |
| sfo_two_pass_transport | output residual_cfg_streaming; output residual_progress_valid; input residual_progress_ready; output [99:0] residual_progress_record | 全为clk125侧接口；mode随原cfg握手原子接受，progress另走原子CDC |
| sfo_residual_estimator4 | input cfg_streaming; input source_progress_valid; output source_progress_ready; input [99:0] source_progress_record | clk125；cfg握手锁存mode，progress按活动frame和slot消费 |
| sfo_residual_fft_grid_stage4 | input cfg_window_granted | 随原cfg_valid/ready锁存，授权只针对这一窗口 |
| sfo_residual_fft_window4 | input cfg_window_granted | 随cfg握手单独保存，CONFIG态转交reader |
| sfo_residual_nominal_window_reader4 | input cfg_window_granted | cfg握手时验证来源许可，不增加未来数据等待态 |
| sync_sfo_top | 内部连线连接新增mode/progress端口 | 算法外部输入输出接口无需因本改动扩展 |
| sfo_residual_delay_backend4 | input source_wait | clk125；仅传递给LS计时使能，详见11.10 |
| sfo_residual_ls74 | input source_wait | clk125；仅禁止纯生产等待期间COLLECT idle_count自增，阈值不变 |

原cfg_descriptor[221:0]、front descriptor[228:0]、req/data/result记录宽度可以保持。新增mode在transport内部把residual_config_cdc从222扩为223，打包{streaming,old_record}，出CDC后分别接原record和新mode；禁止mode用另一个xpm_cdc_single跨域。新增window_granted在两个125MHz包装中与对应descriptor同拍保存，不改变旧字段位段。

sfo_residual_fft_window4实际位于rtl/sfo/fft_service，当前:108实例化nominal reader、:223-234保存描述符。它与sync_sfo_top也是必要修改点，不能只修改最初列举的五个文件。进一步核对LS静默计时后，首选方案还需backend/ls74两处计时使能穿透，合计九个模块，见11.10。旧调用者/明确完整帧模式应显式连接cfg_streaming=0、cfg_window_granted=0；不得把新增输入悬空并依赖X/Z被当作false。生产及非生产实例清单在修改时统一核对。

### 11.4 intermediate_frame_bank：数据存在性与所有权

当前bank:61-76使用writing/write_next；:186-189在末字把write_next归零；:101-105要求所有请求都committed。新增水位不能直接复用write_next。

建议状态规则：

1. 首个合法write handshake锁存source_frame/generation，置source_valid，source_written_exclusive=1。
2. 之后每个合法write handshake令source_written_exclusive=s_beat+1。s_last后保持334098；filled→committed时不清水位/身份。
3. sparse读取、publish和estimate均不释放source owner。sequential请求接受时可沿用现有committed清零，但source_valid仍保持，写入准入仍关闭。
4. sequential最后响应消费且所有读响应排空后，才清source_valid、水位归零，允许新帧首字。若最后消费和新帧首字同拍，采用保守下一拍开放，避免多个非阻塞赋值竞争。
5. reset/poison/故障优先于新授权、读写和释放。异常当拍不得发布提高水位；RAM写命令、计数和水位更新必须采用同一合法提交条件。

当前memory由sfo_uram_frame_bank直接在clk150写入XPM URAM，读延迟2拍。正常write握手边沿与水位寄存更新同边沿；事件发射器下一拍读取旧寄存水位再产生授权，故授权不能早于物理写入。若主任务后续为RAM写口加命令寄存，则watermark必须跟随真实RAM写提交边沿，不能仍跟随上游accept。

writer_allowed在本方案中改为：已在写同一owner，或者bank真正free；free必须包含!writing、!filled、!committed、!reading、!source_valid以及响应FIFO/rv均空闲。不能保留现有!filled&&!committed就开放新writer的规则，因为sequential开始时committed已经清零。

对req_sequential=1保留现有完整帧、committed身份、estimate_seen、base=0、count=FRAME_BEATS的全部要求。对req_sequential=0改为：source_valid、身份匹配、count=512、合法范围，并且33bit无溢出的req_base+req_count <= source_written_exclusive。不要求整帧committed。命中最新write边沿时使用前一拍watermark，最多延迟一拍，不旁路放宽。

transport还应严格核对slot<74、req_start_index==S(slot)、req_beats==512，避免仅满足大范围但读错名义窗。bank可以只验证边界和身份，由transport承担窗口坐标合同。

### 11.5 transport：提前配置、授权与最终提交

当前:324-336把cfg发射与E1成功publish绑在一起；:474-475只从committed身份查找请求；:617把publish直接送bank；:727把尚未committed的残差结果判为bad=8。

建议按以下时间线拆开：

1. E1 context接受(cr)后，锁存独立cfg_pending/record，形成source_complete=0、source_error=0、nominal_length=N、source身份一致的早期cfg。frame级available范围可标为空[0,-1]，它不是窗口准入证明。cfg_streaming=1；cfg_valid与record持续保持直到cfgr接受。不能使用下一帧cw或已被更新的e1frame直接组合替换尚未握手的cfg载荷。
2. bank首字写入后获得有效owner；每bank保存next_window_slot和next_window_end，初值0/7017，已发一个WINDOW后分别+1/+4480。利用小位宽加法与寄存比较，不把动态乘法和64bit身份比较串成跨域ready路径。
3. source_written_exclusive达到next_window_end且该frame cfg已入cfg CDC，才装载一个pending WINDOW事件。事件数据固定W(slot)，不能在valid&&!ready时随实时水位增长。只有progress CDC的write handshake才推进slot/end。全frame事件按E1 frame顺序发射，不在两个bank之间交错。
4. E1成功完成且bank publish_ready时立即提交bank；此时不再依赖旧cfgr，cfg在前面已有独立事务。E1失败不发COMMIT并通过既有fault传播取消所有在途窗口。
5. 已发74个WINDOW并且bank publish成功后，发COMMIT(slot74,water=334098)。为简化单个E1上下文保持，可将e1state的值3用作WAIT_COMMIT_EVENT；完成事件入CDC后再返回IDLE/翻转next_bank。正常额外开销是几个控制拍，必须计入周期表。
6. 125MHz侧cfg与progress是两个CDC，不能假设哪个先可见。estimator在IDLE或当前frame尚未接受时保持progress FIFO头，不弹出/误报未来frame；活动frame需要WINDOW时才检查精确身份和slot。前一frame的75条事件必须全部消费后，才能切下一frame cfg。

窗口req匹配从bcomm/bframe/bgen改为source_valid/source_frame/source_generation，匹配仍要求one-hot。req_valid/ready接受前后不等待未来水位；因为WINDOW已担保数据可读，若bank再检查水位不足，应立即作为内部协议错误，不能在reader启动后无限挂起。

新progress FIFO的wr/rd_error、reset_busy准入和poison必须并入现有两个域fault逻辑。复位要覆盖cfg/progress/request/data/result所有CDC及bank身份，不能只复位estimator留下旧epoch记录。已有global poison策略继续使用，不增加局部成功恢复。

### 11.6 estimator：每窗授权与COMMIT终态

cfg_streaming在cfg handshake锁存streaming_mode，并清commit_seen。旧模式保持当前:309-315的source_complete、身份、nominal范围检查；流模式保留身份、source_error、nominal_length检查，但不把整个帧尚未完成视为失败。流模式每一个front启动都必须有WINDOW授权，不能仅靠frame级cfg声明放行。

WINDOW事件的允许条件：kind=WINDOW、error=0、frame/generation等于活动descriptor、slot==front_issued、slot<74、watermark==W(slot)且<=FRAME_BEATS。授权字段有误立即fail_frame，不通过暂停watchdog掩盖。

在原fcfgv条件(state==RUN、无front_inflight、front_issued<74、inflight<2、qar)上再与合法WINDOW事件；front_start=fcfgv&&fcfgr当拍才消费事件。qav、front_issued自增仍与同一个front_start绑定。front descriptor的available范围用本事件快照重建；传cfg_window_granted=1，source_complete不伪置1。旧完整源模式不需要事件，cfg_window_granted=0并沿用原available范围。

COMMIT事件只在流模式活动frame内接受，要求identity匹配、front_issued==74、slot==74、watermark==FRAME_BEATS、error==0、!commit_seen。可在第74窗计算尚未结束时置commit_seen；不需要等全部point。这条记录是在150MHz bank已成功publish之后发出，因此commit_seen代表真实全帧提交。

数学backend结果仍经过当前:371-373的全部计数/身份/队列空检查。若检查成功但streaming_mode&&!commit_seen，把结果字段保存后进入新增WAIT_COMMIT状态（现有3bit状态值7可用），不重新计算、不输出m_valid。接到COMMIT后转DONE；若先已有commit_seen则直接DONE。同拍COMMIT与数学完成可保守下一拍进入DONE，或用明确的commit_fire旁路，二选一需统一优先级。

这样成功残差结果不可能在bank committed之前跨回150MHz，E2现有匹配/estimate_seen流程可保留。当前transport:727的bad=8不应被简单删除；若不采用COMMIT终态而选择允许early residual结果，必须把“已知owner但尚未commit”改为有界等待，并保留无owner/重复身份的错误判断。这是备选方案，首选COMMIT终态使合同更清楚。

### 11.7 grid/window/reader：最小合同调整

sfo_residual_fft_grid_stage4在cfg握手时将cfg_window_granted与descriptor一起保存，到SETUP给main的cfg握手时传保存值；不得使用当前输入的live标志。其5000拍计时、数值模块和输出计数完全保持。

sfo_residual_fft_window4也在自己的cfg handshake保存此位，并在CONFIG态传给nominal reader；当前cfg_saved[228:0]位段不变，新增独立saved_grant寄存器即可。原30000拍TIMEOUT_CYCLES不变。

nominal_window_reader4:162的许可由source_complete改为(source_complete||window_granted)，仍必须source_error==0且source身份匹配。legacy完整源保留原整帧available范围检查；window_granted模式将:175改为检查本窗口[S(slot),S(slot)+2047]被available_first/last覆盖。先验证slot<74和N，再用充分位宽计算末样点，不能在窄位宽加法溢出后比较。

本模块不增加WAIT_FOR_FUTURE_SAMPLES状态。REQUEST/CAPTURE/PLAY的20000拍计时照常计入仲裁等待、CDC、读取和FFT反压；原512输入/输出、样点索引、lane mask、last、frame/generation检查均保持。读完整512字后才PLAY的本地缓存行为不变。

### 11.8 watchdog：生产墙钟与计算计时分离

保持所有现有计算门槛：front age>=4999、aux age>=4479、reader TIMEOUT_CYCLES=20000、FFT window TIMEOUT_CYCLES=30000；这些已启动事务的计时从不暂停。pilot_grid和peak_triplet各自20000拍计时也保持不变。LS的20000拍COLLECT静默计时另见11.10，不能遗漏。front只在窗口授权后启动，因此生产等待根本不进入5000拍计时区间。

将frame_age重命名为compute_age或明确其新语义，阈值仍为332999。它不是74个窗口各自重置，而是整帧累计；正常ARM/RUN计算时间、仲裁、排队、内部反压和计算间控制拍都计入。

只有如下严格条件同时满足时，才允许把本拍视为纯生产等待并不增加compute_age：

pure_producer_wait = streaming_mode && state==RUN && front_issued<74
  && !source_progress_valid
  && !front_inflight && !aux_inflight && qreserved==0
  && front_issued==point_count
  && fcfgr && bwr && qar;

bwr是backend的window_ready，它同时要求backend处于WAIT_WINDOW且LS可接收下一点。不能用!bbusy替代：backend整个活动frame期间busy一直为真；也不能完全省略bwr，否则point_event后的LS内部累积周期可能被误扣为生产等待。fcfgr要求front真正回到可配置状态；qreserved==0排除已有packet/填充资源等待；source_progress_valid为真但身份错误时必须报错，不可冻结。

ARM始终计时；存在任何front/aux/packet/LS活动都计时；有授权却被内部ready阻塞也计时。compute_age达到阈值时仍按原比较失败，不能在最后一拍突然进入pure wait来撤销已发生的超时。WAIT_COMMIT是在数学结果已完成后等待生产终态，可停止compute_age，但仍接受abort及生产故障，不能输出成功。

另设独立生产墙钟计数，在clk150自E1配置接受到COMMIT事件写入CDC持续计数，覆盖内部停顿及发布等待。建议把E1_PRODUCER_BUDGET150冻结为400896拍（Tf目标），达到截止未完成则sticky fault/poison；这是从持续吞吐指标导出的设计上限，并非本轮已证明E1满足它。若父任务采用更细的每窗release/deadline模型，应保持等价或更严的每帧服务要求，不能用当前536870912保护值冒充生产期限。

这个生产计数不等待125MHz progress_ready，避免把算法消费时间混入E1供数预算；其截止是事件已可靠进入足够深的CDC。双bank/256深度容量证明使健康情况下该FIFO不会因等待T09而满，若其容量前提不再成立，必须重新核算，不能默默停E1计时。

可额外保留32bit饱和elapsed_age125诊断ARM/RUN/WAIT_COMMIT总墙钟，并分别报告compute_age、producer_wait_cycles、commit_wait_cycles。诊断不会替代全局Tf/缓存生命周期判定。生产耗时与计算耗时可以重叠，不能把二者直接相加后认定端到端最坏周期，也不能用较小者冒称吞吐。

### 11.9 每拍边界、错误优先级和静态验收项

正常窗口边界建议按寄存级执行：URAM write与watermark更新 → 下一拍watermark比较/装载pending事件 → event FIFO write → CDC → estimator front_start消费事件 → grid SETUP → fft window CONFIG → reader REQUEST。新增控制级只延迟准入，不改变窗口样点或运算顺序；具体CDC/控制周期并入第7节Cdispatch。

所有接口valid&&!ready期间payload及frame/slot/授权位保持；错误/poison优先于发起新授权/读写，取消后不接受旧返回作为新epoch。COMMIT、last write、publish、last sparse response和E2准入同拍时采用上一拍状态或显式next-state，一处统一，不让多个always块隐式争抢source_valid。

实施后的静态自审必须逐项闭合：

1. W(0)=7017、W(73)=334057、full334098，word/sample单位不混用。
2. 一个frame恰好74个WINDOW+1个COMMIT，无重复、无丢失、不跨frame交错；backpressure不推进发送索引。
3. WINDOW永不先于对应URAM数据写提交，数据在授权到最后读返回期间不被覆盖。
4. 源complete位保持真实含义；partial权限仅作用于被授权的当前窗口。
5. 两个CDC顺序不确定时，早到progress头被保留；当前frame完结已消费其COMMIT，再接受下一frame配置。
6. 没有全局ready组合环；150→125只有记录CDC，水位/身份不逐位同步；比较和事件载荷经过寄存边界。
7. 5000/4480/20000/30000门槛未增大、未暂停；332999只扣除了严格定义的纯生产等待；已有可计算工作不会被隐藏。
8. 生产截止、两个bank复用及T09每窗服务上界共同满足Tf；IP延迟未补齐项继续标明，不以watchdog未触发作为通过证据。
9. 任何生产失败/撤销同时阻止WINDOW/COMMIT成功发布和E2成功准入，所有在途CDC记录随统一epoch复位收尾。

上述方案由唯一主开发者实现；本报告未修改RTL。若之后保留旧覆盖写入模式，或改用累积水位快照，必须重审第11.4、11.5、11.8的所有权、缓存和等待界限。
### 11.10 下层LS静默watchdog补充审查（首选方案的必要组成）

sfo_residual_ls74.sv:4的IDLE_TIMEOUT_CYCLES=20000，:89定义timeout_now，:93据此控制s_ready，:183进入COLLECT，:189检查超时，:192在点接受后归零，:205在COLLECT无点时逐拍自增。它经delay_backend4.sv:138实例化。该计数同样会遇到窗口尚未生产的静默，因此不能只处理estimator的frame_age。

两种方案：

- 首选新增source_wait输入，经estimator→delay_backend4→ls74穿透。source_wait严格使用11.8的pure_producer_wait；LS只将:205改为“若!source_wait则idle_count自增”。20000阈值、timeout_now表达式、s_ready和超时错误码均不变，点接受、ACCUM及后续最终除法路径不变。source_wait不得使idle_count归零，只能保持。该计数仍限制两点之间扣除纯生产等待后的计算静默，窗口已授权后的FFT/队列/peak/LS等待仍照常计时。
- 备选不改LS，将20000拍定义为包含生产等待的更严格点间墙钟约束。这样必须额外证明初次COLLECT到第一点、每次ACCUM后重回COLLECT到下一点均小于20000；正常窗口间隔约3733拍只是其中一部分，不能单独作为证明。若保留备选，不得同时声称全部生产等待已与下层计算计时分离。

首选理由是只增加两个端口与一个计数使能，数值逻辑完全保持，同时统一生产/计算的计时含义。不能为了少改两行而把隐藏的生产期限留在数学模块内部。

非常重要的组合边界：bwr依赖ls_s_ready，后者依赖timeout_now。source_wait可以依赖bwr，但只能作用于下一拍idle_count的自增使能；绝不写成timeout_now=expired&&!source_wait，也不把source_wait直接加入s_ready，否则会构成bwr→source_wait→timeout_now/s_ready→bwr组合环。已经达到阈值的超时不能被source_wait撤销。

WAIT_COMMIT时LS已经输出最终结果并由backend接收，不在COLLECT，无需额外LS暂停。abort/poison始终优先，source_wait不得阻止取消。
## 12. CFO 双 bank 与共享 coordinate 的独立结构复审

本节按主任务提出的方案作独立静态复审：两份 cfo_rotate4、一份带 owner 的 coordinate、两个 335872x128 URAM、8 完整窗口队列、两项入口缓存、64 项最终读响应信用及两级无背压输出。没有修改 RTL、运行仿真、综合或数值实验。下列周期是源码推导和明确前提下的设计预算，不能代替实现时序通过。

本轮读取快照 SHA256：

| 文件 | SHA256 |
|---|---|
| rtl/cfo/cfo_coordinate_control.sv | 398DDEF7C34289369E8DDFC345ACB49CC22AEA0819DB83AC4E001B1A7AE414B2 |
| rtl/cfo/cfo_rotate4.sv | 77CC206F82BCBB0B09583334E14EF7C35FC5ACED1562DF383B91E80F5AABF916 |
| rtl/cfo/cfo_estimator_link_a06.sv | B9F455ECAEC01E93E35014AC3EBD0722067B089EEB0FC77E7A5A7FE8D762D0A7 |
| rtl/buffer/ota_cfo_window_queue.sv | AE1404BA7379D3FB6E6617091AADA8A4FCA3AF7F116D64EEFDC77AD84647F970 |

### 12.1 结论与共享核的确定性调度

首选保留一个 coordinate。正常数学路径由三次 32 拍 MULTIPLY、三次 112 拍 DIVIDE、三拍 ROUND 组成，共 435 个运算边沿。按请求在 E0 接受计，E435 后 m_valid 置高；若 m_ready=1，E436 接收结果；由于 OUTPUT_RESULT 不同拍接受新请求，下一输入请求最早在 E437 接受。依据 cfo_coordinate_control.sv:38-39,80-130。旧报告“435 延迟/436 服务”的表述不可被误读成输入启动间隔 436。

450 拍每任务预算可以覆盖此核心及少量请求/结果寄存级，但新增级数必须明确落在余量内。每帧 coarse/final 各一次，总预算 900 clk150，占名义帧预算 400896 拍的 0.22450%。它显著小于每帧 334080 拍的全帧旋转与 342968 拍等效的窗口 FFT 服务。

在以下不变量成立时，任一合法请求最多受另一 bank 的一次任务阻塞：每 bank 的 coarse 只发一次；final 只能在该 bank coarse 已完成后发；同一 bank 不同时存在 coarse/final 待处理；只有两个 bank，且旧 final 尾拍发出前不得复用 bank。final 优先但不抢占正在运行的任务，因此请求到参数落库预算为至多 450+450=900 拍（6 us），加法中不能再次漏掉仲裁级。两个 final 同时 eligible 时按 admission 顺序选旧帧，禁止按 bank 号永久优先。合法状态空间中没有需要第三个 coordinate 请求排在同一个已获 bank 请求之前的情况。

owner 最少包含 valid、bank、residual。它必须从输入握手保持到输出参数已安全写入 bank，不能在输入 s_valid 置位或结果 m_valid 刚出现时提前更换。结果 frame/generation/residual 要与 owner 及 bank 不可变身份一致；如果采用 epoch，再核对 epoch/lease。结果恒 ready 写入独立 coarse/final 参数寄存，不能直接连接 r1/r2.cfg_ready。当前 ota_cfo_chain_a07.sv:125-132 的 coordinate_output_ready 与全局旋转配置阶段耦合，不能用于新共享调度。

两种结构比较：

- 一个串行核 + 每 bank 参数寄存 + 请求 owner：首选。请求低占空，最多 3 us 额外等待；保持原数学与舍入。请求多路选择与结果身份比较可各自寄存，避免宽组合控制。
- coarse/final 各一核：消除最多一个任务的排队，代价是重复乘除控制/寄存器及更多布局和广播。只有以后出现超出当前两次/帧的工作量、不能满足的明确配置期限或实测布局隔离需求，才有采用依据。它不会消除单核内部 96 位加法、65 位比较/减法、ROUND 中舍入及符号运算的长路径；复制算术核不能作为这些路径的修复。

### 12.2 bank 与配置生命周期

FREE/FILL/SEALED/READING 四态可以使用；READING 必须覆盖最后读请求之后的响应、旋转和输出排空，直到接口末拍发出。另设 writer/final 局部 FSM 与每 bank valid/status，不应恢复全链串行 FSM。

FREE→FILL 在 context 接受时原子预留 bank，保存 frame/generation、step1/step2/raw_origin/coarse_frequency、admission 顺序及完成记录信用。FILL 包含等待 coarse 参数和配置的阶段。每 bank 至少分开 coarse_coord_pending/inflight/valid、estimate_valid、final_coord_pending/inflight/valid，或以等价局部状态保证不重复发请求。

r1 与 window_queue 的 cfg 必须各完成一次，并分别保存 armed；只有两者均完成才允许对应数据流正式推进。不能把 cfg_valid 长期拉高导致其中一方在再次 ready 后重复接受。queue 可以提前 reserve 槽，前 6496 个非窗口字不需要窗口数据槽；在第一个被选中字前必须已有预留槽。

writer 对每个实际 fork 接受字递增 written_count，正确末字必须是 beat334079、last=1、接受总数334080、74窗均完整发布或已被可靠 pending 保存。SEALED 不能由原始 s_record.last 或 r1 的最后输入单独触发：r1 还有 5 级流水。

estimator_link 的 m_ready 恒1合理。每个结果先完整寄存，按 frame/generation 匹配唯一非FREE bank，核对 link/front/backend error、estimate_valid 和未重复写入，再更新该 bank。允许匹配 FILL 或 SEALED；结果可能先于最后写入，不应把它视为错误。无匹配、双匹配、重复结果或失败估计触发全 epoch poison。现有 link:83,98-102,152-154 在末窗口后关闭一帧观测准入，只有结果消费才返回信用；等待 final 状态消费会人为阻塞下一帧。

final 启动条件应为：最旧 eligible bank 已 SEALED、estimate_valid/ok、final_coord_valid、无 poison，r2.cfg 已完成一次握手，旧响应及旧 final 作业已清空。参数/身份从所选 bank 锁存为本 final 作业上下文。不能从最新 coarse/global frame 字段重建最终输出身份。

同拍 result+seal、coordinate response+pending clear、tail+free、free+new context、credit return+issue 使用统一 next-state/计数表达式。首轮建议 bank free 后下一拍才可 allocate，增加一拍而避免同拍重租使旧结果覆盖新 context。另一方案是同拍 free/allocate，但必须规定新 lease 胜出并把旧统计/完成记录先原子搬走。

### 12.3 coarse 分流原子性与局部时序

首选一个 fork_fire = r1_valid && bank_can_write && window_ready。URAM wr_en、窗口队列的接受事件、written_count、beat/last 校验和 coarse 饱和统计均由同一事件推进。可用 window.s_valid=r1_valid&&bank_can_write、r1.m_ready=bank_can_write&&window.s_ready；bank_can_write 是本地稳定状态，queue.s_ready 不依赖 s_valid，因而没有组合环。也可用 fork_fire 作为 queue.s_valid，前提是该队列 ready 不依赖 valid，此快照确实如此（queue:40-46）。

禁止直接给两个分支同时送 r1_valid、又仅把两个 ready 相与返回上游：若 bank 不接收而 queue 接收，同一字会在 queue 重复写入。非窗口字仍须经过 queue 的接受事件以推进其 expected_beat，不能只给它被选中的字。

备选是每字两个独立 pending/accepted 位，分别完成 bank 和 queue 后才释放原字。它可以允许两支路不同拍接收，但控制和取消竞态更多；本场景 URAM 可每拍写，窗口槽预留已提供容量，首选同拍原子 fork。

两项 ingress 的 s_ready 应只取自身有界容量、writer 准入及本地 reset/poison，不能重新穿透 window FIFO 或 coordinate。旧 chain:89 的 stage!=INGEST 清缓存逻辑必须换成 writer 作业生命周期；final 正在读取另一 bank 不是清空 ingress 的理由。满队列同拍 pop 时保守不 push 可造成一拍恢复气泡，不破坏数据；若优化满时同时 push/pop，必须同时修改容量与 head/tail 选择，不能只改 ready。

queue 当前 s_ready 只依赖 active、预先维护的 selected/reserved 与本地 FIFO ready，:36-46，window select 不从当前225位输入做宽比较后再反馈。保留这一边界。r1 自身已检查身份/顺序；新增 bank 诊断比较若直接放进宽 RAM CE 与 r1.advance 扇出路径，需要单独寄存或预算，不能因两项 ingress 已存在就认为所有内部路径已隔离。

### 12.4 最终读响应信用与无背压尾部

sfo_uram_frame_bank.sv:21-44 为128位、335872深度、READ_LATENCY_B=2；数据无响应 valid，由使用方同拍发 rd_en 和 tag valid 并按准确延迟对齐。128位 bank 选择应位于寄存边界；若新增 mux 寄存，响应 tag/credit 延迟也相应变成3拍，不能仍按2拍配对。

64项 FIFO 的信用必须在发读请求时预占。推荐 used = issued - rotation_accepted，其中包括所有 URAM 在途、响应FIFO和其输出holding；发请求条件 used<64，消费 r2 输入时归还。只看 FIFO 当前 level 会漏掉2拍或更多在途响应，可能在 ready 突然撤销时溢出。若使用 issued-returned 及 FIFO占用两个计数，也必须证明二者之和与上述 used 等价，且所有额外holding计入同一容量模型。

当 used=64 且同拍 pop 时，可保守暂停 issue 一拍；不要为了消除这一低概率气泡增加到 r2 的长组合 ready 链。最终 r2.m_ready=1 后，cfo_rotate4:26-29 的 advance 恒为1；合法配置后，它在最后输入之前每拍可接受。因此正常 full 帧可连续发一个128位读请求/clk150，64项并不用于补偿外部 DDR 停顿。

首选先完成 r2 cfg，再启动 RAM 读；备选提前预读进入64项 FIFO，并用信用保护等待 cfg。两者数学不变，但前者状态更少，配置时间仅几个周期，本轮采用前者。

最后一次 rd_en 之后保留READING/排空状态，不能清 tag pipeline 或信用。第二级输出 last 是唯一 bank free 事件，同时核对 frame/generation/beat334079、issued=returned=rotation_accepted=interface_emitted=334080，以及无在途/残留响应。输出 last 的比较要使用本拍后的 emitted_count 或显式 +1，避免尾拍 off-by-one。

两级输出每拍无条件移动 valid，完整 IQ、frame/generation、beat、last 与饱和/诊断边带同步寄存；不受外部 m_ready、DDR ready 或 done_ready 影响。completion 槽在 admission 时预留，最后输出拍原子写完成记录后退 bank；done_ready 可以影响以后新帧准入，不能阻止已启动的最终流或丢弃完成记录。

### 12.5 周期表与容量包络

令 B=334080，Tf150=400896，Tf500=1336320。以下以“首个 coarse 输出被写入 bank”为 t=0，采用完整窗口发布后服务，源连续四点/150MHz，window/observation 路径无额外停顿。若从 context admission 计 bank 寿命，还要加入 coarse coordinate 排队/计算及配置/旋转首字流水。

| 事件或阶段 | 静态周期公式 | 说明 |
|---|---:|---|
| coarse 全帧写入 | B clk150 | 受内部窗口槽或上游供数停顿时加实际有界停顿 |
| 窗 j 完整 | 7008+4480*j clk150 | j=0..73；末窗334048，尾部另32字 |
| FFT2048 每窗 II | 15449 clk500 | 2048装载+11*(1024+7)+2051输出+9前端尾部 |
| 74窗核心服务 | 1143226 clk500 | 等效 ceil(*3/10)=342968 clk150 |
| 最末观测至残差 | 6792+1 clk150 | quality最坏正常分支与结果join；另计CDC/输入调度 |
| 结果可用基准 | 7008+342968+6793=356769 clk150 | 2.378460 ms，不含新增控制/CDC；此前各级流水可重叠 |
| final coordinate | ≤450 clk150 | 如果被另一任务占用，再加≤450排队 |
| 最终读出与尾部 | B+Lfinal clk150 | Lfinal明确包含读延迟/FIFO首字/旋转5级/输出2级/控制 |
| bank占有基准 | 691299+Lfinal clk150 | 4.608660 ms + 尾部；尚未加 admission前置及控制/CDC |
| 两帧 bank复用窗口 | 2*400896=801792 clk150 | 基准剩余110493拍=736.62 us |

建议把最终 local FSM 的 Lfinal 设计上限冻结为32拍，再用最终 RTL 的准确边沿表闭合，不能把32写成已验证实测。正常配置先完成、RAM每拍响应、r2恒可收时，RAM2、mux可选1、FIFO首字、5级旋转、2级输出和少量控制应能在这一预算内。所有等待项必须有硬件原因及有限上界；当前静态报告不把 watchdog 当服务上界。

稳态若 coarse 首字间隔确实不小于 Tf，则下一帧首窗在2.719360 ms，前帧估计约2.378460 ms完成，有约340.9 us用于内部控制/CDC裕量；前帧 final 与后帧 coarse/FFT可以重叠，最终流2.2272 ms小于Tf。实际 SFO burst 发布若允许压缩两个 frame，必须另用下面的跨帧包络，不能只引用单帧4窗。

8槽包括完整待消费窗口、正在捕获的预留窗口和归还信用尚未跨回150MHz的窗口。容量是4096个128位字=64 KiB；当前 ota_cfo_window_queue:36-38,107-112 的 occupied_slots 跨frame cfg保留，归还在窗口末样本被安全复制到本地tagged holding后发出，:64-70。FWFT FIFO 数据/头可见时间不同，但 issue 仍检查dq_v，:64，不能仅因header已到就无条件读数据。

通用静态条件是 Qreserved(t) ≤ 1 + Acompleted(t) - Rreturned(t) ≤ 8；最后一窗之后不再预留，可省掉前式的1。A由每帧的7008+4480*j决定，R由完整FFT装载完成及返回信用延迟决定。源码名义每窗相差30.898-29.866667=1.031333 us，单帧4槽只是其中一个边界。

作为可核查的“两帧最短间隔”保守包络：假定第一帧服务开始前队列空，两个coarse首字仅隔 B/150MHz=2.2272ms，窗口顺序不交错，最多一次帧间link关闭。可把这次关闭全部保守计为6793/150MHz=45.286667us，而不利用它与下一窗FFT计算的重叠。在第二帧末窗完成处，距第一窗完整为4.407466667ms；首窗装载4.096us。要让1+148-R≤8，只需至少141个信用已归还，即全部附加延迟 J 满足：

J ≤ 4407.466667 - 4.096 - 140*30.898 = 77.650667 us。

扣除完整45.286667us后端关闭，尚有32.364us给此两帧累计的额外窗口控制、CDC及信用返回延迟；这比仅说“8槽应当够”更具体。对于此前已有排队、不同 frame admission 规则或更多压缩帧，必须用真实的 A/R 重新闭合；不能把这个有前提的界限当任意多帧最坏证明。bank必须先等本帧估计成功和final尾拍后才free，这限制无限压缩，但应在全链周期表明确其与SFO输出ring的关系。若8槽耗尽，当前设计会在窗口起点内部回压r1，安全性可保持；这段停顿仍要计入bank寿命和SFO缓存最高占用。

### 12.6 资源、真实时序与故障恢复的未闭合项

两个335872x128 URAM各需 ceil(128/72)*ceil(335872/4096)=164块，共328块，逻辑有效帧每bank334080字，物理padding1792字。8窗128位BRAM FIFO约16 RAMB36，另有header/credit小FIFO、64项响应缓冲与两项入口。不能把URAM总bit数整除当实际拼接块数。

深URAM的地址译码、cascade选择、128位读出bank mux与FIFO写入均在150MHz真实路径上；原封装READ_LATENCY_B=2仅是功能延迟，不证明82级深度拼接能在具体布局过6.667ns。首选按原primitive封装保持数学与地址含义，在读出mux附近给明确寄存边界并同步tag；备选分组bank/read pipeline并增加固定延迟。后者占少量寄存器并改变控制周期，不能无依据直接改CASCADE_HEIGHT或时钟约束。

cfo_coordinate_control:40-55,117-124 的96位加法、65位比较减法和ROUND舍入/符号路径仍需真实综合/布局证据。请求宽mux和499位backend结果的两个64位身份比较应从寄存器起止，先捕获结果再比较/写bank，避免把结果频率或多bank选择广播至上游ready。双核不处理这些本质路径。

错误恢复首选整epoch sticky poison：立即停止新准入/读写承诺和成功输出承诺，两域通过既有async assert/sync release与FIFO reset completion屏障统一冲刷，所有owner、bank状态、窗口/观测/信用与在途tag一起失效，再允许新epoch准入。备选逐bank取消需要同时处理window FIFO、link单帧信用、coordinate在途与final输出前缀，明显更复杂，本轮不选。

poison不可只发一拍后自动恢复窗口串化而保留旧FIFO；当前queue快照已把poison150||slow_fault同步到500MHz，错误保持应一直覆盖至真正统一reset。复位不能依赖已经由复位清掉的短暂error作为唯一请求源而产生重复脉冲；不得在XPM reset busy未完成时再次自动触发reset。若自动恢复，外层首错/epoch状态必须保留至上层读取，避免复位把故障证据同时清空。

已经发出的输出前缀不能被RTL收回。整epoch失败时接口必须有可识别的epoch/失败完成状态，使接收方不把未完整结束的帧当成功；不应宣称poison能撤回之前已被Target VI接收的样点。此处不引入后级背压，也不要求为外部DDR停顿增加缓冲。

本节静态结论：该双bank/8window/双旋转/单coordinate结构在声明的周期合同内可行，保留单coordinate是首选；首轮必须落实原子fork、参数落库、按issued预占信用、completion预留和统一epoch恢复。尚未完成的控制/CDC延迟、任意允许跨帧到达包络及真实150/500MHz路径不得标为已通过。所有RTL实现仍由父任务唯一开发者完成。

## 13. 第11节逐窗方案首次 RTL 静态复核

本节对主开发者实际修改的九个 SFO 文件逐行只读复核，使用忽略行尾差异的 git diff，并阅读完整相关状态机。范围包括 sync_sfo_top、two_pass_transport、intermediate_frame_bank、residual_estimator4、fft_grid_stage4、fft_window4、nominal_window_reader4、delay_backend4 与 ls74。未切换生产 source manifest，未编译、仿真或综合；尚不构成全工程功能/时序通过。

### 13.1 发现项及处理状态

1. P1，新增 progress CDC 错误未进入 fault 聚合。最初快照 transport:346 把错误连到we[7]/re[7]，但:303、:797仅聚合旧0..6。父任务已收到即时反馈；再次只读核对确认现有:303已包含clk125的re[7]，:797已包含clk150的we[7]，本项已关闭。首选加入原有对应时钟域故障表达式；备选另建progress fault寄存/CDC，但重复已有机制，没有收益。
2. P2，WAIT_COMMIT期间绕过子级sticky错误：已关闭（2026-09-18，Europe/Berlin）。最新 estimator:341-344 在该状态先检查qerror、aerrors，再允许COMMIT转DONE；错误与COMMIT同拍时fail_frame优先，保持计算期限不作用于WAIT_COMMIT。采用分支内检查，未改其他正常运算。快照SHA256：899027E0EE348ABF3B4103A994FFEC97385A764509223AF3D99A01972AF1226A。

### 13.2 已逐拍核对的正确项

- 参数/端口：sync_sfo_top以SHARED_RAW_INPUT驱动transport与residual的渐进模式；transport的配置CDC从222扩展到223，仅附加streaming位，外部222位descriptor布局不变。estimator→grid→fft_window→reader的PROGRESSIVE_SOURCE与cfg_window_granted都传递，grid与window各在cfg握手时保存grant，没有live输入穿透。backend→LS的ALLOW_SOURCE_WAIT默认0，legacy未连接source_wait不会改变计数语义。
- 水位/地址：transport窗口端点初始化7017，每次WINDOW真正进入CDC后加4480，共74次；最后窗口334057，COMMIT为334098。estimator按同一序列独立核对slot与watermark。available_last=4*expected_window_end−37，第一窗28031，恰为25984+2047；reader使用有足够位宽的窗口末样点比较。原完整源模式仍要求整帧范围。
- 源所有权：progressive bank第一笔正确写入建立source_valid/identity，written_exclusive每次写入递增；last写和publish均不清水位。只有顺序读最后响应被消费才撤销source_valid。completely_free还要求无reading、qvalid、qbusy或RAM在途，下一frame不能覆盖未读旧数据。req部分范围采用33位基址+长度与19位水位零扩展比较，不因窄加法溢出放行。
- 稀疏/顺序互斥：部分读请求先匹配source_valid与source身份，再校验slot固定地址及512字几何；顺序读仍要求committed和estimate_seen。第74窗计算与COMMIT成功结束之前不会产生成功残差结果，故E2不会先于T09最后稀疏读抢占同bank。
- E1发布顺序：cfg_pending保存早期descriptor直到配置CDC接受，cfg_sent后才允许publish。publish同拍完成bank提交及E1 done消费，随后e1state=3；COMMIT可靠进入progress CDC后才回IDLE/翻next_bank。progress_pending满时payload保持；WINDOW与COMMIT不能同拍覆盖pending。commit_event当拍旧pending=1，下一条生成条件!progress_pending为假，不会重复COMMIT。
- 下一frame隔离：estimator的progress_active显式要求!commit_seen。旧frame可在COMMIT后继续最后数学尾部，此时下一frame FIFO头既不被消费，也不因身份不同报错。DONE/IDLE/ARM不消费progress；下一cfg在IDLE原子清commit_seen并换descriptor，到RUN才检查自己的FIFO头。
- COMMIT与数学结束同拍：commit_fire进入commit_seen，并参与最后结果处的WAIT_COMMIT选择。因此同拍COMMIT可以直接转DONE；没有COMMIT则保存结果进入WAIT_COMMIT，不重新计算。第73窗WINDOW与COMMIT分别占FIFO头，不会在同拍被消费两次。
- LS计时：pure_producer_wait完整包含无progress、无front/aux在途、qreserved=0、front_issued=point_count、fcfgr/bwr/qar。backend.window_ready又要求LS在COLLECT可收；source_wait仅门控下一拍idle_count自增，未进入timeout_now或s_ready，没有bwr→source_wait→ready组合环。20000门槛未提高，已到期错误不能因等待信号取消。
- 计算期限：frame_age只在ARM/RUN且非纯生产等待时递增；332999比较仍在纯生产等待时执行，因此不会因临界拍等待而撤销已有超时。front的5000、aux的4480、reader的20000及FFT window的30000计时未被暂停或放宽。
- 生产期限：cr接受边沿E0把producer_age置0，随后e1state非0时逐拍递增。在E400895之后age=400895，若E400896不是COMMIT入FIFO的成功边沿则报11；若该边沿commit_event=1则正常结束。因此该表达式实施400896个后续边沿的截止，并非明显少一拍。其起点是E1 cfg接受，终点是COMMIT入CDC，包含publish/pending控制耗时，不取决于125MHz最终消费。
- legacy默认：新增模式参数默认0；bank的整bank复用限制只在PROGRESSIVE_READ=1，旧覆盖前沿路径保留。新增source_*诊断寄存不参与legacy准入。实际生产切换前仍须明确使能SHARED_RAW_INPUT与新源集，不可因编写了可选路径就声称正在生产使用。

### 13.3 仍属全局预算的项目

上述逻辑关系正确不等于E1已被证明小于400896拍。FIR/FFT加密IP延迟和允许仲裁/内部背压上界仍按前文保留缺口，不能将新producer timeout当性能证明。两bank复用已由覆盖写改为最后顺序响应后整bank释放，应把新释放时刻纳入全链bank寿命与raw/SFO输出ring水位表。

窗口完整即授权之后，read request/data CDC的等待及FFT反压都仍计入计算期限；pure_producer_wait只扣除没有任何可计算工作且尚无授权的时间。若以后放宽其表达式或把bwr替换成!bbusy，必须重新审查LS/compute计时含义。

COMMIT握手整理已关闭（2026-09-18，Europe/Berlin）：estimator:85现为commit_fire=source_progress_valid&&source_progress_ready&&commit_good，:86的ready仍受rst/abort、当前frame/状态和!commit_seen约束。因此取消时不会计入未被消费的COMMIT；该修改未引入ready组合环。

## 14. 收口：可证周期界限、IP 预算门槛与剩余证据边界

本节截至 2026-09-18（Europe/Berlin）。只作源码与现有元数据的静态推导，没有运行仿真、综合、MATLAB 或 IP 生成。第13节两项修订已关闭；全局服务包络仍未闭合。以下的“上界”都列出必要前提，不用 watchdog 值反推正常服务性能，也不把预留余量写成已经测得的周期。

父任务已核对生产 FFT：main 与 aux 的 C_ARCH 均为3，即 pipelined_streaming_io；main 固定2048点，aux 的最大配置为16384点，本路径实际配置2048点。现有 XCI/XML 没有导出足以直接代入的完整数据/状态延迟。不能从 IP 实例名称、最大点数或某次旧波形猜测延迟。

### 14.1 健康 FIFO/CDC 固定开销的保守界限

设 T125=8ns，T150=20/3ns，T500=2ns。下列界限要求各域时钟连续、reset busy 已退出、没有协议错误、读端一直许可，且所述完整数据单元已写入；不包含满队列恢复、尚未生产数据、仲裁等待或物理亚稳态造成的额外同步延迟。CDC 是数字时序模型下的固定保守界限，物理 CDC 可靠性仍由实现约束与结构审查保证。

| 路径 | 源码界限 | 可使用条件 |
|---|---:|---|
| 已接受写入至异步 FWFT 第一次接受读出 | ≤1*Twr+8*Trd | CDC_SYNC_STAGES=2、空 FIFO 起步，完整目标宽度单元已写完 |
| 同步 FWFT 第一次接受读出 | ≤4*Tclk | 空 FIFO 起步且下游一直 ready |
| 窗口水位达标至 progress 在125MHz被接受 | ≤3*T150+8*T125，取11个clk125 | pending未被前一事件阻塞；窗口事件间隔满足下文服务条件 |
| 125→150 残差结果 CDC | ≤T125+8*T150，取10个clk150 | 结果通路空且 transport可收 |

依据为本工程可读的 XPM 源：xpm_fifo.sv:655-670 的写指针 CDC 加目的域寄存器，:745-750 的 RAM empty 寄存器，:1184-1265、:1353-1356、:1387-1393、:1435-1440 的两级 FWFT/empty/data_valid；xpm_cdc.sv:373、:378-382、:388、:416 的源 Gray 寄存和两级目的域同步。第一个接受写边沿先改变二进制写指针，随后源域边沿才寄存相应 Gray 值，故不能只算两个目的域同步拍。目的域预算包含指针寄存、empty、FWFT 两级和接受边沿，并留一拍保守边界。同步模式在 xpm_fifo.sv:893-961 绕过上述指针 CDC，连同 FWFT 和接受边沿取4拍。

FFT wrapper 的 prefill 依赖 rd_data_count，而非仅 empty。该计数路径在 xpm_fifo.sv:674 使用 CDC_SYNC_STAGES+2=4，:683-685 再寄存写指针，:1525-1529 再寄存读计数；所以不能用两级同步替代其延迟。132→33、33→132 的宽度转换每4样点构成一个128位数据字，2048点正好整除，不需要等待另一个不完整尾字。以上开销是空流水起步费用，不应逐数据字相加。

所读 XPM 源快照：xpm_fifo.sv SHA256=D3C1E861CDDF00EBC82552C464A46FB5228E68B4D458001D064B99E04134B9D4；xpm_cdc.sv SHA256=D08434ED5A310C44C13936D6EDA5381D64FF0F627A335368C85826A30E8ADAA7。最终生产源若更换这些实现，需要重核相应固定项。

### 14.2 一窗从授权到计算结束的可执行预算

窗口被授权即表示512个128位字已经写好。T09 对同一 bank 的稀疏读不与 E2 顺序读同时发生；另一 bank 的 E2 使用另一物理端口。因此在无故障且请求/数据 FIFO 已排空的正常窗边界，可列出：

1. reader请求125→150：≤T125+8*T150。
2. transport接收命令、发bank请求、首RAM请求、RAM两拍、同步响应FIFO首字：合计保守8*T150。
3. 首字数据150→125：≤T150+8*T125。
4. 后续511字以clk125连续填入窗口cache。数据FIFO深度1024大于单窗512字，150MHz生产快于125MHz消费；该段不需要满恢复停顿。

因此 reader请求被接受至512字cache填完 ≤520*T125+17*T150，向上取535个clk125。front_start至reader请求接受另3拍，cache填完至首个FFT输入宽字另3拍，合计前置 ≤541个clk125。

定义 Xm、Xa：对应 vendor FFT 从首个真实输入握手至本窗最后数据输出和最后状态输出均完成的最大clk500数，须含实际配置下可能的核心输入停顿；这里不是 C_LATENCY 的别名。main、aux均按本路径2048点配置取值，aux不能直接代入最大16384点的其他配置数字。wrapper的32个窄样点prefill等于8个宽字，连同4级计数同步、计数寄存及fft_active启动，保守取12个clk125；核心最后窄字至目的域最后宽字接受取9个clk125。状态toggle返回预算4拍已被该保守尾部覆盖。于是 wrapper附加界限为21个clk125。

主 FFT 最后宽字被pilot侧接受至最后grid宽字，已有源码界限为518+G拍，G∈[1,15]，故取533拍；grid完成/finish/重新允许下一front取4拍。aux完整包启动至首FFT宽字取3拍，最后IFFT宽字至point被接受为601拍，point至aux_inflight释放取2拍。因此采用下列带5拍边沿余量的充分界限：

Cfront ≤ 1104 + ceil(Xm/4)       （clk125）

Caux   ≤  632 + ceil(Xa/4)       （clk125）

窗口最快间隔4480个clk150，在125MHz为3733又1/3拍。两份grid packet slot和 front_issued-point_count<2 要求把释放边沿也考虑进去。选择每级 ≤3732拍作为本轮无窗积压的充分条件，则得到明确的 IP 门槛：

Xm ≤ 10512个clk500 = 21.024us；Xa ≤ 12400个clk500 = 24.8us。

这是结构能够使用的 IP 延迟预算，不是现有 IP 已满足的结论。其好处是 front、aux各自都快于源窗口节拍，而且两者串联预算7464拍小于两个最短窗口间隔7466拍，保留双slot信用释放边沿余量。若某IP超过门槛，不立即等同全局不可行：需要用实际front/aux串行与双slot依赖作max-plus调度，计算有限积压、最末窗尾部与332999计算年龄；不得擅自提高计算门槛。

在上述 IP 门槛、无既有窗积压条件下，末窗已生产至残差结果在125MHz被接受，取：

Ctail125 ≤ 11 + 3732 + 3732 + 176 = 7651拍 = 61.208us。

其中176拍为最后point至外层结果接受，601拍已在Caux内，不重复额外加777拍。再加结果CDC，ceil(7651*6/5)+10=9192个clk150，后续保守统一用9200拍；其余不到8拍为交接边沿余量。

### 14.3 E1/E2 与双bank复用的定量合同

令 C1 为 E1 cfg接受至本帧提交、包含计算/原始输入仲裁/发布控制的完整服务周期；C2为E2从允许启动至完整服务结束的周期，均以clk150计。实际 bank可在E2最后输入响应被消费时释放，比E2最终输出结束早；用完整C2核算是保守选择。

源码循环、descriptor和流水中已有固定量可以组合成以下条件性预算：

C1 ≤ 334664 + 5172*ntrain + Lfir + K1 + D1stall

C2 ≤ 334447 + Lfir + K2 + D2stall

Lfir=Σ四个FIR真实AXI空流水延迟；K1/K2为尚未完全封闭的控制/边沿开销，D1stall/D2stall为额外内部停顿的有限上界。ntrain为一个E1服务区间内实际抢占raw读端口的完整5172字训练任务数。固定基数已包括描述符96拍、scheduler150拍、输入字数、允许step下的几何漂移与初始预取、Farrow24拍，以及FIR输入FIFO保守64拍和clip四拍；不得再次重复收费。该式仍以FIR名义每拍接受及下游合法连续供数为前提；它明确显示尚需证明的量，而非声称所有IP停顿已经计算完。

ntrain=1时C1基数339836，ntrain=2时345008。不能只因名义每帧一个训练任务，就自动认定任意E1区间至多一个；应由任务到达、前一帧延迟和准入规则证明。训练支路在自身响应信用不足时不持续占用raw读端口，因而不能把其下游任意停顿直接等同raw每拍被抢占；真实仲裁事件仍须闭式计数。

外层残差年龄332999拍不包括被严格识别的纯生产等待。即使完全不利用这一减免，下式也足够保证年龄期限：

ceil(5*C1/6) + 7651 ≤ 332999。

对应C1≤390417拍；建议把390400拍作为设计服务目标，保持RTL原有5000/4480/332999和producer400896门槛不变。这个更严格的目标还为producer提交截止留10496拍，不代表将其watchdog修改成390400。

| 预算情形 | 留给真实Lfir、K和额外内部停顿的余量（clk150） |
|---|---:|
| E1目标390400，ntrain=1 | 50564 |
| E1目标390400，ntrain=2 | 45392 |
| E2目标400896 | 66449 |

双bank的精确所有权条件是 Rseq(k)≤E1cfg_accept(k+2)，其中Rseq是第k帧E2最后顺序RAM响应真正被消费且无在途/holding的边沿，不能用E1写完、估计完成或E2开始替代。令WE2为本帧满足commit与残差后因前一E2作业/下游内部供数而等待的周期，则在固定帧期Tf150=400896下，下式是充分的保守复用条件：
C1 + C2 + WE2 + 9200 ≤ 2*400896 = 801792。

ntrain=1时，对未闭合项的具体预算是：

2*Lfir + K1 + K2 + D1stall + D2stall + WE2 ≤ 118309拍 = 788.726667us。

ntrain=2时为≤113137拍。若同时只采用较松的C1≤390400、C2≤400896，则WE2还必须≤1296拍；不能由两个单独的服务目标擅自推出双bank一定够用。更实际的FIR和控制延迟一旦得到，直接代入前一个更宽的118309拍余额即可。

确定WE2应使用同一时间轴上的递推：A2(k)=max(COMMIT(k),RESIDUAL(k))加实际结果交接延迟，S2(k)=max(A2(k),D2(k-1))，D2(k)=S2(k)+C2(k)，WE2(k)=S2(k)-A2(k)。若下游CFO内部存在有界停顿，则它已计入C2(k)，不可在两处漏计或重复收费。仅证明平均C2<Tf不足以令WE2=0，仍需考虑A2(k)的跨帧抖动及首帧条件。

### 14.4 CFO 与全链缓存的已有余量及仍需联立的量

第12节的CFO单帧核心服务为1143226个clk500，相对1336320个clk500的帧期，差193094拍=386.188us。即便把完整6793个clk150的后端尾部全部串行收费，仍留170450个clk500=340.9us给相关交接、仲裁和额外停顿。这是有意义的设计余量，但实际允许的连续帧到达由SFO输出ring、CFO bank所有权及配置共同决定。

第12节从首个coarse写入计的CFO bank基数691299拍，对两个帧期尚有110493拍。必须在同一条寿命中再计入coarse前置坐标/配置、final坐标排队、CDC/控制和读出尾部；不能拿首字后的余量直接证明从context准入起bank已经可复用。单coordinate每job接受间隔437拍，按450拍保守预算，两job/帧900拍只占400896拍的0.2245%，因此没有仅为吞吐复制coordinate的必要。参数必须按bank落库，不能因核空闲就覆盖另一bank后续cfg所需的结果。

全局raw最高占用应计算Qraw(t)=Araw(t)-Rretire(t)，并逐时刻满足≤393216字；Rretire受frontend lease、训练pin、E1安全读取前沿共同约束。E1读334215、训练5172、合计339387字/帧只是平均带宽需求；raw的469.96us起读余量不是所有延迟可自由相加的池子。必须把早期frame/coarse/fine、训练完成、初始估计、E1准入和响应消费的前后关系放到同一时间轴。特别是在完整raw窗口已经到达之后，直到E1开始安全退休前沿之间的延迟必须≤(393216−334215−256)/125MHz=469.96us；处理段初始化和等待下一个空闲SFO bank都计入这段接口级期限。仅满足两帧bank寿命不自动满足该raw截止，这一约束当前仍未闭合。

SFO输出ring的65536字深度需要证明 max_t(AE2(t)-DCFO(t))≤65536；CFO两bank和8窗信用会影响DCFO。第12节两帧压缩示例提供32.364us附加交接余量，但它明确要求开始时队列空、仅一个帧间后端关闭和两个连续coarse帧，不能替代任意允许多帧包络。所有安全内部反压应计入上述Dstall/WE2/高水位，不能因为FIFO不会溢出就称持续吞吐达标。

用户已明确最终输出没有后级背压。当前新top完成记录CDC的125MHz读端也固定许可，不再保留旧报告中“Host done_ready可能任意延迟”的性能依赖。本节不为外部DDR停顿增加预算或缓存；内部准入、窗口、bank和结果归属仍要完整核算。

### 14.5 剩余工作分类与当前能否宣称达标

1. 已从现有源码闭式取得：固定窗口位置/次数、FIR配置的名义rate、Farrow与控制固定循环、上述健康FIFO/CDC开销、残差最后point尾部、coordinate服务、CFO自写FFT循环、bank释放事件以及每一容量必须满足的不等式。第13节WAIT_COMMIT错误优先与COMMIT真实握手已关闭。
2. 仍可继续纯静态闭合、不需要反复仿真猜测：允许step下FIR/Farrow链所有内部弹性停顿的有限包络，ntrain的跨帧最大值，训练/初始估计/raw pin与lease退休时刻，C1/C2和WE2的递推，raw/SFO输出ring/CFO窗口的最高占用及双bank完整寿命。此类问题需要补齐设计合同和数学时序表，不能仅写OPEN后交给测试发现。
3. 缺失的静态IP参数：四个FIR真实AXI空流水延迟及C_LATENCY与握手延迟的确切对应、主/辅FFT实际2048点配置的完整输入至数据/状态结束界限。当前FIR C_LATENCY=18/10/14/30不自动等于整链真实AXI首字延迟；FIFO深度只给容量，不能证明任意停顿后的恢复拍数。需要生产版本的已有元数据/官方合同，不应拿watchdog或旧波形替代。本轮明确可接受FFT门槛为Xm≤10512、Xa≤12400个clk500；若超出再以真实参数重做有限排队，而非提高验收门槛。
4. 必须留给后续有授权的EDA/有限验证：真实映射资源（848/960 URAM只是当前拼接预算）、125/150/500MHz完整约束下的路径/布线/扇出/级联时序、CDC与同步释放复位实现、vendor核心实际接口和边界行为、数值bit一致性以及Target VI/板级连续接收。源集类型绑定零error不覆盖这些证据；保持旧数学算子也不自动构成0 LSB数值比较。应按冻结设计只验证必要边界，不重新创建猜想驱动的实验序列。

结论：本轮局部控制修订通过静态复核，架构有可量化的周期余量；但缺失的IP延迟、内部停顿包络及联立多帧缓存寿命尚未全部代入，因此当前不能宣称全局持续500MS/s已达标，也不能宣称“已无静态风险”。本报告给出的是下一步闭合设计所需的数值门槛和确定性约束，不是仿真或上板许可。


## 15. E1/E2 完整服务上界的进一步收紧（继续静态审查）

本节针对主任务要求把第14节K1/K2/Dstall收敛到确定的控制拍数、几何事件数和外部仲裁事件。没有运行仿真、MATLAB、编译或EDA。源码中未发现新的确定功能缺陷；明确区分已经证明的RTL性质与由父任务另行核实的vendor服务合同。

### 15.1 必须给FIR变量的准确含义

仅给“空流水首字延迟”不足以推出任意有输入空洞/下游暂停时的服务曲线。因此本节Li表示第i种FIR在生产配置下的有限、无丢失、保序、II=1弹性服务延迟上界：完成reset恢复后，若数据可供且下游许可，不允许额外的无界自主停顿；输入空洞和下游停顿只能造成对应数量的服务空拍，再加该有限流水延迟。Lfir=ΣLi，四个16字输入FIFO另保守收费64拍，四个clip弹性寄存器另收4拍。I/Q两核共用控制且配置一致，所以它们是同一逻辑字的两个分量，不能把上述延迟/容量再乘2。

这个定义把先前含糊的“IP内部额外停顿”改成可检查的准确生产合同，而不是宣称已经从加密主体证明。C_INPUT_RATE=1和C_OUTPUT_RATE=1给名义速率；父任务仍需核实此配置的实际服务延迟/恢复含义。本节给出合同成立后完整的RTL上界，不再保留未知的RTL控制K或笼统Dstall。若只能取得单次空流水延迟，则下列完整吞吐式不得被误写为已通过。

### 15.2 从cfg到RUN的148拍，逐边沿固定

两种descriptor状态机的有限循环完全相同。以外层resampler接受合法cfg为E0、没有context FIFO满或reset恢复等待为前提：

| 边沿 | 操作 |
|---|---|
| E0 | 保存cfg，descriptor进入PREP，外层进入PREPARE |
| E1、E2 | PREP、COORD |
| E3..E32 | 30次DIVIDE |
| E33..E35 | ROUND_STEP、SET_STEP、START_PHASE_MUL |
| E36..E64 | 29次PHASE_MUL |
| E65 | SET_PHASE |
| E66..E94 | 29次END_MUL |
| E95、E96 | SET_END、CHECK；E96之后descriptor的HOLD有效 |
| E97 | 外层看到descriptor有效，PREPARE→LAUNCH |
| E98 | descriptor、engine cfg、对应context同拍接受 |
| E99..E130 | CLEAR_CORE，恰32拍 |
| E131 | START_CORE |
| E132..E147 | INIT_PHASE，恰16拍；Farrow的15个额外lane相位已经完成 |
| E148 | 首次RUN_FRAME输入握手许可 |

依据：first_pass_descriptor:135-219、second_pass_descriptor:134-218；first_resampler:PREPARE/LAUNCH与second_resampler:221-234；first_frame_scheduler:CLEAR/START/INIT。context_ready仅影响E98边沿，不改变描述符数学。

transport在E0同时登记e1state/e2state，在E1即可发raw frame请求或顺序bank请求，故读端预取与后面的147拍配置阶段重叠。SFO bank一笔顺序请求之后首RAM issue一拍、RAM两拍、同步FWFT首字≤4拍；64项响应信用在RUN开始前能够预填。既有raw hub的请求至首响应约6拍，同样通常被148拍启动覆盖。不能再把完整请求启动延迟按每个输入字收费。

### 15.3 Farrow环的几何证明：无隐含的每字气泡

设Q=2^28、P为当前第0 lane相位、s为step。代码的RNE只有在mu从255.5舍入至256时进位，因此用于索引的carried base可精确表示为 b(P)=floor((P+Q/512)/Q)。合法step下16lane窗口的端点为min=b(P)-1、max=b(P+15s)+2，故：

max-min ≤ ceil(15*s/Q)+3 ≤ 19。

即一窗最多覆盖20个样点。ring为64样点，每次接受写16点。设当前已写样点数w，下一次写后oldest=max(0,w-48)。ready条件是oldest_after_write≤min；issue要求当前[ min,max ]全部存在。

- 如果窗口因为未来样点未到而不能issue，则max≥w。由max-min≤19可得min≥w-19，必有w-48≤min，因此该时刻输入写不会被覆盖保护挡住。
- 如果输入写被覆盖保护挡住，则min<w-48，因而max≤min+19<w-29<w；旧窗口已经全部写入。旧数据不被覆盖的归纳不变量又保证min≥oldest，所以只要算术信用许可，这一拍能issue。
- issue使用接受边沿前的ring内容，下一次写保护的也是该旧窗口。对同拍issue/write的保守保护不构成组合ready环，也不产生固定II=2。

所需第k个请求的输入字数可写为：

F(k)=floor((P0+(16k+15)*s+Q/512+2*Q)/(16*Q))+1。

F(k+1)-F(k)只能是0、1、2；相对每请求一个输入字，额外供需事件不超过ceil((R-1)*abs(s-Q)/Q)。E1的R=334106、abs(s-Q)≤40265，取51个事件；E2的R=334088、abs(s-Q)≤805，取2个事件。正偏差体现为偶尔等待多一个输入字，负偏差体现为偶尔抑制一个过早写入；每个几何事件至多多一个服务拍。在第15.1的弹性FIR合同下，这些有限几何事件只移动对应的有效数据，不会被放大成额外无界的FIR停顿。

合法descriptor的首窗最大预取量分别为H1=60字、H2=9字。初始预取收费与上面的51/2个长期漂移事件分开，且对总输入I再加H本身已经是保守预算。最后request发完后pending=0，Farrow s_ready不再受旧窗口约束，所有尚未通过两级up FIR的尾部输入能够继续排空。

Farrow算术input_ready=!reset，valid_pipe[22:0]给23级不可暂停流水；接受issue至其结果可被响应FIFO消费，保守24拍。无下游停顿时issued-popped峰值为24，远小于64个预占信用。因此正常连续服务不会因credit_used<64而产生额外气泡。下游停顿时所有在途结果已有信用，FIFO不会先溢出；64满时首pop不允许同拍新issue只是恢复边沿的保守选择，已有约40个返回结果足以遮蔽重新发射的23拍流水，不形成额外的每字吞吐折损。依据为guarded_farrow_stream:52-60、81-113、177-210与farrow_arithmetic:480-491。

### 15.4 接口停顿逐一归属

E1输出：PROGRESSIVE_READ下，新frame仅在completely_free bank获准。首字之后writing保持为1，整帧最后字之前writer_allowed持续为1；T09稀疏读令seq_active=0，不能使safe_frontier撤销。E2顺序读必须等待本帧commit及残差成功，不能与本帧E1写阶段重叠。因此健康E1已经准入之后，bank写端m_ready每拍许可，E1输出背压项严格为0。依据intermediate_frame_bank:73-84、190-228和transport:377、392、599-605。

E2输入：顺序bank请求在cfg后立即登记，进入RUN前已有充分预取时间。issued-consumed预占64项，包含RAM两拍与FIFO在途；稳态每拍issue/pop，在途需求≤约7拍。短暂停顿后满信用恢复不造成缺少数据的额外固定气泡，因为剩余缓存远大于响应管线。因此没有其他读端争用、无错误时，E2数据源不增加独立服务等待。最后一条T09稀疏读必须先完成才有残差结果，本帧E2不会与该稀疏读争同bank。

E1输入：raw hub只有t_issue为1的边沿压掉p_issue。训练WAIT/MAP/切换不占读口，训练响应FIFO无信用时也不会持续霸占raw端口；因此训练仲裁总费用精确满足Braw≤5172*ntrain，不另加每任务切换费。这一结论由frontend审查者对rawstore:56-58独立复核。合法连续帧合同下ntrain≤2；它依赖Pmin>240169个输入字，名义帧间隔334080字满足。当前高密误确认不是有效连续帧的吞吐合同，不能用严格递增frame地址替代Pmin。

E2输出：仍以Bout表示在本帧运行区间内输出ring实际撤销ready的总拍数；它是唯一保留的下游服务项，由CFO/ring服务包络审查给出具体数值，不能设为任意外部背压。它包括ring满或首字header FIFO满等健康容量等待，不包括最终Target VI（该接口没有背压）。如果CFO审查证明ring不会到满，Bout严格取0。

context许可：当前join的first和second各为32深同步FIFO，不存在CFO ready组合穿透。metadata在T06完成之前已经独立排入CDC。未进入E2的first上下文最多由两SFO bank保留；CFO拒绝新上下文时，下一E2帧无法整个容纳于65536+64字output ring及有限FIR/Farrow流水，故不能连续完成任意多个E2而不断积累second上下文。保守得到first待join≤3、second待join≤1，32项容量不满；因此正常epoch复位完成后Wcontext=0。这里要求内部FIR容量远小于剩余的268k字；本设计必须满足的Lfir≤59693服务预算及现有小FIFO已足以满足该容量前提。如果IP有未披露整帧缓存，该前提必须重核，不能只引用接口名。

### 15.5 完成/提交/下帧与bank复用的边沿

令T为“最后一个up15输入被Farrow接受”和“最后一个物理down47输出被pack接受”二者中的较晚边沿。使用较晚值可覆盖输出先结束、输入guard尾部还在排空的情形。

| 最迟边沿 | 操作/可见状态 |
|---|---|
| T+1 | 最后一条packed输出接受（若其早已完成则更早） |
| T+2 | scheduler观察完整stage计数、arithmetic_empty、pack空，RUN→QUIET |
| T+3..T+103 | QUIET_TAIL恰101拍；末拍进入COMPLETE_FRAME |
| T+104 | 外层ACTIVE接受engine完成，进入HOLD_RESULT |
| T+105 | E1 publish或E2 completion被接受；E2外层/transport归IDLE |
| T+106 | E2可接受下一个cfg；E1生成COMMIT pending |
| T+107 | E1 COMMIT进入progress FIFO、transport归IDLE |
| T+108 | E1可接受下一个cfg |

E1最后window结束水位334057，最后写入334098，随后还有上述排空101拍，所以在本节规定的健康progress容量条件下，第74个WINDOW已入FIFO，不会把COMMIT卡在尚未递增的slot后。progress FIFO256项大于两bank共150项WINDOW+COMMIT，cfg CDC32也大于并存帧数；因此此处不需要另加未知CDC满等待。COMMIT入FIFO的边沿与125MHz端何时消费是两件事。

bank释放不等待上表QUIET：E2最后输入响应真实pop时，intermediate_frame_bank:231-236同拍撤销reading和source_valid。消费的是整个FRAME_BEATS的最后响应，所以issued=returned=consumed_next=FRAME_BEATS，RAM在途已经为空；XPM FWFT最后pop同拍清empty/data_valid（xpm_fifo:1219-1227、1387-1393、1435-1440）。因而该pop之后bank的completely_free成立，最早下一边沿可被E1 cfg准入。不能提前到最后rd_en或最后RAM返回来释放。

### 15.6 收紧后的完整数值式

下式以clk150计，Lfir按第15.1定义，健康复位已经完成，所有cfg合法。训练数取实际抢占本帧E1的ntrain。E1 bank已准入后无输出停顿，E2输出总等待为Bout。

C1_commit ≤ 334215 +148+60+51+64+4+24+107-1 +Lfir+5172*ntrain
          = 334672 + Lfir + 5172*ntrain。

C1_nextcfg ≤ 334673 + Lfir + 5172*ntrain。

C2_done ≤ 334098 +148+9+2+64+4+24+105-1 +Lfir+Bout
        = 334453 + Lfir + Bout。

C2_nextcfg ≤ 334454 + Lfir + Bout。

C2_bank_free ≤ 334098 +148+9+2+64+4+24+1-1 +Lfir+Bout
             = 334349 + Lfir + Bout。

上述最后一式用T作上界，已经保守包含本不必等待的down FIR尾部；真实bank释放通常更早。与第14节相比，原K1/K2可取8/6，几何和仲裁外没有新的内部Dstall变量。下帧cfg所需的一拍区别已经显式列出，不能把done周期直接当最小启动间隔。

首个E2 packed输出另有独立界限：cfg→首输入148拍，初始预取9字、Farrow24拍、四clip、物理前导8字及pack1拍，保守加四FIR FIFO64和2拍边沿余量，得到≤258+Lfir拍。相对首字，帧内源侧额外空洞可保守界为2+64+Lfir拍，再加Bout；这是有第15.1服务合同支持的到达包络，不能只由空流水latency推得。父任务CFO审查可用它核算ring与8window占用。

采用ntrain≤2后，C1_commit≤345016+Lfir。若仍采用第14节390400设计目标，则允许Lfir≤45384；E2独立帧期条件为Lfir+Bout≤66442（采用nextcfg口径）。使用更准确bank释放而非整个C2_done，双bank保守复用条件成为：

C1_commit + 9200 + WE2 + C2_bank_free ≤ 801792，

即 ntrain≤2 时 2*Lfir + Bout + WE2 ≤ 113227。

这些预算不要求修改400896/332999等watchdog。实际Lfir和CFO Bout代入后，父任务应以同一递推核对所有帧，不能只证明某一帧两个算式各自成立。

### 15.7 raw容量必须与服务空洞联立

frontend独立审查进一步指出：分别满足“完整raw窗口后开始退休≤469.96us”与“C1≤390400”并不足够。令Dcfg150为完整原始窗口到E1 cfg实际接受的延迟，考虑原始持续输入率5/6字每clk150和256字保留前沿，保守联合约束为：

Dcfg150 + C1_commit - 334215 + 2 ≤ 70494。

理由是本帧334215个输入字最多每拍消费一个；既然最迟C1已经全部消费，任意前缀消费下界为max(0,u-(C1-334215))，训练和内部暂态不能被藏在首次退休之后。以ntrain≤2代入本节已收紧式：

Dcfg150 + Lfir ≤ 59691拍（约397.94us的合计预算）；另列的2拍是pfloor至实际retired的流水。

此Dcfg必须包含等待初始估计、前一E1结束以及下一个SFO bank释放。若只使用较松的C1≤390400，则Dcfg最多14307拍=95.38us；不能仍保留全部469.96us给bank等待。该条件是同一缓存容量的接口级必要预算管理，不是新增仿真验收门槛。

### 15.8 跨帧服务的两个设计选择

当前E2完成后可以立即接下一cfg，没有固定400896拍整形；因此单帧服务小于Tf不能自动证明CFO看到的每一对帧都间隔Tf。没有发现由此直接导致的丢字，但它是必须由全局到达/服务包络封闭的调度选择。

方案A：保持当前E2尽快服务，使用合法raw帧间隔、上述C1/C2到达抖动、CFO bank/窗口服务和output ring容量联立，证明有限积压；优点是raw/SFO bank尽早退休，尤其有利469.96us容量约束，且不增加RTL。只要父任务得到足够宽的ring/两bank余额，这是首选。

方案B：在E2 cfg准入施加400896拍最小帧节拍，或等价的有初始相位定义的令牌节拍；每次仍允许帧内连续600MS/s burst。它让CFO帧间包络更简单，但等待必须算进WE2及raw的Dcfg联合约束，不能随意把一个完整Tf等待加在已满raw上。另一种直接等CFO bank预留才开E2同样需要该审查，且会把CFO最终读出寿命直接反馈到SFO退休，本轮不应在缺预算时盲目选用。

若唯一缺口最终是vendor无法提供第15.1的有限服务合同，有两种明确路径：保留生产FIR并从固定版本元数据/官方接口保证补齐该合同；或重新实现完全显式的定点FIR/弹性流水，并证明同一舍入/饱和和II=1。首选前者，避免没有实际瓶颈便重写半带FIR。外加一个FIFO不能把一个未知服务率的黑盒自动变成可证明II=1，这不是有效的第三种“补丁”。


## 16. 与CFO服务包络联立：消除Bout/WE2的循环假设

本节独立复核CFO审查者的新服务式，并采用主开发者拟加入coordinate ROUND_PRE后的Q=440拍，以及本节之后LS/除法改造预留的残差尾部R=9600个clk150。该数值表是设计预算，实际RTL变更须由主开发者落盘后再对照。

### 16.1 G与Bout不是互相定义

G只表示本帧相对一字/clk150的内生供数空洞，不包括output ring反压本身。当前SFO充分界为G≤66+Lfir；单独的Bout表示该ring实际施加给E2的外部服务等待。第15.1的vendor弹性服务语义保证暂停与恢复不会把Bout放大为另外一个无界内生G。

令b_k为CFO第k帧首个coarse字写入bank，e_k为残差估计被chain接受，d_k为最终输出last。CFO审查者给出：N=334080，L=4635，B=6832，E0=356850，S=345216，Fmin=334520，Fmax=334992。估计递推为e_k≤max(b_k+E0+G,e_(k-1)+S)。串行coarse满足b_k≥b_(k-1)+N，交替bank所有权满足b_k≥d_(k-2)≥e_(k-2)+Fmin。因此直接有：

e_(k-1) ≤ b_k + max(E0+G-N,S-Fmin) = b_k+22770+G。

当前coarse尾部最早b_k+N，旧bank最迟e_(k-1)+Fmax释放，所以帧间等待≤23682+G；加coarse坐标/配置912拍，再加ring满恢复16拍，得到Bout≤24610+G。

关键容量不变量是accepted-consumed=occupancy+outstanding≤65536+64=65600<N。E2串行生产一帧的过程中，CFO消费者最多跨越一次帧间bank切换；当前帧数据不会横跨两次完整N字vacation。源端内生空洞只能使ring少积数据，不能在ring满时另外创造一个CFO拒收区间。故Bout不是必须再代回G的循环变量。

8窗信用的独立充分界为Qslot≤2+floor((G+23098)/4480)。当G≤8192时≤8。证明方式是取“第一次第9槽需求”之前的无窗阻塞历史，按源窗口最短4480拍间隔与确定FFT服务得此上界，矛盾于第一次第9槽需求，因此没有假设结果来证明自己。跨帧最短窗口间隔7040拍更宽，不削弱该界。

final不跨下一估计的依据必须用严格最短服务，而不能把15449上界误当下界。源码cfo_fft2048_core:151-188每窗至少2048 LOAD、11*1024蝶形和2048 OUTPUT，合计15360个clk500，忽略所有排空/控制仍成立。新frame观测0信用恢复后尚有73窗，最少73*15360*3/10=336384个clk150，大于Fmax334992，保留1392拍余量。因此final不会积累任意多个待执行任务。

### 16.2 联立后的E2、两bank与raw

代入Bout≤24610+66+Lfir后：

C2_done≤359129+2*Lfir；C2_nextcfg≤359130+2*Lfir；C2_bank_free≤359025+2*Lfir。

G≤8192对应Lfir≤8126。取这个门槛时，C1_commit≤353142、C2_nextcfg≤375382，均小于名义400896。对物理±150ppm的真实连续帧，应使用frontend报告的Pmin=334029字与保守Tmin=400834个clk150；不能把细定时搜索±360当成已证明的真实TO抖动。更宽的物理偏差合同则替换Tmin重新代入。

下面给出正常连续帧的归纳，前提是frontend的本帧有效context在完整raw窗口之前已经可用，且F_k表示该完整窗口在150MHz域可见的时刻。令固定准入可见延迟为δ（包括实际读写指针可见与cfg接受边沿）。假定前帧尚未导致额外bank等待，则E1在F_k+δ启动。E2资格时间A_k有足够保守的界：

F_k+334215 ≤ A_k ≤ F_k+δ+345016+Lfir+9600 = F_k+δ+354616+Lfir。

因而资格抖动J≤20401+Lfir+δ。对单个E2服务器，C2_nextcfg<Tmin时，max-plus递推的任意长度忙期都满足：

WE2≤max(0,C2_nextcfg-Tmin+J)=max(0,3*Lfir-21303+δ)。

取Lfir≤8126、δ=0时WE2≤3075拍。第k-2帧bank的最迟释放相对F_k不晚于：

δ +713641+3*Lfir+WE2-2*Tmin，

即至少提前60574拍；δ的小幅增加至多消耗2δ拍该余量。前一E1服务结束也至少提前约47691拍。因此“本帧E1不额外等前E1或同bank”由归纳结果反过来成立，并非把WE2设0后跳过bank约束。首帧epoch空bank提供归纳起点。

raw联合约束仍是Dcfg150+C1_commit-334215+2≤70494，ntrain≤2时为Dcfg150+Lfir≤59691。上述归纳把Dcfg收敛到δ，避免了任选一个接近469.96us的bank等待。对应一个便于核查的raw保守高水位式为：

Qraw≤334471+ceil(5*(10803+Lfir+δ)/6)。

它把334215完整输入字、256保留、两训练任务和退休2拍均显式计入。δ须由当前实际接口逐拍决定，不随意写零；其允许余量远大于健康CDC和cfg控制的固定拍数。

### 16.3 生产FIR合同取Lfir=72时的设计数值

父任务确认PG149将GUI latency描述为core latency，blocking ready/valid向输入传播背压以防丢失，生产四核input/output/oversampling rate均1、无reload/config/aclken。对这种固定参数FIR，使用标准II1有限弹性服务语义作为硬件设计依据是合理的；本报告接受以XCI C_LATENCY总72作Lfir，另64拍输入FIFO已单独收费。该选择是明确IP接口合同和数值预算，不冒称已经独立读懂加密内部或做过原生验证。

| 项目 | 设计上界（clk150） |
|---|---:|
| E1 COMMIT，至多两次训练抢占 | 345088 |
| E1下一cfg许可 | 345089 |
| E2首输出 | 330 |
| 内生G | 138 |
| CFO对单E2帧的Bout | 24748 |
| E2完成 | 359273 |
| E2下一cfg许可 | 359274 |
| E2输入bank重新可用 | 359169 |
| WE2（Tmin400834、δ为健康固定控制开销） | max(0,δ-21087)，正常小δ时为0 |
| 8窗槽数保守上界 | 7 |
| 同SFO bank相对隔两帧raw窗口的释放余量 | 87811-δ-WE2 |
| raw允许的cfg可见延迟δ | ≤59619拍（已含退休2拍，不再另加） |

例如δ=16拍仅用于展示公式，Qraw≤343547字；必须由主任务确认实际δ后才能将该示例写成冻结设计最高占用。该数值不包括无效候选泛滥、错误帧不reset继续运行或外部背压等不在正常合同内的场景。

重新只读检查manageddir现有网表后，t07_g3_up47_sim_netlist.v在157行进入pragma protect，.vhdl在13行进入protect；其2021.1/目标器件、C_LATENCY=18及rate/FIFO属性与XCI一致。内部FIFO/clock-enable结构并未明文发布，故没有所谓遗漏的可读原生网表可以独立证明所有恢复行为。后续有限原生验收应直接核对该合同；不能把随意增大到512/1024拍当作证明。

## 17. LS与Farrow的确定结构优化设计审查

### 17.1 LS宽乘法：选择共享完整精度串行乘法

原LS74:67-70包含abs40→40×40→80位寄存器，:233-239在单拍内执行80×18、80×7、54×24常数乘法，:255又有abs41×20。它们每帧只在74点收齐后使用，不需要连续一拍一个结果。将全部延迟敏感性推迟到最终EDA不合适，主开发者选择共享98位shift-add服务。

所需六次乘法顺序及精度为：

| 操作 | 被乘数有效宽度×乘数迭代数 | 完整结果宽度 |
|---|---:|---:|
| abs(sum_delay)平方 | 40×40 | 80 |
| abs(sum_weighted)平方 | 40×40 | 80 |
| 第一平方×135050 | 80×18 | 98 |
| 第二平方×74 | 80×7 | 87 |
| sum_square×9993700 | 54×24 | 78 |
| abs(beta_numerator)×1000000 | 41×20 | 61 |

统一acc和shift均98位，所有输入零扩展后只作无符号乘法，原sign与ppm方向单独保存。每轮计算acc_next=acc+(multiplier[0]?shift:0)，shift左移1，multiplier右移1。仅有效迭代的acc参与结果；最后一次左移可能丢弃的高位不再被使用，不能把该无效shift截断误报成结果溢出。相应结果落入原80/98/61位目标寄存器，合法域内高位恒零，保留原完整数学，不新增中间舍入或饱和。

总迭代40+40+18+7+24+20=149拍。若每次REQ/RESP各保守1拍，总161拍；若每次另有PREP操作数寄存，总167拍。原四个数学状态SQUARE_SD、SCALE_SD、SCALE_SWD、PREP_PPM合计4拍，因此净增不超过163个clk125。确认主任务的实际FSM后应替换这个保守数，不能漏算非阻塞赋值导致的operand晚一拍。

控制必须遵守：REQ握手时捕获操作码/目标寄存器与乘数迭代数；WAIT期间不得切换live源；只有匹配本帧、当前操作的result真实握手才写目标并推进状态；abort/reset一并取消busy、result valid和操作码；74点收集、quality门槛、所有原有溢出检查不变。现有point_square的24×24和weight的9×24暂保留，后者可落一个DSP；不能因为一次乘法较宽就把所有小算术一律改串行。

备选为18/18/4 limb拆分的40位平方和16位limb的常数乘法，分产品寄存与平衡加法树，保持完整80/98位结果；优点是仅增加少量流水拍，代价是多个并行DSP、更多中间寄存器以及本场景不需要的连续吞吐能力。共享串行方案仅在每帧末尾多约1.3us，资源更少、控制更易核对，故首选。

98位串行加法仍是一条真实125MHz路径；它替代的是宽乘法及多级部分积树，不是宣称98位加法没有时序要求。其起点和终点均为本地寄存器，单拍仅一项98位加法和操作数选择；不得再把abs或结果比较串接在该加法前后。若实现显示这一条加法仍不满足8ns，备选拆为低49位与高49位带进位两拍，每迭代多1拍，共再增加149个clk125，也可在全局余量内重新计数，不降精度或放宽时钟。

### 17.2 SFO除法末拍：分离除法、舍入判据与加一

旧div_u80_u49:34-41、86的最后迭代把50位trial比较/减法、余数RNE比较及81位加一接在同一拍。优选三个相邻阶段：第80次DIVIDE只存next_quotient和next_remainder；ROUND_PRE从已寄存余数和divisor形成round_up；ROUND_EMIT单独计算81位{0,quotient}+round_up并发布m_valid。

每调用净增2拍，80次除法迭代不变。busy保持到ROUND_EMIT完成，m_valid遵守原ready/valid保持；divide-by-zero快速结果及rst取消语义仍保留。备选只加一个ROUND阶段，会让50位比较仍接81位加法，虽然比原链短，但末级仍有两个宽运算，故本轮选择两阶段。

peak每窗一次除法、LS末尾两次除法：单窗aux服务最多增加2拍；最后一窗至全帧结果最多增加6拍。加LS≤163拍，总残差尾部净增≤169个clk125，约203个clk150。旧R9200加该增量≤9403，统一R9600足够。相应Caux改为634+ceil(Xa/4)，无窗积压的保守Xa门槛由12400变为12392个clk500；main门槛10512不变。

### 17.3 Farrow地址选择：首选6位模索引与端点保护

方案B保留相位、RNE、tap顺序和全部数值，但ring地址只使用：

index6 = 6bit(lane_phase[lane][33:28] + RNE_carry + tap - 1)。

它严格等价于旧signed64 address的低6位；必须显式使用6位中间量，不能让integer tap把数据路径重新扩成32/64位。完整lane_base与issue_base诊断保留，宽值不再串到64:1数据mux之前。

正step与RNE单调已经由合法descriptor保证，因此原64个逐tap宽范围判断可严格替换为min_index>=oldest、max_index<written、min_index>=0、max_index<=0xffffffff四个端点判断。非法step/phase仍由原descriptor错误机制拦截，不能因优化索引而放宽其合法域。

方案B不增加任何流水拍，ring同拍写保护继续以旧请求min为准，credit/Farrow23+1拍、H1/H2、51/2几何事件和所有服务预算均不变。它去除64位地址加法到动态数据mux的串接，也去掉64份宽比较；这是当前首选。

方案A是在phase/address与数据mux之间插入索引寄存。它能进一步切断mux前路径，但必须保留pending读窗口的最小地址直到真实取数，ring写保护取当前请求与pending读两者最旧前沿；新增stage valid/tag/mu必须与issue预占信用一致，不能只给issue_window加寄存器。若单pending不能每拍同时退旧进新，会意外变II=2。当前B先减少确定的组合深度，A只在有路径证据需要时再设计。

## 18. 实际源组覆盖与剩余物理路径检查

以rtl/sources_v51.f为当前清单，SFO共74个文件：buffering7、common2、control3、fft_service5、first_resampling3、initial_estimation30、resampling8、residual_estimation14、second_resampling2。不能把“清单中出现”与“本审查者独立逐行覆盖”混为一谈。

| 实际源组 | 本审查覆盖/对应负责人 |
|---|---|
| resampling8、first_resampling3、second_resampling2 | 完整握手/状态/几何/有限服务、pack与四FIR封装；§15、§17 |
| residual_estimation14 | 逐窗配置、水位、双packet slot、pilot选择/旋转/grid、功率/峰值/插值、LS与除法、错误和等待门槛；§11、§13—17 |
| fft_service5 | 本审查覆盖residual FFT/aux IFFT/fft_window三文件及125↔500 CDC；initial_fft_service与arbiter交由frontend/T06审查，避免冒称独立重复覆盖 |
| buffering7 | 本审查覆盖URAM、同步/异步FIFO、intermediate bank、output ring、legacy raw ring；training_capture与新shared raw/training由frontend审查，初始接口关系见前文 |
| control3 | domain_reset、sync_sfo_top、two_pass_transport的源集/端口/CDC/发布/释放与故障聚合 |
| initial_estimation30、common2 | frontend审查覆盖T06接口、训练坐标、所有权和服务依赖；旧定点算子沿用，并未在本轮全部重新数学证明/数值比较。本审查核过frame/capture发布前后依赖，不替其30文件逐一背书。stream包和vendor算术适配作为共享依赖，版本/源集由主任务统一锁定 |
| 新top/context join/窗口队列/CFO | 本审查作跨组所有权及服务式独立复核，CFO完整RTL由对应审查者负责 |

已有具体路径与动作如下。这里标识的是需由实现数据确认的实际寄存器间路径，不把没有STA的怀疑写成已经失败：

- 150MHz Farrow：lane_phase寄存器→20位RNE判据/8位mu进位→6位模索引→64:1 ring数据选择→算术首级寄存器。方案B已给出；宽端点保护仍单独通向issue_valid/s_ready，需查其扇出与路由。mux的真实层数由综合映射决定，不能用一个“模块边界”隐藏它。
- 125MHz LS/除法：§17已给确定拆分结构，98位迭代加法、50位trial比较减法、81位RNE加一分别成为独立寄存器边界。新增拍数计入R9600。
- 125MHz peak_triplet4:88-100为四次32位peak compare/select串行优先链，平手还比较有符号FFT偏移；:109-122为四lane competitor最大值链。若需要改，备选是保持原优先级的两层pairwise树，或逐lane局部max后再加一级寄存汇总；必须保留平手选择较小有符号offset。四lane单8ns拍尚不能仅凭源码断言失败，本轮先保留并列明具体起终点。
- 125MHz pilot_grid4:95-112，输入四个18位实/虚部绝对值与max链，再接身份/掩码判断至BRAM写使能；:63-90的abs→可变移位/RNE→符号恢复至输出寄存器。已有同步BRAM raw寄存边界；必要时把幅度比较做平衡树、把normalize拆成“取幅值/移位”和“舍入/符号”两级，同时对齐beat/last/gain与ready。不能只延迟ready。
- pilot ROM的地址{slot,fft_beat}直接取寄存器字段，phase_rom为同步读进入m_phase，未发现把大ROM寻址与旋转乘法塞在同一拍；select/rotate/gain各级仍须查实际clock-enable扇出。pilot_rotate2已有pre_rotate、constant multiply、RNE三拍，未据此无差别追加寄存器。
- 500MHz FFT适配器：prefill计数/transaction_active→in_fifo_rd_en/FFT TVALID、FFT TREADY→读使能，以及返回last/status计数是2ns约束的本地控制路径；输入/输出数据经XPM FIFO隔开，不与125MHz ready组合相连。应核真实XPM生成约束、clock groups和status toggle同步，不把通用false_path当作整条接口时序豁免。
- 150MHz深URAM：19位读地址加法/issue信用→82深度拼接读选择→128位响应FIFO；两bank选择与reset/poison广播是真实物理网络。READ_LATENCY_B=2是功能合同，不等于自动满足6.667ns布局。窗口访问与E2顺序读互斥已证明，地址/响应/所有权错配不能用增加无标签寄存器修补。
- reset：domain_reset通过4级xpm_cdc_async_rst同步释放，再hold64拍；FFT子服务先在125MHz寄存decoded reset再跨域。正常帧只重置本resampling engine的FIR/Farrow，不冲刷跨域窗口/metadata队列；全epoch取消必须由主任务统一屏障完成。此处结构核对与真实CDC约束/物理恢复验收分开。

本轮设计层的结论是：自写SFO控制、缓存、几何与服务公式已收紧到确定拍数/事件数；采用明确的生产IP服务合同后可以给出完整多帧预算。当前剩余不是任意OPEN参数清单，而是vendor合同的有限原生核验、上述已定位路径的实际资源/时序和数值边界验收。它们必须保留证据层级，不能把静态设计预算改称已仿真、已布线或已上板通过。


## 19. 实际Farrow B与未应用LS/div候选的逐差异复核（2026-09-18，Europe/Berlin）

本节只读检查生产Farrow和reports/v51/pending_arithmetic中的代码候选、manifest及patch，未写生产RTL、未执行仿真/综合/数值实验。候选检查时manifest状态为REVIEW_ONLY_NOT_APPLIED；本节是应用前独立设计意见，不改变原自动审批流程。后续应用应比对下列身份，不把目录中的候选误称为实际生产结果。

| 文件 | 本次检查SHA256 |
|---|---|
| 生产sfo_guarded_farrow_stream.sv | 7A6893FC14D31EFED724DC260B41E398DBC9316660138740FC39391C529E969E |
| LS候选 | 38B8CACBBAB1A23155EDD20937F0C661AC041628D097B2FB5C7E0CBC9C59F58E |
| divider候选 | 936B8AF63564CFD242855EEAC6EBCE17360B6BEC06ADC65E94D2B67B1047385A |
| LS被替换生产版本 | C3A1CB3073748C3607534D266A38B6ED7ED6DB0CD143CCB387F8C7525F18BC75 |
| divider被替换生产版本 | D600F457C3C5821A9B7349FE4AEBC2370D02909C4E3A8C171CDBA630C4F88D7A |

### 19.1 已应用Farrow B

实际代码:63将ring_base/ring_address均声明为6位；:90在rounded_mu溢出处理前保存phase[33:28]+rounded_mu[8]，:101以显式6位tap求模索引，:109-110采用四项端点判断。rounded_mu只可能0..256，故其bit8严格代表原256时的整数进位；先取carry、再把mu清零的顺序正确。负相位的二补码低6位也与旧signed64 address[5:0]等价；负窗口在issue_valid之前由min_index>=0排除，不依赖数组的组合读取值作为合法输出。

合法正step使RNE后整数base单调，因此lane0的base-1及lane15的base+2是全部64个tap的最小和最大地址。四项端点条件与旧逐tap范围比较等价。phase_ready仍保护初始化阶段，旧retain/min_index保护和信用统计均未改变。本改动不增加pending请求或流水拍；§15的23+1在途信用、51/2几何空洞以及全部服务式保持。未发现本diff需要修正的功能/所有权缺陷。6位加法后64:1 mux仍须实现时序确认，静态等价不替代STA。

### 19.2 LS串行乘法候选

候选:72-78的factor41、shift98、acc98和mul_sum98，完整覆盖六种乘积；:238-261/:289-298六个准备状态各自重新装载全部运算寄存器。:263-275仅在MUL_ITERATE递推，末轮写入mul_sum而非旧accumulator，未漏最后一个乘数bit。

平方结果80位、乘135050结果98位、乘74结果87位、sum_square乘9993700结果78位、abs(beta)乘1000000结果61位。40位和41位最负有符号数的绝对值作为同宽unsigned传入，原最小负数边界没有变成负的无符号因子。截取平方[79:0]和ppm[60:0]不会丢弃合法完整乘积高位。共享wide_square按“SD平方→SD常数项→SWD平方→SWD常数项”使用；非阻塞更新不会让SD常数项误读SWD平方。ppm符号和分母在PREP_PPM先保存，后20迭代不再读live数据。

abort使外层FSM离开MUL_ITERATE并进入原DONE错误结果；残留乘法寄存器在下次准备状态全部重写，不可能作为新帧结果发布。reset明确清零新增寄存器。原74点计数、SSE符号/溢出判断、质量门槛、结果保持和除法错误传播未改。未发现本候选需要修正的代码缺陷。

### 19.3 divider两级RNE尾部

候选:81-94的最后DIVIDE边沿仅保存next quotient/remainder；下一拍从已保存的Q/R计算round_up_q，再下一拍计算81位商加一并发布valid。RNE平手检查使用最终Q最低位，50位2R避免49位左移丢失进位。busy覆盖全部尾部，round_phase非零时不再迭代remaining；最后remaining=0不会下溢进入新除法。

若请求于E0接受，80次除法在E1..E80，E81保存舍入判据，E82发布；旧实现E80发布，故净增严格2拍。m_ready为0时结果保持，consume旧结果与接受新请求同拍的原接口行为仍保留。除零快速路径未增拍，reset/上层abort仍取消在途结果。未发现本候选需要修正的代码缺陷。

### 19.4 精确增拍与全帧计费

六个准备状态加40+18+40+7+24+20=149次迭代，共155拍，替换旧四个数学状态，LS乘法净增151clk125。本候选没有单独REQ/RESP握手状态，所以§17.1的163只是应用前保守数，不是实际新增拍数。

| 路段 | 旧拍数 | 候选拍数 | 净增clk125 |
|---|---:|---:|---:|
| LS六项乘法所替换状态合计 | 4 | 155 | 151 |
| LS两次除法 | 保持原迭代数 | 各增加ROUND_PRE/EMIT | 4 |
| 最后一窗peak除法 | 保持原迭代数 | 增加ROUND_PRE/EMIT | 2 |
| 最后point接受至外层残差结果 | 176 | 331 | 155 |
| 最后IFFT word至point | 601 | 603 | 2 |
| 最后IFFT word至外层残差结果 | 777 | 934 | 157 |

74个窗口的peak各增加2拍，不能只给最后一窗计费而继续沿用旧逐窗门槛。对应Caux=634+ceil(Xa/4)，以每级不超过3732clk125为无跨窗积压的充分条件，Xa门槛必须采用12392，主FFT门槛10512保持。只要两级均满足该逐窗界，前73个新增尾拍由窗口间的空闲吸收，最后尾部只额外157；若按所有活动周期求和，74个peak新增合计148也须显式列入，不能改写成最后peak仅2拍适用于整帧累加。

157clk125折合向上取整189clk150；旧R9200加189为9389，采用R9600覆盖本候选。§17的169clk125保守设计数仍有效，但实际实现应记录157，以免后续重复加保守空拍。98位本地加法与81位RNE加一均为独立真实寄存器间路径，其8ns实现检查仍属于后续物理验收。

## 20. FFT的已证外围拍数与厂商服务合同边界

### 20.1 当前实际配置和外围服务

父任务保存的installed Vivado2021.1 GUI timing结果位于reports/v51/ip_metadata_06/timing.txt；按两份实际XCI传入C_ARCH3参数，main2048 latency6287、aux runtime2048 latency6306（aux最大16384）。本审查没有重新启动IP工具。两XCI实际C_HAS_CYCLIC_PREFIX=0、C_HAS_OVFLO=1、C_THROTTLE_SCHEME=0，生产service实例无输出数据/状态TREADY端口。

residual_fft_service4:160-165配置只在epoch初始化时完成一次；configured置位后至少隔一拍才置transaction_active，再下一边沿才可能取首数据，因此配置先于首数据的要求有结构保证。正常窗口结束不重新配置或flush；只有BOOT/错误FLUSH/HALT才复位。每个窗口完整512个128位字已缓存后才回放，32个复样点预填，125MHz每拍4点对应500MHz每拍1点；核心初始等待只使输入FIFO蓄积，不能形成外部循环等待。

输出FIFO可容4096个复样点，而单窗为2048点；上层等本窗全部数据和status消费后才发下窗。故正常单窗不会因输出存储不足而丢数，也没有下游TREADY任意阻塞核心的路径。service:289在500MHz采到status脉冲后翻转toggle，:299-301用两级125MHz同步和沿检测；从核心status到上层接受保守≤4clk125=16clk500，已包含在输出末字/状态的9clk125界中。

既有§14已收费prefill≤12clk125与返回FIFO/状态≤9clk125，共21clk125；Cfront/Caux另有各自前端、grid/peak和状态收尾。新增64clk500不能声称替代了这84clk500的全部wrapper开销，二者统计边界不同；本轮没有删掉原21clk125。

### 20.2 官方合同与64拍的含义

官方[PG109 v9.1，2022-05-04](https://www.amd.com/content/dam/xilinx/support/documents/ip_documentation/xfft/v9_1/pg109-xfft.pdf)第26页规定OVFLO状态在帧末发送；第51-53页描述Realtime无输出/状态背压，以及无CP的pipelined streaming可按N拍连续加载/输出；第58页要求首次配置握手至少先于首数据一拍。它比安装版2021.1晚，不能冒充安装目录同版PDF；第97页列出的后续修订涉及配置字段文字及C model，不作为新增硬件时序证明。

以上文档与实际端口消除了“我方status ready可能无限拖延”的风险。它未给出这个参数组合首次config-ready、内部首样点等待或接口与GUI延迟定义差值的逐拍最大表。自写RTL也没有能力独立证明加密核心永不延后ready。正常固定配置、时钟/reset健康、完整连续供数、GUI latency适用于该配置的IP服务语义可作为设计依据；这与任意拿watchdog当成功上界不同。但额外64clk500仍应明确为这一IP服务合同的边界容差，不得称已经穷尽证明的核心内部最大值。

因此本轮冻结采用：首次残差窗口发起前核心已经成功配置；以后每窗保持2048/noCP/Realtime同配置，核心按其固定配置II1服务，OVFLO在本窗末端发布；按GUI核心延迟保守串加2048输入、2048输出及64边界容差。config在本帧前发生的epoch启动不应偷偷塞进每窗64预算。若后续原生验收显示该合同不成立，应修正具体延迟或初始化接口；不能降计算门槛/扩大watchdog来保持原声明。

### 20.3 数值代入及声明层级

Xm=6287+2048+2048+64=10447，Xa=6306+2048+2048+64=10466clk500。

- Cfront≤1104+ceil(10447/4)=3716clk125，低于3732充分门槛16拍；对应Xm允许最大10512，尚余65clk500。
- 候选除法后Caux≤634+ceil(10466/4)=3251clk125，低于3732门槛481拍；对应Xa允许最大12392，尚余1926clk500。
- 两级都小于最密窗口间隔4480clk150=3733又1/3clk125。因此在该明确IP合同下逐窗服务不累积，§19.4的末窗净增157及R9600可与§16的SFO/CFO多帧归纳联立。

这是“源码已证外围成本＋具体厂商服务合同＋有余量的全局设计预算”。它不是原生数值比较、综合资源、布局布线时序、连续输入实测或板测通过；后续用户授权的有限验收应直接对这些固定条件取证，不再用未知K值泛试设计猜想。


## 21. budget()全链闭式公式独立复核（2026-09-18，Europe/Berlin）

检查tools/v51/static_design_audit.py:68-124，初始读到的SHA256为6957BF6FBE0485D2FE148449109F81EEF33350A1AC9F67D352417F448B900E08。只读代码及候选manifest、核对文件哈希，并独立作常数代数计算；未运行audit脚本，未启动仿真/综合或修改生产RTL。

本次四个CFO生产文件逐一匹配cfo_manifest.json的production_sha256，全部未匹配candidate_sha256，因此当前生产应取Delta=0。以下Delta=259列只表示用户尚未批准的四候选组合；不得把候选数字称为已经应用后的结果。

### 21.1 Delta259的实际意义与正确计费

CFO独立报告§21和算术复核报告均给出quality末观测后尾部6792→7051clk150；新增259=74个真样点归一化各3拍222、N_CONFIG1、功率尾排空2、MATH准备2、频率串乘30、两次divider各1拍2。phase尾部5272→5687仍早于quality，不与quality串行相加。259clk150约1.726667us，是每帧后端主导尾部的固定增量，不是每个原始输入样点或每个2048点FFT窗都增加259拍。

令D为这项增量，E0=356850+D、S=345216+D。两者均增加D是同一后端在不同调度边界上的费用：E0表示独立当前帧完成包络；S表示前一帧结果占用服务对当前帧造成的阻挡。已有两bank反馈与有序coarse写入给出：

e_k-b_k <= max(E0+G, E0+G+S-N, 2S-Fmin)。

在当前值下E0+Fmin-2S=938-D>0、S>N，故可化为E0+G+S-N。于是CFO当前bank从首coarse写入到最终tail的上界为E0+Fmax+(S-N)+G，随D增加2D。这个2D计的是“前帧额外占用＋本帧额外处理”的最坏耦合包络，不是把同一次运算在本帧FSM里跑了两遍。

CFO帧间vacation则用e_(k-1)<=b_k+E0+G-N，得到Bout=24610+D+G，只增加D。输出ring全部未消费字数<=65536+64=65600<N，生产一帧最多跨过一次CFO帧间vacation；因此E2 next/free各只增加D，不能把CFO完整bank寿命的2D又加到E2上。

### 21.2 当前与候选的代数结果

采用原冻结条件Lfir72、G138、cfg32、Rtail9600、Tmin400834、N334080：

| 项目，单位clk150（raw/slot除外） | 当前生产D=0 | CFO候选D=259 |
|---|---:|---:|
| B | 6832 | 7091 |
| E0 | 356850 | 357109 |
| S | 345216 | 345475 |
| 两bank反馈归纳余量E0+Fmin−2S | 938 | 679 |
| CFO首coarse写入至最终tail | 703116 | 703634 |
| Bout | 24748 | 25007 |
| E1 COMMIT | 345088 | 345088 |
| E2 next cfg | 359274 | 359533 |
| E2释放输入bank | 359169 | 359428 |
| 前一E2造成的额外等待 | 0 | 0 |
| SFO bank最迟寿命（含两次cfg32） | 713921 | 714180 |
| 双物理帧801668减上述寿命 | 87747 | 87488 |
| raw保守最高占用，128位字 | 343561 | 343561 |
| CFO窗口保守占槽数 | 7/8 | 7/8 |

脚本jitter=20401+72=20473，候选e2_wait=max(0,359533+20473+32−400834)=0，仍有20796拍服务间隔余量。SFO寿命=345088+9600+359428+64+0=714180，计算正确。D不进入E1或残差SFO尾部；上表同bank在下一次需要前仍提前87488拍释放，故不会反过来增加raw开始等待。

raw_peak=334215+ceil((32+345088−334215+2)*5/6)+256=343561。其中2是实际退休流水费用，256是安全保留，5/6是150MHz服务时间内125MHz持续输入的增长；该式没有遗漏先前审查指出的两拍。393216容量余49655字。它是完整窗口、两次训练抢占、最晚退休的联合界，不是单独把469.96us允许启动滞后加到全帧服务上。候选不改上述E1、cfg或保留常数，所以raw_peak不变。

### 21.3 七槽/八槽的准确边界

代码Qslot=2+floor((G+23098+D)/4480)与独立CFO推导一致。D259时变成2+floor((G+23357)/4480)。对非负整数G：

- G<=3522时上界不超过7槽；G=3523开始公式为8槽。
- G<=8002时上界不超过8槽；G=8003开始公式为9槽。
- 当前G138给2+floor(23495/4480)=7，距离七槽边界还有3384拍。
- 旧充分条件G<=8192只适用于旧D0；候选下G8192会得到9槽，不能继续引用。若仍写为G=66+Lfir，对候选的八槽条件应为Lfir<=7936。

当前budget()直接计算G138的占槽数，因此其结果7是正确的。建议冻结报告同时写出最大G8002，避免后续增大IP延迟预算时只看当前7而机械沿用旧8192。

### 21.4 唯一发现的预算脚本状态缺陷

初始检查版本:71使用all(production_hash==candidate_hash)，:72以false直接选择D0。因此全部旧版本、部分候选已应用、其他未知改动三种状态会被混在同一分支。部分应用尤其可能是quality/divider已经变慢而phase尚旧，此时D0会低估生产服务；inspect()列出文件哈希本身不会阻止这一错误预算被正常发布。

首选修复为三态检查：每文件分别识别已知old/candidate；全部old选D0，全部candidate选D259，混合或未知明确INVALID并让预算发布返回失败，列出不匹配路径。另一方案是在经过完整数值/周期审查后为每个受支持的混合组合维护独立预算；目前没有此需求，增加组合表会扩大维护风险，故首选三态。不能仅将混合情况保守套D259而把未知代码也当作已审查。

此问题属于静态预算工具，已即时通知父任务；本审查未修改脚本。当前生产实际全old，所以上表当前值没有受到此缺陷影响。修复后应在本节补充新的脚本哈希/状态，不能仅保留“已发现”而暗示已经关闭。

### 21.5 仍属明确合同/后续证据的内容

本次闭式一致性不扩大原证据层级。正常服务条件仍为：每真实物理帧至多一个成功确认，最短raw帧距334029字/clk150帧距400834；额外TO漂移有界；T06成功参数按frontend服务合同提前发布；固定cfg延迟32；epoch开始时所有队列/银行身份已清理，错误时统一poison/reset；最终输出无外部背压。

FIR的固定II1/72拍与64FIFO弹性费用、FFT installed GUI数值及额外64边界容差仍是§16.3/§20写明的厂商IP服务合同。自写控制、FIFO信用、有限循环和本节代数已静态核对，但没有把加密IP恢复行为、全数值范围测试、500MHz实际映射/布线、CDC实现约束或板级持续服务改称已验证。上述条件不是可随意调整的OPEN参数；后续有限验收应针对已冻结合同取证。


### 21.6 批准应用后的最终复核与问题关闭

父任务随后收到用户对四份CFO补丁的明确批准，应用记录为reports/v51/pending_arithmetic/cfo_application.json，时间2026-09-18 01:43:13 CEST（UTC+02:00）。本审查重新读取并逐一核对四个生产文件，全部与已审候选SHA256一致。于是§21开头和§21.2表中D0属于应用前快照；最终生产采用D259列，不能再表述为“未批准/未应用”。

预算脚本已改为同时检查all-candidate和all-original，若两者皆不满足立即raise ValueError，且发生在结果JSON写入之前。新脚本SHA256为D6BF4353D741E5EF3F248DF8065C3E71111776BD6048280C7A5A2108B74A6AC9；§21.4的混合/未知版本静默落入旧预算问题在本次实际源码中已关闭。本审查只读核对该修正，没有另外运行脚本或制造混合源码实验。

已读父任务生成的reports/v51/full_static_20260918/cycle_memory_budget.json，production_cfo_pipeline_candidates_applied=true，最终发布值与本审查独立代数一致：E1 COMMIT345088、E2 next cfg359533、E2 bank free359428、SFO bank寿命714180、双帧余量87488、raw最高占用343561/393216字、CFO首粗写至tail703634、Bout25007、窗口7/8、反馈归纳余量679、final不积压余量1392，均按冻结服务合同成立。

static_binding_07/summary.json为父任务的实际生产静态绑定/类型检查，candidate_overrides为空，errors=0、diagnostics=958；厂商IP只作黑盒端口绑定，XPM只用接口声明，未检验其内部映射。该记录不表示958条诊断被本审查重新逐条清零，也不转化为仿真/综合/布线通过。最终静态服务预算和生产身份已一致；§20与§21.5的IP接口、数值和物理验收边界保留。
