# Sync OTA 新一轮实现报告复核

复核时间：2026-09-18，Europe/Berlin（CEST，UTC+02:00）。分支：V5.1_System_Modify。
本轮只读取已有报告、综合日志和 RTL，未修改 RTL，未启动仿真、综合或布局布线。CFO 与 SFO 分别经过独立只读复核。

## 1. 结论与证据范围

本轮由上一轮 3336 个 setup 失败端点收敛到 **1 个**：500 MHz 的 CFO 导频系数 ROM 寻址/使能路径，WNS/TNS 均为 −0.057 ns。125 MHz 和 150 MHz 的 setup 已满足当前约束，但部分路径余量很薄。当前仍不能宣称完整时序收敛或 NI 集成/板测通过。

- Timing：2026-09-18 17:48:12 CEST，`sync_ota_top_timing_summary_routed.rpt`，Fully Routed。
- Utilization：2026-09-18 16:36:04 CEST，`sync_ota_top_utilization_placed.rpt`，Fully Placed；不是布线后的分层资源报告。
- 器件：xcvu11p-flgb2104，速度等级 −2；Vivado 2021.1。
- 本目录保存原报告、实现日志及 Tcl 的副本；原件路径和 SHA-256 见 `report_identity.json`。
- 当前九份优化 RTL 的哈希与上一轮交付清单一致；新日志存在新结构及 BRAM 映射证据。但 GUI 本次综合没有保存完整冻结源清单，因此不将当前工作区哈希等同于完整的运行输入证明。

## 2. 时序变化

| 时钟 | 上轮 WNS/ns | 本轮 WNS/ns | 上轮失败端点 | 本轮失败端点 | 本轮 TNS/ns |
|---|---:|---:|---:|---:|---:|
| 125 MHz | +0.050 | +0.135 | 0 | 0 | 0 |
| 150 MHz | −0.766 | +0.013 | 1486 | 0 | 0 |
| 500 MHz | −0.727 | −0.057 | 1850 | 1 | −0.057 |

全局 TNS：−647.378 → −0.057 ns，负裕量总量减少约 99.991%。数量取自全设计汇总（新 timing 第 148–177 行），没有用前十条详细路径外推。

Hold：WHS +0.007 ns，失败数 0；脉宽：WPWS +0.431 ns，失败数 0。50 项 bus-skew 约束均满足，最小余量 +0.766 ns。路由状态完成，无未布通、部分布通或失败网络，无节点重叠。

当前实现实际采用 `place_design -directive ExtraTimingOpt`、`phys_opt_design -directive Explore`、`route_design -directive NoTimingRelaxation`；上一轮使用默认指令。改善来自 RTL、存储映射、布局和实现策略共同作用，不能归为单一 RTL 修改的独立收益。

## 3. 唯一失败：CFO 系数 ROM 输入使能

证据：新 timing 第 2973–3024 行。

- 起点：`cfo/observation_front/coefficient_address_reg_0_0_i_6_psdsp/C`，实际单元 FDRE，SLICE_X141Y116；名称后缀不代表它是 DSP。
- 终点：`cfo/observation_front/coefficient_address_reg_1_0/ENARDEN`，RAMB36E2，RAMB36_X8Y30。
- 周期 2.000 ns；路径 1.689 ns＝逻辑 0.285 ns＋布线 1.404 ns；布线占 **83.126%**。
- 仅 2 级 CARRY8；最后一段网络扇出 7，但耗时 **1.025 ns**，不是超高扇出问题。
- BRAM EN 建立时间 0.342 ns，时钟不确定度 0.035 ns，skew +0.009 ns。不能因为数据路径小于 2 ns 就认定满足时序：实际 required 1.662 ns、arrival 1.719 ns。

对应 RTL：`rtl/cfo/cfo_front2048_window_a07.sv` 第 30–35、72–77 行。它已有 index → 地址寄存 → 同步 ROM 读取，因此不能诊断为“RTL 忘记流水”。真实实现路径说明 ROM 地址/页选择产生的输入使能仍有跨两级 carry 的路径；寄存器是否被推断/优化吸收，须检查映射网表才能下确定结论。

两种设计方向：

1. **优先：不增拍，落实已有物理寄存边界。** 将地址及 ROM 页选择/使能明确留在合适的寄存边界，并让局部寄存器靠近对应 ROM。确认映射后是寄存器直接驱动 RAM 命令，而不是仅靠 RTL 变量名判断。避免对整个 CFO 核施加 DONT_TOUCH 或大范围硬布局约束。反馈预算保持 174 个 clk150 周期。
2. **备选：增加一级完整 ROM 命令。** 地址、页选择、读使能与 IQ/index/valid 必须一起对齐，不能只延迟 EN。每窗增加 1 个 clk500 周期，II 仍为 1。现有最坏窗口 15473 → 15474 个快时钟，折算 clk150 时由 4642 取整到 4643；E0 357628 → 357702，S 345987 → 346060，既有反馈余量 **174 → 102**，仍为正。实施前须同步更新周期合同。

