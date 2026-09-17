from pathlib import Path
import json
M=Path('D:/008_MA_Dev/Sync_SFO');A=M/'docs/functional_review_20260915'
(M/'README_ZH.md').write_text('''# Sync_SFO：两级采样频偏估计与补偿

唯一日常 GUI 入口：[Sync_SFO.xpr](Sync_SFO.xpr)。Vivado 2021.1，器件 `xcvu11p-flgb2104-2-e`，综合顶层 `sync_sfo_top`，仿真顶层 `sync_sfo_full_frame_tb`。核心 `OUTPUT_CLOCK_MHZ=150` 保持不变。

| 交付内容 | 入口 |
|---|---|
| 完整核心工程与功能分区 | [工程](Sync_SFO.xpr) · [74 个核心源列表](rtl/sources.f) · [功能/名称映射](docs/functional_review_20260915/NAME_MAPPING_ZH.md) |
| 独立明文 VHDL Wrapper | [sync_sfo_manual_wrapper.vhd](wrapper/sync_sfo_manual_wrapper.vhd) · [102 个端口](wrapper/ports.csv) · [接口合同](wrapper/interface_contract.json) |
| 手工 CLIP、时钟、前端接口及测试步骤 | [当前交付指南](docs/SFO_SYNC_MODULE_GUI_ZH.md) |
| 输入设值、波形及预期输出 | [case6001 设值](handoff/T10_SFO_20260915_manual/data/case6001_settings.json) · [文件哈希和来源](handoff/T10_SFO_20260915_manual/data/data_manifest.json) |
| MATLAB 来源 | [参考入口](matlab/README_ZH.md) |
| 已有整帧行为证据 | [RUN03 独立复核](handoff/T10_SFO_20260915_manual/evidence/T10_RUN03_INDEPENDENT_REVIEW_20260915_ZH.md) |
| 本次变更证据 | [验证状态](docs/functional_review_20260915/REVIEW_STATUS_ZH.md) |

## 处理顺序

原始 I/Q、帧描述及 TO/CFO 记录 → 首次 SFO 估计 → 第一次重采样 → 残余 SFO 估计 → 第二次重采样 → 补偿后 I/Q 和元数据。包含原始环形缓存、中间 bank、输出缓冲和内部跨时钟通道。

本次从 V5_Final `dd5e8f7a642625f06c4996d17e3642bbadc7d557` 整理功能命名、端口声明和排版。74 个自有核心 RTL、2 个测试文件及 3 个头文件通过名称还原后的词法、语法结构和端口一致性检查；厂商 IP 名称、34 个 XCI、生成源码和算法保持。Wrapper 独立存放，不加入核心综合源集。

## 使用边界

输入/控制为 125 MHz，重采样和当前输出为 150 MHz，FFT 服务使用 500 MHz。时钟源、锁定顺序、DDR/DMA 和平台 CDC 由用户的 NI 工程负责；Wrapper 仅拼接和拆分位段。前端 288 位记录尚需适配，上层还须保留并回放完整原始波形。

`handoff/T10_SFO_20260915_manual`、`archive` 和旧 `vivado/T10_SFO*` 保留历史身份。历史包中的旧名字用于追溯；当前操作以本页及根 XPR 为准。已有 case6001 行为证据不等于实现时序、持续吞吐、NI 全目标编译或板测通过。本轮不生成 CLIP XML、配置包或 LabVIEW 工程；原生验证进度见验证状态页。
''',encoding='utf-8')
(M/'docs/SFO_SYNC_MODULE_GUI_ZH.md').write_text('''# 两级 SFO：当前工程与手工 CLIP 交付指南

2026-09-15。SFO 是采样频率偏差；这里交付两次估计、两次重采样及其缓存和控制。综合顶层 [sync_sfo_top](../rtl/control/sync_sfo_top.sv)，独立外围 [sync_sfo_manual_wrapper.vhd](../wrapper/sync_sfo_manual_wrapper.vhd)。本轮保持 V5_Final 的运算、位宽、定点解释、复位、握手和处理期限。

## 1. GUI 入口与文件身份

打开 [Sync_SFO.xpr](../Sync_SFO.xpr)，确认 Vivado 2021.1、器件 `xcvu11p-flgb2104-2-e`、综合 top `sync_sfo_top`、仿真 top `sync_sfo_full_frame_tb`、`OUTPUT_CLOCK_MHZ=150`。完整复制模块时保持相对目录。不要从 archive 或历史同名目录补选源。

核心源集为 [sources.f](../rtl/sources.f) 明列的 74 个自有 RTL、3 个原版 XPM 源及 34 个 XCI；还有明确的数据、头文件及约束。Wrapper 不在核心综合源集内。原生实际选源的核查状态见 [本次复核](functional_review_20260915/REVIEW_STATUS_ZH.md)。

`tools/vivado/create_project.tcl` 创建或打开同一个根工程；`open_sync_sfo.tcl` 只导航。性能辅助脚本保留既有兼容过程名；各 run 的 PRE 钩子请求 general/synth 8，xelab 上限 16，实际构建并发按总资源准入。打开工程或静态检查不会自动获得实验启动权限。

后续需要核心检查点时，核心综合使用 out-of-context 模式，确认综合 top、器件、IP 状态、未解析黑盒和报告，再导出核心 DCP。DCP 不包含 NI 时钟、DDR/DMA 或平台布线的完整证明。手工 CLIP 由用户将核心及独立 Wrapper 接入 NI 工程；本次不提供 XML、配置包或 LabVIEW 工程。

## 2. 时钟、复位与内部 CDC

| 域 | 实际功能 | 平台应提供 |
|---|---|---|
| 125 MHz | 原始四点输入；frame/CFO/fine 握手；两个估计器慢侧、残余点和 debug125 | 连续硬件时钟；输入回放与配置在本域接受 |
| 150 MHz | 两次重采样、原始/中间/输出存取调度；默认 m_*、E1 观察流和 debug150 | 连续硬件时钟；能够承接输出突发的接收端 |
| 500 MHz | FFT/IFFT 服务快侧及其入出 FIFO | 平台合法派生的连续时钟、锁定和复位控制 |

[当前 XDC](../constraints/sync_sfo_clocks.xdc) 仅声明 8 ns、6.666666667 ns 和 2 ns 三个根时钟。工程和 Wrapper 未生成 MMCM/PLL；XDC 不证明时钟硬件、CDC 或平台时序闭合。三域外部时钟关系、派生约束、I/O 延时和 NI 上下文由平台集成落实，不能只按频率比假定相位相关。

[sfo_domain_reset](../rtl/control/sfo_domain_reset.sv) 使用 4 级 `xpm_cdc_async_rst`，异步置位、同步释放后再保持 64 个本域周期。传输层 [sfo_record_cdc_fifo](../rtl/buffering/sfo_record_cdc_fifo.sv) 为读写域分别同步复位；FIFO rst 来自写时钟域；读写 busy 经有源寄存器的双级同步器交叉确认，两侧忙时禁用传输。每条多位记录整条通过异步 FIFO，不逐位同步数据。

| 传输层记录 | 位宽 | 方向 |
|---|---:|---|
| 原始四点 | 128 | 125 → 150 MHz |
| 首次估计及帧上下文 | 236 | 125 → 150 MHz |
| 残余估计配置 | 222 | 150 → 125 MHz |
| 残余窗口请求 | 102 | 125 → 150 MHz |
| 残余窗口数据 | 235 | 150 → 125 MHz |
| 残余估计结果 | 160 | 125 → 150 MHz |
| 旧 125 MHz 输出选项 | 225 | 150 → 125 MHz，仅参数选择 125 时存在 |

FFT 服务另外使用 125/500 MHz 变宽异步 FIFO。500 MHz 复位从已寄存的慢域复位经 4 级同步得到；输出 FIFO 由其写侧 500 MHz 复位，慢域复位保持及 ready/busy 条件约束启动。原有粘滞状态和 toggle 同步逻辑保持。以上是源码结构核查，原生 `report_cdc`、实现时序和板级行为仍分别需要证据。

所有时钟先稳定并确认平台锁定，再按测试台将 reset_request 保持高至少 80 个 125 MHz 周期（640 ns）。释放后等待各接口 ready/复位状态，不能立即送数。运行中时钟应持续；失锁或取消时先保存故障及计数，再执行平台总复位恢复。Wrapper 不负责生成复位顺序。

## 3. 核心与 Wrapper 端口

完整逐端口信息见 [ports.csv](../wrapper/ports.csv) 和 [interface_contract.json](../wrapper/interface_contract.json)：名称、方向、宽度、符号/单位、默认值、时钟域、valid/ready 和背压条件。核心 37 端口与 Wrapper 102 端口的拼接/拆分一致，Wrapper 无额外寄存器、FIFO、CDC 或通用参数。其 component 绑定固定 `sync_sfo_top` 默认输出 150 MHz。

| 核心记录（高位 → 低位） | 格式 |
|---|---|
| frame_record，188 位 | frame32 / generation32 / raw_first_word64 / nominal_absolute32 / q0Q28 |
| cfo_record、fine_record，各 96 位 | value32 / quality16 / status16 / frame32 |
| m_record，225 位 | frame32 / generation32 / beat32 / last1 / IQ128 |

输入每拍 4 点，每点低 16 位 I、高 16 位 Q，均为二补码 I16 Q1.15；归一化值为整数除以 32768。128 位最低 32 位是最早样点。CFO value 为有符号 Hz，fine value 和 s_absolute_index 为约定坐标中的有符号样点数；q0 为 Q28 位模式，不是运行中估计答案。`frame_raw_first_word` 是核心内部接收流的 128 位拍地址，不是 DDR 地址。

所有可握手接口仅在本域 `valid && ready` 同拍为 1 时前进；阻塞期间保持 valid 及整条记录。观察接口 residual_point_valid（125 MHz）和 debug_e1_valid（150 MHz）没有 ready。跨域读取 debug 总线须使用整条稳定快照握手，Wrapper 没有提供平台快照控制器。

## 4. 前端 288 位结果怎样适配

只读核对来源为 `../Sync_Frontend/rtl/frontend/sync_frontend_top.sv`。前端联合输出如下，不能直接接到 SFO 三类配置记录：

| 前端位段 | 字段 | SFO 集成时需要的处理 |
|---|---|---|
| [287:256] | epoch32 | 用于采样段身份；与 generation 的关系由适配器明确，不能默认等同 |
| [255:224] | frame_id32 | 映射成 SFO 各记录和 raw 的同一帧号，保持单调及复位规则 |
| [223:192] | candidate_id32 | 捕获候选标识；SFO 无直接对应端口，平台保留用于追溯 |
| [191:128] | coarse_absolute64 | 连续采样段坐标；上层用于回放定位，不可直接截成内部地址 |
| [127:64] | fine_absolute64 | 用选定名义原点转换为 32 位有符号帧坐标，检查范围和溢出 |
| [63:32] | cfo_hz32 | 有符号 Hz 可映射到 cfo.value；仍需独立合法 CFO status/quality |
| [31:16] / [15:0] | fine quality / fine status | 属于精定时结果，不能无条件复用为 CFO 状态 |

适配器必须先原子保存这条联合记录，再分别按 frame/cfo/fine 的 ready 提交且每条恰好一次。还需生成 raw_first_word、generation、nominal_absolute 和 q0。核心检查首次 SFO status=0x4800、fine status=0x3800、三方帧号一致且 fine−nominal 在 −101…101 样点内；测试用 cfo status=0x2800。状态常量是当前记录种类/状态约定，不能把失败结果硬改为成功状态。

前端 local capture 仅保存 [-256,2919] 的 3176 点上下文（794 拍），历史 RAM 为 2048 拍。它不提供完整帧 I/Q 回放。当前独立用例原始输入含 1,336,860 个复数点，需从 [-172,N+367] 回放，其中 N=1,336,320；范围仅适用于此冻结用例。用户平台须在检测完成前保留所需原始样本，再按统一坐标回放。SFO 内部 ring/bank 不会自动取得前端已过去的样本。

完整接通尚需：原子记录适配器及坐标/状态转换；外部原始样本存储与回放；DDR/DMA 与域间 FIFO；平台时钟/复位与诊断快照。上述接口和职责已明确，本轮未增加适配器或重设计缓存。

## 5. 可独立操作的 case6001 测试

沿用 [固定设值](../handoff/T10_SFO_20260915_manual/data/case6001_settings.json)、[文件清单及 SHA](../handoff/T10_SFO_20260915_manual/data/data_manifest.json) 和 [完整 Host/Target 步骤](../handoff/T10_SFO_20260915_manual/docs/HOST_TEST_ZH.md)。历史步骤里的顶层/Wrapper 名称以本页新名称替换，其端口、数据和操作含义不变。MATLAB/定点参考来源见 [参考指南](MATLAB_REFERENCE_GUIDE_ZH.md)，本轮不重新生成数据。

1. Host 读取无头 U32 小端 raw 文件，1,336,860 元素、5,347,440 字节，校验 SHA 后完整装入用户 DDR。第一拍 IQ0…3 为 FFA40DE7、FE4B04FE、E51021B9、E9E21B89。
2. 三路时钟稳定；清空接收区和适配器计数，valid=0、abort=0、m_ready=0；按上一节复位并等待就绪。
3. 125 MHz 域提交 frame={6001,1,raw_first_word=0,nominal_absolute=0,q0=0}，再提交 CFO={100000 Hz,quality=0,status=0x2800,frame=6001}，再提交 fine={0,0,0x3800,6001}。每条保持到握手成功。提交 fine 前应准备好完整回放，首次估计器有 65,024 周期限制。
4. raw 的第 b 个接受拍送数组 [4b…4b+3]，s_frame_id=6001、s_lane_valid=0xF、s_absolute_index=−172+4b。仅接受后增加 b；共 334215 拍，不额外补零。
5. 150 MHz 接收端已具容量时令 m_ready=1，同时捕获输出。冻结测试台连续 ready；任意长停顿不在已验范围。125 MHz 捕获 74 条残余点，可选在 150 MHz 捕获 E1 观察流；这两个观察流不能背压。
6. 最终输出 334080 拍 / 1,336,320 点，beat 连续 0…334079，只有末拍 last=1，frame=6001、generation=1。输出排空、内部空闲后锁存各域状态，再经 DMA 读回。重复同帧前完整复位。
7. 用户 Target 每接受一拍保存 8 个 U32：frame、generation、beat、last、IQ0、IQ1、IQ2、IQ3。最终文件无头、小端，共 2,672,640 个 U32 / 10,690,560 字节。使用历史包 [compare_capture.py](../handoff/T10_SFO_20260915_manual/tools/compare_capture.py) 比较，报告写新文件；该工具只读取捕获数据，不启动实验。

输入场景为无噪声单径、SFO −150 ppm、CFO +100 kHz。已有完整帧基线实际最大 IQ 误差为 0 LSB；允许门槛、窗口 EVM 与元信息检查保持原定义。可选 E1 参考 1,336,392 点，残余点每条 5 个 U32，共 74 条。缺少某种观察数据就不能声称该项板上比较已完成。

输入回放峰值为 2.0 GB/s，IQ 输出突发为 2.4 GB/s，若按上述 256 位结果保存则捕获端峰值预算为 4.8 GB/s。这只是端口带宽计算。外部 DDR 各区须按生命周期及读写重叠核算，并考虑控制器效率、FIFO 和对齐；没有实施新缓存方案或证明持续吞吐。

## 6. 证据边界

本次静态命名/排版等价、原生工程打开、编译/展开、核心综合、实现时序、持续吞吐、NI 全目标编译及板测在 [验证状态](functional_review_20260915/REVIEW_STATUS_ZH.md) 分开报告。未重新运行已完成的 case6001 整帧仿真。没有仅截短估计器输入而产生的功能 PASS。
''',encoding='utf-8')
plan=json.loads((A/'rename_plan.json').read_text());lines=['# 功能目录与名称映射','','基线：V5_Final `'+plan['baseline']+'`。完整可机读文件、标识符、实例类型/名字映射见 [rename_plan.json](rename_plan.json)。厂商 IP 标识保持；T 编号保留在历史来源及测试证据标识中。','','| 目录 | 功能 |','|---|---|','| initial_estimation | 训练符号处理、相位与加权拟合、首次 SFO |','| first_resampling | 第一遍描述符、帧调度和重采样 |','| residual_estimation | 74 个窗口/点、残余 SFO 拟合 |','| second_resampling | 第二遍描述符和重采样 |','| resampling | 两遍共用 FIR/Farrow 与保护样点处理 |','| buffering | 原始环、中间 bank、输出和同步/跨域 FIFO |','| fft_service | 首次/残余 FFT、IFFT 服务与仲裁 |','| control | 两遍顶层、传输调度和域复位 |','| common | 记录类型与自有算术适配层 |','','## 文件迁移','','| 原路径 | 当前路径 |','|---|---|']
lines += [f'| `{o}` | `{n}` |' for o,n in plan['paths'].items()]
lines += ['','## 实例命名','','187 个实例逐一归档，27 个模糊/编号实例改成功能名，其余保留已有功能名。完整上下文及类型在 JSON 的 instances 字段，避免按局部同名误改。`sfo_farrow_parallel` 保留泛化 LANES 参数及原默认值 16；FIR up15/up47/down15/down47 沿用滤波器身份，不把名称中的数字解释成重采样倍率。','']
(A/'NAME_MAPPING_ZH.md').write_text('\n'.join(lines),encoding='utf-8')
(A/'REVIEW_STATUS_ZH.md').write_text('''# 当前命名版本的验证状态

2026-09-15，设计与静态复核阶段。原生结果返回后更新本页。

| 项目 | 状态与证据 |
|---|---|
| V5_Final 基线 | dd5e8f7a642625f06c4996d17e3642bbadc7d557；原件/历史包保留 |
| 词法、语法结构和端口 | PASS，79/79；328 个继承端口展开；[完整结果](preview_equivalence_v2.json) |
| 条件编译、宏和注释词法 | PASS，完整 raw token 序列核对；仅忽略排版空白，宏体末尾空白规范化 |
| Wrapper | 名称还原后 VHDL 词法相同；37 核心端口、102 Wrapper 端口；[结果](ancillary_preview.json) |
| 实际原生选源 | 基线导出已逐一复核；新名称原生导出待唯一 Luna 作业 |
| GUI 工程原生打开 | 新名称版本待执行 |
| 编译/展开 | 待冻结作业及管家资源授权；不运行整帧 |
| 短功能对照 | 本轮未运行；不将编译/0 ns 当作功能结果 |
| 核心综合 / 实现时序 | 本轮未运行 |
| 持续吞吐 / NI 全目标编译 / 板测 | 未验证 |

第一次候选流程因 Windows 换行和排版搜索限制失败，失败预览与报告保留。第二版统一 LF，补齐宏/条件编译 raw token 检查并提高排版搜索预算后全部通过。失败候选未写入活动 RTL。新活动源码精确对应第二版通过候选；没有算法功能修复。

本次结果只证明当前命名与声明排版的静态等价。已有 case6001 整帧行为证据保留原身份，未重新运行；不能声称当前版本已经完成新的整帧、时序、吞吐或板级验证。
''',encoding='utf-8')
print('CURRENT_HANDOFF_DOCS_WRITTEN')
