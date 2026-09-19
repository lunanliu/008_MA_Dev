# Sync_OTA：20% 时序余量重构交付

日期：2026-09-18，CEST（Europe/Berlin，UTC+02）。分支 V5.1_System_Modify；器件 xcvu11p-flgb2104-2-e；Vivado 2021.1。生产入口 Sync_OTA.xpr / sync_ota_top / rtl/sources_v51.f。

**27份活动RTL已修改；129份活动源与XPR一致，顶层静态绑定0错误；三组独立静态审查完成。新版尚未仿真、综合、布局布线或板测，20%物理时序目标状态为NOT_QUALIFIED。** 本轮唯一原生Vivado动作是只读旧routed DCP导出路径，不能作为新版时序证据。用户当前GUI不被控制、关闭或启动新作业。没有commit/push。

## 验收口径

用户已确认按每条路径的实际约束留20%。普通同域clk125：8ns→+1.600ns；clk150：6.666666667ns→+1.333333334ns；clk500：2ns→+0.400ns。原2ns max-delay CDC目标+0.400ns，即使它显示在125MHz组。保持原时钟、波形、精度、持续输入速率和最终无背压输出；hold/脉宽仍须满足原指标。独立核心时间余量不等于20%资源余量，也不保证NI外壳集成必然通过。

旧DCP SHA256：590915429ee7d5191726fd0f27e77c85a9ddbbcd40d8ffda9baa225bd007c45a。原约束WNS依次+0.153/+0.009/−0.199ns；旧完整报告500MHz TNS为−26.125ns。按三个名义门槛导出33276/17137/3623条端点候选；其中125组35条、150组1条实际是2ns约束，按实际门槛重新分类。CSV只保留3位小数，端点相加TNS约−25.990ns，不能替代Vivado完整精度的TNS；贴近目标的舍入边界单列REVIEW。nworst=1同端点不同要求可能互相遮蔽，候选表仅用于整改归因。

完整候选、模块分组及余量缺口见同轮reports目录的 endpoint_margin_classification.csv、module_margin_summary.csv、endpoint_summary.json。负裕量之和才叫TNS；距20%门槛的不足另叫margin_deficit，不混用。

## 结构选择、备选与真实代码

下列路径均位于本工程rtl；精确修改前后哈希见 change_manifest.json，before目录保存本轮开始时的源文本。root为唯一代码写入者，独立审查者只读。