增加 BRAM 输出寄存器并不能直接切断本条 ENARDEN 输入路径。旧的 FFT 内部控制复制脚本也不针对本条路径。当前没有证据支持再替换 FFT 或改变 CFO 算法。

## 4. 已通过但余量较薄的具体位置

### 150 MHz

**范围澄清：这里的 output_buffer 是 SFO 第二次重采样之后、CFO 之前的内部缓存，不是 Sync OTA 到 DDR 的最终输出缓存。** 相关 poison/cancel 来自模块故障或主动取消。最终顶层只有 output_valid/data/frame/generation/beat/last，没有 output_ready 或 DDR 满反馈输入；内部 sfo_r 接 CFO 的输入接收条件。继续遵守用户明确的最终输出无背压合同，后级 DDR 接收能力由 LabVIEW 保证，不据此新增最终输出流控。当前需研究的是内部故障撤销与冗余 collision 门控的组合深度，不应把错误取消保护当作 DDR 回压直接删除。证据：rtl/control/sync_ota_top_v51.sv 第 8–9、23–30、80、97–100 行；rtl/sfo/control/sfo_two_pass_transport.sv 第 767–787 行。

| 路径 | Slack/ns | 主要证据与原因 |
|---|---:|---|
| poison_sync → SFO output_buffer BRAM ENBWREN | +0.013 | timing 1798–1867；8 层 LUT，6.288 ns 中布线 5.609 ns；链路经 E2 abort/m_valid、collision、读使能，末端 enb 扇出 305 |
| poison → CFO coarse_bank0 URAM 读控制 | +0.028 | 11 级，含 7 个 URAM 级联节点；写命令已流水，读停止控制仍需关注 |
| intermediate0 ram_ra → URAM CAS_IN_ADDR | +0.051 | timing 2163–2234；入口网络跨 SLR1→2，单网 4.919 ns，含 7 个 URAM 级联节点 |
| intermediate0 write_next → ram_wa 副本 | +0.063 | timing 2448–2498；0 层组合逻辑，布线 6.505 ns，占 98.845%；跨 SLR0→2 |

输出缓存的候选 A：正常状态以 O=accepted−issued，wp=accepted mod D，rp=issued mod D，可证明同时读写时地址不相等（读要求 O>0，写要求 O<D）。因此可研究从 RAM 功能使能中移除冗余 collision 门控，保留诊断和非法 epoch 丢弃；必须先核对异常语义，无需增拍。候选 B：完整、匹配地寄存读写命令并调整响应流水，信用在原请求时预占，增加 1 拍。不能只给 ready 或读使能单独打一拍。

URAM 路径优先方案是按已有存储分区让命令寄存器、局部控制与 RAM 靠近，保持当前周期。备选是显式分段存储并缩短级联，配套返回数据选择流水及 bank 标签对齐；不能只改变 CASCADE_HEIGHT 而忽略数据与所有权延迟。当前这些路径均通过，不宜直接扩大修改范围。

### 500 MHz

- generation 校验 → estimator expected_window CE：+0.011 ns，6 级逻辑，路由占 1.281/1.886 ns。
- windows/output_record → FFT2048 状态 CE：+0.013 ns。
- FFT2048 twiddle/RAM 控制、SFO aux vendor FFT 所列路径：约 +0.015～+0.018 ns。

这些是余量监控项，不是本轮失败。上一轮厂商 FFT 与 FIFO 的失败数量不能继续沿用。

### 125 MHz

最差路径：`peak/bank0 → m_competing_power[31]`，+0.135 ns；timing 第 225 行起。21 级逻辑，含 7 个 CARRY8，7.800 ns 中逻辑 2.685 ns、布线 5.115 ns。

`rtl/sfo/residual_estimation/sfo_residual_peak_triplet4.sv` 的四路 running-max 串联是可优化点。方案 A：资格掩码后做平衡归约树，再与历史最大值比较，保持周期及圆周排除语义。方案 B：四路局部最大值，窗口尾部两拍归约，约增加 128 FF 和每窗 2 个 clk125 周期，须更新逐窗预算。当前已通过，优先级低于唯一违例和 150 MHz 薄裕量路径。

## 5. 资源与布局

| 资源 | 上轮 placed | 本轮 placed | 当前全器件占比 |
|---|---:|---:|---:|
| LUT | 279728 | 238616 | 18.41% |
| FF | 234152 | 231762 | 8.94% |
| CLB | 57976 | 47257 | 29.17% |
| BRAM tile | 568 | 570 | 28.27% |
| DSP | 2021 | 2021 | 21.93% |
| URAM | 848 | 848 | 88.33% |

