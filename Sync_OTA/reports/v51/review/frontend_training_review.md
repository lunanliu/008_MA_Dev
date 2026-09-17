# V5.1 前端、训练读取与共享 raw 回收静态独立审查

- 时间：2026-09-17 23:03，Europe/Berlin（CEST，UTC+02:00）。
- 仓库：D:/008_MA_Dev，分支 V5.1_System_Modify，HEAD f63bca94558ed0a2bf22a63f25e59da9f1c9c631。
- 实际生产源集：rtl/sources_a07.f，SHA256 CC5FE7BF7F767CF16CDD54E2CBA909D49C593618168150FB65B04070E75F4BD8。
- 范围：独立只读审查现有前端 detector、candidate snapshot、coarse/fine workers、ota_frontend_descriptor 及训练读坐标；补充审查父 Agent 提出的共享 raw 回收方案。
- 操作边界：仅保存此报告；未修改 RTL、其他工程或其他报告，未启动编译、仿真、综合、形式验证或新实验。
- 下文源路径均相对 D:/008_MA_Dev/Sync_OTA；行号对应本次审阅时的源码。结论是静态设计证据，不代表数值、实现时序或板级验收。

## 1. 前端确认延迟并没有无条件的有限上界

rtl/frontend/frontend/sync_frontend_top.sv:161 定义 fine_ready = !fine_result.status[11] || !m_valid || m_ready。成功结果遇到 m_valid && !m_ready 时不可交付。

同文件:253 的外层 70000 拍保护只在 !fine_valid 时触发。rtl/frontend/timing/to_fine_core.sv:331-334 又将 ST_HOLD_RESULT 排除在65024拍服务保护之外。因此成功结果已产生但下游永久不接收时，当前worker和它的snapshot可以无限占用；后面的snapshot也随之等待。不能拿65024或70000直接作为端到端成功交付上界。

前端 s_ready 仅随core_rst_n变化（sync_frontend_top.sv:33-35），不会因snapshot拥塞主动停住入口。此时继续接收输入、继续检测，但新候选按:188-189被丢弃。如果共享raw把这些候选对应的原始帧永久pin住，raw租约则会长期钉住。

静态服务分解：RESET_ESTIMATORS有16计数加转移，REPLAY有794次请求，WAIT_RESULT无有效输出时最多70001个观察边沿。若成功fine结果永远可向结果寄存器转交，则每个worker服务可使用70832拍的保守预算；这个条件不包括结果寄存器往下游的无界等待。正常实际fine计算耗时不能以该故障保护值替代；精确正常服务周期应另按所有IP有效延迟和调度推导。

候选copy等待更多输入的墙钟时间在允许无限输入暂停时也无界。但暂停期间accepted_samples不增长，因此这种等待本身不导致raw样点年龄增长；不能混淆墙钟上界与以输入样点计的保留容量。

| 方案 | 收益 | 约束 |
|---|---|---|
| 有界描述符队列，并冻结最大下游服务/背压时间 | 已接纳候选保持不丢失，raw占用可计算 | 必须真的给出最坏服务上界及队列深度 |
| 结果队列满后明确拒绝或取消该候选并释放租约 | 错误触发不会无限占用连续入口资源 | 存在可报告丢帧，必须是明确系统语义 |

推荐首先用有界正常服务预算完成设计，并保留显式故障退出；不能把永久下游阻塞纳入“正常持续500 MS/s且无丢帧”。

## 2. Snapshot范围不是全链raw保留范围

sync_frontend_top.sv:72、:74、:204、:215规定：

- snapshot起点：anchor-256。
- 794个四样点字，覆盖 [anchor-256, anchor+2919]。
- 开始复制前等待 accepted_samples >= anchor+2920。

to_fine_core.sv:286-287 接纳 coarse_start ∈ [-232,+232]；fine_partitioned_corr_engine.sv:134-135 与 fine_corr_scheduler.sv:4规定257个候选，从 coarse_start-128 到 coarse_start+128。故成功fine绝对位置的保守范围是 [anchor-360, anchor+360]。

rtl/control/ota_frontend_descriptor.sv:21-24、:45 将 nominal=floor4(fine_abs)，replay_first=nominal-172。anchor本身四样点对齐，故每个已接纳候选的最早未来raw需求是：

    candidate_raw_pin = max(0, anchor - 532)

不是anchor-256。早期anchor可能低于532，保留计算必须显式检查下溢；真正描述符还须拒绝不存在的前保护，不能以无符号绕回值通过地址检查。

| 方案 | 评价 |
|---|---|
| 仅保留固定大历史，等确认才正式pin | 依赖已证明的有限确认/交付上界；目前无界背压使此方案无法单独成立 |
| 候选接纳时建立raw租约，拒绝释放，确认原子转交frame租约 | 能表达真实所有权，推荐 |

## 3. 无候选历史可以有界保留

sync_continuous_detector.sv:90将run_length饱和在1025；:93只接纳4..1024；:95将平台中点减256后向下四样点对齐。无限长合格平台不会在很久之后生成一个极老候选，它最终被拒绝。这一点可用于无帧期间的回收，但不能据此忽略已经接纳的snapshot或成功结果。

结构事实：

- lag为256个四样点字，即1024样点（sync_continuous_detector.sv:33、:45）。
- rolling为256个相关字（sync_rolling_metric.sv:60-74）。
- lag RAM 1拍；CMPY有效延迟4拍（coarse_corr_energy_4lane.sv:4、:85）；rolling有历史/延迟与累加寄存级；threshold为6拍乘法元数据加3个寄存阶段（coarse_metric_threshold.sv:4、:149、:169、:187）。
- metric_position=K的统计对应输入窗口起点K；关闭平台的metric相对被估计帧位置还有上述已处理窗口和流水滞后。

按照现有固定IP延迟逐边沿推导，持续满速输入时，候选被top接纳前的accepted_samples-anchor最大约4420样点。再保留532样点的最早SFO原始需求，仍小于8192。8192可作为第一轮保守侦测历史，不应把约4420写成已经由波形验证的值。源集/IP有效延迟若改动，必须重推该界限。

建议：

    retire_floor = min(
        max(0, frontend_accepted_sample_sequence - 8192),
        所有已接纳候选的candidate_raw_pin,
        所有尚未原子转交的成功结果的raw起点,
        所有正式frame lease和各raw读者仍需要的最早位置
    )

新候选接纳、确认交接、取消与retire同拍时，不能出现一拍所有pin都消失的窗口。读命令发出不代表数据已经安全；应等相应响应进入不可覆盖的私有/弹性缓冲后才推进可覆盖前沿。

另一方案由检测器导出精确scanner watermark，能进一步省历史容量，但证明负担包括平台状态、全部流水valid与IP失步处理。第一轮建议8192保守历史加显式租约。

## 4. 两槽不保证任意误触发下真帧无丢失

重复4个合格metric加1个不合格metric的模式，每5拍可产生候选。copy需要794次读，worker还需数万拍。sync_frontend_top.sv:188 在copy_active或两槽已用时直接drop。

因此真实帧间隔很长不能被当作候选到达间隔。有限增大队列只能吸收有限突发，不能解决无限超过服务率的误触发流。

可选方案：

1. 维持有限候选槽及明确drop事件，冻结允许的误触发/输入条件和正常服务合同。
2. 增大snapshot/descriptor队列吸收给定突发，但必须给出突发上界，仍需overflow语义。

推荐先采用1完成可证明合同，再根据明确输入统计和器件预算决定是否采用2。不得静态声称对任意允许输入“所有真实帧都接纳”。

## 5. 训练真实样点与物理对齐

rtl/sfo/initial_estimation/sfo_initial_ps3_ps10_job_sequencer.sv:33-34、:78-91：

    k=0..7，对应PS3..PS10：
    [fine_abs + 5632 + 2560*k,
     fine_abs + 5632 + 2560*k + 2047]

共16384个逻辑样点；联合最早fine_abs+5632，最晚fine_abs+25599。

sfo_initial_raw_reader_local_capture.sv:44 的旧私有capture范围为[5272,25959]，覆盖以前fine在[-360,+360]的全部可能性，逻辑长度20688样点=5172字。

新描述符坐标 A=floor4(fine_abs)、δ=fine_abs[1:0]：

- 逻辑范围：[A+δ+5632, A+δ+25599]。
- 四样点物理字保守联合范围：[A+5632, A+25603]。
- δ=0每窗口512物理字；δ!=0每窗口最多513物理字；8窗最大4104物理读。
- 各窗口间512样点CP间隙不是训练有效数据，不必全部复制进独立训练RAM。

sfo_initial_raw_reader_4lane.sv:116-129、:135-137已有相邻字拼接逻辑。不能把未对齐窗口起点向下取整后直接输出原字而丢掉δ。

| 方案 | 收益 | 约束 |
|---|---|---|
| 保留旧5172字训练私有副本 | 修改小，沿用capture_complete | 要维护连续tap、frame/generation顺序和覆盖生命周期 |
| 从共享raw取8个真实窗口 | 取消重复私有RAM与额外复制，适合本次重构 | 要有读端口服务预算、固定延迟/信用、frame租约和到达水位 |

推荐第二种。若共享读端口设计无法给出训练最坏服务预算，则不能只因为省存储而采纳。

## 6. fine低两位与-172 halo是不同原因

ota_frontend_descriptor.sv:24、:49、:51 将fine低两位同时交给fine记录和CFO raw_origin_q28。它们是四样点物理对齐后的TO残差，是真实坐标信息。

-172来自一遍SFO的输入保护合同。sfo_first_pass_descriptor.sv:36定义INPUT_COUNT=N+540，:89-99核查raw_first=nominal_first-172及可用范围；:158、:181构造包含53、215等滤波/重采样坐标常数的相位；:214-215核查完整请求支持范围和step。它并非由低两位δ引起。

推荐保留“对齐物理起点加δ”。另一方案把raw起点直接改到fine_abs以令TO=0，会使raw起点未对齐，要求E1读取和相位合同同步修改；第一轮收益不足。不能因为δ缩成0..3直接删除halo。

## 7. 旧descriptor的整帧到齐条件须拆分

ota_frontend_descriptor.sv:41要求接受结果时完整1336860样点raw范围已经存在；不满足置错误33。:26使错误后s_ready保持0直到cancel/reset。

连续流里fine确认通常远早于帧尾，照搬此条件会把正常未到齐帧当错误。

| 方案 | 评价 |
|---|---|
| 等整帧到齐再发布descriptor | 可沿用旧地址检查，但增加raw寿命并减少前段并行 |
| 先发布合法descriptor和租约，读请求按committed watermark等待到达 | 适合共享环，推荐；必须区分未来尚未到达与过去已过期 |

接受时检查epoch、地址算术无溢出、前保护仍保留以及lease有容量；发读时检查requested_last < committed_watermark且requested_first >= retained_floor。尚未到达应等待，已过期或跨epoch应明确失败。

## 8. 传输段first/last不能自动成为算法frame/session

sync_frontend_top.sv:32、:39、:164规定session_start/abort/gap会刷新样点计数和候选状态。旧ota_capture_controller_a07.sv:50、:57、:112是一段捕获对应一个session，并在首个结果后停止向前端供数。

连续模式建议：

- 段first/last只用于传输段长度、顺序和入口协议检查。
- raw全局序号跨连续段累加。
- 算法frame_id由检测确认生成。
- 只有真实采样不连续、显式取消或新epoch才复位detector。
- 段last不能伪造一个不合格metric来关闭平台。
- 有限输入最终结束时，未闭合平台应明确归为等待更多数据或会话结束丢弃。

将每段视作独立session是另一合法离线结构，但不能满足跨段前导与连续多帧的合同。

## 9. 对拟定150MHz共享raw回收方案的补充审查

拟案：

1. 150MHz写共享raw；125MHz frontend输出 min(max(accepted-8192,0), 占用snapshot的anchor-532)。
2. 成功record交给descriptor FIFO后保留candidate pin，直到150MHz frame lease队列接纳且ACK返回125MHz再释放。
3. 150MHz取 min(frontend watermark, oldest unlaunched frame rawfirst, current E1 safe frontier, training frontier) 退休。
4. E1 launch移出待启动lease；E1只在响应进入安全FIFO后推进释放。

方向正确；它用所有权交接阻止CDC期间出现回收空隙。但须补足以下条件。

### 9.1 同一绝对序号与epoch

accepted必须是frontend实际接纳的样点序号，而且与共享raw的序号处在同一坐标系。不能将150MHz写指针直接当frontend accepted：写入端可能已领先125MHz frontend ingress FIFO，若以写指针减8192退休，会覆盖前端尚未观察的数据。