| 位置 / 文件 | 采用结构及理由 | 对比后未采用方案 | 周期影响 |
|---|---|---|---|
| initial_estimation/sfo_initial_dds_phase_4lane | ready只排除已占用dummy；与valid相与的真实fire恒等，消除valid→ready依赖 | 整个reader新增弹性级，代价796bit及对齐变化 | 0 |
| initial_estimation/sfo_initial_shared_gain_s16_4lane | 2×176bit出口槽、注册lane CE；后级ready不再穿过所有原生IP | 只复制原组合CE，仍保留长逻辑 | 连续流+1clk125，II1 |
| frontend/carrier/cfo_preamble_rotator | signed floor商+非负余数的RNE，21bit保存正进位 | 绝对值→舍入→恢复符号或新增算术级 | 0，精度相同 |
| initial_estimation/sfo_initial_pair_phasor_bfp | magnitude按位OR求共同MSB，分层最高位编码 | 数值max比较后线性优先编码；或两级额外流水 | 0 |
| initial_estimation/sfo_initial_regression_tail | 共享ROUND_PRE/ROUND_ADD；移位/判据与119bit加一分拍 | 把完整长组合只接一个结果寄存器，仍保留长路径 | 每帧+4clk125 |
| frontend/frontend/sync_frontend_top | 先锁anchor，在原RESET首拍判断重复，持续持有bank | 排序、64bit差值和98bit数据CE同拍串联 | 合法候选0；重复候选晚1拍释放 |
| control/ota_training_dispatch | 登记IQ/身份/绝对坐标/valid完整命令；尾字实际写后发布 | 仅延迟valid会串位；改所有capture调用范围更大 | +1clk125 |
| initial_estimation/sfo_initial_frame_context_join | payload与复杂fault/valid控制分离，背压时保持 | 整个输出再加一级，增加接口状态 | 0 |
| buffer/ota_raw_training_hub | raw CDC之前局部双槽，入口原子fork不改 | 在通用CDC裸寄存ready，难以保证最后容量 | 正常+1clk125，另计2clk150准入 |
| buffering/sfo_uram_frame_bank及raw/intermediate/CFO三个调用者 | URAM按16384字分段，本地完整命令+注册选择树；实际commit更新水位、SEALED | 仅加READ_LATENCY不能保证切开全局MUX | 读2→6；写提交+1clk150 |
| buffering/sfo_output_buffer | 内部BRAM环按16×4096分段；读信用与在途valid同步延长 | 仅复制全局地址无法保证缩短零级长布线 | 读2→5；物理写+1 |
| resampling/sfo_guarded_farrow_stream及core | 双槽入口→完整ring写命令；descriptor固定双槽；4组16:1采样再4:1选择；父级排空包含入口在途 | 更大的ring增加存储；延迟ready破坏所有权 | 每重采样器保守+3clk150，II保持 |
| 三份fft_service | 双槽预取隔开FIFO读与FFT ready，实时FFT出口登记完整data/last/valid | 直接连控制；假定实时核能背压不成立 | 每事务保守≤+5clk500 |
| residual_peak_triplet4 | pair→beat→global比较树，峰值与竞争峰各两级排空 | 四路串行比较；组合平衡树仍把多级比较放一拍 | 每窗+4clk125 |
| residual_pilot_grid4 | 完整validated写命令和WRITE_DRAIN；负移位只展开合法−1/−2常量RNE | 18级校验直接驱动RAM；通用动态右移 | 每窗+1clk125 |
| residual_nominal_window_reader4 | 锁定cfg错误码及起点，CHECK_CFG后发布请求 | 复杂cfg校验同拍控制宽起点寄存 | 每窗+1clk125 |
| cfo/cfo_front2048_window_a07 | ROM页输出FF借原E3，E4完成页选；提前计算末pilot提交位 | 新增整个ROM级会吃紧窗反馈预算 | 健康0 |
| cfo/cfo_fft2048_core | 比较flags、LOAD完整写命令借START；RAM payload与使能分开，tag/算术自由运行，局部parity | 每stage增加RAM命令拍导致每窗至少+11，原反馈余量不足 | 健康0；错误发布+1clk500 |
| 两份CFO RNE17 | 四个7bit加法并行、段间前缀进位 | 宽串行进位；加新算术级扩大11stage尾部 | 0，逐位代数等价 |
| buffer/ota_cfo_window_queue、common/ota_async_fifo_a06 | 固定tail→head，packed FIFO短级联；仍只在末IQ发出时归还整窗信用 | 4096×128改1024×512需重做打包、所有权与延迟 | 完整窗发布合同下健康0 |
| cfo/cfo_estimator_link_a06 | 空槽自由采样mailbox，171bit FIFO由distributed改block | 宽控制驱动分布式RAM写入及payload CE | 接口不变；映射待综合 |
| cfo/ota_cfo_chain_onchip诊断 | 完整499bit shadow+单bit提交隔离；算法bank提交不改 | 仅物理复制宽结果CE | 仅诊断快照+1clk150 |

未改FFT256、半带算法、厂商FFT算法和CFO直接投影；旧全路径表没有FFT256的20%不足证据。

## 边界与所有权审查

1. raw/intermediate issue到response由3→7拍，owner同步7拍；CFO由2→6；输出BRAM为5。64响应信用在请求时预占直到消费，包含新在途。URAM尾段8192有完整地址范围检查，不能靠截位产生别名。水位、写满、SEALED都用真实wr_commit及保存的地址。
2. leaf payload无复位、无CE；只用command/valid决定可见性，保持完整事务。存储真正访问仍受合法命令约束。取消边沿可能落地一个此前已接受的私有写；停止epoch不得发布结果或复用所有权。最终DDR没有ready，内部缓存控制仍保留。
3. gain的注册CE可能消耗第一复位边沿，wrapper复位至少3拍；生产原8/64拍满足。KEEP只是保留种子，四份局部CE与复制效果必须检查真实网表。
4. Farrow W=物理写入数，R=预约数，保持R−W=16×cmdvalid。head在partial采样边沿退休，下一窗口lo至少前进15（生产R28 step已限制）。read_fire时允许以lo+15作为下一头保护下界。cmdvalid=1时历史保护给W−lo≤48；拒绝新预约只在48边界，此后两窗可用差值至少30，仍大于所需20，因此新增写命令不引入周期性读气泡。父级empty包含入口双槽和待写命令。
5. FFT2048末输入E接受→E+1 START实写→E+2首RUN读；stage写回未增加流水。input_error仍3>1>2优先；front错误及HOLD清空同时清sum_commit_q。有效tag/数值对齐，无效payload自由运行增加翻转，功耗尚未测量。
6. 三个SFO FFT均为realtime，无输出ready。原FIFO预填仍≥32，加双槽最坏多等一组4个fast周期，出口再+1，故按+5计费。overflow在实际FIFO提交边沿检查。
7. peak哨兵power0/bin2000为最小signed offset，保持零功率及并列峰顺序；last逐级伴随排空。reader保持已接受非法cfg优先，健康cfg在CHECK遇abort则取消、不发请求。