LUT 减少 41112，约 14.70%。本次综合日志明确：FFT256 的两个 128×40 bank 各映射 1 个 RAMB36，共 2 个，解决了旧结构落成大量寄存器/选择器的问题。全设计 LUT 净差不能精确等同于 FFT256 单模块差值；当前没有新的 routed 分层 LUT/FF 报告。

全局 LUT/DSP/BRAM 容量有余量，但布局分布不均匀：

| 资源 | SLR0 | SLR1 | SLR2 |
|---|---:|---:|---:|
| CLB 本区域占比 | 85.69% | 0.85% | 0.97% |
| LUT 本区域占比 | 54.69% | 0.27% | 0.27% |
| BRAM tile | 570（84.82%） | 0 | 0 |
| DSP | 2021（65.79%） | 0 | 0 |
| URAM | 274（85.63%） | 286（89.38%） | 288（90.00%） |

全部 BRAM/DSP 及绝大多数逻辑集中在 SLR0，而 URAM 分散三个 SLR。它同时解释了局部密度高与 URAM 远距离命令路径；不等于整片 LUT 不够。SLL 占比约 3%，也不代表单条跨区网络延迟小。路由局部 1×1 tile 的热点约 95.19%，不可当成全芯片布线占用率。

优化优先保持 500 MHz 核局部紧凑，修复系数 ROM 附近的实际长连线；对于 125/150 MHz 存储访问，在寄存/CDC 边界规划模块与 bank 局部控制。不要为追求三个 SLR 数量均匀而拆散关键算术通路。URAM 全局 88.33% 已是后续扩展的主要容量约束。

## 6. 尚不能据此认定满足的集成条件

- clk500 与 clk125 出现 TIMING-6/7：被按有关时钟分析，却没有公共主时钟/公共节点。必须根据 NI 实际时钟来源落实关系：同源则定义正确 generated clocks；异步则核对 CDC 结构和对应约束，不能用无依据 false_path 掩盖。
- 内部未约束端点数 0、no_clock 0；但仍有 **133 个输入与 1536 个输出没有 I/O delay**。这是核心 OOC 边界的限制，不能外推为 NI 接口已经验收。
- OOC 时钟端口 HD.CLK_SRC 未设置，工具提示时钟延迟/skew 估计准确性受限；数据边界尚有 HD.PARTPIN_LOCS 提示。最终集成需以真实时钟网络、端口连接和位置重新检查。
- 两条 LUTAR-1 与组合 reset_request/compute_cancel 驱动异步复位相关；需依据完整复位合同复核，不能只由 setup 已通过推导其正确。
- 本次物理报告没有新增数值对比、功能仿真、持续吞吐或板测证据。

建议顺序：**500 MHz 系数 ROM 唯一违例 → 150 MHz SFO 内部缓存故障撤销/读使能链与 URAM 局部性 → NI 时钟/I/O 约束落实 → 视余量需要优化 125 MHz 峰值归约**。下一次任何 RTL 调整仍应先完成两方案比较、周期/所有权审查，再按授权做必要验证。

## 7. 唯一违例的具体设计候选（用户要求先说明，尚未应用）

优先采用零增拍的显式两页 ROM：60680 个 3-bit 索引按线性地址拆为两个 32768×3 页，第二页未用尾部填充；有效窗口小于74，最大有效地址73×820+819=60679，不访问填充区。该重排不改变任何有效系数值。

- 在现有地址计算拍，从同一个完整加法结果同时寄存低15位地址和one-hot页读命令。不得在同一always_ff中以旧coefficient_address生成新标签。仅对必要的局部命令/地址寄存器落实保留，不锁定整个模块。
- 下一拍同步读选中的ROM页，并寄存该次读取的页标签；在原c_pipe[1]拍根据返回标签选择3-bit索引并查8项系数表。避免无意新增coefficient_index0一级，保持IQ/index/valid原延迟。
- 页标签逐笔对齐；特别检查从零计数window39、pilot788的32767→32768跨页。复位、abort、FFT错误、HOLD退出时，valid/读命令清空优先级须与现合同一致，旧payload不作为新事务发布。
- 预计仍为6个RAMB36，与当前系数ROM六个实例相当；增加少量页标签/命令FF与3-bit选择逻辑。零增拍，II不变，既有反馈预算174个clk150保持。
- 独立只读审核认为该结构静态可行；是否最终保持FF→RAM EN/ADDR的边界、读出选择是否成为新关键路径，必须由后续映射和时序报告确认，不能预先宣称收敛。

备选是增加完整一级ROM命令流水，所有配套数据/标签一起延迟；每窗+1个clk500，按既有逐窗取整预算反馈余量降为102个clk150。选择优先方案是因为当前仅57ps违例且布线主导，应先以局部结构保持既有周期，而非先消耗紧张的全链周期余量。本节是设计说明，未修改RTL或系数文件，未运行EDA。