如果150MHz先写raw，再通过FIFO交给frontend，则raw写提交、frontend观察入队需要原子约束或明确的保留登记：不能写入成功但永久丢失对应frontend项。FIFO积压也必须计入raw占用；持续500 MS/s来源是否可背压及溢出行为必须冻结。

水位CDC推荐使用记录FIFO或req/ack握手原子携带(epoch, sequence)。不要逐bit同步64位水位，也不能把任意大步跳跃的min水位当普通逐一递增Gray计数器。旧的同epoch较低水位只会保守保留；旧epoch较高水位却能错误回收新会话数据。

必须满足单epoch水位单调不退。每次新candidate被接纳时，candidate_raw_pin >= 已发布的侦测保守floor；8192预算就是证明该约束的依据之一。若检测器IP异常导致该不变量失效，应停止相关回收并按epoch故障流程处理，不能把水位倒退当作“恢复数据”。

### 9.2 Candidate pin应独立于snapshot存储槽的复用

当前sync_frontend_top.sv:245会在fine握手时释放bank_used；拟案要求保留pin至ACK。实现时必须明确：

- 方案A：snapshot bank和pin一并保持到ACK。硬件简单，但两个snapshot槽都可能因descriptor/CDC拥塞不能接新candidate。
- 方案B：fine计算完成后释放snapshot，将(epoch,candidate_id,raw_pin)移入小型pending-handoff表；ACK只释放匹配表项。更好地分离计算存储和所有权，推荐在队列容量可明确时采用。

不论哪种，ACK必须至少携带epoch和不复用的candidate/lease token，不能只有slot bit；旧ACK不能释放已经复用槽的新人。候选计数32位绕回或epoch清零应有禁止复用/排空条件。

### 9.3 可以去掉独立ACK通道的简化选择

当前“双通道watermark更新＋frame descriptor/ACK”安全但状态较多。可选将单调watermark更新和lease创建/释放事件放入同一有序125→150控制事件FIFO：

- 150MHz严格按FIFO顺序先安装frame lease，再处理随后提升的frontend floor。
- 125MHz只有lease-create事件成功进入此FIFO后才能发送提升floor事件。
- 150MHz用本地事件处理结果表示所有权，不再需要仅为该交接设置ACK回125。
- FIFO满时不得丢lease事件；水位更新允许合并，但必须保证lease事件前后顺序。
- 若125MHz还需要知道“frame确实被资源准入”，或两事件走不同FIFO，则仍需ACK，不能仅凭descriptor已经入125侧FIFO就释放pin。

推荐第一轮保持父案显式ACK，因其审核较直接；统一事件流是后续减少状态的备选，而非必须叠加改动。

### 9.4 E1出队与活动lease安装必须原子

E1 launch当拍必须先/同时安装active_E1_frontier=frame.rawfirst，再移除unlaunched queue项。E1尚未发首读时仍需该pin；不能用“尚无当前read”表示不需要raw。

如果允许训练和E1读取并行，二者各自保留，不因E1启动就自动释放training pin。若训练在E1启动前已经完成，则可用已证明的阶段依赖消去training项，但要有所有响应排空及数据在私有FIFO/FFT缓存中的证据。

“oldest unlaunched”可代替所有queue项的min，前提是frame.rawfirst按队列顺序单调不减；否则必须显式取min或拒绝逆序描述符。候选anchor按顺序处理并不自动证明一切重新排序/重试/CDC后的rawfirst单调。

E1安全FIFO不仅要已写入数据，还需确保FIFO不会因取消/错误清空后再次向raw要求已退休地址。reader retry若允许重读，则retry所需保留界限须一同计算。只有单向读、捕获后的数据不再回读raw，才可按响应捕获推进。

### 9.5 段last以后仍存在流水候选

入口的最后一个样点接受后，lag/CMPY/rolling/threshold流水还会产生metric、candidate；copy也可能尚未完成，worker更可能仍在计算。

因此不能因为s_valid=0、segment_last或frontend ingress FIFO暂空就：

- 清除candidate pin；
- 清除epoch；
- 将frontend floor突然提升为writeptr；
- 宣布“不会再有descriptor”。

连续段之间只暂停接受而不重置算法；当前accepted-8192保守floor仍保护流水中可能生成的候选。若明确整个有限session结束并希望释放最后8192历史，需一个终止协议：停止新输入→固定且冻结的流水排空窗口/显式valid链排空→处理所有已生成候选→对缺尾copy和未闭合平台明确拒绝→全部pending handoff与reader响应排空或转交→epoch结束ACK。不能用普通传输last替代这个协议。

若不要求有限session立刻释放最后历史，保留8192至下一显式epoch结束是最简单且安全的选择。

### 9.6 拒绝、取消和无界等待需分类

| 情形 | 当前静态性质 | 回收要求 |
|---|---|---|
| candidate因为copy_active/槽满而未接纳 | 当拍可确定拒绝 | 不建lease；报告drop即可 |
| candidate_anchor过小或复制历史已过期 | 当拍或进入copy前可确定拒绝 | 释放已建临时pin；不能继续读过期raw |
| coarse/fine无信号、协议错、无结果超时 | worker有保护；invalid结果不依赖m_ready | 拒绝完成后释放pin，并排空旧响应/重置本worker |
| 成功fine但descriptor队列满 | 现RTL没有有限上界 | 需要正常服务界限或明确取消策略 |
| lease create已发但150端不接纳/ACK不返回 | 仅有FIFO不能证明有限 | 保留pin；容量/服务/故障退出必须冻结 |
| 等待frame尚未到达的未来尾部 | 连续源下有采样到达界限；允许无限停源则无墙钟上界 | 可等待但保留占用须计算；真正session结束后明确拒绝缺尾帧 |
| 整个系统下游永久背压 | 任意有限缓存都无法永远保持无丢帧500 MS/s | 只能明确故障/丢帧/可背压合同，不能靠增加有限深度承诺解决 |

上述“拒绝”是对特定candidate或frame终结所有权，不等于全局reset。只拒绝一帧时，raw环和其他帧的CDC/reader信用不得一起抹掉。若允许取消跨域在途读，必须等待旧tag响应被归类丢弃并不再访问已释放raw地址；不能仅清本地valid就复用slot/token。

### 9.7 125/150MHz的时序路径

对两snapshot anchor、pending pin与accepted做64位min时，建议拆成局部寄存候选floor再做小树比较，不把64位减法、比较、所有读者min、环地址差和全局ready连成一个组合路径。150MHz退休水位可以使用保守滞后一拍的寄存结果：它只延后回收，不得反向延后写满保护；写入准入要预留水位CDC、RAM响应和入口在途数据的容量。这里应按实际存储读写周期与在途信用算深度，不能盲目给ready打一拍。

## 10. 静态结论与尚未关闭的风险

可以确认本轮应优先采用：四样点对齐物理raw环、保留fine低2位、candidate到frame lease的原子交接、按响应进入安全FIFO推进E1前沿、真实8个训练窗口读取、传输段边界与算法frame分离。

尚未给出且必须冻结的条件：

1. 候选可允许突发/误触发与drop语义。
2. descriptor准入、ACK及各reader的正常最大服务时间。
3. frontend ingress FIFO backlog与150MHz raw写端的原子顺序。
4. 多域epoch终止与迟到响应/ACK丢弃规则。
5. 训练/E1读端口带宽仲裁与最高raw占用。
6. 新电路真实资源和实现时序仍需用户授权后的相应工具证据。

不能静态宣称任意误触发、无界输入暂停或永久下游背压条件下，无丢帧且可持续500 MS/s。该限制来自有限服务率和有限存储，不应通过多跑仿真来回避合同。
## 11. 新增 ota_shared_raw_store 首版独立静态审核

审查对象：rtl/buffer/ota_shared_raw_store.sv，首次读取版本SHA256 95889A874EAD9482194FFEB68A9B08D64109100027FF4970107C51FF499DAA74，共130行。尚未加入生产源集。以下问题已即时告知主开发者；主开发者已说明修正方案，但本节不把拟修正视为已完成验收。

### 11.1 必须修复的确定问题

1. 第35行声明pqbusy/tqbusy，第46-47、55-56行用于ready和issue，但第67、70行的FIFO reset_busy()悬空。这两个wire无驱动，不能认为其为0。应连接实际端口，或删除已被FIFO s_ready/m_valid覆盖的冗余条件。
2. 第101-103行对RAM命令和rv标签仅检查collision；第107行却以bad==0门控accepted、指针、credit、返回计数和输出pop计数。若同拍出现非法floor/frame等bad，RAM仍可能收到新读写，但计数完全不更新；响应FIFO也可能pop而pc/pout不更新。必须统一故障发现边沿已握手传输的记账语义，避免未计数命令。不要将依赖wf/pf的bad直接反接ready而形成组合环。
3. 退休pipeline遇新lease的反例：old retired=0、external_floor=100、retirement_candidate=0、occupancy>=100、ps=IDLE，同拍接纳frame_first=50。第109行仍以旧IDLE计算candidate=100，而第115行只安装pfloor=50。下一拍第110行会退休至100，第89行仍看旧retired=0不报错；再下一拍才发现first已越界。仅比较first<retired不够。
4. 第80、123行p_safe可能小于初始pfirst，使pfloor向后退。应保持pfloor=max(pfloor,p_safe)，不能让已经发布的可退休前沿回退。

主开发者拟案：连接busy；故障发现当拍对已握手读写/输出继续统一计数，下一拍停止新接受；退休当拍遇bad冻结；新frame/train请求同时检查first>=retired、external_floor、流水retirement_candidate；collision作为终止故障阻断冲突RAM命令；pfloor只单调前进。该方向可以成立，待实际修订复核。

### 11.2 正常路径静态成立的部分

- 总读链为1拍命令寄存加sfo_uram_frame_bank的XPM READ_LATENCY_B=2；rv/owner有3位移位。若edge N记录issue，则edge N+1 RAM接受命令、N+2后数据稳定、N+3 FIFO采样，对应rv[2]。数据和owner对齐。
- 两类pout/tout从内部issue计数、直到各自输出pop才释放，包含RAM在途与FIFO占用。只要所有实际issue和pop都被记账、深度参数有效，pout/tout<RESPONSE_DEPTH保留了响应容量。返回无需再占一次信用。
- 每类仅一个活动reader，pframe/pgen等保持到最后输出pop，响应FIFO可仅存数据；没有中途提前复用身份的正常路径。
- 默认DEPTH=393216、AW=19是非2次幂深度。在0<=gap<=DEPTH且wp/accepted对应同一序号边界时，两分支(wp-gap) mod DEPTH映射正确。WAIT_DATA先检查written，再进入MAP，避免使用尚未落RAM的末字。
- wp/pp/tp显式在DEPTH-1回0，没有把2^AW回绕误当DEPTH回绕。

### 11.3 仍需冻结的合同与风险

- 所有first/floor/accepted接口单位是128位字序号；前端此前8192/532为样点数。转换后保留侦测历史2048字、candidate偏移133字。不能混用。
- 若新请求必须first>=external_floor，上游pending training也必须被外部floor保护，不能只pin尚未安装的E1 frame。即使已有E1内部pin使物理数据还在，也不能恢复外部已经放弃的training范围。
- 当前training固定优先、可反复接受下一训练请求；单次TRAIN_WORDS=5172不保证任意持续请求下E1不饿死。应冻结每帧一次训练及调度顺序，或提供有界grant/配额。
- poison应明确是终止状态直至reset，还是可解除暂停。首版poison期间RAM旧响应继续进入FIFO，但pr/tr不更新；若随后解除，返回前沿记账已丢失，不具备完整暂停/恢复语义。
- 本模块没有epoch身份输入，只转发frame_generation作响应标签，不能独立识别坐标恰好合法的旧epoch请求。上游CDC/lease控制器必须阻断迟到跨epoch事件。
- WAIT_DATA目前等待完整FRAME_WORDS到齐后才开始E1读。这是合法的整帧发布结构，但会增加raw初始高水位，不能按“估计一出便立刻从raw流式启动E1”预算它。
- capped_floor是三次串行64位compare/mux。可以改为min(external,written)与min(active_frame,active_train)再合并的两层树，或分级寄存；若寄存，继续保持新lease禁止恢复已发布退休权的合同。属于静态硬件路径预算问题，未有真实时序证据。
- 泛化参数应约束DEPTH、AW、FRAME_WORDS/TRAIN_WORDS、RETAIN及RESPONSE_DEPTH合法。默认值并不等于所有参数组合都可用。