## 每帧与多帧预算

全部为闭式静态上界，非实测；假设既定IP服务、合法帧间隔和无最终背压成立。完整阶段表见 frame_cycles.csv / final_static/cycle_memory_budget.json。

| 项目 | 周期 | 约束/余量 |
|---|---:|---|
| 最小到帧周期 | 400834 clk150 | 原合同保持 |
| 初始训练发布 | ≤214521 clk125 | 完整raw到齐前119694 clk125，即957.552µs |
| 固定准入 | 34 clk150 | 原32+raw入口2；256字保护量保留 |
| E1物理提交 | 345098 clk150 | 原345090+存储5+Farrow3 |
| E2下一配置 / bank释放 | 360085 / 359980 clk150 | 各+28；不等待上一E2，余20232 |
| 最后残差窗尾 | ≤9422 clk150 | 仍预留9600，余178 |
| CFO每窗 / 首帧E0 / 稳态S | 15473 clk500 / 357628 / 345987 clk150 | 健康服务保持 |
| CFO final上下界 | 334520..334996 clk150 | 下界不抬高；上界+4 |
| CFO最大不消费间隙Bout | 25547 clk150 | 原25529+18 |
| SFO bank寿命 | ≤714746 clk150 | 双帧801668，余86922 |
| CFO bank寿命 | ≤704681 clk150 | 双帧余96987；反馈归纳余174 |
| 主FFT服务 / 上限 | 10452 / 10480 clk500 | 余28，未放宽原服务门槛 |
| 辅FFT服务 / 上限 | 10471 / 12376 clk500 | 余1905 |

收费原则：新增级只计真实启动/尾部，不按每样点重复加；前73窗开销必须被逐窗3732clk125预算吸收，最后窗再独立计尾。训练八个FFT事务各ceil(5/4)加16clk125，gain/tap/regression加6、raw加1、URAM响应/写保守加5，原214493→214521。原计算watchdog65024保持，不把成功服务合同扩张成所有信道一定成功。

## 缓存与资源

| 存储 | 静态最高占用/界 | 配置容量 |
|---|---:|---:|
| raw共享环 | ≤343571个128bit字 | 393216，余49645 |
| SFO帧bank | 每bank含保护区≤334098字；最多2bank持有 | 2×335872 |
| CFO帧bank | 每bank≤334080字；最多2bank持有 | 2×335872 |
| CFO训练窗 | ≤7槽，每窗512×128bit | 8槽 |
| SFO内部输出环 | 硬界65536；另64项响应预留；可能内部满 | 65536×128bit |
| 各响应FIFO / Farrow响应 | 已发未消费≤64，含流水在途 | 每处64 |
| raw入口 / Farrow入口 / gain出口 | 每处≤2个完整事务 | 每处2槽 |

所有 measured_peak 为NOT_RUN；输出环的25547拍间隙不是紧致缓存峰值，不把它冒充峰值。

URAM几何保持raw192+SFO328+CFO328=848/960，余112。五组URAM共108个leaf，输出BRAM16leaf。URAM本地128bit写数据副本13824FF，输出BRAM另2048FF；每Farrow partial阵列8192FF，两套共16384FF，此外有metadata、command、mux树和信用寄存。自有显式新寄存规划约5万FF；为XPM叶输出映射和物理复制另外预留，预算文件统一列80000 FF规划 allowance，**不是综合实耗或硬上界**。DSP数学单元不增加；观测FIFO BRAM规划预留5个。

旧placed分层报告：全器件LUT18.42%、FF8.94%、BRAM28.27%、DSP21.93%、URAM88.33%；SLR0局部CLB83.49%、LUT54.71%、BRAM84.82%、DSP65.79%，主要BRAM/DSP集中该SLR。旧输出环实测231个RAMB36，早期几何预算256。本轮16×4096分段几何为256，因此相对旧实测可能增加约25 BRAM，再加观测FIFO；不能声称物理BRAM不增。分段和局部寄存为分散布局提供边界，是否真正改善SLR0拥塞必须看新分层资源与拥塞报告，不能仅看全器件百分比。