本次没有运行RTL、仿真、综合或任何新实验；问题来自源码边沿关系和有限计数不变量。
## 12. raw store 修订与有序lease scheduler联合复核

本节审查身份：

- rtl/buffer/ota_shared_raw_store.sv：SHA256 5508B25B9DDB00FBF0F5A610E8FDB7E100F8A7B4A5AB643C70ABCE0591F10545，共133行。
- rtl/control/ota_raw_lease_scheduler.sv：SHA256 1256A302D45683CE45A0E0FDC92D174EF3D9791EE74EB7EC1B768714EB877A3D，共63行。
- 仅静态阅读，未执行RTL或EDA工具。

### 12.1 初轮确定问题的修订状态

| 初轮问题 | 最新源码证据 | 静态结论 |
|---|---|---|
| FIFO busy悬空 | raw store:67、:70连接pqbusy/tqbusy | 已修正 |
| bad发现当拍的命令/pop未计数 | :110-129仅按旧stopped门控；:116-117、:124-125以实际未collision读命令计数 | 已修正；fatal edge已握手传输记账一致 |
| 新lease插入与退休candidate竞争 | :89-90同时比较retired、external_floor及retirement_candidate；:112-114遇bad冻结退休 | 已修正为明确拒绝重新租用已发布放弃区间 |
| pfloor回退 | :126仅在p_safe>pfloor时更新 | 已修正 |
| poison可解除导致返回前沿语义不完整 | :107将poison锁存为fault 09 | 明确终止至reset |
| 三次串行64bit min | :72-76为upper和reader_pin并行后合并 | 已改两层比较树 |

collision故障当拍，wf仍表示外部已经完成握手，所以accepted_words/occupancy继续记录该接受，而冲突RAM写被阻断，written_words不虚增。这个故障终止场景允许accepted和written不再最终收敛；文档应明确accepted不是“成功写入”计数，只有written表示实际已发RAM写完成边沿。没有据此宣称故障帧可继续运行。

### 12.2 scheduler的FWFT与所有权交接

scheduler使用一条有序事件流，lease-create在可能解除其保护的watermark之前；create同时写frame_leases与training_jobs，s_ready要求两个FIFO均可接受（:24、:28-36）。

held_pin策略在正常FIFO握手合同下是安全保守的：

1. 空队列create：当拍直接held_pin=event_first，不依赖FWFT头出现。
2. lease_count非零但lsv暂不可见：保持旧held_pin，不以无头替代无穷大。
3. release当前头：当拍仍保留旧头pin；下一头实际可见后再升pin。
4. 最后一个release且无create：先多保留旧头一拍，下一拍lease_count=0才切无穷大。
5. 同拍create/release：count保持；继续保留旧头，下一头出现后更新。
6. 从空队列新增lease不会拉低已经输出的水位，因为create必须event_first>=observed_floor，否则故障停止floor_valid。

这些依赖的是sfo_sync_fifo的有效ready/valid接口合同，而不是假定XPM FWFT“写入后一拍立刻可见”；因此不需要固定估算FWFT presentation延迟来维持安全。FIFO full同时出入若s_ready仍低，只产生保守气泡，不会把两个队列拆开接受。

frame_launch必须表示raw store frame_valid&&frame_ready的实际握手，不是准备启动意图。scheduler:26严格匹配(frame,generation,first)，:27同拍pop lease。raw store在同一边沿安装pfirst/pfloor，因此从scheduler pin转到本地active reader pin没有空隙；旧held_pin额外保留一拍只延迟回收。

### 12.3 训练先于E1不是scheduler自身保证

scheduler对训练只有“任务入FIFO”和“train_ready取走任务”，没有training_done/failed状态。launch_matches仅比较frame、generation、rawfirst，不能证明训练窗口已经安全读取，更不能证明T06成功。

若调用者严格保证：对应训练所有数据已从raw转入私有训练/FFT工作区，并产生身份匹配的有效T06估计，才可能产生该frame的E1 launch，则scheduler只在E1 launch释放frame级pin是安全的。训练期间frame_leases仍保护该raw起点，通常比训练最早样点更早、更保守。

若允许先E1再训练，则当前模块组合不够：lease出队后，E1前沿会越过尚未安装的训练范围。后到的训练请求被raw store first<external_floor检查拒绝，不能靠“数据暂时还在RAM”挽救。

两种方案：

- 第一轮推荐维持并冻结T06成功→E1配置的真实依赖，frame_launch只能来自已握手的E1配置路径，不能由调试/准备标志产生。
- 若要放松次序或支持独立训练取消，应在scheduler中跟踪独立train-owner/install/done位；只有两种读者均已安装或终结才能释放公共frame pin。这增加状态，当前并非必需。

错误训练没有E1 launch时，当前scheduler没有单帧reject/release入口，最老lease永久留下，最终使raw填满。必须明确当前错误策略是否整个epoch终止并reset；若目标是错误帧后继续搜下一帧，则需要有身份匹配的reject_lease输入及训练FIFO/在途响应取消协议，不能仅pop最老队列头。无界等待不是有限队列深度能够解决的。

### 12.4 frontend增加只读retention watermark的最小边界

建议端口：

    output logic retention_valid;
    output logic [31:0] retention_epoch;
    output logic [63:0] retention_floor_samples;

也可直接输出retention_floor_words，但端口名与常量单位必须一致。floor不反接frontend s_ready；使用一拍保守滞后的寄存值，有助于避免64bit减法/min进入握手路径。

不能只计算accepted和bank_used。现sync_frontend_top.sv:245在fine握手当拍释放bank_used，:247把成功结果写入m_valid寄存器；m_result随后可无限等待m_ready。因此最小集合为：

    min(
      max(0,accepted_samples-8192),
      所有bank_used对应max(0,bank_anchor-532),
      m_valid对应尚未原子转交的结果raw保留起点
    )

m_valid项可用经过绝对位置有效性检查后的floor4(fine_abs)-172；若要避开无符号fine_abs下溢/非法绝对位置的边缘情况，成功发布结果时附带保存max(0,active_anchor-532)作为m_result独立保留pin，直至它被接收。这多一个64位保持寄存器，但不会改变算法结果或查询流程。

当m_ready严格表示“这条frame create事件已进入与watermark同一有序事件FIFO”，该握手即可转交所有权。后续提升watermark的事件必定位于create后，无需另设ACK。

若m_ready只表示记录进入描述符转换器或另一FIFO，转换器必须继续输出保留pin直到create事件实际入有序FIFO；不能把这一暂存延迟视作无所有者。转换器内可用两种方式之一：

1. m_ready直接与最终事件FIFO接受条件绑定，组合转换字段；需核算125MHz组合预算。
2. 先寄存转换，再由转换器持有pending pin；该pin与frontend水位取min。推荐在转换包含宽地址检查/算术时用2。

### 12.5 segment_end、observer_drained与quiescent的最小语义

建议把信息分成两个层级：

    input wire segment_end;
    output wire observer_drained;
    output wire quiescent;

segment_end是当前传输段结束信息，不能复位算法frame/session，也不能伪造不合格metric来关闭平台。若它是“本epoch绝不再有输入”，应另命名terminal_end/session_end，避免把普通连续段边界当终止。

最小observer drain实现可在合法末拍握手时记录end_seen和end_sample=accepted_samples+(sample_fire?4:0)，然后等待连续空闲周期。当前原始接受到candidate交付路径约16拍；使用冻结IP延迟下的32个125MHz周期作为保守空闲排空预算，sample_fire重新出现则取消旧drain观察。更精确方案是detector逐级导出pipeline_valid OR，但改动更多。

observer_drained仅意味着此前输入的检测流水不再生成新的metric/candidate；平台run_active可以仍保留，等待下一连续段。不得因observer_drained将retention从accepted-8192提升到accepted。

完整quiescent至少要求：

    observer_drained &&
    !candidate_valid &&
    !history_rsp && !snapshot_rsp &&
    !copy_active && bank_used==0 &&
    worker_state==IDLE && !m_valid

其意义是当前没有已接纳候选/结果工作。外部CDC事件FIFO、descriptor暂存和lease ACK不在frontend内部，系统级quiescent还须单独合并这些所有权。

若copy等待anchor+2920未来样点，而段结束时尾样点不足，普通segment_end不能拒绝它，因为下一连续段可能补齐；quiescent因此可能长期为0。只有明确terminal_end并observer_drained后，才能将该缺尾copy作为终结拒绝、释放pin并保留计数。没有终止语义时，等待是正确行为，不能把它误判为卡死。

如果产品不需要observer_drained单独端口，可保留内部drain状态，仅导出quiescent；但文档必须保留以上区别，不能让quiescent自动等价于“raw末尾历史可全部释放”。

### 12.6 本轮联合结论

raw首轮4个确定缺陷已在实际修订中静态关闭；正常有序lease/watermark与FWFT间隙的所有权交接成立。仍需实际集成证明：

- frontend m_result及描述符暂存器的pin未遗漏。
- 所有frame launch实际来自对应T06成功，训练已安全退出raw。
- 训练失败是全epoch终止还是可继续逐帧拒绝；当前scheduler只支持正常E1移交。
- segment_end不清算法状态，不冒充terminal_end。
- error、poison、旧epoch事件和RAM/FIFO在途数据使用一致终止/reset合同。

尚未做仿真或EDA检查，也未把局部源码静态结论扩展为整链无风险或持续吞吐合格。
## 13. 训练dispatch与T06私有RAM复用审查

最新系统决策：任何T06、身份或存储错误终止整个epoch；不实现错误帧单独删除后继续。该决策关闭第12.3节所述“需要单帧reject接口”的适用前提；正常lease仍只能以匹配E1 launch移交，错误时必须统一终止/复位并清空跨域事件，不能继续工作。

审查对象：rtl/control/ota_training_dispatch.sv，SHA256 8C2E21D5D1840A08ED6300662C751EFAC031836FD3423714E0F2C9747210F311，共75行。未改RTL、未执行仿真或EDA。

### 13.1 配置、数据和发布字段

静态字段一致：

- cfg208 = {frame32,generation32,raw_first64,fine_local32,coarse_hz32,quality16}，:27-29与:42-45切片一致。
- 数据225 = {frame32,generation32,beat32,last1,IQ128}，:31-32校验frame/generation/beat/last。
- tap_absolute=5272+4*expected_beat，beat=0..5171，最后beat base=25956，四lane结束25959，与现有T06 capture [5272,25959]一致。
- expected_beat是13位，校验扩为32位；最多5171，不发生位宽溢出。
- fine_local必须0..3。hz经signed检查在±8388607内，因此meta的32位hz<<8不会超出S32范围。
- frame_record188、coarse/fine record96、meta150的字段总宽与声明匹配。
- 最后一个合法数据拍先写入训练capture；dispatch下一拍进入PUBLISH并发布描述符。T06捕获RAM在同一末拍完成capture_valid，随后才有可启动上下文，时序顺序正确。
- 数据身份或last错误的当拍，外部s握手被消费但tap_fire=0并锁存fault；不会把坏拍写入T06私有RAM。错误后整个epoch终止符合最新合同。
- 四路PUBLISH用pending位独立保持，已交付端口不重复发，未交付字段保持context_record不变。

将来的raw hub必须使物理训练读取起点为：

    train_first_word = frame.raw_first_word + (5272+172)/4
                     = frame.raw_first_word + 1361

原因是frame.raw_first对应nominal-172，而tap_absolute以nominal为0。仅检查数据beat字段不能发现源地址错了172样点；此换算必须在rawhub及其静态合同中明确。现版继续搬5172字保留旧私有捕获结构，没有声称已经改为4104字稀疏8窗口方案。

### 13.2 T06 raw lease release早于成功initial_result

真实源码关系：

1. sfo_initial_raw_to_fft_frontend.sv:104-105：当4096个逻辑训练字已经被CFO前端接受，且raw_pending_count=0时，产生raw训练lease_release。
2. sfo_initial_raw_reader_local_capture.sv:61：capture_release还要求lease_active、pending_count=0、无error；:173-175清lease_active。
3. raw_to_fft_frontend.sv:314-322：DRAIN必须看到!lease_active，且accepted_jobs/raw/corrected均4096，seq_finished，raw_pending/cfo_pending为0，raw_valid/cfo_valid/seq_busy均已消退，才发布成功front status。
4. sfo_initial_estimation_service.sv:341-342记录front_done；:389-393在backend输出时检查front_done、FFT lease已释放、FFT输入/输出4096以及6560 observations/weights，否则进入失败流程。
5. 成功initial_result因此已经晚于训练RAM release和所有raw读退出。等待成功initial_result实际握手后再允许新训练填充，是安全且更保守的复用时点。

注意两个不同lease名字：initial_estimator顶层的lease_release是FFT service租约，raw_to_fft_frontend内部的lease_release才是私有训练RAM租约；不能从同名线误认所有权。

两种复用方案：

- 方案A：当前dispatch在成功initial_result后返回release token。结构简单，保守；推荐第一轮使用。
- 方案B：在raw训练lease_release后就给下一帧预填，重叠SWLS backend尾部。可节省等待，但需要额外独立frame/generation token以及capture空闲证明，可能使下一帧数据与当前T06结果共存；第一轮没有必要叠加。

### 13.3 发现的完成握手集成风险：PUBLISH可能晚于T06完成

ota_training_dispatch.sv:47仅在WAIT_RESULT时initial_done_ready=1；:65要等frame/coarse/fine/meta四路全部完成才进入WAIT_RESULT。但coarse/fine先交付即可启动T06，不必等待meta。

静态反例：

1. frame/coarse/fine已接受，meta_ready持续为0。
2. T06照常完成，sync_sfo_top的ctx/fine/result join可被transport接受。
3. dispatch仍处于PUBLISH，initial_done_ready=0。
4. 如果initial_done_valid仅接initial_result_valid&&initial_result_ready的一拍脉冲，该完成事件丢失；以后meta终于接受，dispatch进入WAIT_RESULT后永远等不到done，也永远不返回release token。

该风险取决于将来的接线，当前dispatch孤立源码没有完成事件来源，不能据此声称集成已经安全。必须选择：

- 推荐：T06 successful consume_join在同一边沿创建一条持久valid/ready完成事件，使用独立1槽holding寄存器保存frame（最好含generation或明确同epoch），直到dispatch initial_done_ready接受。训练单任务未release前不能启动下一次，1槽足够，但新事件与旧事件同拍取出需明确优先级。
- 备选：原子fork consume_join，使transport和dispatch都能接受时才消费T06结果。需要在ready/valid链中核算组合路径，也会让meta背压直接拖延结果消费。
- 也可让dispatch在PUBLISH收集并锁存done，再等所有pending发布结束后release，但必须仍然是可保持的valid/ready接口，不能无身份地记一个任意脉冲。

不建议直接用initial_result_valid电平作为“已完成握手”。RAM物理上虽然已释放，但结果尚未与对应SFO上下文原子绑定；后续新训练虽然可能数值安全，却破坏该dispatch采用的完成/身份合同。

### 13.4 发布、完成与release的其余条件

- release_record={frame,generation}在RELEASE中稳定。release_ready完成后下一拍才cfg_ready，所以新配置和旧RAM复用不会同拍混写。
- initial_done接口只携带frame，没有generation。若事件来自同一125MHz域且与dispatch/T06同epoch同步清空、frame在epoch内严格递增，可以成立；若从跨域返回或跨reset保留，应增generation/epoch身份，不能仅匹配frame0。
- initial_done必须代表成功状态4800的结果已经消费。任何失败应先/同时驱动全epoch poison，不能把错误结果包装成普通done释放并接收下一帧。
- 现有T06 capture还检查下一tap_frame==last_frame+1（sfo_initial_raw_reader_local_capture.sv:55-56），coarse/fine context join也检查严格帧序。不能跳过失败帧后偷偷继续，但这与已决定的全epoch终止策略一致。
- rawhub不能在raw store training reader最后一拍入CDC FIFO后就重启下一份训练RAM写入；必须等dispatch返回release token。数据已离开raw store并不等于125MHz训练算法已读完私有RAM。
- meta可无界背压、initial_result join可无界等待transport，这些属于调度/队列服务预算，不能把T06自身65024拍watchdog当成dispatch完整服务上界。

本轮结论：配置、数据字段和正常RAM复用顺序静态可成立；完成事件必须保持直到dispatch接收，之后与rawhub联合审查才能关闭集成风险。
## 14. raw hub、SFO选项与frontend retention联合审查

时间：2026-09-17 23:37，Europe/Berlin（CEST，UTC+02:00）。

本节身份：

- rtl/buffer/ota_raw_training_hub.sv：SHA256 D3EC6DCFE9AB1ED330C26E54489BA147C26B76F24005C4099A31BADE65DB653C，共139行。
- rtl/frontend/frontend/sync_frontend_top.sv：SHA256 933232CBA31D52F7F277DA268DB6A552DF650931886F457FF5E1143B01F65119，共289行。
- 同时只读审查sync_sfo_top、sfo_two_pass_transport的SHARED_RAW_INPUT分支及前述dispatch/lease scheduler。
- 默认SHARED_RAW_INPUT=0，4个新模块仍未纳入生产manifest；本节不声称生产top已切换。
- 主开发者报告的“10文件语法0诊断”不替代这里的所有权/时序静态检查，本review未自行运行语法器、仿真或EDA。

### 14.1 已关闭的前轮集成风险

1. sync_sfo_top:207将dispatch_done_ready纳入transport_ctx_v，:217生成consume_join；dispatch.initial_done_valid=consume_join（:104）。dispatch_done_ready只依赖已注册WAIT_RESULT状态、rst/poison/fault，不依赖initial_done_valid，因此没有组合ready/valid环。T06结果只有dispatch能够接收时才与SFO context一起被消费，关闭第13.3节的完成脉冲丢失风险。
2. hub:97-101只有匹配训练release ACK才写trained_frames；:79-82与:105要求trained token和lease同时匹配，E1握手同拍消费token和lease。这样实际门控了训练完成先于E1，无需仅依赖注释。
3. hub:128正确使用raw_first+1361作为训练物理起点；溢出检测在:129。
4. frontend retention同时包含scanner、两snapshot和m_result（:280-286）。所有分支先同一级寄存，再同深度比较寄存，输出对应共同的旧时刻。正常单调pin交接条件下，额外延迟只扩大保留，不提前回收。

### 14.2 新发现：错误frame_first会永久等待而不报身份错误

hub:81的frame_ready要求lease_match&&trained_match，:125仅对trained token身份不符报错31。scheduler的错误检查则为frame_launch&&!launch_matches。

具体反例：

- frame_id/generation正确，与trained_frames队头一致。
- frame_first被错误配置，不能匹配scheduler lease头中的raw_first。
- trained_match=1、lease_match=0，因此frame_ready=0，frame_launch永远不会发生。
- hub不报31，scheduler也看不到frame_launch触发其12错误；系统永久等待。

这与“身份/存储错误终止整个epoch”合同不符。建议scheduler导出lease_head_valid（必要时头身份），hub在frame_valid且头确实可见时检查完整(frame,generation,first)不匹配并终止。不要单独使用!lease_match报错，因为FWFT头尚未呈现是正常可等待情形。

备选方案是在scheduler中新增独立request_valid用于检查，而frame_launch仅表示实际所有权转移。这样检查和pop职责分开，但端口改动略多。

上述问题已实时通知主开发者，待实际修订再关闭。

### 14.3 独立CDC通路的顺序与等待

- Raw数据和ordered events使用独立FIFO，彼此可见延迟不同。hub:73-74在watermark超出raw accepted_words时保持事件头，不会让floor先于对应IQ提交而触发raw非法水位。frame-create可以先到，raw读者WAIT_DATA会等待实际written范围。
- Lease-create和解除其保护的watermark仍在同一events FIFO里，事件流内部顺序未被跨通道拆散。
- Training cfg和data各走独立150→125 FIFO，数据可以先可见，但dispatch只在cfg已握手后的FILL接收data。数据FIFO会保留提前到达的数据，不会按错误context解释。
- Training release从125→150带(frame,generation)，hub只在WAIT_RELEASE且trained_frames可接受时接收。只有这个ACK后hub才允许下一job配置；不会因“最后数据已入CDC FIFO”过早复用私有训练RAM。
- 训练单任务context保持至ACK，响应225位中的frame/generation/beat/last由raw store稳定reader身份产生，dispatch再次校验。
- 对各FIFO错误，hub分别在实际所属时钟域收集wr/rd错误位；未发现把一侧错误总线未经CDC直接送另一侧的路径。
- 故障反馈经过寄存器/CDC，没有fault组合环。sfo_domain_reset在同步释放后额外保持64拍，要求两时钟在reset期间继续运行，与现有CDC FIFO注释合同一致。

需要未来顶层冻结：frontend accepted样点必须与raw_hub125输入真实接受一一对应。现raw_cdc深度1024字，frontend scanner保留2048字历史；在入口原子广播成立时，scanner floor不会因最多1024字的数据CDC积压越过150MHz实际写入。若未来末段想把floor直接提升到所有125MHz已接受字，则超前floor等待与满环之间可能形成无进展条件，必须另有排空协议，不能照搬普通运行水位规则。

### 14.4 系统级等待环边界

本次所见consume_join门控没有组合逻辑环，但元数据接收的系统合同必须明确：

    dispatch PUBLISH等待metadata_ready
      → dispatch_done_ready尚为0
      → T06结果不能consume_join
      → E1 context不能产生

因此metadata_ready不能反过来要求对应E1 first_context已经产生。推荐由独立元数据FIFO接纳meta，之后再按frame/generation与两级SFO参数配对。若CFO入口设计成等参数齐全才给metadata_ready，会形成系统等待环，语法检查和局部ready无环检查都发现不了。

当前生产top尚未切换，metadata输出的最终消费者仍需总集成联审。

### 14.5 retention输出剩余边界

- retention_valid=core_rst_n，retention_epoch=epoch；样点水位三级寄存。系统不能跨epoch复用旧高水位，必须统一清空旧event/lease和转换器暂存。
- 已确认m_result被接收后，frontend会解除它的pin；因此m_ready必须代表create事件进入有序FIFO，或接收者显式接管pending pin。该转换器尚不在本次模块中，不能认为已经闭环。
- 8192样点guard覆盖candidate形成前以及retention流水滞后；新candidate pin必须不低于已发布floor。合法fine范围使bank pin向m_result精确raw起点转移时只升不降。
- 本次frontend只有retention端口，没有segment_end/observer_drained/quiescent；第12.5节关于有限末段排空和缺尾候选的合同仍然适用，尚未由新端口实现。
- m_result中非法绝对fine坐标（例如极早candidate上的有符号下溢）应由转换器拒绝并全epoch终止；不能把它构造成高位绕回的合法raw lease。

### 14.6 当前联合结论

正常路径的CDC记录完整性、训练RAM复用顺序、训练完成token与E1租约原子转交、frontend三级保留水位已具备可解释的静态结构。新发现的frame_first不匹配永久等待尚待修订；最终入口原子广播、descriptor转换pin、metadata消费者和epoch末段排空尚未接入本次审查闭环。

未运行仿真、综合或板测，不把语法零诊断解释为整链可靠性或持续吞吐验收。
## 15. 新输入入口、候选生产顶层与独立段终端联合复核

时间：2026-09-18 00:08，Europe/Berlin（CEST，UTC+02:00）。只读代码审查；未运行仿真、语法器、综合、实现或板测。主开发者仍是RTL唯一写入者。

本轮最后实际读取的文件身份：

- rtl/control/ota_stream_ingress.sv：SHA256 DA5AFECCF4117AEDA54DA57AE531C4568D1C777953409064D4CA568DC3D93765，117行。
- rtl/control/sync_ota_top_v51.sv：SHA256 68A40C68CCD94D39A4FC047B1D343447A8709642507A73521149CD8D0B0835BC，132行。
- rtl/frontend/frontend/sync_frontend_top.sv：SHA256 C688453D3CD688E9A3608C1776B6CD5AE121A956620BC57983D145B58F274095，308行。
- rtl/buffer/ota_raw_training_hub.sv：SHA256 A2BD64B2D3DCFFB861718BEA180F4458F46DC4D79449AF636BAC18816F21F5E7，140行。
- 上述身份对应本节代码结论。第15.6、15.7节注明的进一步修正是主开发者已选定方案，其落地RTL应另核对，不把设计同意写成实际修订完成。

### 15.1 candidate pin到descriptor/event的移交已闭环

frontend在snapshot占用时保留anchor-532，在m_result有效时改由floor4(fine_absolute)-172保留（frontend:299-305）。两种pin在共同采样的三级最小值流水中转交；合法fine搜索范围下新的精确pin不低于旧候选pin。

新ingress:68在接收m_result的边沿保存288位record并进入D_MAP，:69-77校验epoch、3800状态、坐标、范围和帧号，再形成208位lease。D_MAP/D_PUBLISH期间不产生任何新的watermark（:81-87），直到frame-create实际进入同一个有序event FIFO，才回到D_IDLE（:61-65）。因此这里选择“转换器冻结watermark”接管候选pin，无需额外125/150往返ACK。