CFO旧2072端点归为：明确结构目标族478、混合覆盖1372、physical-only222。混合组仍保留合法控制与XPM内部计数；SFO500中1331条位于厂商内部。厂商TW地址、DSP→scaler、BRAM地址/WE仍需在严格目标下实现。普通reset/NFFT驱动可同拍复制；ASYNC_REG、同步器、DONT_TOUCH均排除，不把no_sclr_lut误当reset。没有硬塞Pblock、复制同步链或放宽时钟。

## 数值与静态证据

- CFO RNE17：q=x[44:17]，inc=x16∧(低16位非零∨q0)。每7bit段进位=inc∧所有低段全1，结果与原(q+inc) mod 2^28逐位恒等，包括负数和tie。
- fine RNE：有符号floor商与非负余数，half时按商奇偶加1；使用21bit结果防止正溢出，再比较S18上下限。等价原绝对值RNE/恢复符号。
- pair BFP仅消费零值与MSB，MSB(a OR b)=max(MSB(a),MSB(b))，不将OR当数值max使用。
- regression保留原q/r/half/inc，只分开加一；共享状态不改变除法请求顺序和错误优先级。
- grid只使用gain12..−2，两种负移位为原RNE的常量展开；其余精度、缩放、饱和、ROM数值不改。
- **新数值比较/仿真：NOT_RUN。** 以上是静态代数与逐拍对应证明，不是假造的零误差测试结果。

semantic_final：pyslang11.0.0，顶层sync_ota_top，0错误、964条诊断保留。主要为未连接审计端口、符号/位宽和既有缩进；厂商只绑定原stub/XPM接口，不展开加密核或原语映射。stage2的声明先后8个错误已保留并修正，final源与27份manifest一致。未知当前RTL哈希会使预算工具拒绝发布，旧routed→ROM→本轮版本链及四份CFO算术候选均验证。

独立审查覆盖：frontend的数值/双槽/取消；SFO的真实commit、ring退休、比较排空及服务预算；CFO的LOAD/START、tail→head、RNE与结果提交。物理余量、原生厂商展开、功耗、持续实测和NI集成仍未验收。

## 下一次手动实现与报告读取

磁盘XPR已仅给impl_1挂OPT PRE、PHYS_OPT PRE、ROUTE POST；共用run_threads与IP/OOC不改。若GUI在修改前已经打开，为防它保存旧hook覆盖磁盘，先在该Sync_OTA工程Tcl Console执行：

```tcl
source {D:/008_MA_Dev/Sync_OTA/tools/v51/configure_timing_margin20.tcl}
```

脚本仅配置、不启动run；核对工程根目录/名称/器件及完整hook路径后统一写入。若启用了post-route phys_opt，自动把最终报告放在最后物理阶段。随后Reset synth_1及依赖实现、重新综合，再Run Implementation；必须使用新网表。

OPT PRE在已链接原IP约束后，仅给三个同钟setup pair额外加20%周期uncertainty；不改周期、jitter、hold或CDC max_delay。已有任何显式uncertainty会保存并停止，要求合并依据；不会覆盖合法原值。物理优化前也核验owned签名，防止旧checkpoint错用。按官方方法，额外setup uncertainty用于驱动实现优化。[UG906 2021.1](https://docs.amd.com/r/2021.1-English/ug906-vivado-design-analysis/Clock-Uncertainty)。普通FF复制参考[UG949高扇出优化](https://docs.amd.com/r/2021.2-English/ug949-vivado-design-methodology/Optimizing-High-Fanout-Nets)。

最后hook在本次impl目录创建独立margin20_日期_时间_PID目录，先保存routed_tightened.dcp / tightened_summary.rpt，再核验并撤销仅本轮owned setup，保存routed_nominal.dcp / nominal_summary.rpt、分层资源、CDC、时钟交互、例外及check_timing。同一次布局布线、两个约束视图：tightened目标WNS≥0；nominal目标为+1.600/+1.333333334/+0.400ns，不能重复扣20%。默认Vivado报告可能受POST插入顺序影响，首次以显式nominal文件为准。

margin20_gate.txt按时钟pair输出不足候选和hold失败，自动结果只有FAIL或REVIEW；CDC作用范围、混合要求、脉宽和未约束I/O须完整审阅后才能接受，不能从nworst=1候选表直接宣称所有path PASS。独立核心仍属OOC，NI时钟/DDR/FIFO/I/O完整约束由最终集成验收。

本轮配置Tcl只完成静态审查，尚未在新原生构建中执行；若本机工具报告命令兼容问题，应保留证据修脚本，不修改验收门槛或重跑已成功阶段。