同时事件核查：

- 若接收m_result时已有旧floor待发，该floor来自更早、frontend仍持有候选pin的采样时刻，不能越过该frame的raw_first。
- 同拍旧floor握手与新m_result握手，分别清pending_event及设置D_MAP，不覆盖saved_result。
- frame-create握手时旧descriptor_state为D_PUBLISH，旧pending_event为1，所以不会同拍重复构造第二个create。
- frontend同拍消费旧m_result、产生新m_result时，新result仍保留在frontend；ingress已经进入D_MAP，ready拉低，不能漏掉第二条。
- DRAIN只有在frontend quiescent、descriptor空、result空、event空时才能进入CLOSE，故terminal floor一定排在最后一个create之后。

备选的显式pending-pin加独立ACK也能实现同样安全性，但增加跨域身份和取消状态；当前有序事件法更简洁。

### 15.2 原始输入原子广播与first/last

输入FIFO存储{first,last,IQ128}，first/last与IQ不会在背压时分离（ingress:25-32）。只有fe_ready和raw_ready同时为真才弹出一个字，frontend与raw CDC的实际握手在同一125MHz边沿发生；accepted样点坐标因此与全局raw字序保持一致。

- IDLE先检查队头first，不弹出；ARM等待新frontend epoch和ready成立，之后才进入FEED（:91-99）。
- FEED只允许第一个实际转发字带first；last与该字同拍转发后才进入DRAIN（:100-104）。单字first+last段也覆盖。
- FIFO可预取下一段，但DRAIN/CLOSE不弹出下一段，前段尾流水不会读到后一段样点。
- read_done不负责闭段；只有已接受字上的last有终端语义。普通valid暂停不会重置epoch、改变accepted坐标或取消候选。
- 错误first是在已广播该字的边沿被发现，随后全epoch失败；它不是可恢复的单帧丢弃。
- input_occupancy按真实s端握手减真实广播握手计数，8位可表示128；同拍入出保持。input_idle纳入该计数，关闭FWFT数据尚未呈现时busy提前变0的窗口。

### 15.3 255空拍覆盖当前detector有效流水

从最后sample_fire到最后candidate被frontend分配，当前实现依次为：lag RAM 1拍、CMPY及对应metadata 4拍、rolling延迟与累加2拍、threshold乘法valid 6拍及square/threshold/output三个寄存级、detector候选寄存、frontend接收候选。按采样边沿展开约17拍，保守计入接口边界仍小于20拍；全部流水valid每个clk推进，不依赖后续sample_fire。

证据：sync_continuous_detector:33-59、78-98；sync_rolling_metric:24-42、45-75；coarse_metric_threshold:33、86-112、149-195；coarse_corr_energy_4lane:CMPY_LATENCY=4及143-168、214-227；sync_beat_ram的read_pipe按clk无条件移位。这里只核对当前固定IP延迟合同，没有运行IP。

frontend:37-41只有segment_end设置end_seen；255拍计数是末输入之后的固定排空裕量。:228-230只取消已闭独立段中永远缺尾的snapshot，既不补零、也不制造非qualified metric强行关闭plateau。:290-291还检查copy/bank/worker/result/候选和RAM响应，避免在后续确认仍在进行时宣告quiescent。

两方案比较：当前固定255计数在此固定、无背压detector流水下成立，状态少；若以后增加有背压或可变延迟探测核，应改成显式在途valid归零/完成计数，此时不能沿用255常量的证明。一直qualified到段尾的开放plateau不会被虚构为候选，下一独立段session_start清空它，这是明确的算法边界选择。

### 15.4 段坐标和训练坐标

ingress:45-47、74采用raw_first=segment_base+floor(fine_abs/4)-43，fine_local=fine_abs[1:0]。即raw存储从floor4(fine_abs)-172开始，但T06和后续算法局部fine仍为0..3；-172 halo与低2位细定时并未混为同一偏移。

hub训练物理起点raw_first+1361，dispatch逻辑tap从5272开始，因此全局物理样点=segment_base*4+floor4(fine_abs)+5272，与原训练局部窗口一致。训练cfg/data跨域、完成token与E1 lease的顺序保持第14节结论。

ingress:75累计所有已确认frame所需raw_end的最大值，:105-107在quiescent后用forwarded_words检查末尾完整性。不足时错误22终止整个epoch，不能在独立下一段拼接补齐上一段frame。普通valid暂停不触发这一检查。

### 15.5 前轮风险关闭与完成记录

- hub:125使用lease_head_valid检查完整frame/gen/raw_first不匹配并报34，关闭第14.2节“ready永远为0而错误永不发生”的缺口。FWFT头尚未可见时仍允许正常等待。
- metadata独立125→150 FIFO（top:70-75）可在E1 context产生前接收，关闭第14.4节PUBLISH→metadata→E1→PUBLISH等待环。
- CFO done来自最终输出m_valid与同一record的last（ota_cfo_chain_onchip:139-140），top:93-97同边沿传递该record中的frame/gen，所以completion身份没有错取下帧寄存器。
- top在150域锁存local_fault150并保存context错误，之后同步回125；不会因context join被cancel清零而丢失根因。

### 15.6 新发现：frontend硬错误仅诊断，需进入统一epoch失败

所审top:123-128的fault入口不包括frontend_error125，而frontend:198-201、234、276-278包含计算/IP协议错误、历史读取越界和超时。只暴露诊断端口会允许这些硬错误之后继续接收，甚至出现零frame“段完成”；不能把它们与正常缺尾拒绝等价处理。

两个方案：

1. 顶层使用明确硬故障掩码，锁存全epoch错误；保留正常拒绝bit为诊断。端口改动小，需固定bit语义。
2. frontend单独导出fatal_valid/fatal_code，顶层不理解内部bit位。分类更清晰，但接口改动多。

主开发者已选择方案1，掩码0x006f=bit0/1/2/3/5/6；bit4历史不足丢候选、bit7独立段缺尾拒绝不使epoch失败。该分类静态认可。应同时将frontend_fatal纳入frame_done125当拍抑制条件，避免同拍已经知道硬错误仍发成功完成。

另选择暴露candidate/rejected/drop/confirmed计数有助于区分零帧与漏检，但这些frontend计数在每次session_start清零，应标明“本段/本epoch计数”，不能当整个reset会话累计。

### 15.7 新发现：terminal floor等待raw写入的条件性进度环

原hub:73-74只有floor<=accepted_words时才取event头；ingress CLOSE:84直接发F=forwarded_words，而DRAIN不发布普通较低floor。数据CDC可使F比150MHz accepted领先最多约1024字。

若DRAIN后期才解除旧candidate/result pin，最后已发布W仍很低，且raw环已满，则控制关系可能为：

    terminal F等尾部raw接受 → 满raw环等退休 → 退休受旧W限制 → 更新W的terminal事件仍等F。

无背压快路径中F-W约2048字，远小于393216深度，不会触发该情况；本review没有证明在全部允许背压和候选队列状态下环路前提一定不可达。因此这是未闭合的全局进度保证，不能称已验证普通输入必死锁，也不能靠worker70000拍watchdog消除（m_result背压不计入该有界服务）。

两个方案：

1. 推荐：scheduler按序接收desired floor；实际送raw store的floor=min(scheduler_floor,written_words)。有序lease pin保持不变，写入前沿只限制实际退休，不再阻挡控制事件本身。
2. DRAIN/CLOSE先发F-2048保守floor，在有明确数据排空条件后再发F。可保持旧store接口，但需要额外终端状态/反馈且证明更繁琐。

主开发者已选择方案1。该替代在设计层面成立：

- written_words<=accepted_words，保留store现有“实际floor不可超过accepted”检查。
- scheduler floor在正常有序create/launch下单调；written_words单调，其min也单调。
- 任何未launch frame均仍由held_pin保护；E1 launch同边沿把保护交给raw store活动reader。Training在其frame E1之前完成，现有token合同不变。
- raw store仍用活动primary/training reader pin与该实际floor取min，不会因terminal desired floor很大而越过活跃读者。
- 64位min可增加寄存器；滞后只多保留旧数据，不能把它串入raw ready容量路径。
- 这是改变“允许回收前沿”的提交方式，不是提前确认未写IQ，也不是单帧取消。

该设计选择消除了上面的自阻塞结构，实际落地后需复查连线/寄存初值及新lease保护，没有要求启动仿真。

### 15.8 本轮结论

已闭合入口原子广播、descriptor转换暂存pin、有序lease/floor、独立段固定流水排空、metadata接收独立性和错误raw_first检测。发现的frontend硬错误出口与terminal floor等待问题已形成两方案比较并给出主开发者选定的静态可行修正；在实际RTL复查前仍列为待落地。

候选误触发密度、下游允许背压和整链服务预算仍必须来自总体设计合同；两slot候选缓存与有限event FIFO不能对任意输入噪声保证真帧零丢失。静态结构审查不等于持续500 MS/s、布局布线或数值比较通过。
本次复核记录时间：2026-09-18 00:10:18 +02:00，Europe/Berlin。

## 16. 第15节两项修订及raw地址流水的实际RTL复核

本节为只读静态复核，未运行仿真、语法器、综合、实现或板测。

文件身份：

- ota_raw_training_hub.sv：SHA256 9846AC71E2A56B58691CE7C1DE86F14E9479A14DCBC804B4ECB06EFC11D3921F，142行。
- ota_shared_raw_store.sv：SHA256 B88F85491C632BCEF22230470A6125CC60DE4B554FC5B42AC6FAAF2BF99F07B2，133行。
- sync_ota_top_v51.sv：SHA256 F61DF59D6F00C7E4CC3324AF774B0299318968042B590CA0D08203940EEB24E2，135行。
- ota_stream_ingress.sv：SHA256 DA5AFECCF4117AEDA54DA57AE531C4568D1C777953409064D4CA568DC3D93765，117行。

### 16.1 applied_floor已落实，关闭第15.7节等待结构

hub:74-76将min(scheduler floor,written_words)寄存为applied_floor，:86把event FIFO直接交给scheduler，不再以event_available等raw接受位置；:106送raw store的确实是applied_floor。

复位值0与store external_floor=0一致。正常运行scheduler floor和written_words均单调，applied_floor也单调且不超过此前已写位置，因此始终不超过当前accepted_words。新lease的event_first必须不低于已公布的observed_floor；同拍create或FWFT头延迟不会把retire_floor从旧合法高值降到更低地址。非法事件触发scheduler fault后floor_valid拉低，不能借寄存延迟恢复非法回收权。

E1 launch同拍仍消费lease并在raw store建立pfirst/pfloor。旧held_pin还保留到后续头可见，因此新增applied_floor寄存只延迟解除旧保护，不会提前退休新读者所需raw。Terminal desired floor即使领先数据CDC也能按序消费，实际退休逐拍跟随written前沿；第15.7节控制事件与满环相互等待的结构已关闭。

### 16.2 WAIT_DATA与MAP_ADDRESS的指针/距离保持同一时刻

raw store:120-121在written_words已覆盖完整读范围时，同边沿保存p_map_wp=wp、p_map_gap=accepted_words-pfirst（训练侧同理），下一拍:122-123只对保存量做物理映射。

设保存时刻accepted=A、wp=A mod D、first=F，gap=A-F，则映射结果为(wp-gap) mod D=F mod D。保存边沿或下一边沿发生新的wf，均只改变实时wp/accepted，不改变这组映射快照；不能把新wp与旧gap混用。

默认D=393216、AW=19。合法gap<=D由:93独立检查，在wp<gap分支中wp+D-gap位于0..D-1；即使19位中间加法wp+D截位，随后同宽减法的模2^19结果仍与该合法区间内的精确结果相同。这里不需要通用除法或非2次幂取模电路。

MAP阶段若gap>D，bad在同边沿锁存fault；该阶段没有该reader的RAM read issue，下一拍fault阻断read，因此截断低位不会形成未报告的错误读。已有其他reader的合法同拍命令仍遵从原有统一fire计账规则。

与原方案比较：旧版把64位差值、比较与地址加减组合串在同一映射阶段；新版同拍冻结完整差值与wp，再进行19位比较/加减，有明确寄存边界。它改善了结构上的组合预算，实际150MHz时序仍须由后续授权物理报告证明。

### 16.3 pfloor/tfloor增量更新与原公式等价

每次frame响应进入已预留容量的安全FIFO后，旧pr为此前已返回响应数。新:126仅在旧pr>=RETAIN时pfloor加1；RETAIN=256时，第1到第256个响应均保持pfirst，第257个响应才第一次增加到pfirst+1。

归纳结果：完成R个响应后的pfloor=pfirst+max(R-RETAIN,0)，与此前每拍max保护的pfirst+R-RETAIN公式完全一致。新表达避免了每个响应路径上的64位加法、减法及max比较串联，也不会出现初始前沿低于pfirst。

训练:127每个treturn令tfloor加1，从train_first初始化，因此始终为train_first+返回响应数。主/训练响应仍分别由rv[2]/owner[2]识别；这里没有把前沿提前到request issue。响应信用、RAM三拍标签和同拍输入输出记账未被此次修改。

### 16.4 fatal、完成门控、busy与计数实际接线

- top:36掩码006f已接，:128将frontend_fatal锁存为全epoch错误30；bit4和bit7仍只诊断。
- top:123在生成frame_done125时同时检查frontend_fatal，关闭已知硬错误当拍仍发成功完成的缺口。
- top:14、52暴露candidate/rejected/drop/confirmed，它们仍按frontend session/epoch复位。
- ingress:22、59用真实入/出握手计数input_occupancy，:43纳入input_idle；top:119使用该idle，关闭FIFO已有字但FWFT尚未呈现时的busy空窗。

诊断边界：全epoch poison使frontend core_rst_n变低，frontend原生error_sticky和上述计数会被清零，top当前保留的只是错误30。因此错误分类能可靠终止epoch，但Host若要在故障后读取具体frontend bit或故障前计数，需要顶层另行保存快照。这不是本次所有权/终止行为的功能阻断，不把当前端口宣称为故障历史存档。

### 16.5 本轮结论与证据界限

第15.6、15.7节已选方案现已在实际RTL中核对，相关风险关闭；新增地址映射拆拍及读前沿增量更新在正常合同下与原运算等价。本轮受审改动未发现新的功能阻断。

主开发者报告“含真实IP stub/XPM header的静态binding为0 errors”，本review未重跑该工具。这是静态绑定证据，不是原生Vivado展开、功能仿真、综合时序、持续吞吐或板测证据；全链服务预算、数值比较和物理实现仍按主任务未完成项分别记录。
复核时间：2026-09-18 00:15:43 +02:00，Europe/Berlin。

## 17. 前端诊断快照的小修订复核

仅检查sync_ota_top_v51.sv前端live诊断接线与顶层镜像寄存，未重新遍历设计、未修改RTL、未运行工具实验。

文件SHA256：E0EB770938DB60B9F8830157C68B73123A390D91685212244A1E22B015D81BDD，共146行。

- :63-64实际frontend输出接入live_candidates/live_rejected/live_dropped/live_confirmed及live_frontend_error。
- :38的fatal掩码仍直接作用于live_frontend_error，没有因诊断输出多一级寄存而延迟故障判定。
- :41-46在!poison125时镜像，poison时保持；reset_request经rst125明确清零。
- 当live_frontend_error首次为fatal且fault125尚为0时，同一clk125边沿:139锁存fault，同时:44-45采集已有live错误和计数。该边沿之前poison125=0，故快照不会被阻止；之后poison125变1，下一个边沿frontend内部取消复位、诊断镜像保持，错误根因不会被清零覆盖。
- :134仍用live fatal屏蔽当拍frame_done125，不依赖较晚的输出镜像。

第16.4节的“故障后具体frontend错误位和计数清零”诊断限制现已关闭。正常运行输出比live信号延迟一拍，并随正常新segment的计数复位镜像更新；故障/取消后保持最后已采集快照，直到显式reset。没有新增功能阻断发现。
## 18. 输入到训练完成、E1准入与raw退休的联合上界

本轮仅做源码阅读、固定循环推导和普通算术，不运行RTL、仿真、EDA或新实验。以下以125MHz域一拍接受一个128位字（4个复样点）、150MHz raw单写单读端口、时钟连续运行、reset恢复完成为合同。a_i为第i个正式lease的raw_first字序号，B=334215字，D=393216字，RETAIN=256字。零点取raw字a_i开始进入连续流的时刻。

### 18.1 合法物理帧周期必须包含SFO范围

生产sfo_first_pass_descriptor.sv:154–177将S32/F18 ppm换为R28步长，公式为step=2^28+RNE(ppm×2^28/10^6)，不是可任意改写的常数1。:85限定±150ppm，:214给出最小合法R28步长268395191。对于真实采样时基也处在该±150ppm合同、每个真实帧恰好确认一次且确认起点符合所冻结数值精度的连续帧：

    Pmin=floor(1336320×268395191/2^28/4)=334029 raw字。
    Tmin=334029/125MHz=2.672232ms。
    Tmin×150MHz=400834.8拍；保守单帧整拍预算400834，双帧801669。

334080字/400896拍仍是名义值，不能用于最短物理周期的严格不等式。上述±150ppm是物理输入合同；仅有估计值被RTL范围检查接受，并不能倒推真实输入必在该范围。若将两级±150ppm与±3ppm定义为可独立叠加的物理偏差，应把实际最小总step代回同一式；若允许相邻真实TO误差变化，还应扣除其差值界。fine局部±360样点搜索范围只说明候选局部坐标覆盖，不能冒充已证明的真实TO误差界。本轮按主任务明确的物理±150ppm/Pmin334029合同预算，不暗改吞吐指标。

### 18.2 已接纳候选在完整raw窗口之前交出训练的界限

sync_frontend_top.sv:217–225只有在oldest_age+3200<8192时开始复制；oldest_age=A_samples−anchor+256，所以开始copy时A_samples−anchor<4736。候选可能需要的最早raw为anchor−532，四点对齐得到相对raw_first最多1317字的已接受前缀。加794次snapshot读取、RAM返回和状态转换余量，采用保守snapshot就绪上界2120个clk125。

worker在:252–280的固定控制为16计数复位、794次replay请求、WAIT_RESULT的70000比较；成功结果可以转交时，每个worker可采用70832拍保守上界。双snapshot最多使一个在先worker占用等待，因此当前已接纳候选确认/拒绝界为：

    Cconfirm≤2120+2×70832=143784 clk125。

这里的worker界是成功或受控拒绝/失败的保护界，成功valid受下游无界阻塞时不成立；不是对所有输入数值必然确认成功的算法证明。正常合法确认流的event/lease/metadata容量与服务合同消除了该无界下游等待；密集误候选则可能在接纳前明确capture_drop。

hub:130–136的training raw首字=a_i+1361，5172字，最后所需写前沿为a_i+6533；它在输入52.264us时已经齐备。dispatch:33–37、60–65在FILL连续接收5172字，按125MHz计41.376us；数据身份、beat和last逐项检查后才PUBLISH。

T06 sfo_initial_estimation_service.sv:105、283、287–323、394–396从context join后对ACQUIRE/START/RUN整体计时，成功输出必须不迟于65025拍保守边界。HOLD_RESULT不在此计时内，故context实际消费仍由整链容量合同覆盖。65024 watchdog用于受控终止，不得被写成所有合法信道数值均必成功的正常算法服务证明。实际t04_div_u63_u47.xci:65、89、100给固定latency66、clocks_per_division8；6560次weight运算的吞吐主项为52480拍，但其前后FFT/phase/tail的完整数值成功性仍继承既有模块合同，未在本轮重新做全数学证明。

配置映射、有序FIFO、跨域、发布/消费及release token取512个clk125统一余量：健康已恢复的2级同步FWFT跨域单跳按32个慢域周期封顶，少于8个串行可见性跳，加局部有限状态边沿仍小于512；此项只覆盖固定控制，不替代任何FIFO满等待。

    Ttrained_i−a_i ≤ max(143784,6533)+5172+65025+512
                  =214493 clk125=1.715944ms。
    Tfull_i−a_i=334215 clk125=2.673720ms。
    Tfull_i−Ttrained_i≥119722 clk125=957.776us。

若没有在先worker，则总界143661 clk125=1.149288ms。Pmin334029大于当前确认和训练的联合214493界，因此前一真实帧训练最迟完成在下一真实帧最早可能发布之前；每真实帧确认一次的合同下不会积累T06训练队列。即使为单个已接纳真候选保留一个在先拒绝worker，仍有上述957.776us前置余量。

raw hub:81–84、99–103使用对应frame/generation的trained token许可E1 launch；token只在dispatch实际消费initial_result并送回release之后产生。故成功正常路径中“E1 cfg尚缺训练/初始化结果”的延迟贡献为δcfg_training=0。真正的δcfg还包括前一个E1未空闲、目标SFO bank未释放与固定准入边沿；这些必须由SFO跨帧复用递推计算，不能用本节把它们设0。对已经空闲且raw整窗可见、训练token已在队列头的启动固定开销，可保守在150域再预留32拍，不包括bank/E1忙等待。

### 18.3 每次训练只抢5172个raw读边沿

ota_shared_raw_store.sv:56–58中p_issue唯一的训练阻塞条件是同拍t_issue。训练REQUEST、WAIT_DATA、MAP_ADDRESS以及响应FIFO无信用时均不抢E1读端口；仲裁没有额外每任务切换气泡。每个成功训练作业只有5172次t_issue，因此：

    B_raw≤5172×ntrain 个clk150。

raw和training响应分别预占64项信用；150→125的training data FIFO为1024项。5172字满速150MHz突发、125MHz消费的速率差积压为862字，再保守加64字首次可见性余量为926<1024。下一个training作业要等上一个5172字全消费且T06结果消费后的ACK，不能把上个作业尾巴叠在新burst头部。这说明健康warm FIFO无需额外不可计算的训练阻塞费用；发生真实FIFO协议错误时全epoch停止。

E1_i launch已经消耗自己的trained token，所有j≤i的training均已完成；只有未来j>i可能抢占。第j次training不早于a_j+6533输入前沿。设完整窗口之后最迟准入延迟G=58745输入字（469.96us），暂用比物理单帧预算还宽松的C1≤400896 clk150作保守排除，则E1_i结束时输入前沿不超过a_i+334215+58745+(5/6)×400896=a_i+727040。因此：

    ntrain ≤ floor((727040−6533)/Pmin)
           = floor(720507/334029)=2。

排除第三个训练只要求Pmin>240169字，因此±150ppm的51字修正远不改变ntrain≤2，但它仍须进入每帧服务/双bank复用预算。该证明以前置δcfg界成立为条件，与下一节联合不等式构成闭合条件；不能反过来无条件声称当前RTL对任意严格递增地址都ntrain≤2。恶意高密假确认不在真实连续帧服务合同内。

### 18.4 469.96us只能花一次：启动等待与内部停顿联合约束

设Dcfg150是完整raw窗口可用到E1 cfg实际接受的拍数，C1是该cfg到完整E1完成的总拍数。因为每拍至多完成一个raw响应，且C1结束前B个响应均已返回，对任意E1前缀u都可使用：R(u)≥max(0,u−(C1−B))。rawstore:126的安全前沿是a_i+max(R−256,0)，:112–113再经retirement_candidate与retired两拍生效。由此得到一个保守、容易复核的充分条件：

    Dcfg150 + (C1−334215) + 2 ≤ 70494。

70494=(393216−334215−256)×150/125，2是退休寄存器生效余量。该式同时收费bank等待、前一E1等待、配置起停、FIR有限服务延迟、全部训练抢占及剩余内部空洞，不允许先给首次起读469.96us、再另外免费发生C1内部停顿。

若仅用C1≤390400设计目标，则Dcfg150≤14307拍=95.38us。SFO独立review进一步收紧为C1≤334672+Lfir+5172×ntrain；代ntrain≤2得C1≤345016+Lfir，从而：

    Dcfg150+Lfir≤59691 clk150。

Lfir须是四种FIR在实际配置下、含允许暂停/恢复的有限II=1弹性服务上界之和，而不只是某次空流水首字latency。这一合同由主任务从现有生产IP配置/接口核实；本review不运行IP实验。

若Dcfg150=0，独立用松界C1=390400，则保守raw高水位为：

    Qraw≤334215+256+ceil((5/6)×(390400−334215+2))=381294字。

有Dcfg则将其加到ceil内部；达到联合式边界时393216字，实际实现还应保留额外边沿余量以避免正好full时入口暂停。相邻未launch lease、frontend watermark和训练pin仍必须不早于此处假定的活动E1退休前沿；在真实帧间隔/早期确认合同下，它们的位置由上述同一时间轴核查，不能仅靠读口平均带宽宣称容量闭合。

两个设计选择：A保留当前早启动/响应退休结构，用SFO双bank释放递推证明Dcfg150与Lfir的上述合计界，优先；B若实际IP服务合同确实超界，则调整存储/分级流式准入或读者服务架构，并重新算资源与坐标边界。盲目扩大watchdog、把未来training费用忽略、仅增加一个小FIFO均不解决同一容量预算。

## 19. 长段、短段与误候选的明示行为合同

| 输入类型 | 静态能保证的行为 | 不得宣称的范围 |
|---|---|---|
| 长无帧段，无活动旧lease/worker | scanner floor只落后8192样点=2048字，floor每至少64字发布，固定warm CDC/退休链再预留64个125周期，保守raw占用≤2176字；段长本身不造成增长 | 此数不适用于仍有上一真实帧活动reader或无限持有成功result的情形 |
| 无确认、但有可按时拒绝的密集候选 | 两snapshot限制已接纳工作；snapshot就绪+至多两个70832拍worker+固定64拍退休余量给保守pin占用≤143848字；额外候选在copy忙/双bank占满时capture_drop | “真帧零漏检”不适用于任意噪声候选密度；candidate计数不能视为真实帧计数 |
| 持续合法多帧 | 每真实帧确认一次、Pmin334029字、物理±150ppm、成功数值/服务合同下，训练早于整窗、ntrain≤2，raw和双bank按§18联合递推 | 端口4lane×clock、单帧完成或watchdog有限不是持续500MS/s证据 |
| 独立短输入段 | 真实last之后固定255拍探测pipeline排空，缺snapshot尾部按bit7拒绝；confirmed frame所需raw缺尾则ingress错误22终止epoch；普通valid暂停不结束段 | 任意短独立段零间隙达到500MS/s不受支持，初始化/排空握手本身占周期，不能暗把last改成算法帧尾 |
| 高密假确认 | 有序地址/身份检查、raw满背压、FIFO溢出/下溢及非法前沿fail-stop防止silent corruption；真实FIFO错误经hub/top poison终止整个epoch | full容量反压本身通常不是fault；上游不支持暂停时当前接口不能保证无丢样，不能把此类输入改称合法持续吞吐通过 |

对恶意高密假确认，当前不新增噪声拒绝策略或无限重构候选调度：选择A保留现有明确受控拒绝/背压/整epoch错误语义并限定上述真实帧性能合同；选择B新增物理帧间隔准入或候选优先策略会改变检测行为和允许输入，只有确有需求时另立设计。有限加深候选队列无法保证任意长的高密噪声真帧零丢失，不能作为当前缺口的伪修复。

控制层silent corruption边界已逐项审查：数据/配置/lease/release均带frame/generation；训练beat/last严格匹配；lease_first严格有序且不可落在已放弃区间；主/训练RAM响应分别预占信用；新fault边沿已公布握手仍记账，下一拍屏蔽；terminal floor按written前沿截断；已知前端fatal屏蔽成功完成。原始IQ本身无ECC/CRC，真实存储器物理bit翻转不在这些协议身份检查的覆盖范围；本句是证据边界，不新增硬件特性。

## 20. 候选ID回绕与按anchor排序：实际修订复核

本轮已在sync_frontend_top.sv:115–118读到主开发者的方案B：两个bank_ready同时有效时比较64位bank_anchor，candidate ID明确注释为模2^32标签。此前32位candidate_count连被丢候选也递增，结构上每5拍一个候选足以在约171.8秒跨零；用unsigned candidate ID排序会把回零的新snapshot选在旧snapshot之前。这个确定缺陷现已关闭。

选择比较：A在候选ID达到FFFFFFFF时停止整个epoch，改动少但无必要限制正常长噪声段；B按已有绝对样点anchor排序，ID只作等值tag，保持连续段，优先且已落实。没有扩大所有tag宽度或增加新表。

完整tag消费核对：

- sync_frontend_top:150的halo tag=active_candidate−1，:154 nominal tag=active_candidate；candidate=0时halo=FFFFFFFF。
- coarse_lag1024_beat_ring:68–75的beat_frame_id==explicit_halo_frame_id+1'b1以及previous_complete关系均为32位模加法，因此FFFFFFFF+1正确为0；显式active/clean/valid决定存在性，没有以ID0作空值。
- to_coarse_estimator:153–154由beat_base_sample_index==0判定新帧，:444保存tag，:491、509、512只等值检查。coarse_result_pair_fifo只原样存储/输出record。
- sync_coarse_pair_join:97、108–114匹配TO/CFO等值tag；fine_local_capture_buffer:136、148–165匹配capture tag；to_fine_core:285、614、636、714、750以相同tag校验和输出，没有大小排序。
- top:142在IDLE/RESET_ESTIMATORS复位worker，:259–265保留16计数清空；只有一个估计job活动，跨job无未清算响应可借同tag误认。
- ota_stream_ingress:70–74重新赋正式frames_created/global generation；frontend内部next_frame_id/candidate_id不是全局lease序号，frames_created溢出已有错误12保护。

结论：candidate编号跨零不破坏halo、coarse/fine身份或全局lease身份；这次最小anchor比较修正通过独立静态复核。64位比较只用于两个ready bank的任务选择，不串入输入raw ready容量路径；物理125MHz时序仍由后续授权实现报告证明。

## 21. 前端与训练完整sourcegroup覆盖表

以实际rtl/sources_v51.f为清单；同一行“完整sourcegroup”包含所述目录/前缀全部源文件，不将未重新推导的旧算子误标为本轮数值验证通过。这里的资源是结构/容量预算，不是综合映射结果。

| 完整sourcegroup/入口 | 本轮接口、所有权和数值边界重点 | 资源/CDC/超时证据与限度 |
|---|---|---|
| rtl/frontend/common/bistatic_stream_pkg.sv | record字段、signed值、frame tag宽度 | 前端全部125MHz；32位tag为模标签 |
| frontend/frontend的sync_continuous_detector、sync_frontend_top、sync_coarse_pair_join；timing/sync_rolling_metric；buffering/sync_beat_ram | 连续样点坐标、plateau关闭、snapshot接纳/拒绝、bank顺序、成功result保持、段结束/排空、retention三级 | 8192样点history、2×794字snapshot；无帧floor2176字保守界；worker70832有条件界；新增64位比较不在raw ready链 |
| buffering/coarse_lag1024_beat_ring、coarse_result_pair_fifo；timing全部coarse_*、to_coarse_estimator、to_coarse_ports | 显式halo与mod标签、1024lag、valid/data对齐、plateau/phase结果顺序、snapshotreplay覆盖 | 固定4lane运算/IP寄存；旧乘加定点没有重写，未把继承算子当0LSB比较结果 |
| frontend/carrier全部3文件 | coarse CFO/phase increment/rotator范围、对应tag与本地训练坐标 | 原phase/舍入/饱和保持；IP延迟和reset flush按原冻结合同，物理DSP时序未测 |
| buffering全部fine_*；timing全部fine_*、to_fine_core、to_fine_estimator | capture一致性、coarse_start±232、257候选±128、fine范围±360、quality/status、输出tag、成功HOLD背压 | 分块相关而非无限并行；fine65024保护不包括成功HOLD，不能代替正常算术服务证明；PS1 ROM数据保持原件 |
| rtl/control/ota_stream_ingress、ota_raw_lease_scheduler、ota_training_dispatch；buffer/ota_raw_training_hub、ota_shared_raw_store | 原子fe/raw广播、全局raw序号、D_MAP/D_PUBLISH pin、有序lease→reader、5172字完整训练发布、T06消费→ACK→trained token、fault同拍记账 | raw393216×128、主/训练各64响应信用、raw/training CDC各1024；event/config/release/trained各32；RAM3拍标签与非2次幂映射已审 |
| sfo/buffering/sfo_training_capture_buffer、sfo_uram_frame_bank、sfo_sync_fifo、sfo_record_cdc_fifo；control/sfo_domain_reset | 训练私有RAM不可提前复用、FWFT瞬时空与reset_busy、完整record原子CDC、响应安全入队后退休 | 125/150域同步释放；Gray/XPM必须由真实约束覆盖；逻辑CDC结构不是MTBF或布局布线报告 |
| initial_estimation的sfo_initial_estimator、sfo_initial_estimation_service、sfo_initial_frame_context_join、sfo_initial_raw_to_fft_frontend、sfo_initial_raw_reader_4lane、sfo_initial_raw_reader_local_capture、sfo_initial_ps3_ps10_job_sequencer | T06 context join、8个PS3–PS10窗口最早fine+5632/最晚fine+25599、真实5172字tap区、低2bit跨字拼接、FFTlease释放不同于initial_result消费 | initial service65024覆盖ACQUIRE/START/RUN；首次训练先完整到齐再发布，避免把输入等待算入计算watchdog |
| initial_estimation的sfo_cfo_phase_increment、sfo_initial_cfo_derotate_s16_4lane、sfo_initial_dds_phase_4lane、sfo_initial_derotate_wide_4lane、sfo_initial_shared_gain_s16_4lane、sfo_initial_shared_gain_s16_lane；sfo/common的pkg及vendor_multiplier_adapters | CFO、phase、共享gain、S16/宽运算adapter继承原数值含义，四lane valid/metadata一致 | 旧运算未改且未重新穷尽数学证明；不能将此覆盖表称数值比较报告 |
| initial_estimation全部sfo_initial_fft_pair_extractor*、sfo_initial_fft_swls_backend；fft_service/sfo_initial_fft_service、sfo_initial_fft_arbiter | FFT输入/输出4096字、4对6560 active bins、完成计数/身份、lease尾部8拍guard | 生产FFT固定配置和有效服务仍需冻结元数据；没有把clock×lanes当服务保证 |
| initial_estimation全部sfo_initial_observation_engine*、sfo_initial_observation_store*、sfo_initial_pair_max_tracker_2lane、sfo_initial_pair_phasor_bfp | 2lane observation、4pair顺序、store封存与回读、BFP/phase/权重范围 | 老数值算子保留；本轮重点为边界/服务依赖，不声称重新证明全输入数值可靠 |
| initial_estimation的sfo_initial_five_sum_accumulator、sfo_initial_regression_tail、sfo_initial_swls_weighted_backend、sfo_initial_unsigned_divider_service及其fifo、sfo_initial_weight_pack | 6560观测/权重、4封存pair、divider meta与结果tag、除零/容器错误、回归结果status | divider真实XCI latency66/CPD8；任何T06错误终止epoch；65024成功条件和HOLD等待分开 |
| sfo/control/sync_sfo_top、sfo_two_pass_transport；control/sync_ota_top_v51相关连接 | consume_join原子通知dispatch、frame/gen一致、E1仅持trained token准入、前端fatal006f、诊断冻结、完成CDC | 与SFO/CFO reviewer交叉覆盖；本文只认输入/训练/lease边界，不代替他们的SFO/CFO整帧数值与周期报告 |

rtl/control/ota_frontend_descriptor.sv作为旧坐标参照已读，但它不在sources_v51.f生产路径；旧整帧raw到齐即刻判定被ota_stream_ingress+lease等待结构取代，不能从旧模块仍在磁盘推断生产仍走该限制。旧sfo_raw_frame_ring同理：SHARED_RAW_INPUT=1选新hub，保留旧文件是兼容源路径，实际展开应核实参数选择。

当前静态结论：候选跨零、段边界、训练所有权、CDC有序交接与raw退休的确定功能问题已按实际修改关闭；合法连续帧条件下训练不会消耗完整窗口后的δcfg预算，ntrain≤2有物理帧距依据。持续500MS/s还须把实际FIR服务合同和SFO/CFO双bank/ring跨帧递推代入§18联合预算，并由以后用户批准的必要验证与真实时序报告分别取证。本文没有宣称“全工程所有静态风险已消失”，也不以仿真试错代替仍可解析的设计预算。
复核记录时间：2026-09-18 01:15:10 +02:00，Europe/Berlin。

## 22. 129个生产源、include与厂商依赖的责任索引

本节只读核对当前 `rtl/sources_v51.f`、现有审查报告、`reports/v51/final_static/source_audit.json`、`static_binding_07/summary.json`、XPR/XCI与XDC；没有重新启动绑定、仿真、综合或实现。F=本报告，S=`sfo_schedule_review.md`，C=`cfo_output_review.md`，A=`arithmetic_review.md`。下表的覆盖表示存在具体接口、状态、数值边界或所有权/服务分析，不等于每份旧数值RTL已重新完成全域数学证明。

| 当前源目录/完整组 | 文件数 | 责任报告与章节 |
|---|---:|---|
| rtl/frontend（buffering6/carrier3/common1/frontend3/timing21） | 34 | F§1–8、15–21；完整组索引F§21，本节后续告警语义F§23 |
| rtl/sfo/initial_estimation、common | 30+2 | F§5–7、13–14、18、21；接口/坐标/所有权/服务依赖明确，旧算术保留和未完成数值比较的边界见F§21 |
| rtl/sfo/resampling、first_resampling、second_resampling | 8+3+2 | S§6、15、17–19；F§23补定点截位/descriptor符号警告 |
| rtl/sfo/residual_estimation | 14 | S§7、11、13–19；LS/div实码算术另见A§1–8 |
| rtl/sfo/fft_service | 5 | initial_service/arbiter两份F§18、21；其他三份S§11、14–15、18、20 |
| rtl/sfo/buffering | 7 | training_capture由F§13、18、21；其余六份由S§4–5、11、15、18；共享FIFO/URAM另由C§19.1交叉覆盖 |
| rtl/sfo/control | 3 | S§11、13、15、18；F§14–18覆盖consume_join、训练与raw接线 |
| rtl/cfo | 12 | C§19.1、22.1逐文件覆盖；后端四份实际应用对应C§21–22，A§9独立算术复核 |
| rtl/buffer/ota_shared_raw_store、ota_raw_training_hub | 2 | F§11–18、21 |
| rtl/buffer/ota_cfo_window_queue | 1 | C§13、17.4、18、19.1 |
| rtl/control/ota_stream_ingress、ota_raw_lease_scheduler、ota_training_dispatch | 3 | F§12–18、21 |
| rtl/control/ota_sfo_context_join | 1 | C§9、15.5、19.1；S§16及F§18交叉服务分析 |
| rtl/control/sync_ota_top_v51（module名sync_ota_top） | 1 | F§15–18、21；C§15–16、19.1；S§18 |
| rtl/common/ota_async_fifo_a06 | 1 | C§13、19.1明确核查reset、Gray同步与FWFT；F§14–16的CDC所有权边界 |
| 合计 | 129 | 未发现没有责任报告/完整sourcegroup索引的自有生产源 |

旧 `ota_frontend_descriptor.sv` 不在本生产清单；磁盘上其他旧control文件也不能自动计入当前top。`sfo_raw_frame_ring.sv`在所选兼容源集中，但SHARED_RAW_INPUT=1选择shared hub；保留文件的静态覆盖不意味着当前硬件实际实例化它。

129之外的依赖另列如下：

- `rtl/include/initial_observation_ip_config.svh`：square3、weight4；与实际 `t06_observation_engine_square`、`t06_observation_engine_weight_product` XCI的C_LATENCY/PipeStages3/4相符。调用方F§21的observation_engine组。
- `rtl/include/initial_pair_max_tracker_ip_config.svh`：cross4，与 `t06_pair_max_tracker_2lane_cross` XCI的4拍相符。调用方F§21的pair_max_tracker组。
- `rtl/include/initial_shared_gain_ip_config.svh`：mult3、div55，与 `t06_sg_mult_u37_u16` 的3拍及 `t06_sg_div_u53_u37` 的C_LATENCY/latency55相符。宏/参数一致不等于工具已展开验证所有IP有效服务。
- `rtl/vendor/xpm/{xpm_cdc,xpm_fifo,xpm_memory}.sv` 共3份：生产XPR有显式来源，static_binding_07锁定三份SHA。使用端的CDC/同步释放、FWFT、RAM响应延迟和信用已由F§12–18、S§15/18/20、C§6/19.1审查；未声称逐行证明厂商内部体。绑定只采用XPM接口声明，内部和primitive映射未检查。
- managed XCI共45份（farrow5、t03 2、t04 6、t05 9、t06 19、t07 4）：父任务source_audit核对身份/参数，F§21覆盖前端/T06调用接口，S§10/15/16/20覆盖FIR/FFT配置与有限服务合同。对45份黑盒的完整数学/物理实现没有本轮独立证明；原生生成、展开和真实映射仍属后续证据。
- `constraints/sync_ota_clocks.xdc`只建立clk125=8ns、clk150=6.666666667ns、clk500=2ns三个核心时钟，没有笼统false_path/异步组。S§18与C§19.1覆盖约束责任边界；XPM scoped约束在原生工程中实际加载/生效、CDC路径、NI外部I/O和布线时序不能由这5行或静态stub绑定证明。

## 23. static_binding_07高风险告警的逐项语义处置

实际快照为pyslang11.0.0、top=sync_ota_top、candidate_overrides为空，**958条诊断、0 errors，绝不是0警告**。先前报告有相关几何/定点分析，但没有将本次4条UnsignedArithShift、27条WidthTruncate、1条CaseDefault逐一编号关闭，因此本节补读实际警告位置和上游范围后给出32条处置。仅处置这三类不能宣称其余926条已逐条审清。没有为消除警告改RTL。

### 23.1 四条UnsignedArithShift

| 实际位置 | 语义与有效范围 | 结论 |
|---|---|---|
| frontend/buffering/fine_local_capture_buffer.sv:62 | FIRST_SAMPLE为unsigned使差值/>>>为逻辑右移；:59–64在写入前检查signed样点范围[152,2916]并4点对齐。有效差值非负，地址0..691。负数/越界计算即使产生其他组合值也不写RAM。 | 生产有效输入与算术右移一致，非静默丢符号。 |
| sfo/buffering/sfo_training_capture_buffer.sv:61 | 同结构；实际reader参数FIRST=5272、LAST=25959、ADDR_WIDTH=13，合法base至25956。地址0..5171，负数/越界不写。 | 当前实例安全，参数推广需重新核范围。 |
| sfo/first_resampling/sfo_first_pass_descriptor.sv:77 | 与unsigned布尔carry相加使v>>>28变成逻辑右移；:214–216 CHECK独立拒绝m_phase<0、phase_last<m_phase和边界错误。成功描述符两phase均非负，右移与期望floor一致。 | 非负成功域等价；不是通用signed carried_base函数全域等价。 |
| sfo/second_resampling/sfo_second_pass_descriptor.sv:79 | :212–215同样独立拒绝负phase和倒退，成功两端非负。 | 同上；错误路径不能借此告警被改写成合法结果。 |

### 23.2 二十七条WidthTruncate

下表行内编号对应27个实际诊断位置；同一位置若另有unsigned-shift已在23.1计数，不能误认为额外截断。

| 编号/源与行 | 被截位及实际范围依据 | 处置 |
|---|---|---|
| W01 frontend/buffering/fine_local_capture_buffer:62 | 32→10；写入地址0..691，见23.1。 | 丢弃位全0。 |
| W02 frontend/carrier/cfo_phase_increment:52；W10 sfo/initial_estimation/sfo_cfo_phase_increment:50 | U60 magnitude逻辑右移35后恰剩25位，赋U25；余35位另用于RNE，符号另保存。 | 两条均精确，无非零高位丢失。 |
| W03 frontend/carrier/cfo_preamble_rotator:117 | U38 magnitude>>17恰剩21位；RNE进位放入22位，再独立检查18位饱和。 | 精确位提取。 |
| W04/W05 frontend/timing/fine_corr_scheduler:41/42 | 实例固定group0..127、lane0..15、candidate0..256。ref最大2047 fits U11，sample最大2303 fits U12。 | 两条均精确。 |
| W06/W07 frontend/timing/fine_quality_controller:97/116 | bitlength82循环写0..82 fits U7；仅length>63时减63，最大19 fits U6。 | 两条均精确。 |
| W08 sfo/resampling/sfo_farrow_arithmetic:275 | C14/D16/W32生产实例，ca是两个S16之差、绝对值≤65535，乘2^(C−3)=2048后绝对值<2^27；64→S32只去符号扩展。C16/D18/W36支持实例亦满足同一推导。 | 保留全数值，不是饱和/模近似；Farrow其他显式定点截位不由本条自动覆盖。 |
| W09 sfo/buffering/sfo_training_capture_buffer:61 | 32→13；实际地址0..5171，见23.1。 | 丢弃位全0。 |
| W11 sfo/initial_estimation/sfo_initial_fft_pair_extractor:106 | 原FFT bin k∈[0,2047]；active仅1..820或1228..2047，index为k−1→0..819，或k−408→820..1639，fits U11。k=0产生−1截位但active=0，后续:123–135跳过。 | 活跃bin精确；inactive数据不成为观测。 |
| W12 同上:285 | valid_in_half为0..2，四pair各1640，accepted_active_bins≤6560 fits U13；2048第二符号beat总量及sequence检查限制生产。 | 无合法溢出，不把无限坏流当合法域。 |
| W13 sfo_initial_five_sum_accumulator:52；W14 sfo_initial_observation_store:129；W17 sfo_initial_swls_weighted_backend:286 | 三处12→signed11；index0..819映射+1..+820，820..1639映射−820..−1。store输入与seal、五和期望index及divider/meta等值检查约束tag顺序。所有映射在S11的[−1024,1023]内。 | 三条去冗余符号位；不扩展为任意损坏tag数值正确性保证。 |
| W15 sfo_initial_regression_tail:153 | headroom_shift函数形式参数118位，不能只按形参假定其所有输入安全；实际调用:265 numerator≤118位/denominator78位，h=max(0,hn−62,hd−46)≤56。:323–325调用为86位ppm numerator/49位positive denominator，h≤24。 | 所有实际调用fits U6；若未来将118位任意divisor传入，可能需要h=72，该推广不安全。 |
| W16 同上:264 | p02为78位，hquality=max(0,bitlength(p02)−46)≤32 fits U6。 | 精确。 |
| W18 sfo_initial_weight_pack:68 | 两个97位积共同bitlength≤97，shift=max(0,length−45)≤52 fits U6。 | 精确。 |
| W19 sfo/first_resampling/sfo_first_pass_descriptor:143 | 32→26 abs ppm；合法abs≤39321600<2^26；input_error在IDLE握手同拍决定直接HOLD或PREP，非法值即使截位存入ppm_mag也不计算。 | 合法精确、非法受控拒绝。 |
| W20/W21 sfo/residual_estimation/sfo_residual_peak_triplet4:89/110 | 两个索引均9位beat×4+lane0..3，最大2047，fits U11；FILL计数和scan512次限制。 | 两条精确。 |
| W22 sfo/residual_estimation/sfo_residual_power4:39 | 两S16平方各≤2^30，和≤2^31；U33求和赋U32只去必0最高位，最大0x80000000有效。 | 不会丢失负满幅I/Q的功率。 |
| W23 sfo/second_resampling/sfo_second_pass_descriptor:142 | 合法abs≤786432（3ppm×2^18），fits U26；非法descriptor直接HOLD，不进入PREP。 | 合法精确、非法受控拒绝。 |
| W24 cfo/cfo_fft74_quality_v2:36 | int→signed6；LOAD_Z:134明确拒绝S38最小负数−2^37，maximum=0走零信号捷径，故成功0<max<2^37，highest0..36，返回−21..16。 | fits S6；没有漏掉可合法输入的bit37。 |
| W25/W26 cfo/cfo_fft256_core:67 | stage s=0..7，h=2^s，butterfly b=0..127；base=floor(b/h)*2h，offset=b mod h，a最大255−h，baddr最大255。 | 两个9→8地址精确，无访问回绕。 |
| W27 同上:68 | twiddle=(b mod2^s)*2^(7−s)，范围0..128−2^(7−s)≤127。 | 9→7精确。 |

本节W08、W19–23与SFO审查交叉核对；W24–27与CFO审查交叉核对。原始类别中的其余SignConversion、SignCompare、ArithOpMismatch等没有被本节32条代表，仍应按父任务最终诊断分类报告保持真实状态。

### 23.3 一条CaseDefault

`frontend/frontend/sync_frontend_top.sv:100`定义2位enum四状态IDLE、RESET_ESTIMATORS、REPLAY、WAIT_RESULT；:251–283普通时序case全部列出，:189复位到IDLE，所有赋值均来自这四状态。当前硬件二值编码没有未覆盖状态，且处于always_ff不会因无default产生组合锁存。未覆盖X/Z属于四值仿真/未知传播或故障注入边界，本工程没有据此实现SEU自恢复。本条无需为风格新增default改变故障语义。

结论：这32条在当前生产参数、现有有效输入和错误拒绝条件下未发现需要修改RTL的确定功能问题，报告保留其诊断而不称“消除”。该结论不是958条全部无风险、原生厂商展开通过、全数值比较通过或真实时序通过的替代物。
记录时间：2026-09-18 01:52:18 +02:00，Europe/Berlin。
