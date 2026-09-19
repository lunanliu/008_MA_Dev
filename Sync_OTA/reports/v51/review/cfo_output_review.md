# V5.1 CFO 与输出接口独立静态审查

最新生产应用和12个CFO源覆盖见第22节；四份已应用算术代码的等价与最终服务数字见第21节；一般多帧证明结构见第17节，并使用第21节更新后的B/E0/S。第20节保留初始规划，第21节标题中的“尚未应用”是审查时历史状态，现由第22节明确覆盖。

审查范围：Sync_OTA 的 A07 CFO 生产源、实际工程、现有历史综合/CDC报告，以及 Sync_DDR 的结果捕获/写入控制和接线合同。审查人仅写本报告；未修改任何 RTL、DDR 工程或其他文件，未运行仿真、综合、MATLAB 或 EDA 工具。以下周期及容量均为源码静态推导，不是新实验结果。

## 0. 最新用户最终合同：无背压输出（覆盖第7节原候选约束）

用户最新明确：本版Sync_OTA最终输出按无背压设计，后级不通过ready阻塞核心，不在OTA内部建立DDR停顿缓冲；Target VI由用户保证足够容量与吞吐。因此第7节的10/11打包服务、DDR等待和FIFO容量分析仅保留为此前接口背景，不再作为本版核心输出节拍或bank回收条件。

本版选定结构：

1. 现有最终cfo_rotate4之后设置两级固定吞吐输出寄存器，逐级寄存valid、128-bit IQ、frame/generation、beat index、last及需要的错误/取消身份。没有输出ready反馈和基于后级消费的停顿；每级固定一拍。
2. 最终旋转的接收侧按本地连续通路始终可接受设计。数据每拍可发四点，clk150，即有效突发600MS/s；静态帧服务按334080次四点读取及固定RAM/旋转/输出流水开销计算。
3. 不配置最终大FIFO，不为DDR停顿分配OTA内部容量。Target VI必须在每个输出valid周期原子接收四点及相应记录，不得丢弃或延后单独某个边带。接口完成表示最后有效输出记录已经发出；不等于DDR物理写完。
4. bank回收以最后一次读响应已进入安全的本地数据流水、所有在途读响应清零为依据；若实现选择等待最终last发出再退bank，也只增加固定流水尾部。最后RAM读接受、最后rotation输出、第二级接口last必须分别计数/定义，不能拿一个事件冒充另外两个。
5. 旋转约5拍尾部后再加2拍输出寄存，新增固定2/150MHz=13.333ns；两级流水不降低启动间隔。按600MS/s内部最终读出，CFO双bank寿命仍约4.609ms，而不是第7节历史背景里的4.831ms或5.054ms。
6. 用户承担Target VI的持续接收能力和外围缓存，不改变本文对旧DDR捕获内核实际10读+1写的源码事实；二者衔接由外围实现。核心不据DDR_ready停发，也不宣称旧capture控制器本身每拍都能接四点。

本次仅更新设计审查报告；具体代码由父任务唯一开发者实现。


## 1. 源集与边界

Sync_OTA/rtl/sources_a07.f 与 Sync_OTA/Sync_OTA.xpr:136-208,408 使用 ota_cfo_chain_a07、cfo_front2048_window_a07、cfo_estimate74_backend_a07，以及现有 cfo_fft2048_core、cfo_fft256_core、cfo_rotate4、cfo_coordinate_control。XPR:10 器件 xcvu11p-flgb2104-2-e；XPR:1213 综合 top 为 sync_ota_top。

两个 CFO 旋转实例已经存在于 rtl/cfo/ota_cfo_chain_a07.sv:118,190。当前障碍是全局串行调度及外存/单点供数，不是缺少第二个旋转算术核。

该链现行顺序是粗旋转整帧写 DDR、seal、74 窗口、残余估计、最终整帧旋转，见同文件:27-30,227-250。窗口输入在 clk150 每周期仅发送一个复样点，见:142-150,188,233-238。

## 2. CFO 每窗和后端周期

前提：合法正常数据、时钟持续、FFT 输入连续、观测结果及时接收，无取消、复位或外部停顿。

| 环节 | 源码静态周期 | 依据 |
|---|---:|---|
| FFT2048 LOAD | 2048 clk500 | cfo_fft2048_core.sv:147-152 |
| 11 级蝶形 | 11*(1024+7)=11341 clk500 | 同文件:154-172 |
| FFT 输出及预取 | 2051 clk500 | 同文件:175-184 |
| 导频前端尾部与释放 | 9 clk500 | cfo_front2048_window_a07.sv:96-118 |
| 单窗口启动间隔 | 15449 clk500=30.898 us | 上述合计 |
| 74 窗服务总量 | 1143226 clk500=2.286452 ms | 静态计算 |
| phase 后端末观测至结果 | 5272 clk150 | cfo_phase74_core_v2.sv:103-139 |
| quality 后端末观测至结果，最坏正常分支 | 6792 clk150=45.28 us | cfo_fft74_quality_v2.sv:102-154 |
| 两后端结果 join | 另 1 clk150 | cfo_estimate74_backend_a07.sv:73-82 |
| 坐标转换 | 435 拍延迟，436 拍服务；设计预算可取450 clk150 | cfo_coordinate_control.sv:66-130 |
| 单次全帧旋转 | 334080 次四点接受，另约5拍排空及配置 | cfo_rotate4.sv:20-30,55-81 |

quality 的6792拍为 PREPARE 1 + 输入512 + FFT256蝶形5120 + FFT输出512 + 功率扫描512 + MATH 1 + 两次除法各67。phase 路径包含最后一次CORDIC/STORE 25拍、频率除法67拍、74次预测各68拍、中心检查148拍。

旧150MHz逐点供数即使允许每窗预装满32点FIFO，其保守下界仍为：
74*((2048-32)/150MHz + (11341+2051+9)/500MHz) = 2.977908 ms。
这已超过2.67264 ms帧间隔，且未加入DDR事务等待。忽略FIFO预装的名义值约2.993695 ms，不能把后者称为严格下界。

## 3. 保持数学不变的两个窗口供数候选

A：粗旋转输出同时写帧URAM及4槽完整BRAM窗口队列；窗口发布后在500MHz连续串化。4槽IQ有效容量32KiB，128-bit组织约8 RAMB36。优点是读口独立、占用容易证明；代价是窗口复制与两个消费支路的原子握手。

B：粗旋转仅写URAM；写水位到达窗口末地址后发布窗口任务；当前写bank的独立读口预取512个128-bit字，经32/64字packed CDC FIFO在500MHz串化。每帧额外窗口读取37888个128-bit字，占150MHz帧预算9.45%。旧帧最终旋转读取另一bank，因此不争同一bank读口。代价是2拍URAM读延迟、在途信用、FIFO预填及响应身份必须明确。

若已有可靠URAM读信用模块，B省资源并避免双分支复制；否则A更直观。两案都必须保持旧输入扩位和顺序：I16/Q16符号扩位至S26并左移6位，见 ota_cfo_chain_a07.sv:142-145。原FFT各级RNE、饱和、导频映射及求和顺序保持。只增加FIFO不能弥补旧单点150MHz的平均供数瓶颈。

窗口字区间由首字6496、间隔4480、每窗512字定义，最后窗口为[333536,334048)，见 ota_cfo_chain_a07.sv:69-70,204,238。

四点150MHz连续生成时，窗口到达间隔29.866667us，服务30.898us。四个完整槽足够容纳该确定性帧内包络：若直到观测完成才退槽，峰值4；若FFT装载完成即退槽，峰值3。需另计CDC及控制延迟，不能把此数当实测峰值。

首窗完整约46.72us；74观测约2.333172ms完成；后端约2.378452ms产生结果。加450拍坐标预算后，最终读取可约2.381452ms开始。独立两bank、无外阻塞、最终四点150MHz时bank寿命约4.609ms，小于2Tf=5.34528ms。

## 4. 实际资源和现成优化依据

sfo_uram_frame_bank.sv:21-44为共同150MHz、128-bit、335872深度、读延迟2的 xpm_memory_sdpram，MEMORY_PRIMITIVE=ultra。每bank宽深拼接需164 URAM；旧分层综合报告 work/OTA004/synth_a05/synth_utilization_hierarchical.txt:21572-21594 也实际显示164。

CFO双bank新增约328 URAM：旧552增至约880/960。若原SFO输出ring的32 URAM转至BRAM，约848/960。仅是规划预算，不能保证新布局通过。

隐藏的实际瓶颈：旧分层报告:45中 cfo_fft256_core 是38673 LUT、10573 FF、0 BRAM，尽管源码:22写 ram_style=block。源码:95,101,113,123对同一数组描述了装载写、双蝶形读写及输出读。应比较明确双端口RAM复用与parity双bank结构；两者可保持蝶形算术、舍入和原状态周期。这属于有现有综合证据的存储结构问题，不必更换FFT算法。FFT2048旧报告:78为734 LUT、3 RAMB36+2 RAMB18、4 DSP。

## 5. 跨帧参数、身份和取消

当前全局 frame_id/generation/step1/step2/origin/coarse_frequency/residual_frequency 仅对单帧安全，见 ota_cfo_chain_a07.sv:41-44,216-219。最终输入记录:189仍取全局帧号；直接放开context_ready会把旧帧数据贴新帧身份。

每CFO bank应保留不可覆盖上下文、写水位、sealed/失败及估计结果；粗旋转、窗口任务、最终旋转分别锁存身份。共享坐标转换器足够，但请求和结果都需frame/generation/bank/epoch及用途，不能读会被下一帧覆盖的全局参数。

cfo_estimator_link_a06.sv:61-103,152-154只支持一帧观测在途并在结果消费后归还信用。可保留此结构，但结果须及时写入按帧记录，不得等旧全局FINAL阶段才消费。

ota_cfo_chain_a07.sv:33-40的取消会冲刷整条CFO跨域计算。多帧后需明确全流水冲刷和epoch失效，或另行设计局部取消/排空；不能默认取消一帧不会影响其他在途帧。

## 6. 历史时序和CDC证据

reports/OTA004/A06R3_ASTRA_REVIEW_ZH.md:28：125MHz WNS +2.410ns；150MHz -2.358ns/2240失败端点；500MHz -1.279ns/347失败端点。

A06R3_OFFLINE_EVIDENCE_REVIEW_R2.json:3600-3608：CFO频率结果寄存器到SFO输出header RAM EN，-2.358ns。:3888-3897：FFT输出索引到系数ROM EN，-1.279ns。:3504-3513：quality peak_bin到divider numerator为+1.059ns，不能误报成失败。

A07增加的结果寄存与系数地址流水应保留，但没有新版通过证据。审查文档:11的182条CDC Warning仍OPEN。ota_async_fifo_a06.sv:15-41的同步复位完成握手应保留；每帧不使用reset作分隔。

## 7. 历史接口背景：现有Sync_DDR的150MHz/1280-bit写入（不再约束核心输出）

本节仅只读核对 Sync_DDR，不授权或修改其代码。最新无背压输出合同见第0节；下述ready接法、容量与服务限制描述旧DDR外围，不能重新引入本版OTA输出ready或大FIFO。

ddr_capture_ctrl.vhd:53-88只实例化ddr_upload_ctrl，未增加寄存器或握手延迟。其端口没有IQ数据总线，控制40-U32 Pack_Array留在LabVIEW；不能把该文件当成已经实现1280-bit数据打包的完整RTL。

DDR_WIDTH_BITS=1280时，每DDR逻辑元素40个U32，每次结果FIFO成功读4个U32，共10次读取。每个U32是一复样点原始I16/Q16位模式。结果捕获要求已知N_out>0且4对齐，M_out=ceil(N_out/40)，实际分配C_out>=M_out。参数在命令接受时锁存，见ddr_upload_ctrl.vhd:59-60,87-90,196-205。

### 7.1 四点ready/accept的精确关系

源码 ddr_upload_ctrl.vhd:107-115：

- read_enable = 非reset、run_enable、非abort、LOADING、dram_ready、pending=0、loaded<samples。
- read_fire = read_enable AND fifo_output_valid。
- write_fire = 非reset、run_enable、非abort、LOADING、dram_ready、pending=1、ddr_write_ready_now。
- fifo_read_enable就是read_enable；ddr_write_valid就是write_fire，见:117-123。这里的write_valid是成功提交脉冲，不是必须独立保持的普通AXI valid。

Sync输出端的Ready来自结果FIFO的写端本地许可，绝不能接capture.result_fifo_read_enable。按当前项目接线合同，NI FIFO.Write.Ready for Input承诺下一拍，需在Sync所在域经一次Feedback(False)形成ResultReady；ResultReady同时接Sync.Ready及FIFO.Write.Input Valid = Sync.Valid AND ResultReady。见Sync_DDR/docs/tutorial/LABVIEW_FOUR_STAGE_WIRING_ZH.md:37-45。OTA不能再无条件延迟一次ready。若实际NI节点合同是同拍ready，必须按实际接口适配，不能机械套一次反馈；本次仅确认本地文档合同，未检查远端NI Context Help。

DDR写侧的NI Ready for Input也由LabVIEW恰好反馈一次形成ddr_write_ready_now，源码:4-7及接线文档:65。同源同拍CLIP/SCTL不得再添加额外同步寄存器；否则既要调整数据/控制对齐，也要明确在途容量，不能将其简单当多等一拍。

本地普通ready/valid输出需要保持data/last/tag直到接受；FIFO只收到成功接受的完整四点记录。现行NI结果FIFO只存四U32，不自动保存frame/last；帧边界、N_out和Tag必须由原子结果描述符/本地计数维护，不能把元数据塞入IQ或凭Last私自缩短N_out。

### 7.2 10次读取+1次提交何时成立

| 接收/提交周期 | pending旧值 | read_enable | 作用 |
|---|---:|---:|---|
| R0..R8 | 0 | 1 | 各接受四点，pack_offset依次0,4,..,32 |
| R9 | 0 | 1 | 接受最后四点，pack_offset=36，边沿将pending置1 |
| W | 1 | 0 | ready_now=1时提交完整旧Pack_Array，清零下一拍数组，地址加1 |
| 下一R0 | 0 | 1 | 接收下一块首四点 |

依据 ddr_upload_ctrl.vhd:118-123,243-256。pending决定接收/提交互斥，W拍不能同时接第11个四点字。ready_now=0时重复等待W，数组、地址和pending保持。提交拍Memory消费旧Pack_Array，pack_clear只更新下一拍数组；接线文档:49-67要求如此。

11拍成立需要：配置已完成、FIFO每个R拍均有有效四点、run_enable始终1、dram_ready始终1、无abort/reset、首个W拍的ddr_write_ready_now已为1，以及LabVIEW数据与这些控制同拍。NI写物理延迟可以重叠，只要接口在W拍接受；不能把物理写延迟逐次加到11拍，也不能因请求已接受就宣称物理写完成。

注意接线文档:54,59使用Read.Output Valid直接驱动数组更新，所依赖的是NI“成功读出”脉冲语义。若替换为普通FWFT valid且stall期间持续为1，必须使用valid AND read_enable更新；否则pending等待DDR时可能覆盖尚待提交的尾四点。按当前选定接口，只连接现有NI FIFO写端，不绕过此合同。

### 7.3 服务公式、命令开销与500MS/s预算

令N为合法输出样点数，B=N/4，M=ceil(N/40)；在一个成功会话中：
C_loading = B + M + E + W + P。
E为请求读取但FIFO无有效四点的周期，W为pending且DDR当前不接受的额外等待，P为run暂停。正常LOADING且dram_ready保持有效时三类按源码:153-167计数互斥；abort/DRAM失效会进入FAULT，不是可无限追加的普通服务等待。

总服务再加不能与其他帧重叠的控制/会话空隙H：
C_total = B + M + E + W + P + H；
R_eff = 150e6*N/C_total。

固定宽度完整块的无限长理想上界为40*150/11=545.454545 MS/s，约2.181818 GB/s。不是600MS/s，也不是已测持续DDR速率。

对名义同步帧N=1336320：
B=334080，M=33408；
C_ideal=367488 clk150=2.44992ms；
Tf预算400896 clk150=2.67264ms；
额外等待/空隙总额度=33408拍=222.72us。

因此稳定500MS/s必须满足每帧长期平均 E+W+P+H <=33408，并用额外突发上界约束有限缓存。等价于每40点平均附加不超过1拍；严格超过500MS/s需要严格小于1拍。该额度同时支付DDR仲裁/刷新等待、FIFO数据空隙和控制间隙，不能重复分配。

命令精确时序：在边沿0接受capture命令，边沿1 CONFIG_CALC，边沿2 CONFIG_CHECK并进入LOADING，最早边沿3首次read_fire。连续理想数据D=B+M拍时最后write_fire在边沿D+2。上一会话末写边沿L进入DONE，最早L+1接受新命令、L+2计算、L+3检查、L+4首读；若每帧独立命令，两个首读之间最少D+3拍，即每帧控制开销H至少3拍，且不含Target会话许可/反馈等待。预先启动捕获并确认配置就绪，可将首次配置延迟放到数据产生前；整段多帧合为一次已知N_out会话可避免逐帧这3拍，但需实际DDR容量和结果描述符覆盖该多帧段。

ddr_upload_ctrl.vhd:3、ddr_capture_ctrl.vhd:8明确done仅表示最后写请求接受。WriteVisible和旧结果处理完成才能重用结果区；这是额外会话条件，不能从done推导。每次新命令地址都清零(:199-200)，该核没有base_address或循环结果区。Sync_DDR/docs/DDR_FOUR_STAGE_DESIGN_ZH.md:32,42-44及接线文档:35,101-109规定独占结果区及旧事务清理。因此现有外围支持按已知长度捕获段；无限连续多帧输出还需要外围分配不覆盖旧结果的会话/存储策略，OTA内部多帧吞吐并不能替外围补齐该策略。

若每次DDR提交增加固定L个额外pending等待周期，理想满块服务变为M*(11+L)。L=1正好只达500MS/s，任何额外空隙使其低于500；L>=2则确定不满足。本合同所需一次NI ready反馈不是额外每块L=1：若上一拍已有有效承诺，首个W拍仍可直接提交。额外同步寄存若没有匹配的信用/数据保持可能先破坏协议，不能只折算性能扣减。

### 7.4 历史有背压候选的容量计算（本版不采用）

545.45MS/s理想DDR捕获消费者面对600MS/s连续旋转突发时会积压。单名义帧旋转持续334080个clk150；按10读/11拍服务，理想相位积压30370个128-bit字，考虑相位上界取30371字=474.546875KiB。512KiB有效IQ FIFO理论上可以覆盖这一个无额外等待的确定性突发，但仍须留在途、控制和已有占用；16KiB外围结果FIFO不够让整个600MS/s帧完全不停。

如果允许的平均额外等待达到每40点1拍，服务只有500MS/s，600MS/s单帧突发积压可达55680字=870KiB。此时128/256/512KiB FIFO均不能保证整帧不背压；应允许局部回压并据此延长CFO最终bank持有时间。

仅16KiB结果FIFO有4096点：完全停服时，在500MS/s输入下仅8.192us容量，在600MS/s突发下仅6.826667us，且还须扣掉当前占用及在途量。正确条件为free_words >= 已承诺在途字 + 停服期间新增字，不能盲目把ready寄存一拍。

按前述CFO估计2.378452ms、坐标450拍：
- 600MS/s无阻塞最终读取：bank寿命约4.609ms。
- 理想545.45MS/s捕获限制、保守不借输出FIFO提前释放：约4.831372ms，距2Tf尚约0.513908ms。
- 500MS/s捕获限制：约5.054092ms，距2Tf约0.291188ms。
这些都依赖有界服务和正确调度；平均速率本身不限制任意长停顿。小FIFO可提前转移部分所有权，但只有数据已进入安全的本地/外围存储后才能退bank读引用。

## 8. 结论的可信范围

静态核对能确认源码状态依赖、每帧周期公式、条件性容量上界、位宽/舍入顺序和所需所有权。不能据此宣称新BRAM/URAM推断、实际150/500MHz布线时序、CDC实现约束、NI节点远端语义、DDR持续带宽、板级运行或逐样点一致性已通过。

现有报告仍保留历史身份。本次无新数值仿真、资源综合、布局布线或持续吞吐实验结果。用户批准后应采用必要且有明确验收目的的验证，不能把反复试跑当设计推导的替代。

## 9. 新三队列 ota_sfo_context_join 的独立集成审查

审查对象是V5.1当前修改的 rtl/control/ota_sfo_context_join.sv（WAIT_HEADS/CHECK_IDENTITY/HOLD_RESULT，三组深度32的sfo_sync_fifo）。只读查看真实A07顶层、capture控制器、两个重采样器及输出buffer，未运行仿真。

### 9.1 高优先级：A07的cfo_base没有随metadata排队

P1，多帧启用前必须关闭：sync_ota_top_a07.sv:160-179在每次meta_mv&&meta_mr时覆盖单寄存cfo_base，却把它实时拼在当前joined_context前。新join的meta_ready只看metadata_queue容量，不再等当前帧context交给CFO。若第k帧joined_context正在等待context_ready，而第k+1帧metadata到达，则完整278位context的base变成k+1的地址；此时有效载荷还可能在valid高、ready低期间变化，最后造成第k帧使用错误DDR区。

修复候选A：将base与metadata一起原子排队并随当前context保持，可在外部建立同消费事件的base FIFO，或把join接口明确扩展。修复候选B：新的纯片内CFO/top彻底去掉DDR base旁路，改用bank/context身份。不要仅给现有单寄存增加一拍，也不能只用新帧号和旧base凑记录。

旧capture_controller_a07.sv:53,69,148-153仍只有一个会话，meta仅在PUBLISH产生，下一start须当前流程结束，因此当前A07单帧路径暂时遮蔽该问题；这不是当前单帧必现回归，却是复用此caller做多帧的确定性错误。单改join不能称整链多帧已连通。

### 9.2 正确项：布局和普通ready/valid

214位输出与旧合同一致：
frame[213:182]、generation[181:150]、step1[149:118]、step2[117:86]、raw_origin[85:32]、coarse_hz_q8[31:0]。

held_meta的frame/generation是[149:86]，coarse是[85:54]，origin是[53:0]；held_first/second身份为[95:32]，step为[31:0]。CHECK_IDENTITY里的拼接正确，没有发现符号位/宽度丢失。

三FIFO在take时共同弹出并锁存一套头部，下一拍检查身份和非零step，再寄存m_context。HOLD_RESULT期间不会弹下一套，也不更新m_context，普通stall时稳定；完成后回WAIT_HEADS，不会重复发同一记录。ready取各自本地FIFO空间，与下游m_ready没有组合通路。sfo_sync_fifo.sv:22-24已把XPM reset_busy纳入ready/valid，忽略其单独reset_busy输出不代表丢失该保护。深度32加一个held/result槽最多可积存33组完整关联，不能把这当实际可在途帧数预算。

### 9.3 E2启动语义已经改变

旧join规定second_ready=m_valid&&m_ready，即第二遍重采样启动时CFO同拍获得完整context。新join的second_ready只表示second_queue能接收记录，E2可在CFO尚未取得该帧context时启动。sfo_second_resampler.sv:90-91,155,234把context_ready用于engine配置/LAUNCH，故此变化真实影响数据开始时间，并非单纯多加输出延迟。

对当前A07单帧：CFO从接收context到配置粗旋转还要约436拍坐标转换；SFO输出buffer容量65536字且合法回压，见sfo_output_buffer.sv:4-8,41,49及two_pass_transport.sv:690-715。因此早开始本身不必导致初始数据丢失；数据保存在输出ring直到CFO ready。尚未借此运行新用例。

对V5.1多帧：是否允许E2启动必须与CFO bank租约、ring剩余容量及响应在途量一致；metadata FIFO容量不是CFO帧bank准入。若CFO仍是旧单帧串行链，早启动只会更早填满ring并阻塞E2，不能满足持续吞吐。A07把PROCESSING_LIMIT_CYCLES设为536870912，见top:143-145，不能把它的宽松超时当400896周期帧预算通过。若V5.1恢复严格周期预算，E2被输出等待消耗的周期也要支付。

### 9.4 外部诊断与完成记录仍是单会话设计

sync_ota_top_a07.sv:102在每次metadata握手清held错误；:166同时清held_first_step/held_second_step，随后由任意E1/E2握手覆盖。多帧metadata提前入队时会清除旧帧未完成的结果/诊断，两个step也可能来自不同帧。这些端口目前是诊断，不改变join已保存的算术参数，但不能继续作为一条原子帧结果输出。

建议结果/诊断按frame/generation登记，或在有明确身份的完成事件统一快照。现有completion通道仅8位error，见top:188-198，没有frame/generation；新多帧调度必须同步更新，而不能靠“第几个到达”在取消/错误后猜身份。

### 9.5 错误、取消和顺序合同

当前实现遇到41/42身份或step错误、43 FIFO错误、44非法状态时锁死，active撤销三输入ready及m_valid，只能通过rst/cancel恢复。其语义是整个join队列全局中毒/冲刷，不是跳过一帧继续。正常满FIFO只会回压，不是error。

身份检查被推迟到三队列都有头部：如果一条流丢了记录而另两条尚未齐，不会立刻报错；齐后错位会报41/42。该模块没有缺记录超时，调用者须保证三路各帧同序、恰好一次，或以全局故障/取消结束。现行SFO发布与残余结果FIFO顺序能作为当前顺序依据；后续若采用可乱序的窗口/估计服务，须先重排，不能只复用这三个FIFO。

cancel高时同步复位三个FIFO、held和输出并清error，同时组合撤销ready/valid。新系统必须让相关生产者、消费者和在途数据在同一恢复协议/epoch中失效；只复位join而保留生产者旧valid，会在恢复后把旧记录重新入队。原A07的取消会同时作用SFO/CFO，V5.1改造后需重新确认该连通性。

如果FIFO错误在输出HOLD期间出现，新active会撤销尚未被消费的m_valid。这可作为明确的全局故障取消例外，但不能同时声称“除reset外所有stall期间valid都必须保持”；文档要把cancel/致命error与普通背压区分。

结论：局部布局、寄存保持及普通队列握手未发现问题；A07外部base/诊断/8位completion和旧CFO串行调度未具备新多帧语义。必须在新的集成顶层中一起处理，才能将join从准备性结构改动认定为多帧连通。

## 10. 无背压输出在当前A07里的完整耦合清单

当前实际路径：

wrapper.m_ready -> core_m_ready -> sync_ota_top.m_ready -> ota_cfo_chain.m_ready -> second_rotation.m_ready -> cfo_rotate4.advance -> r2_sr -> memory_mr -> ota_frame_store的OUTPUT_WORD消费/下一DDR读请求。

精确位置：
- wrapper/sync_ota_wrapper.vhd:60-65,168-170,245-247,330-335,434-436：外部ready和225位记录透明连接，无输出寄存器。
- rtl/control/sync_ota_top_a07.sv:25,177-180：ready原样转交CFO。
- rtl/cfo/ota_cfo_chain_a07.sv:195：m_ready进入第二旋转。
- cfo_rotate4.sv:26-29,59-81：末级满且m_ready低时整个5级数据/相位管线不advance，s_ready随之低。
- ota_cfo_chain_a07.sv:188,194：最终存储回读随r2_sr停止；ota_frame_store.sv:83-87等待OUTPUT_WORD消费后才发下一次DDR读。
- ota_cfo_chain_a07.sv:214：最终拍数/饱和计数按m_valid&&m_ready更新；:250：最后输出握手决定退出FINAL_DRAIN；:252：done_ready另行影响下一帧接收。
- top_a07.sv:188-199：done先写8位completion FIFO再确认。此通道满会影响后续帧准入，虽不是逐样点ready，仍是帧间服务依赖。

需要特别区分：
1. OTA当前没有最终结果DDR写回实例。top:48-57的DDR桥只接原始raw store和CFO粗补偿coarse_store；CFO最终输出直接外送。取消最终m_ready不自动去掉这两处中间DDR访问。
2. sfo_output_buffer是E2到CFO之间的65536字URAM中间ring，见two_pass_transport:690-715，不是最终输出DDR停顿FIFO。去最终背压不能只因名称output把它删除。
3. CFO两项入口记录、FFT窗口FIFO、观测FIFO、参数FIFO及完成FIFO都是内部容量/所有权边界，不应一概tie-ready=1。用户无背压合同只约束最终IQ输出。

### 10.1 两个接口迁移候选

| 候选 | 实施 | 优点 | 必须处理的边界 |
|---|---|---|---|
| 保留兼容m_ready端口并在核心内忽略/tie有效消费为1 | A07型top/wrapper形式可先保留，接CFO/第二旋转的有效ready由内部常1决定；文档注明外部m_ready已无功能 | 少量旧接线可继续打开 | 不能只在远端接1而让核心逻辑仍依赖端口；不能默默保留“可反压”的假合同。输出计数/完成也须改按第二级valid |
| 新生产top/wrapper移除m_ready | 新顶层仅输出m_valid和记录；第二旋转内部m_ready=1，外围每个valid拍接收 | 接口直接表达用户最终合同；不会误接DDR_ready | 必须同步改SV端口、VHDL组件声明/端口映射、XPR明确top/source set和文档；旧接口保持历史身份 |

本轮建议最终采用第二项。第一项可作为临时兼容层，但不能宣称旧m_ready仍有握手意义。保留输入s_ready、context_ready和内部存储信用，不受该选择影响。

### 10.2 固定两级输出寄存的安全规则

- 将第二旋转输出记录225位及m_saturation 8位一同经过两级寄存，valid逐级同拍推进。若epoch/error/cancel身份另有位，也作为相同记录推进。
- 每周期无条件推进valid，数据可只在对应valid时更新；不得使用外部ready作CE，也不得在valid空洞中改变拍序/相位。
- 旋转内部正常输出始终可消费。复位/全局取消时清两级valid；数据本体无需为了功能清零。
- 正常m_valid直接来自第二级寄存valid。不能继续使用旧FINAL_STREAM/FINAL_DRAIN状态掩码而在r2最后一拍提前转RELEASE，否则会丢掉固定两级尾部。
- 最终输出拍计数、final_last完成、与用户可见输出对应的饱和计数均基于第二级valid。若饱和在旋转输出处计数，必须明确它是内部旋转计数，并在帧结果发布前等待同帧最后一拍；不能把未延迟sat2配第二级m_record。
- 先定义三个独立事件：最后RAM读响应安全接受；最后旋转输出；第二级接口last发出。最简单的bank释放是等待第三事件；只多固定几拍，却避免旧帧计数/身份被新租约覆盖。
- 完成记录须保证有预留空间。可以在frame admission时预留completion条目，接口last时无条件写入，再独立退bank。不能在已经承诺无背压的最后输出拍临时等待Host done_ready。
- 中途致命错误可能已发出部分有效IQ，无法撤回；通过带身份的失败完成记录使外围弃用该帧。取消优先级须与所有流水valid同步，不能只关data而保留last或反之。

## 11. dualbank + 8window CFO的可实现结构清单

本节给父任务唯一RTL作者的结构输入，不声称已实现。

### 11.1 复用实例及端口

1. 两份sfo_uram_frame_bank：BEAT_WIDTH=128、DEPTH_BEATS=335872、ADDR_WIDTH=19；clk/rst=150MHz本地域；wr_en/wr_addr/wr_data只由粗旋转实际接受事件驱动；rd_en/rd_addr为最终读调度；rd_data按READ_LATENCY_B=2使用。
2. 保留first_rotation与second_rotation两份cfo_rotate4：cfg_valid/ready、cfg_frame/generation/phase0/step/sample_count=1336320；输入s_valid/ready/s_record[224:0]；输出m_valid/m_record/m_saturation、fault/first_error。第二份m_ready固定1；第一份m_ready由本地bank写入与当前窗口槽接收容量决定。
3. 保留cfo_coordinate_control：s_frame/generation/residual/frequency_code/step1_q28/step2_q28/raw_origin_q28；结果m_frame/generation/residual/ok/error/step/phase0。一次请求接受时另存owner={bank,kind,epoch,frame,generation}，直到结果安全写入对应参数寄存。请求不能从可变全局current_frame组合取得。
4. 保留cfo_front2048_window A07：500MHz下输入s_frame/generation/window/index/last/i/q；输出z_i/z_q、pilot_count、fft_saturations、error。底层FFT2048数学和系数不动。
5. 保留cfo_estimator_link A06：接front输出；clk_fast500/clk_slow150；m_backend_word[498:0]与m_link_error/m_front_error。结果m_ready改为匹配bank的结果槽可接收，不能再绑旧全局stage==ESTIMATE。其一帧观测信用在结果被消费后归还，可继续使用。
6. 复用ota_async_fifo的完成初始化握手传窗口descriptor与slot-return记录。现封装深度须满足其XPM阈值，取32即可，不能把FIFO深度直接写8而保留PROG_*阈值。
7. 新增8槽窗口BRAM及固定500MHz串化器；新增per-bank context/status与三项局部调度状态；新增最终两级输出寄存。不要复用ota_frame_store作为片内bank，它实现的是DDR事务协议和单请求等待。

### 11.2 8窗口的具体存储及CDC

容量8*512*128=524288 bit=64KiB有效IQ，按128-bit组织约16 RAMB36。数据和描述符分离，避免每个四点字重复frame/gen标签。

建议窗口RAM为XPM block SDPRAM：写端150MHz、读端500MHz、independent_clock、128-bit写/128-bit读、地址12位{slot[2:0],word[8:0]}、读延迟2；depth=4096。这里不能复用common_clock UltraRAM封装跨域。槽所有权确保两域不同时读写同一slot，不能仅依赖RAM碰撞模式。

写域维护8位free bitmap，先取得槽再开始该窗口。窗口写第511字成功后才发布descriptor；header至少有frame32、generation32、bank1、slot3、window7，共75位；若系统有epoch32，则107位。窗口长度固定，不必在每拍存index/last。

descriptor跨域FIFO按窗口顺序发布。500MHz读域锁存一个header，按word0..511预取，并用当前/下一128-bit字寄存器及在途计数串化。每个word依次送lane0..3，完整index={word_index[8:0],lane[1:0]}；last只在index2047。样点复用旧S26符号扩位左移6位。RAM读2拍和四lane消费周期需要明确双字预取，不能每word“读请求->等2拍->读4点->再请求”，否则人为增加窗LOAD空拍。

front.s_ready只在FFT LOAD时高。descriptor可提前锁存，但串化样点及index仅在s_valid&&s_ready时推进。next-word请求使用本地信用，不以不断变化的FIFO输出直接选择地址。

当窗口最后样点被FFT接受且该窗口所有RAM响应已安全进入本地寄存、无残余在途请求后，才返回slot credit；也可以直到该窗口观测完成后退槽，结构更保守。return记录含slot与epoch，另一个CDC FIFO从500回150。发/收两侧同时事件使用统一next bitmap/count表达式，避免“归还”和“分配”两个非阻塞赋值互相覆盖。不要把3位binary slot逐位同步当原子消息。

现有静态正常包络峰值4槽（保守退槽），8槽提供结构余量，不意味着可容忍无限FFT/后端暂停。新增预取/发布开销必须计入15,449拍基准之外，仍须保留每帧服务上界。

### 11.3 按职责划分状态，避免恢复全局串行长FSM

每bank至少存：allocated/epoch/frame/generation、214位输入context、粗参数valid/phase0/step、残余结果valid/frequency/quality/error、残余参数valid/phase0/step、written_count、sealed、failed、窗口数、各级饱和/输出计数、admission序号。

bank所有权可采用FREE/FILL/SEALED/FINAL_READ/FINAL_DRAIN，估计完成作为独立标志，不能把整个系统只放在一个INGEST/ESTIMATE/FINAL状态。最大并行图是bank A的旧帧FINAL_READ与bank B的当前帧FILL+窗口估计同时进行。

写侧FSM：
- W_IDLE：仅当有FREE bank、输入context有效、必要结果/记录信用已预留时接受context，原子锁存bank lease和214位context。与外部DDR base无关。
- W_WAIT_COARSE：请求/等待本bank粗坐标参数；两记录入口弹性队列可吸收短控制延迟，s_ready只反映本地容量。
- W_CONFIG：旋转配置真实握手后进入W_FILL。
- W_FILL：每个粗旋转接受字只写一次URAM；检查frame/gen、beat0..334079和last。窗口范围6496+4480*w至+511，符合窗口时同一接受字也写BRAM。窗口起点前准备槽和地址，避免当前r1_record宽比较直接形成长ready反馈。
- W_SEAL：仅在正确last接受、written_count精确334080且无写/窗口错误后置sealed并退出writer；估计不必等seal才运行。
- 所有窗口出错都标记该bank失败；不能继续把局部观测当完整帧成功发布。

窗口服务FSM：
- 所有descriptor顺序为frame admission顺序、window0..73；不在同一estimator_link中交织两帧窗口。
- 空闲等待descriptor、装载/串化、归还槽。front及link可以正常局部背压。
- backend结果匹配唯一非FREE bank的frame/gen，并核对epoch/lease没有被重用；比对498位结果中的frame/gen、error、estimate_valid和link/front error。只匹配成功后写bank结果槽。
- 结果可早于sealed到达，但最终启动必须两者同时成立；若写帧后续失败，已有估计只保留诊断身份。

坐标调度：
- 两个请求源是writer的COARSE和oldest eligible bank的RESIDUAL，数据记录保持至接受；共享核owner必须锁存。
- 公平仲裁，最多等待一个436拍同类转换；不因粗输入连续而饿死final配置。
- 结果先进入对应bank参数寄存，ready由该寄存空间决定，不让第二旋转cfg_ready组合穿透整个算术控制。
- 旋转各自只读取自己的配置寄存；first和second不能共用会被下一帧覆盖的phase0/step输出信号。

最终读取FSM：
- F_IDLE：按admission顺序挑sealed&&estimate_ok&&residual_parameters_valid且未failed的bank，锁存全部身份/参数，配置second_rotation。
- F_READ：cfg握手完成后每拍发一个URAM读，index0..334079；用2拍valid/index/last/bank pipeline对齐rd_data。正常第二旋转s_ready在该帧整个正确输入区间保持1；若出现不符合预期的ready低或身份故障，按明确fatal流程取消，不得静默丢RAM响应。
- F_DRAIN：最后一次RAM响应后停止读，排空约5拍旋转及固定2级输出；两级输出没有外部ready。
- F_COMPLETE：第二级last有效时记录实际输出完成，并写有预留容量的完成记录；同帧计数/结果完整保存后bank变FREE。只需固定控制间隔。
- 提前按最后RAM响应退bank也是候选，但必须将所有旧frame统计/结果另存，避免新租约覆盖；首轮推荐等待接口last以减少竞态。

### 11.4 必须定义的同时事件和内部不变量

- free同拍allocate、最后窗口字同拍descriptor发布、credit归还同拍分配、结果同拍seal、最终last同拍完成记录及新context到达。
- 同bank禁止FILL和FINAL_READ，两个bank可分别读写；BRAM slot在完整信用归还前不可重用。
- first/coarse接收数=bank written_count；每帧窗口complete/publish=74；最终issued=returned=rotation accepted=interface emitted=334080（各事件完成后比对，过程中允许流水差）。
- 第二级last必须伴随beat334079、正确frame/gen；结果队列身份与最后IQ帧一致。
- reset/cancel采用全流水屏障、两域复位完成与epoch统一失效；不得新帧已经启动时为清旧错误单独复位FFT/observation FIFO。
- 外部m_ready、DDRready和Host轮询不出现在F_READ/F_DRAIN数据使能逻辑中。
- 先在源码和结构表中核对这些条件；本报告未为它们运行仿真或形式工具。

## 12. A07 实际输出去背压改动复核（2026-09-17，独立静态审查）

### 12.1 复核对象和限定结论

复核当前 git diff 中的 `rtl/cfo/ota_cfo_chain_a07.sv` 与 `rtl/control/sync_ota_top_a07.sv`，同时只读核对实际依赖 `Sync_CFO/rtl/cfo_rotate4.sv` 和 VHDL wrapper。未修改 RTL，未运行仿真、综合或任何 EDA。

当前源码 SHA256：
- `ota_cfo_chain_a07.sv`：E4F8D3395361ECB763873ED3D66363FA58CFD787877C277F652FA2BBD78A470B。
- `sync_ota_top_a07.sv`：89F6AF1AA01FD3B23F4F55B359C202107B9080F4799DC2CEA2A6CAF9F8C4C2C6。

本次有限差异的静态复核未发现新增的尾拍丢失、重复计数、饱和位错拍或完成提前问题。此结论不覆盖尚未实现的双 bank/八窗口整合，不等同于整链功能、持续吞吐或实现时序通过；第 9 节已有 cfo_base 与多帧 caller 所有权风险仍未由输出改动解决。

### 12.2 数据、尾拍与完成逐拍推导

- CFO 链第 108–122 行新增两个 225 位事务寄存器、两个 8 位饱和寄存器及两位 valid。第 116–118 行每拍推进 valid，数据分别由对应前级 valid 使能；气泡不复制事务，无下游 ready 使能。完整 225 位记录保持 `{frame32,generation32,beat32,last1,IQ128}`，last 仍在 bit128。
- 第 208–215 行 second_rotation 的 m_ready 固定为 1；实际旋转核第 26 行 `advance=!valid_pipe[4]||m_ready` 因而恒可前进。其 tag/data/saturation 在同一内部输出级对齐，新增级未改变数值运算、舍入或饱和函数。
- 令边沿 E 前第二旋转输出为本帧尾拍且 r2_valid=1：边沿 E 将该拍及 sat8 采入第一级；边沿 E+1 将其采入第二级；从 E+1 后至 E+2 前该拍对外有效；边沿 E+2 为无背压接口接受尾拍并计数的边沿。第 268 行只在此时观察 `m_valid && m_record[128]` 并进入 RELEASE；E+3 才进入 COMPLETE。
- 最后一个 memory beat 被旋转接收后，第 267 行进入 FINAL_DRAIN；第 111 行 final_active 仍覆盖 FINAL_DRAIN，因此旋转在途拍和两个新增寄存器都能排空。不会因离开 FINAL_STREAM 而吞掉新增两级中的尾拍。
- 旋转核第 32、63、67 行已校验 beat/last 和身份，并在接受最后输入后撤销 active；因此正常帧尾拍之后不会再注入同帧额外拍。完成后 output_valid 自然移出，不会在 COMPLETE 重复发布尾拍。

### 12.3 取消、故障与统计

- 第 113–114 行在 reset、compute_clear 或 fail 时清两个有效位；compute_clear 包含 cancel150 与 CANCEL_DRAIN。第 121 行同周期屏蔽 reset/fail/cancel 下的 m_valid。取消时不要求保留或补发尚未对外接受的在途拍，符合整帧取消的已有定义。
- 主状态逻辑第 224–229 行取消/失败分支优先于第 232 行正常输出计数；被掩码的拍既不被接口认为有效，也不增加最终计数。已经在先前边沿对外接受的拍保留其累计值，取消不会伪造整帧成功。
- 第 232 行改为按 m_valid 累计 final_beats，饱和计数使用 output_sat1，而非旋转当前 sat2；因此气泡、两个新增寄存级和尾拍的计数含义一致。pop8 最大值为 8，全帧最大 2,672,640 次分量饱和，不溢出 32 位计数器。
- output_record 和 output_sat 不必复位：reset 清 valid 后不存在可观察有效的未初始化记录；首个有效事务按两个寄存级完整覆盖记录与饱和字段。
- top 第 191–200 行 completion FIFO 仍可能延后 done_ready 和下一帧准入，但本帧 IQ 尾拍已经在 COMPLETE 之前发出。新输出链不存在通过 completion_ready 回压已启动的最终读出；未来多帧调度仍需按第 11 节预留完成记录容量。

### 12.4 兼容端口与剩余证据边界

- top 第 25 行明确每个 m_valid 都已转移，第 181 行传给 CFO 的 m_ready 固定为 1；CFO 本身第 213 行也固定第二旋转 m_ready。外部兼容 m_ready 的 0/1 不再进入最终数据使能、计数或完成条件。
- VHDL wrapper 第 61、331、435 行仍保留并转接名为 m_ready 的端口，实际落到已忽略的 top 端口。接口行为正确，但最终手工接线指南及 wrapper 注释应同步写明“兼容输入，忽略；每个 m_valid 必须接收”，避免调用方沿用旧 ready/valid 含义。
- 数据和标签已有两级寄存器，但第 121 行 m_valid 仍组合 AND rst150、fail 与 cancel150。它不是完全由单一输出触发器直接驱动的引脚路径；尤其 fail 来源还包含后端身份/错误比较。此设计是否满足 150 MHz 接收时序，不能仅凭增加两级数据寄存器声称通过，须在获授权后的真实器件时序报告中检查。
- 此次改变消除了最终消费端的背压路径；它没有消除 A07 外部 DDR replay 本身的供数空隙，也没有把原全帧串行调度改成并行。不得将“外部 ready 已无作用”换成“当前整链已持续达到 600 MS/s 或平均 500 MS/s”的结论。
## 13. 八窗口 packed FIFO 与 500 MHz 串化器审查

### 13.1 版本与选择

只读审查 `rtl/buffer/ota_cfo_window_queue.sv`。初版以 `buffered_words150<=3584` 预留窗口；评审期间父 Agent 已改为显式 8 个窗口信用，当前审查快照 SHA256 为 582309813A4E9AC2C2CB6BBA851BAF1761D281C8E269981EDC8A87288772F62A。未修改 RTL、未启动工具实验。

比较两种容量控制：
- 方案 A：wr_data_count 加最坏本地计数滞后补偿，并约束两次预留之间的写入静默间隔。这可以实现，但正确性依赖具体 XPM 版本与计数路径。
- 方案 B：全局 4 位 occupied_slots 记录预留后尚未归还的窗口数，跨帧保持；500 MHz 域只在最后 packed word 被取走时送还一枚信用。推荐并支持父 Agent 已选的方案 B。wr_count 只保留为遥测值。

本机 Vivado 2021.1 的 `C:/NIFPGA/programs/Vivado2021_1/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv:1503-1512` 明确 wr_data_count 是写指针与同步读指针之差的额外寄存输出：本地新写至少存在一个边沿的报告滞后，远端读同步则会偏保守。因此“wr_count 永远保守”的孤立注释并不充分；初版是否恰好借 header_pending 产生的无写间隔规避，要另证明，不应作为新设计的主要容量依据。

### 13.2 显式窗口信用与整窗发布

当前代码第 34–38、98、105–115 行：occupied_slots 只在全局 reset 清零；reserve 加一，return_fire 减一，同时发生保持；cfg 开新帧不清占用。reserve 只在 `<8` 时发生，且每次 reserved 防止重复预留。初始有 8 个隐含空闲信用。

容量不变量是：未归还的完整窗口、部分消费窗口、正在采集窗口和已预留尚未采集窗口的总数不超过 8；每个占用信用最多贡献 512 个 packed word。因此数据 FIFO 中未取走的 packed 数据不超过 4096 字。信用返回 CDC 的延迟只推迟下一次准入，不会提前释放空间。

第 64–70 行在 sample_index==2047 时要求 return_ready，再同时 issue/弹出最后 packed word/写入 return FIFO。若 return FIFO 暂时不能接受，最后 lane 保持；不允许先弹出数据后丢失归还事件。return FIFO 深度 32，而全局最多 8 枚未回收信用，正常运行不可能累积到满。第 101 行检测无占用时收到归还事件。

头 FIFO 只在第 512 字被接受后的 header_pending 发布，带完整 71 位 `{frame32,generation32,window7}`；读侧见不到尚未写完的窗口。头队列最多对应 8 个占用信用，深度 32 充足。两条独立 CDC FIFO 的可见延迟不要求完全相同：读侧始终以 dq_v 决定是否 issue，头先可见不会读取无效数据。

末窗窗口 73 对应 beat333536..334047；全帧还有 32 个普通尾字 beat334048..334079。cfg_ready 等 active 清除且 header_pending 清除，因此在正确输入下旧帧头发布完成后才能接受新 cfg；窗口数据/头仍可在跨帧 FIFO 中排队。全局信用跨 cfg 保持是必要条件，当前实现具备。

### 13.3 供数、保持与窗口尾拍

- 第 71–72、86–87 行按 sample_index[1:0] 顺序选择 packed word 的 lane0..3，每个 lane 低 16 位 I、高 16 位 Q。S26 值为 `{{4{S16.sign}},S16,6'b0}`，与原 A07 数值转换逐位相同，没有新增乘法、舍入或截位。
- 第 63、74、83–89 行只在输出 holding 寄存器为空或被接受时 issue。sample_index 仅随 issue 增加；lane3 issue 才弹 packed FIFO。停止期间 dq_data、index 和输出记录的取样关系不会错位，m_valid=1 且 m_ready=0 时 output_record 保持。
- sample2047 被 issue 时，最后 lane 数据、旧头和 last 已原子复制到 output_record，因此这一刻归还整窗容量是安全的；无需等 FFT 做完，也无需等该末 lane 被接收。返回信用只管理 packed 数据空间，不表示观测计算完成。
- 上一窗末 lane 尚在 output_record 被阻塞时，hq_r 可以提前装载下一窗头并将 sample_index 清零。旧记录已经完整寄存，因此不会被新 fast_header 改写；advance 为 0 时不能发出新窗首样本。旧末样本接受后才正常替换为新首样本。
- 窗口内具备每 500 MHz 拍一个样本的逻辑供数能力，消费 packed FIFO 仅每四拍一次；前提是 FFT 处于连续 LOAD、无 reset/poison 且 FIFO 数据已经可见。新头装载/首数据可见及前端服务状态仍须计入首拍和窗间边界，不得把该条件式能力写成已测持续速率。

### 13.4 必须关闭的 poison 恢复缺口

当前快照第 19–26、78–81 行中，poison500 是 poison150 的同步电平；fast_stop 分支只清 header_active/output_valid，没有锁存 poison。数据、头和 return FIFO 则仅由 reset_request 清除。

若 poison150 只是脉冲，随后撤销且没有全局 reset，500 MHz 串化器会恢复并弹出下一个旧 header，而部分已消费窗口剩余的 packed 数据仍在 FIFO，破坏头/数据配对。slow_fault 虽已在第 100 行锁存，也没有在此快照被同步到 fast_stop。不能依赖 FIFO underflow 检测该错配；ota_async_fifo 已在接口内用 m_valid/s_ready 阻止空读满写，正常协议下物理 underflow/overflow 本就不会替代事务层身份检查。

两种可行修复选择：
1. 由顶层保证 poison150 是 sticky fatal，保持到两个域及三个 FIFO 完成统一 reset；把此合同写明，绝不能直接接一次 cancel 脉冲。
2. 模块内部锁存 fast poisoned 状态，或把 sticky slow_fault 同步至 500 MHz 并参与 fast_stop，唯全局 reset 清除。推荐自包含的第二种，使局部输入身份错误也能使两域永久停机直到 reset。

此项已即时反馈父 Agent。全局复位必须同时丢弃旧 FIFO 内容和旧信用、清除 parser 状态，重新建立完整窗口边界；单独清局部错误或单独恢复 serializer 不合法。

### 13.5 500 MHz 组合路径与物理证据范围

明确存在的新增寄存器间路径：
- XPM packed FIFO 输出寄存器 → 128-to-32 四选一 lane 选择 → S26 接线 → output_record。这一数据路径已有专门 holding 边界，lane mux 不再与 FFT 输入 RAM 写入逻辑叠在同一拍。
- sample_index 寄存器 → lane select、11 位递增、2047 比较和最后字控制 → output_record/index/信用 FIFO 使能。
- FFT LOAD/前端 FEED 状态与 reset → m_ready → advance → issue → output holding CE 与 XPM rd_en；最后样本还经 return_ready。当前数据有寄存边界，ready 仍是局部组合反馈，不能称完全隔离。
- FIFO full/empty/reset completion → dq_v 或 return_ready → issue。500 MHz 的 2 ns 预算需要考虑控制扇出与 XPM 内部路径，而不能只看 4 选 1 数据 mux。

复用 FFT 本身仍有 `cfo_fft2048_core.sv:75-86` 的输入身份/索引比较与优先错误选择 → RAM 写使能路径；这是本次 queue 未改变的既存路径。若后续授权的真实时序显示局部 ready 控制是瓶颈，可比较两项改造：保留当前单输出 hold 并局部寄存/提前产生 last 判定；或使用两记录弹性缓冲隔断上游 XPM 控制对 FFT ready 的组合依赖。后一方案必须按两槽容量核算在途数据，不得只延迟 ready 一拍。

packed FIFO 名义容量为 64 KiB。由八独立 512x128 窗槽改成单 4096x128 FIFO 后，BRAM 具体宽深拼接可能不同；需以实际综合的层级 RAMB36/RAMB18 计数结算，不能把“8×2 块”当本新 FIFO 的已测资源。当前无新的数值仿真、功能运行、500 MHz 时序或综合资源证据。
## 14. on-chip 双 bank CFO 整链静态复核

### 14.1 快照与结论边界

复核 `rtl/cfo/ota_cfo_chain_onchip.sv` SHA256 A34F3426AC6589EE37AB40983B65948A6B5972855CE74642C2FDF4D219715697；窗口 queue 同时更新为 AE1404BA7379D3FB6E6617091AADA8A4FCA3AF7F116D64EEFDC77AD84647F970。本次只读检查双 URAM、八窗 queue、两旋转器、共享坐标核、A07 前端/后端及实际复用 FIFO。未修改 RTL、未仿真或综合。

在正常握手和全局故障后必须 reset 的合同内，本次未找到 bank 同拍覆盖、广播重复接受、正常 estimator 跨帧状态残留或最终尾拍过早释放的新增功能问题。结论仅针对这些静态路径；第 14.6 的接口迁移事项与第 14.7 的物理实现风险不能省略。

窗口 queue 第 20 行已同步 `poison150||slow_fault`，第 79 行在 poison500 到达时锁存 fast_fault，直到全局 rst500 清除。第 13.4 节所指出的脉冲撤销后恢复旧 parser 缺口，在本快照关闭。

### 14.2 bank 同拍事件

以时钟边沿之前的状态判断：
- context_allocate（37–38、163–166 行）要求 next_write bank 为 FREE，且 cs=C_IDLE；分配后写 FILL 和完整 214 位 context。该 bank 不可能同拍是 done_free 的 READING bank，也不可能是 backend_good 匹配的非 FREE bank。
- coarse seal（182–184 行）只来自 cs=C_FEED 的 wb 尾拍；其合法 bank 状态为 FILL。final_launch（167–170 行）只选择 SEALED 且 bank_estimated 的 next_final，不能在同一边沿将正在写最后字的 bank 启动读出。
- estimate 与 seal 可以合法同拍：分别写 bank_estimated/residual 与 bank_state，没有字段覆盖；下一边沿 final_launch 才看到两项都具备。
- final done（194 行）只释放 fb，清估计标志并切换 next_final。context_ready 检查的是边沿前 FREE，所以不会同拍复用刚释放的 bank；至多产生一个确定控制空拍。
- 写入和最终读出各按 next_write/next_final 交替且只有一个 writer/reader；bank FILL 与 READING 互斥。跨两个 bank 的分配、估计、尾拍释放可同时发生，相关字段属于不同租约。
- 旧 bank 的 residual/phase 值可以留在寄存器中，但新 context 会先清 estimated，再经独立 coordinate 结果写入 phase/step 后进入 C_CFG/F_CFG；没有将旧参数有效性错误继承给新租约。

### 14.3 广播接受和参数所有权

第 83–89 行的 `coarse_fire=r1_v&&qsample_ready&&cs==C_FEED&&!stopped` 同时等于第一旋转输出接受和窗口 queue 输入接受；第 125 行用同一 coarse_fire 写 wb URAM。URAM 为每拍可写且无 ready 的端口，因此没有某一分支先接受后等待另一分支导致重复写入的问题。queue 只将选中窗口字写其 packed FIFO，但仍接受并检查所有 334080 个输入字。

第 88 行 cfg_valid=context_take；context_ready 本来就包括 qcfg_ready，故 bank context 与窗口队列 cfg 原子接受。214 位字段依次为 frame32/gen32/step1_32/step2_32/origin54/coarse32，字段未变宽或错位。

坐标仲裁第 60–77、171–181 行锁存 owner(kind,bank)，结果根据已锁 owner 存入 bank 的独立 coarse_phase/step 或 final_phase/step。只有下一 C_CFG/F_CFG 状态才配置各旋转器，不再直接广播当前 coordinate 输出。coord_identity 核对 owner 对应 frame/gen/residual；错误在同边沿锁存全局 fault，后续 cfg 被 stopped 抑制。结果接受与下一请求因 coordinate_busy 不能同拍，避免 owner 被覆盖。

final 请求有优先级，但 final_job 持续读出期间没有新的 final coordinate 请求，故持续 coarse 输入不会被无限饿死；正常一次等待至多一个已启动或同时优先的完整转换服务。

### 14.4 旧 estimator 的多帧复用

`cfo_estimator_link_a06.sv:83,93-104,152-154` 在观测 73 后 closed_fast；只有 backend 结果被取走后才翻转 done_toggle，并经 CDC 回收下一帧观测信用。新链第 106 行 m_ready=!stopped，第 186–188 行结果直接存入唯一匹配的非 FREE bank，因而不会等待全局 FINAL 或旧帧尾拍而扣住 estimator。

`cfo_estimate74_backend_a07.sv:24-25,34-44,73-82` 将 phase/quality 同时消费并生成 held 结果；两个子核分别在 RESULT 消费后回到 observation0，并在新 observation0 清累计、身份和有效结果。quality 的 256 点 FFT 在最后输出消费后回 LOAD。A07 window front 在 HOLD 消费后也清 first_pending、sum、pipeline valid。正常帧之间不需要 reset。

链第 110–112 行要求 frame/gen 只匹配一个 bank，且未估计过；重复结果或两 bank 复用相同身份会进入 fault。queue 按帧窗口顺序发送，因此不向一个 estimator 交织两个 frame 的观测。帧 k+1 的首窗 FFT 可在帧 k backend 计算时运行，首窗结果若先到会停在 front HOLD 等信用，顺序仍保持。

### 14.5 最终读出、标签与尾拍

- URAM `READ_LATENCY_B=2`，对应链第 116、157 行 rv 两级 valid；issue 边沿锁入地址，第二拍输出数据稳定后，在下一接受边沿以 rv[1] 写同步响应 FIFO。两个 bank 共用固定 fb 选择器，fb 从 F_COORD 到最终输出 last 都不改变。
- 第 118–120 行以 issued-consumed 限制最多 64 个尚未被第二旋转接受的读事务，覆盖响应 FIFO 内数据和两拍 URAM 在途数据，不能只按 FIFO 当前 level 计数。每次 issue 预占一个位置，每次 pop 释放一个位置。
- 第 129–131、190–192 行返回数据按顺序进入 FIFO；消费时用固定 fb 的 frame/gen 加 consumed 构建完整标签。当前只有一个 final job 且读请求严格顺序，因此不必在每个响应中另存 bank/tag。若未来允许读作业交织，此推导立即失效，必须给请求/响应显式 tag。
- 第 200 行检测返回时无 FIFO 空间、outstanding 超界及 consumed/returned/issued 逆序。正常尾拍标签只能在 consumed=334079 时产生，第二旋转同时检查递增序号和 last；最大读地址也为 334079，小于 bank 深度335872。
- 最后一拍经过第二旋转及固定两个输出寄存器，done 在外部 m_valid && last 的实际接受边沿发生；第 194 行此时才释放 fb。到此最后响应早已 pop，rv 和响应 FIFO 正常已排空；下个 final_launch 又要求 !fq_v、!fq_busy、rv==0，避免旧响应被新 fb 解释。
- cancel/fault 立即抑制新的 issue/pop/对外 valid；原有 rv 最多再向内部 FIFO 排入两拍已承诺响应，不发生新的 bank 重用。所有 bank/FSM/信用与 FIFO 只由全局 reset 恢复，故停止后保留部分状态不被误当成功。

### 14.6 顶层集成必须采用的新接口合同

1. done 从旧 A07 的 held-until-done_ready 改为最终 last 同拍脉冲（第 140 行），没有 done_ready。不能直接复用旧 top 的 completion_sent/held-done 接收方式；如需跨域记录，必须当拍存入预留空间或用不会丢脉冲的事件结构。
2. coarse_beats/final_beats/saturation 仅 reset 清零，当前是跨帧累计值；estimator_result 为最近一次估计结果，不保证属于当前 done 帧。数值上的 per-bank residual 已正确保存，但如果外部需要每帧完整诊断，应随 bank 保存或按带 frame/gen 的事件记录发布，不能读这些全局寄存器拼成原子帧报告。
3. fault 为 sticky，cancel 也变成 sticky fault（197 行），故障时不产生正常 done；调用方必须处理 fault 并统一 reset，不能等一个永远不来的成功完成脉冲。
4. 当前 `rtl/sources_a07.f` 仍只包含旧 `ota_cfo_chain_a07.sv`，新文件未接入现有生产 top。本次是新模块结构审查，不能声称 XPR 已在使用新链。
5. 新源集继续明确选择 `ota_async_fifo_a06.sv`。同目录无后缀 `ota_async_fifo.sv` 是同 module 的旧变体，额外将原始 reset_request 直接 OR 到 busy 输出；a06 仅用域内异步断言/同步释放尾。不能两个同名 module 一起收集，也不能靠扫描同名选源。

### 14.7 现在可优化的路径与尚未形成的物理证据

建议将第 118–119 行 `issued-consumed` 的 32 位组合减法/比较替换为 7 位 outstanding 寄存器，按 issue/pop 同拍加减，32 位计数保留用于独立诊断。两种方案算术等价，但局部 7 位信用把最终 URAM 读使能从宽计数相减路径中隔离；不改变有效读序列和 64 项容量上限。

仍须按真实实现检查：第一旋转输出身份/窗口选择→qsample_ready→coarse_fire→大 bank 写使能扇出；fb/wb bank 选择和 128 位 URAM 数据布线；coarse/final 配置广播；窗口500 MHz ready/地址路径；共享 coordinate 的串行宽加减；既有 FFT256 非预期 LUT RAM。两个完整 CFO bank 的名义资源增量为328 URAM，不能靠本次静态审查证明布局容量及 150/500 MHz 时序闭合。

本次没有新的 RTL数值比较、持续吞吐测量、综合或实现报告；已指出的旧 A06R3 负裕量不得由本次控制结构审查自动改成 PASS。
## 15. V5.1 新 top、无背压完成事件与本域故障传播

### 15.1 审查快照

本次只读核对新 `rtl/control/sync_ota_top_v51.sv`、on-chip CFO、上下文 join、训练 dispatcher、SFO 控制接口及完成 CDC。评审期间父 Agent 修正本域故障传播与取消优先级，以下以修正后的快照为准：
- sync_ota_top_v51.sv：3AE14C4FA4941F1A8B0250B7657E5BF104F66A39175254757073BAD73A19535F。
- ota_cfo_chain_onchip.sv：A4EC499E95296894D1FD657EE049BB47075C04AD161DCB71433A2F3E54FBA975。
- sync_sfo_top.sv：B90A9417E2FCCCFDDD6F1D69132FA475ACFA795D9E375C55BD1EFB104C65E96B。
- sfo_two_pass_transport.sv：96DABE8500A74FEE3358F80D864B20514C0B64E31828C164BA5D3C009FEEFD90。

没有修改 RTL，没有启动仿真、综合、编译或原生工具实验。

### 15.2 CFO 上次建议的关闭情况

on-chip CFO 第 118 行已用 7 位 outstanding 寄存器，190 行按 issue/pop 同拍加减；同时发生保持，最终作业开始清零。32 位 issued/returned/consumed 保留作独立完整性诊断。第 205 行在 done 时检查三个计数全部为334080、outstanding为0以及 frame/gen/beat 身份，上一节的宽组合相减建议已落实。

### 15.3 无背压输出与 done CDC

新 top 外部没有最终 ready 或 DDR 事务端口。第 86、90 行直接导出 CFO 两级寄存后的完整225位事务，不重排输出字段；每个 output_valid 都是已经转移的一拍四样本。输出最后一拍与 cfo_done 完全同拍。

第 92–96 行以64位 `{output_frame,output_generation}` 写入完成 CDC FIFO。第125域 m_ready 固定1，完成记录自动逐拍消费；没有 Host 应答反馈到最终 IQ 读出。正常相邻完成事件至少相隔334080个150MHz时钟，而消费端每125MHz时钟可消费一个记录。双方时钟持续运行、统一reset完成且无FIFO故障的合同下，32深度足够，不存在从正常帧率推导出的积压风险。若写入信用意外不足，第102行锁存 completion_fault150，而不是静默忽略事件。

第120行现在将 cancel、ingress_fault、sfo_fault、meta_we、completion_re 和 remote_fault125 的当前电平一起纳入 frame_done125 屏蔽；取消/已知故障与完成同拍时不再发成功脉冲。第121行仍计数并记录实际从 FIFO 排出的完成事件，这可用于已输出帧统计，不能把 completed_frames125 在故障后的增长误写成新的成功确认。

完成FIFO是低速事件队列，不是最终IQ停顿缓冲。它的正确性依赖两时钟不停转，不能据此支持任意暂停125MHz域而150MHz域继续无限输出。

### 15.4 本域故障无需跨125域往返，且避免组合环

初版将150域本地故障先同步到125、锁fault125，再同步回来驱动 join/CFO cancel；这会使其他150域模块额外运行一个完整CDC往返。此项已在评审中即时反馈并关闭。

当前 top 第24–25、104–109行把150域故障锁存为 local_fault150，形成 local_stop150；第58、77、84行分别连接 SFO.abort150、context_join.cancel 和 CFO.cancel150。SFO transport 第74行 halted150 包含本域 abort150，其读写、调度、窗口、重采样和输出因此在本域停止，不必等125域回传。fault150同时保留到统一复位。

必须保留此处一级寄存边界：SFO m_fault 本身包含 halted150/abort150，若把整个 remote_fault150 直接组合 OR 回 abort150，就会产生组合反馈。当前方案在下一明确150MHz边沿将原因锁存，允许这个有界本域传播延迟，避免跨域往返和组合环。125域CDC只负责系统通报和125域停机。

context_join 在 cancel 时会清其 error_code；当前 top 的 held_context_error150 在取消生效前保存首个非零 live_context_error150，并只由全局reset清除（27、106、109行），不会因故障广播而丢失原始上下文错误。

外部 cancel 仍属于125MHz输入合同，先使125域 poison，再通过CDC传播到150；不要将异步按钮或500MHz脉冲直接当作该输入。故障/取消后必须统一reset全部域及相关FIFO；仅撤销 cancel 不会恢复本地 sticky fault。

### 15.5 元数据、帧身份与 epoch

新 top 第71–81行的 metadata CDC 宽度150，包含 frame32/gen32/coarse32/origin54；与两个96位E1/E2上下文一起进入有序join，输出214位完整context，再在CFO接收时原子存入选定bank。旧A07的单独 cfo_base 寄存器已退出新top，不再存在该字段被下一帧metadata覆盖的caller依赖。

`ota_training_dispatch.sv:45` 发布 `{frame,generation,hz<<8,24'd0,fine[1:0],28'd0}`，coarse Q8与54位origin字段相符；dispatcher第65–67行等四路描述符全部发送后，才允许T06完成/释放训练租约，避免仅因 metadata FIFO 阻塞而出现缺少元数据的E1结果。

ingress使用全局递增frame和segment_generation标记新段；frontend epoch 用于拒绝旧段前端结果，不直接重置已经在SFO/CFO中的旧帧。CFO bank保持自己的frame/gen至最终last，完成CDC也携带同一身份，因此新段frontend开始不会覆盖旧帧输出身份。取消后以全局reset清FIFO与bank建立新世代，不能仅清局部错误后重用从零开始的身份值。

当前 cfo_result150 仍是“最近估计”、各beatz/saturation仍是累计统计，不是每次done帧的完整快照；本top没有声称提供所有per-frame诊断字段。

### 15.6 仍需明确的状态接口边界

- 当前 busy125（116行）只看 ingress_stage、创建/完成计数差和同步CFO busy。输入FIFO接受首字后，FWFT头尚未可见且ingress仍IDLE的几拍，busy125仍可为0。因此它暂不能单独作为“输入队列完全排空、可安全reset”的判断。若需要这种Host语义，应把本地已接受未转发的输入占用纳入busy；若仅作算法活动指示，应在接线文档明确。此点已反馈父Agent。
- frontend_error125是独立公开诊断，当前并未并入fault125。前端包含候选丢弃/历史不足/段尾不完整，以及协议、算术和deadline等不同原因。需明确哪些仅为候选级诊断、哪些为整段失败；不能把fault125为0解释为前端所有错误位为0，也不宜无差别把全部前端诊断OR成fatal而改变检测合同。
- output_*属于150MHz，done_*与frame_done125属于125MHz。外部Target VI必须按所属时钟域接收，不得将多位输出标签逐位同步到别的域。

本次修正后的局部停机、完成事件与元数据连接未发现新增正常路径丢拍/串帧问题。busy语义、前端诊断分类以及新的150/500MHz实现时序、持续吞吐和数值证据仍须按各自层级交付；本报告没有把静态接线复核等同于全工程可靠性证明。
## 16. 最终收口：完成边界、生产接口及剩余风险（2026-09-18，Europe/Berlin）

本节为最新结论，覆盖第14–15节有关“done与最后输出同拍”、生产源尚未切换、busy未含输入占用及前端错误尚未分类的历史状态。历史审查及其源码行号保留用于追踪，不应当作当前接口合同。审查人仅更新本报告；没有修改RTL或启动任何仿真、综合、数值实验和EDA。

### 16.1 当前快照

- `rtl/cfo/ota_cfo_chain_onchip.sv`：SHA256 `8FF834228BD5D4AF674B1C1E747FD9D30298C83671A55D5AB0D19183F35DAFA1`。
- `rtl/control/sync_ota_top_v51.sv`：SHA256 `E0EB770938DB60B9F8830157C68B73123A390D91685212244A1E22B015D81BDD`。
- `rtl/buffer/ota_cfo_window_queue.sv`：SHA256 `DB0040EB0B1396C118AAF92F0BA41A670BF0837621FBCB5E01A751C3F1F17877`。

### 16.2 本轮发现并关闭的完成事件缺口

修改前，`done=m_valid&&last`直接驱动完成CDC写入，而尾拍的计数/身份错误在同一边沿才置fault；错误帧的“成功完成”记录可能先进入CDC。完成FIFO与故障同步器是不同跨域路径，不能用其延迟猜测保证125域一定先看到fault。

两种可选修正：A在组合done中加入全部计数、身份和故障判定；B在实际尾拍照常传输后，将检查通过的完成事件及独立64位身份寄存。选B可避免将长比较链直接放到完成CDC写使能，同时保持IQ吞吐不变。

当前onchip第143–158行把`tail_event`与`tail_good`分开，并统一当拍已可见错误的优先判定；第216–218行仅在`tail_event && detected_error==0`时释放bank、增加完成计数、寄存done_q及done_frame/done_generation。top第108行以独立完成身份写CDC，不再从延迟一拍后可能变化的output_record取身份。本问题已在源码层关闭。

正确的边沿关系：

| 边沿 | 最终IQ与计数 | 完成事件与bank |
|---|---|---|
| E之前 | 第二级输出valid=1、last=1、beat=334079；已发出拍数为334079 | final job仍为READING |
| E | Target VI无条件接受第334080拍；累计拍数/饱和数在同一事件更新 | 校验三个请求/响应/消费计数均334080、outstanding=0、输出身份/序号及已发拍数；无当拍已知错误才释放bank并寄存完成身份 |
| E到E+1 | 输出流水照常前进，没有等待完成CDC | done_q保持一个周期，done身份稳定；发生cancel/已锁fault会屏蔽done |
| E+1 | 不依赖输出总线的后续内容 | 完成CDC在有信用时采样独立完成记录；信用异常明确置completion_fault150 |

`emitted_in_job==334079`检查的是E边沿前的计数，随后正常尾拍才加为334080，不是少算一拍。bank释放仍在实际尾拍接受边沿，完成通知额外一拍不延长bank租约。若尾拍发现错误，已经输出的IQ不能撤回；不发布成功完成，并由Host按frame/generation处理失败帧。

此保证针对本地边沿已经可见的错误和该帧尾拍完整性。后续其他帧的新故障不可能追溯撤回已正常发布的早先完成事件；多域故障通报也不构成对所有历史完成的全局原子撤销。

### 16.3 无背压、两级寄存、身份与取消边界

- onchip第134–141行将第二旋转m_ready固定为1，对外无ready；第181–183行将完整225位记录、8位饱和标志和valid同步走两级寄存。第215行在第二级实际m_valid上更新拍数及饱和数。未发现尾拍比身份/饱和标志提前或落后一拍的问题。
- top第4–18行和`wrapper/sync_ota_wrapper.vhd`均无最终ready或中间DDR接口；第104行按原225位布局拆出frame32、generation32、beat32、last1、IQ128。新增前端计数仅在125域作诊断，不参与CFO数据流。
- top第106–110行的32深度完成FIFO只传64位事件，125域自动消费；没有通向最终IQ的数据等待。正常帧率下每至少334080个150域周期仅一个事件，其安全前提仍是所有时钟持续运行且统一reset正确完成。
- context214位仍为frame32/gen32/step1_32/step2_32/origin54/coarse32，接收时原子安装到所分配bank。共享coordinate的owner/bank锁存，结果先存bank再进入独立C_CFG/F_CFG；最后输出使用固定fb，未发现下一帧coarse参数或当前全局估计覆盖旧帧的问题。
- 150域`local_fault150`经一级寄存形成local_stop150，同时送SFO.abort150、join.cancel、CFO.cancel；不再等待150→125→150往返。保留该一级寄存是避免SFO m_fault/abort组合反馈的必要条件。
- cancel/fault抑制输出valid、输入接受和新的读请求；已承诺URAM响应最多继续进入内部响应FIFO，bank不再重用。恢复必须统一reset，不支持撤销cancel后接着运行或只清一个模块。
- 窗口queue的8个显式信用跨帧保存；信用在最后packed word已经复制到带身份的500域输出寄存器后返回。新cfg不清occupied_slots。FIFO wr_count仅为滞后观测值，不能替代信用作整窗准入。

### 16.4 已关闭的其余集成静态项

1. `ota_stream_ingress.sv:22,43,59`显式统计已接受未转发输入占用，input_idle还包含描述符/事件排空；top第130行使用它，先前首字接受后busy短暂仍为空闲的问题已关闭。
2. top第38行采用前端fatal mask 16'h006f，位4/7保留候选诊断语义；第41–47行在健康时镜像错误和四项计数，故障poison后冻结，避免前端复位清掉Host需要的原因。当前错误判定使用live位，没有额外等待诊断镜像。
3. `rtl/sources_v51.f:120,126–129`和`Sync_OTA.xpr:1179–1205`明确选择a06异步FIFO、新queue、新onchip CFO及V5.1 top。XPR综合顶层为sync_ota_top。a07历史源集仍可作为历史入口，不再代表当前生产选择。
4. 当前XPR sim_1已移除旧smoke TB，注释明确新版未授权仿真；不再把旧调用接口误当新顶层验证证据。新版独立VHDL wrapper端口目读与top一致，包括四个新增前端计数。

在本节限定的CFO/最终输出/顶层取消与身份范围内，没有发现另一个需要立即修改RTL的确定功能缺陷。这不表示全工程静态风险已经关闭。

### 16.5 可由源码与设计资料继续关闭的剩余项

| 事项 | 当前证据与必须保留的边界 |
|---|---|
| 完整SFO/Farrow服务包络及全链bank寿命 | 现存`reports/v51/integration_static/cycle_memory_budget.json`仍把resampler_worst_case_service与residual_window_service标为OPEN；`docs/v51/REFACTOR_DESIGN_ZH.md:63`仍列FIR/Farrow、SFO完整延迟、长无帧段回收、段尾排空、租约更新和跨帧失败/取消。应由相应设计者根据实际IP配置/寄存边界/仲裁建立最坏包络并更新状态，不可用本CFO局部预算替代，也不必为了补推导先运行实验。 |
| CFO窗口及输出缓存上界的口径 | 硬结构为8个整窗信用、4096×128 packed FIFO、64项最终读信用及2个整帧bank。此前4窗峰值为给定连续供数与FFT服务的解析结果，未包含任意上游突发合同。应和全链服务包络保持相同的帧间隔/到达假设；buffered_words150是观测计数而非精确高水位记录。 |
| 诊断字段语义 | coarse/final拍数与饱和数为跨帧累计；cfo_result150是最近估计并自带身份，不能与当前done拼成一份原子的单帧诊断。completed_frames125在故障时仍统计实际排出的完成事件，frame_done125才是受已知故障屏蔽的成功脉冲。需要在交付接口文档写清，不能默认为每帧快照。 |
| 外部时钟与取消合同 | 输出数据/标签属150域；frame_done和done身份属125域；cancel按125域同步输入使用。所有时钟须在reset及运行中保持活动。Target VI必须原子接收每个valid拍的四点及标签；不能用后级ready或停125MHz来隐含增加核心缓冲能力。 |
| 接口文档路径 | 本快照wrapper第4行指向`docs/v51/INTERFACE_CONTRACT_ZH.md`，只读核查时该文件尚不存在；需在交付收口时补齐该文档或修正到真实入口。该项不要求改算法或运行实验。 |

以上是本审查发现/关联的当前设计资料待闭合项，不把其他独立审查者尚未交付的结论臆断为已失败或已通过。

### 16.6 必须由后续获准实现或数值证据确认的事项

| 证据层级 | 仍未确认的实际事实 |
|---|---|
| 综合映射与分层资源 | CFO两个335872×128 bank按器件宽深打包为328 URAM；全方案候选848/960 URAM是静态预算，非新综合网表。8窗FIFO、SFO BRAM环、XPM控制开销和全部DSP/FF/LUT实际占用要看新版分层资源。`cfo_fft256_core.sv:95,101,113,123`仍有多处同数组读写，历史实现出现38673 LUT/10573 FF/0 BRAM；ram_style字符串不能证明此版映射已改善。 |
| 150/500MHz物理时序 | 新queue的500域FIFO DOUT→4:1 lane选择→输出寄存、FFTready→advance/issue/rden、FFT身份判定→RAM使能，以及150域qsample_ready→coarse_fire→bank写使能、bank选择/数据布线、坐标运算与大范围控制扇出须看真实路径。两级最终输出只解决该处边界，不会自动修复既有核的负裕量。旧A06R3的150MHz -2.358ns和500MHz -1.279ns不因本次静态审查变PASS。 |
| CDC/复位与约束 | 当前XDC只有8ns/6.666666667ns/2ns三个core时钟并依赖XPM自身局部约束；新版所有CDC实例、复位释放、Gray路径及约束实际加载需原生报告核实。旧182条CDC警告不能继承为已关闭。没有板级输入输出延迟/NI完整约束的core报告不等于Target VI时序通过。 |
| 数值一致性 | 未替换FFT/旋转/固定点算术且S16→S26映射保持，可支持“旨在保持数学与定点行为”；不能据此声称多帧地址、窗口、fine低位和相位原点完全等价。新版逐样点数值比较目前NOT_RUN，旧限定输入0 LSB不得继承。 |
| 实际持续吞吐、最高占用与板测 | 74窗15449clk500的服务推导和约4.609ms CFO bank租约是有前提的静态结果。运行中的接受周期、停顿、最高占用、丢重复乱序以及用户服务器板测结果尚无新版证据。600MS/s只说明四点150MHz有效突发能力，不能单独认证全链500MS/s持续服务。 |

静态审查结论是“已识别的CFO控制与身份缺口按源码关闭，尚存设计资料待闭合项和明确的实证边界”，不是“整个工程已经没有风险”。本次没有提出或运行额外仿真用来试探设计猜想。
## 17. 任意帧数的CFO服务、八窗信用与SFO输出环联合模型

本节将第16节的条件性单帧数字扩展为一般递推；不以两帧压缩示例代替长期证明。只作源码推导和闭式算术，未执行RTL、事件仿真、综合或EDA。当前首选仍是保留尽快服务的E2，由既有bank/窗口信用及有限输出环回压建立有界系统；下述G合同若未从实际FIR服务封闭，不能宣称全链已完成证明。

### 17.1 时间、流量及前提

统一用clk150周期计时，N=334080字/帧，T=400896周期/帧，外部500MS/s等于5/6字/clk150；每字四个复样点。定义：

- b_k：第k帧首字经粗旋转实际写入CFO bank的边沿。
- e_k：第k帧残差估计被onchip控制器接收的边沿。
- d_k：第k帧最终输出tail实际转移、bank被释放的边沿。
- G：从首个粗校正写字开始，该帧除下述CFO内部阻塞以外的累计供数空洞上界。G包含E2内生服务空洞及一次允许暂停后的恢复代价；不能再次把同一output ring回压时长Bout加进G。SFO独立审查暂以G=66+Lfir表示，但其实际vendor弹性服务合同仍须封闭。

健康且已复位完成、三个时钟持续运行、帧身份有序、E1/metadata已在E2首字之前按顺序提供、合法估计能够成功的条件下：每帧窗j完整写入时刻不晚于b_k+7008+4480*j+G；任意两个相邻完整窗口的最小产生间隔为4480。跨帧的相邻窗口间隔至少7040，不比帧内更密。

“任意上游停顿”不具有有限bank寿命；本节明确依赖有限G。取消/估计失败走全局停止合同，不假造成功服务上界。

### 17.2 帧边界服务不能只用74个FFT相加

CFO自写2048点FFT仍为15449clk500/窗。整数化取L=ceil(15449*150/500)=4635clk150。不能混用SFO的厂商FFT latency。

`cfo_estimator_link_a06.sv:83,98–101,152–154`在obs73后关闭跨帧信用，直到前帧结果被消费并回传toggle；下一帧首窗可以先运算，但front HOLD不能越过这个信用。故连续压缩多帧时，第一窗的部分服务可与旧帧backend重叠，之后73窗仍须串行完成。

保守常数如下；它们是按固定源码状态和XPM两级指针同步/FWFT边界留出的静态上界，非测量值：

| 符号 | 周期 | 来源 |
|---|---:|---|
| L | 4635 | 每窗15449clk500逐窗向上取整 |
| B | 6832 | 后端正常最坏6792，加观测FIFO、A07结果join及链路接收余量40 |
| H/Credit | 各16 | 完整header可见/首数据，以及backend信用返回控制余量；steady state不含复位 |
| E0 | 356850 | 大于7008+74L+B+16=356846 |
| S | 345216 | 大于73L+B+16=345203 |
| Q | 440 | ROUND_PRE落实后三次除法各增1拍，438步正常运算及结果/配置边界 |
| Fmin | 334520 | N+Q，最终转换和N个输出字的保守下界 |
| Fmax | 334992 | N+2Q+32，最多一个已开始/优先的坐标作业，外加读响应、旋转、两级输出及状态边沿 |
| Ccfg | 912 | 2Q+32，coarse得到空bank后至首粗写的协调/流水上界，源数据已经可供给 |

两级CDC及FWFT控制不是无界软件队列：packed/header/credit均`CDC_SYNC_STAGES=2`、读输出持有，帧间不重新reset。其first-word/header等待在上表有限余量内计入；物理亚稳概率、真实CDC约束仍另需实现证据。

由于下一帧obs0必须等前帧结果回传，下一次正常估计至少还需要73个完整窗。SFO独立审查交叉核对`cfo_fft2048_core.sv:151–188`给出严格下界：每窗仅计2048个LOAD、11*1024个蝶形和2048个OUTPUT就需15360clk500，故73窗至少336384clk150>Fmax334992，余量1392拍。此处故意忽略流水排空和后端费用，不把服务上界15449误当下界。因此最终读出不会在成功估计之间无限排队，且有：

    e_k <= max(b_k + E0 + G, e_(k-1) + S)
    e_k + Fmin <= d_k <= e_k + Fmax

### 17.3 两bank反馈消去更早积压：一般归纳

`next_write`/`next_final`严格交替，只有最终tail才释放bank。因此不论此前经历多少帧：

    b_k >= d_(k-2) >= e_(k-2) + Fmin
    b_k >= b_(k-1) + N

展开估计递推两次即可覆盖全部历史，而不需要枚举多帧：

    e_k <= max(b_k+E0+G,
               b_(k-1)+E0+G+S,
               e_(k-2)+2S)
        <= b_k + max(E0+G, E0+G+S-N, 2S-Fmin)

E0+Fmin-2S=938>0，S-N=11136，故对所有k：

    e_k - b_k <= E0 + G + 11136
    d_k - b_k <= 702978 + G

同样有：

    e_(k-1) <= max(b_(k-1)+E0+G, e_(k-2)+S)
             <= b_k + max(E0+G-N, S-Fmin)
             = b_k + E0+G-N

这里不仅给容量不变量，也给出等待如何通过bank回收限制的因果关系。源有界G、各本地服务满足上表时，第k−2帧之前的工作不能继续向第k帧叠加无限FFT积压。

| G条件 | 从首粗写到最终tail上界 | 时间 |
|---|---:|---:|
| G=0 | 702978clk150 | 4.68652ms |
| G<=3584 | 706562clk150 | 4.710414ms |
| G<=8192 | 711170clk150 | 4.741134ms |

这些是一般压缩多帧的保守值；此前约4.609ms仅为孤立/正常间隔帧的名义推导。

bank从context接受起已经占有，因此完整租约还须加Delta_pre=(首粗写−context接受)。在SFO给定cfg→首输出<=258+Lfir、上下文先到且本域协调有界的合同下，可保守取Delta_pre<=1186+Lfir。以G=66+Lfir、Lfir<=8126代入，完整bank租约<=704230+2Lfir<=720482clk150=4.803214ms，小于2T=801792。若上下文提前无限久而数据不来，则不能引用该完整租约界。

### 17.4 八窗槽上界，包括提前reserve与信用回传

帧内第j窗相对于最密4480周期到达的排队等待，由前帧信用和帧内略慢的FFT叠加，保守不超过：

    W <= G + (S-N) + 73*(L-4480)
      = G + 22451

最后packed word提取所需ceil(2048*150/500)=615周期；再给信用返回32周期。故已经产生但信用未返回的窗口数不超过1+floor((G+23098)/4480)，再加队列对下一个窗口的提前预留：

    occupied_slots <= 2 + floor((G+23098)/4480)

因此G<=3584时最多7槽，G<=8192时最多8槽。第一个假设的“第9槽需求”若出现，其前缀仍无队列停顿，上述服务及到达不等式仍成立，从而与该上界矛盾；这完成了不用先假设无限缓存的首次违例归纳。信用实际返回早于FFT观测输出，不应错误地等到整窗FFT完成才计算释放。

此界不是buffered_words150的实测高水位。8槽保证packed FIFO最多4096个128位字；提前预留与已被本地holding复制的窗口也可能计占槽，所以槽数不能直接等同FIFO瞬时字数。若G合同大于8192，本式无法证明8槽无停顿，须重算服务或调度；不能继续沿用“4窗足够”的单帧说法。

### 17.5 CFO帧间停顿与65536字输出环

当前粗写第k帧结束最早为b_k+N。下一帧要复用第k−1帧bank，按17.3的估计界、最终读出上界以及coarse配置仲裁，其由CFO引起的无消费间隙不超过：

    Vcoarse <= E0 + G + Fmax - 2N + Ccfg
            = 24594 + G

再计入output ring满转非满、64项预取信用恢复及输入/粗写边界差异的16拍余量，采用：

    V = 24610 + G

`sfo_output_buffer`的健康计数恒等式是：

    ring_occupancy = accepted - issued <= 65536
    outstanding = issued - consumed <= 64
    Qtotal = accepted - consumed = ring_occupancy + outstanding <= 65600 < N

所以65536只是物理环占用上限，完整未消费数据上限是65600，不能漏掉已从环退休的读响应。持续压缩供数时环确实可能达到65536；此时合法s_ready反压E2，而不是覆盖数据。环/响应FIFO共同容量并不承担最终Target VI背压。

E2严格串行生产完整帧。生产第k帧期间，kN<=accepted<=(k+1)N，而Qtotal<N，故CFO的consumed只能落在第k−1帧或第k帧；不可能在该帧生产期间跨过两个完整的CFO消费边界。在八窗没有内部停顿、已有数据且context先到的条件下，CFO帧内每拍消费。因此每个E2帧最多受到一次CFO帧间vacation：

    Bout <= V = 24610 + G

不是按任意长历史累加Bout，也不是每次raw/FIR输入空洞都重新增加一次CFO等待。源空洞使环趋空时不会同时因环满阻塞E2；一次反压恢复的内生费用必须由同一个vendor服务合同计入G。

任一已经进入环的字，前方最多65600字且至多跨一个帧边界，其保守等待为：

    Waccepted_word <= 65600 + V = 90210 + G

G<=8192时，这给出Bout<=32802clk150=218.68us、字等待<=98402clk150=656.014us。以上字等待不是新增的整帧截止允许值，不能直接将其全量再加到每帧服务。

与SFO独立审查的C2<=334454+Lfir+Bout（上下文额外等待另计）联立，若G=66+Lfir：

    C2 <= 359130 + 2*Lfir

Lfir<=8126时C2<=375382<T=400896，尚有25514周期给父任务联立的其他有界项。此式只在暂停恢复服务合同得到证明且Wctx不被遗漏时成立；不能把未知的Bout再次加进G形成循环论证。

### 17.6 可用于全链的服务曲线与到达曲线

当输入数据/已匹配context持续待服务时，CFO每N次输入消费至多有一次长度V的vacation。保守严格服务曲线可写为：

    P = N+V
    beta(u) = N*floor(u/P) + max(0, (u mod P)-V)

它也下界于rho*[u-V]^+，rho=N/(N+V)。G<=8192时rho>=0.91059字/clk150，即该保守服务下界仍高于500MS/s要求的5/6字/clk150；这里不是把端口峰值600MS/s当吞吐证明，而是把帧间最坏等待一并计入。

允许到达可由父任务采用有限突发alpha(u)=min(u,sigma+r*u)，r<=5/6<rho，或更紧的周期帧包络：

    alpha0(u)=N*floor(u/T)+min(N,u mod T)
    alphaJ(u)<=min(u,alpha0(u+J))

J必须来自raw/E1/E2的真实延迟抖动，不应自行设为0。无反压存储的充分条件是sup_u(alpha(u)-beta(u))<=容量；仅给平均r而sigma/J不界定，不能声称任意长600MS/s压缩突发无等待。当前E2→环有合法ready，因此有限环达到上限后由Bout调节接受流；全链raw持续接受仍须由父任务把这份Bout、Wctx与raw/SFO bank期限联立。

### 17.7 必要时的两种调度选择及代价

首选保留当前E2尽快服务：上述一般递推满足时，不新增时钟节拍器或额外整帧缓存，raw/SFO bank能更早退休。只有实际G/Wctx无法在现有余额内闭合，才采用以下显式调度之一：

| 方案 | 硬件与收益 | 不能省略的检查 |
|---|---|---|
| E2 cfg最小间隔400896周期 | 19位倒计数器、到期标志及局部cfg门控；在真正cfg接受时重新装载，不积攒补发令牌。帧内仍600MS/s突发，持续500MS/s指标不降低；迟帧不会紧接着压缩多帧补发。 | 等待进入WE2/后级bank占有，再联立raw保留容量；不能让已近满raw凭空等一个完整T。 |
| CFO空bank预留后才启动E2 | 增加显式reserve/accept及64位frame/gen持有，两个bank各增加RESERVED状态；同150域无需新CDC。E2启动之前先获得CFO容量，对ring初始等待更直接。 | 预留不能等待尚未产生的E2 step后才返回，否则形成配置环；须把“容量预留”和“完整参数提交”分开。CFO最终读出释放的等待会反馈到SFO bank/raw期限，仍须重新联立。 |

两方案都不依赖最终输出ready，也不修改FFT、精度或500MS/s要求。增加FIFO而不界定源服务与bank回收，不是一般多帧证明的替代品。

## 18. 当前实际组合路径、信用修订与FFT错误写入方案

### 18.1 SFO输出环小信用修改复核

`rtl/sfo/buffering/sfo_output_buffer.sv`当前SHA256为`428663E39F26245FBD80F50CDB67864D1BB9882317017835BBE54E77255E7371`。原64位issued-consumed组合减法已改为`$clog2(RESPONSE_DEPTH+1)`位信用寄存；64深度时为7位。更新与正常issued/consumed计数同处`!halted && bad==0`，按read_command/pop同拍增减/保持，reset清零；RAM发命令和两级rv不变。

健康不变量outstanding=issued-consumed由reset基例及四种同时事件逐拍保持，因此此修改不改变接受/返回/消费序列。故障边沿允许诊断计数停止保持，统一reset恢复；不能在故障状态继续用正常不变量声明成功。这一修改已经切断64位相减到RAM使能的确定组合链。

### 18.2 实际寄存边界与剩余路径

| 真实起点→逻辑→终点 | 域与边界 | 设计判断 |
|---|---|---|
| CFO input_count/状态寄存→s_ready→SFO output_buffer.pop→小信用/消费计数寄存 | 150MHz；CFO两项输入holding把r1_sr与外部s_ready隔离；SFO环s_ready来自占用/header信用，不组合依赖m_ready | 没有把FFT ready一直穿回E2 FIR的整链组合回压。不能再给s_ready随意延一拍，需维持两项holding容量。 |
| queue expected_beat/window_word/reserved及XPM full寄存→selected/qsample_ready→coarse_rotation.advance、coarse_fire→CFO URAM WE/queue FIFO写 | 150MHz；queue内ready未寄存，但依赖本地状态/full，不依赖r1数据比较；sample_good宽身份比较另行进入window FIFO WE | 确实存在一个本地ready扇出到旋转全流水CE及大bank WE；状态比较、扇出/布局是该路径的具体预算对象。 |
| FFT LOAD状态寄存→front.s_ready→queue.advance/issue→packed FIFO rd_en、output_valid/record CE | 500MHz；队列holding隔离数据lane mux，未隔离ready控制；return FIFO ready仅在sample2047加入 | 是本地2ns ready/CE路径，起终点可明确定位；其间没有多级其他算法ready。 |
| queue output_record寄存→frame32/gen32/window7/index11/last校验与错误优先级→FFT LOAD bank WE | 500MHz；`cfo_fft2048_core.sv:75–86`中间没有寄存 | 宽协议检查直接门控RAM写使能是确定结构问题；18.3给出两种不改健康数值的修正。不能因已有lane寄存就认为此路被切开。 |
| coordinate div_rem/div_num/div_den寄存→并行65位比较与65位减法→选择→div_rem寄存 | 150MHz；同一DIVIDE拍完成比较和条件减法 | 比较与减法可以并行，不能把源码条件表达式误解为两条串行carry链；末端选择与布局仍占本拍预算。可评估共享扩展减法的borrow，但需看映射，不能无依据声称已有串行两次进位。 |
| coordinate div_rem/div_quot寄存→round_up比较→48位rounded_quot加一→D_PHASE的48位取负→rne_down16再加一→m_phase0寄存 | 150MHz；这些ROUND/D_PHASE运算之间没有寄存 | 这才是明确多级串行算术。方案A分开round与phase寄存/状态并重新计Q；方案B先RNE down16再按符号取负32位结果，48位相位另算，利用RNE奇对称但必须保留原两次舍入的顺序和模2^32语义。不能把两个RNE直接合并。 |
| rotate phase/step寄存→phase+3*step→RNE地址进位→address0寄存 | 150MHz；后续ROM读取已有独立coef1寄存 | 3*step可能形成一段加法再与phase相加；可在cfg时预存lane偏移，或用四个独立相位累加器。两者均需保持模2^32顺序及相位RNE一致。 |
| rotate sum_i3/q3寄存→算术右移/RNE加一→正负饱和比较/选择→output4寄存 | 150MHz；乘积、加减和该舍入分别已有流水 | 不属于长跨模块ready问题，属于本级定点舍入/饱和逻辑预算；优化不能改变tie-even或饱和阈值。 |
| local_fault150寄存→local_stop150→SFO halted/CFO stopped/join cancel；SFO m_fault→remote_fault150→local_fault150寄存 | 150MHz；本域故障环有明确一拍寄存 | 没有组合环；保留一级锁存。复位/取消高扇出仍要在布局中核实，但不应重新改成等待125域往返。 |
| 多组tail计数/身份比较、backend身份匹配→detected_error优先级→fault/bank_state/done_q寄存 | 150MHz；done_q之后再写完成CDC | 完成CDC写使能不再穿过这些比较；比较到本地状态寄存仍存在，必须预算，不能误称全部tail检查已流水化。 |

### 18.3 500MHz LOAD校验到RAM写使能：两方案与方案B安全性

A：把完整样点、内部写地址、valid和校验结果增加一级寄存，再根据已寄存结果写RAM。需要相应处理最后输入与RUN首读边界、错误覆盖优先级，重新计入LOAD尾部服务。

B：LOAD有有效样点时允许将该字写入当前窗口RAM，不用input_error直接门控WE；保持控制always_ff中错误优先于末字转RUN。错误窗口的RAM视为废弃，后续错误结果/取消流程保持。B不增加寄存资源、不改健康窗周期或算术，能直接移除宽协议校验到RAM WE的路径。

独立核对B的成立条件：

1. `cfo_fft2048_core.sv:149`的`if(input_error!=0)`必须继续优先于150–152行末样点进入RUN；不能改为两个独立if。
2. LOAD写地址来自内部11位input_index的reverse11，错误的外部s_index不会成为RAM地址；最多修改当前窗一个合法内部地址，不能越界。
3. ERROR_HOLD没有LOAD/RUN/OUTPUT的RAM使能，错误当拍之后不会继续计算废弃窗；错误输出m_i/m_q清零且m_error非零，不从该RAM读出错误结果。
4. front第114–115行看到f_error会优先转HOLD并清地址/乘法valid和有效观测；link第72、101行把front_error编码且关闭帧，onchip最终停机。
5. 即使错误回传的CDC尚在传播，ERROR_HOLD被消费后核心短暂回LOAD，任何之后能合法进入RUN的窗口仍必须按内部index0..2047完整覆写所有2048地址；错误残字不能进入新的健康窗。因此安全性不依赖RAM reset或“CDC一定先停住”。
6. 外层`!rst && !abort_sync`门控必须保留，不能以移除input_error为由同时放开复位/取消写入。

方案B已由父Agent落地，独立复核git diff仅移除LOAD写使能中的input_error==0并补注释，复位外层门控及错误优先于末样点RUN保持。当前`cfo_fft2048_core.sv` SHA256为`7E08B542D9D26B3B2F53D28C45F460D75D724AD4DD8EB167AF95E5E42A9800CA`。宽校验到RAM WE路径已按结构切除；输入校验仍驱动控制/错误寄存器。本审查没有改RTL，也没有把改后500MHz时序宣称通过。

### 18.4 原资源与失败时序的可追踪来源

原始`work/OTA004/synth_a05/synth_utilization_hierarchical.txt:32`的coordinate为1089 LUT、862 FF、0 DSP；第45行FFT256为38673 LUT、10573 FF、0 BRAM、4 DSP；第78行自写FFT2048为734 LUT、867 FF、3 RAMB36+2 RAMB18、4 DSP。它们属于旧A05综合网表，不能作为当前双rotation、双bank和BRAM环的新分层资源。

`reports/OTA004/A06R3_ASTRA_REVIEW_ZH.md:28`保留125MHz+2.410ns、150MHz−2.358ns/2240失败、500MHz−1.279ns/347失败；当时具体150路径穿过CFO一致性算术到ready/存储使能，500路径穿过FFT索引、系数地址和BRAM选择使能。A07结果/系数地址寄存和本次局部修正改变了结构，不能用旧失败数字断言相同新路径仍失败，也不能无新证据宣布已通过。
## 19. 已落地ROUND_PRE/step3复核及当前源覆盖

本节再次只读核对根任务实际修改，非“建议待采用”：

- `cfo_coordinate_control.sv` SHA256 `4AAAF3FF56F5C3BE49571FBDC9FF7B11B42A61D32D425663F719C439F097E06C`：DIVIDE末迭代先寄存next_rem/next_quot并转ROUND_PRE，下一拍对已更新结果作RNE并存48位rounded_quot，随后ROUND按原顺序恢复符号/下舍入。三次除法各加一拍；正常核心435→438，调用方配置预算437→440。IDLE错误捷径、OUTPUT_RESULT保持与消费、reset/abort优先级没有改变。新增约48个RTL寄存位，六状态仍容纳于原3bit枚举。
- `cfo_rotate4.sv` SHA256 `32F334BEB4A2C7B043F27FB6C4CB948435D66F79CBF5B44B13C952A1793ED35A`：合法cfg时step3=cfg_step+(cfg_step<<1)，取低32bit，lane3使用phase+step3。等于原phase+3*step模2^32；其后phase_address的RNE保持。cfg_ready要求旧active=0、valid_pipe为空，该边沿s_ready不成立，因此首数据拍不会读到旧step3。reset清step3；每实例+32位寄存，两旋转共+64位。五级旋转和两级最终输出延迟不变。
- 第17节当前数字已经统一采用Q=440：Fmin334520、Fmax334992、Ccfg912、从首粗写到tail702978+G、Bout24610+G，槽公式不变。下面第20节尚未落RTL的backend建议不混入这些当前值。
- 第18.2表对被定位路径保留审查过程；FFT LOAD的宽校验到WE、coordinate remainder RNE到phase的跨级串算、lane3每拍乘3，已经分别由18.3和本节结构修改切开。ROUND后剩余48位取负→RNE、CORDIC等其他路径仍另列，不以局部修改冒充全核闭合。

### 19.1 当前生产源的实质覆盖表

以下为本审查领域的完整结构覆盖；“覆盖”表示读过所列状态、端口、运算/所有权边界，并非仅比较文件字节，也不等于物理/数值验收通过。

| 实际源或边界 | 已审内容 | 尚需保持的边界/动作 |
|---|---|---|
| control/sync_ota_top_v51.sv | 无背压端口、元数据和完成CDC、125/150故障回路、诊断冻结、busy输入占用 | 全链raw/SFO服务由对应审查并入；NI约束/CDC实现另验 |
| cfo/ota_cfo_chain_onchip.sv | 两bank四种所有权、C/F状态、同拍分配/估计/释放、独立旋转、coordinate owner、64读信用、尾拍完成 | 一般服务必须用第17节G合同；bank物理放置另验 |
| buffer/ota_cfo_window_queue.sv | 完整512字窗发布、8个跨帧信用、500域4lane串化/holding、尾packed退信用、poison锁存 | max8槽的G条件；500MHz本地ready/CE实现 |
| control/ota_sfo_context_join.sv | 三队列有序取头、两级检查/输出、214位布局、错误/取消与ready稳定 | 不支持乱序按身份搜索；错误全局停止合同 |
| cfo/cfo_coordinate_control.sv | 32轮乘/112轮除、两次RNE顺序、符号/原点、共享owner接收；ROUND_PRE实码 | 65bit compare/subtract并行选择及ROUND余下运算的实际路径 |
| cfo/cfo_rotate4.sv | cfg/active/pipe drain互斥、tag97/IQ128/sat对齐、握手推进相位、定点RNE/sat、step3等价 | DSP/双口ROM实际映射、剩余RNE/sat级；两个实例分别计资源 |
| cfo/cfo_front2048_window_a07.sv | FEED/WAIT_SUM/HOLD、系数基址与地址寄存、pilot选择、乘/加/RNE/累加流水、错误优先 | 500MHz累加/地址使能及ROM封装；系数的算法数值证据另列 |
| cfo/cfo_fft2048_core.sv | LOAD内部位反转地址、11级每1024蝶形、7级流水、OUTPUT预取、错误窗隔离与方案B | 数据RAM/ROM端口映射和500MHz路径；健康15449服务保持 |
| cfo/cfo_estimator_link_a06.sv | 171位观测CDC、单帧closed/toggle信用、双域复位握手、错误传播、结果消费返信用 | XPM约束加载与CDC实现；不能删closed握手套用纯74L吞吐 |
| cfo/cfo_estimate74_backend_a07.sv | phase/quality原子双消费、独立held结果、身份/非零一致性、阈值选择 | 后端尾部取两路max，不能相加；结果寄存不能回退为组合ready |
| cfo/cfo_phase74_core_v2.sv | 74观测身份与CORDIC、unwrap/OLS、75次除法、预测残差和中心判定、RESULT复用 | STORE/CORDIC/CENTER与常数乘的单拍路径已定位；20节给最小分拍方案 |
| cfo/cfo_fft74_quality_v2.sv | 最大值/指数、74真值+182零、FFT256喂数、power/peak/邻居扫描、两次除法、RESULT持有 | normalize、power、常数乘/末端判定路径已定位；新增power token须错误清空 |
| cfo/cfo_fft256_core.sv | LOAD/F_READ/F_MULT/F_ADD/F_ROUND/F_WRITE/O_READ/O_HOLD、地址/蝶形、逐级RNE与S20饱和 | 现有乘/加/round已分状态；多处同RAM读写导致旧映射0BRAM仍是资源重点 |
| cfo/cfo_divide_rne64.sv、cfo_divide_rne64wide.sv | signed numerator绝对值、64轮restore、tie-even、符号恢复、0分母及held结果 | DIVIDE比较和减法可并行；ROUND的加一→符号恢复64bit级可另加寄存，需计入调用次数 |
| common/ota_async_fifo_a06.sv | 实际选源、writer同步FIFO reset、双域reset完成、2FF Gray同步、FWFT | 非a06旧同名module不能混入；真实XPM CDC实现另验 |
| sfo/buffering/sfo_record_cdc_fifo.sv | 元数据/完成原子跨域、错误/ready/复位边界 | 完成125域必须持续运行，非无限停钟缓存 |
| sfo/buffering/sfo_sync_fifo.sv | FWFT、full/empty寄存边界、ready不组合依赖读ready | 64项信用包括在途，不能仅按XPM level发命令 |
| sfo/buffering/sfo_uram_frame_bank.sv | common_clock SDP、128bit、READ_LATENCY_B=2、read_first、深度/地址 | 真实URAM/BRAM宽深打包、级联与布局证据 |
| sfo/buffering/sfo_output_buffer.sv | 65536环+64响应、header身份、读命令退休、读写碰撞、累计计数、小信用修订 | 物理环高水位与total pending口径分开；第17节Bout/字等待 |
| sfo/control/sfo_domain_reset.sv | 异步断言/本域同步释放调用边界 | 外部reset脉宽及所有时钟运行由平台合同保证 |
| sfo/control/sync_sfo_top.sv、sfo_two_pass_transport.sv | 仅CFO连接边界：abort150、OUTPUT_CLOCK_MHZ150、E2→输出环、REQUIRE_CONTEXT_ACK、原始metadata | E1/E2/FIR/Farrow/稀疏窗内部由SFO独立审查完整覆盖，本报告不冒领 |
| control/ota_training_dispatch.sv、ota_stream_ingress.sv | 仅metadata帧代号/coarse/origin发布、输入段epoch、计数/空闲边界 | 前端/raw训练完整生命周期归对应独立审查 |
| rtl/sources_v51.f、Sync_OTA.xpr、wrapper/sync_ota_wrapper.vhd、constraints/sync_ota_clocks.xdc | 实际源选择、top、端口映射、三个真实时钟、历史TB隔离 | Wrapper原生编译、NI完整约束与实现尚无本轮证据 |

ROM方面已核对加载入口、宽度、索引/寄存与数学路径的连接；本次没有逐系数重新推导所有三角值，也没有宣称逐样点结果比较已执行。

## 20. 继续消除旧backend具体单拍长链的设计包（仅设计，尚未计入第17节实码常数）

根任务要求先给可审查的设计/代数/资源和服务预算；本节不修改RTL，不启动实验，也不越过任何批准边界。

### 20.1 phase支路：加拍可被观测间隔及并行后端余量吸收

- CORDIC两方案：A保持40bit动态shift→41bit加减→饱和的原单拍；B插入SHIFT寄存x/y移位结果，再在CORDIC做加减/饱和。B每观测增加24拍，观测处理仍远小最密4635拍；只有最后观测的24拍进入末端尾部，不能把74*24全部加到B。
- STORE两方案：A寄存完整unwrapped值、再乘weight、再累计；B将offset判决、unwrap加法、49bit乘积、56bit累计分成四边界。B较旧STORE每观测+3拍，尾部仅+3。weight/observation/angle/offset必须在新阶段保持同一身份；最终累计使用最后一次dot_term后才启动频率计算。
- CENTER两方案：A在原式末端增加乘缩放和abs两个寄存，EVAL仍作max；B先并行寄存`(res<<6)+(res<<3)`与`(res<<1)-sum`，再SUM、ABS、EVAL比较。B比原LOAD/EVAL额外3级*74=222尾拍，但每拍最多一项宽加减或取负/比较，避免把常数74的多个加法与abs/max重新串一拍。
- 频率常数乘两方案：A使用已计划的定宽流水常数乘并看DSP/综合映射；B在单帧末尾16轮signed72 shift-add计算dot_sum*15625。原dot范围检查`abs(dot_sum)<2^49`保证最后截取64位不丢有意义位；累加器/移位项保持有符号扩展，最后加法结果须寄存再送divider，不能把末轮adder组合接divider的绝对值级。采用B增加17拍（初始化/16轮与新请求相对旧握手的差），不占观测stream带宽。

原phase末观测到结果约5272拍；以上B全部选用时为5272+24+3+222+17=5538。即使其75次divider分别增加一个ROUND_PRE，总计再75拍为5613，仍小于下面quality的新6973拍。因此主导B不应把phase这些并行费用与quality费用相加。

### 20.2 quality支路：只为74个真样点加归一化状态，power保持流水吞吐

normalize方案A只注册z_ram后仍单拍完成动态shift/RNE/clamp；方案B为真样点执行N_READ(寄存z)→N_SHIFT(基值、guard/sticky)→N_ROUND(原RNE及clamp)→N_SEND。选B时每个真样点比原来多2拍，共148拍；182个补零仍N_READ直接给零→N_SEND，不走新算术状态。PREPARE先锁指数，再独立一拍预计算shift/guard/sticky mask，避免把优先编码与mask生成重新串成同拍；再加1拍。

power方案A增加F_COLLECT/P_SUM/P_WRITE三个串行状态，会给256个FFT输出逐个增加等待，影响B较大；方案B为accept平方寄存→point_power寄存→energy/peak/power_ram提交的II=1流水，不让FFT为每点等新状态。选B仅在最后FFT样点后等last_commit再开始S_READ，尾部+2拍。

power流水必须携带kind(normal energy/FFT power)、index、last及FFT audit所需原IQ；正常分支的饱和统计与audit仍按对应token更新。FFT身份/序号/错误或abort一旦触发，须清全部power valid，不能在RESULT held期间让旧token继续改变m_quality。last_commit之后才允许读取扫描RAM和用最终peak_bin，不能仅等最后FFT输入接受。

quality频率常数乘方案A采用显式寄存的常数乘流水；方案B对fractional_bin*500000000做29轮signed64 shift-add并寄存最终分子再请求divider。当前合法bin和delta使数学结果也落在signed64范围；即使从位向量角度看，64位串行累加也与原64位乘积模2^64严格相同。选B相对原F_START增加30拍。

因此上述主导尾部为6792+148+1+2+30=6973，增量181。可再给delta numerator/denominator、coherent最终比较准备寄存2–4拍，及两次wide divider ROUND_PRE各1拍，主导增量仍可收在187拍内。delta和coherent的常数移位加减不是“变量少就不用预算”；但不能把相互并行、已有PREPARE/MATH状态的费用误相加。

两核添加这些状态后可能超过16项，必须把原4bit枚举改为5bit；不可依赖工具默默截断枚举。已分拍的FFT2048乘→加→RNE→蝶形、FFT256 F_MULT/F_ADD/F_ROUND/F_WRITE、coordinate ROUND_PRE及旋转五级，当前没有仅因名称相似就继续叠流水的依据。

### 20.3 服务回代不能只看bank余量，还须看八槽

若主导quality尾部增加Delta，则B、E0、S均增加Delta，Fmin/Fmax不变：

    bank反馈余量 = 938-Delta
    槽上界 = 2+floor((G+23098+Delta)/4480)
    八槽整数充分条件 G <= 8261-Delta
    Bout <= 24610+Delta+G
    C2 nextcfg <= 359130+Delta+2*Lfir

Delta=187时，八槽要求G<=8074，不能仍机械沿用旧G<=8192。为代码实施预留整数预算Delta<=200，可冻结B<=7032、E0<=357050、S<=345416，同时要求实际vendor合同G<=8000（若G=66+Lfir，则Lfir<=7934）；这仍满足500MS/s，不是降低用户吞吐或精度。

该G/Lfir条件必须与实际固定IP服务对照，不能自造“通过的延迟”。若真实值超界，应选择更紧推导、进一步调度或增容量并重算，不可掩盖差额。计划分拍尚未实施时不得把这些新B数值混入“当前实码已证明”的报表。
### 20.4 计划新增资源的静态规模（不是综合报告）

phase可复用当前angle、observation、unwrap_offset和frame寄存，不必每级复制整份身份：CORDIC SHIFT约80FF；STORE持有unwrapped40+dot_term49约89FF；CENTER两条PAIR、SUM、ABS约256FF；72bit串乘acc+term+计数约149FF；状态扩宽约1FF，合计约575FF。若phase divider另加ROUND_PRE，再计64FF。

quality按保守64bit normalize临时值/guard/sticky/mask约336FF；power两级持有square/point_power及kind/index/last/audit IQ/valid约220–250FF；64bit串乘acc+term+计数约133FF；delta/coherent持有再预留约300FF，合计约1kFF量级。真实实现可按38bit输入及已证明的缩放范围收窄暂存，但不通过降精度省资源。

这些结构不要求增加BRAM/URAM。串乘用一次宽加法逐拍复用，不能将其FF增量与“新增多个宽组合乘法器”混为一谈；LUT、DSP、RAM真实映射与布线仍须实际综合报告，不能从上述RTL寄存位数直接宣称器件利用率。原FFT256异常LUT映射仍单独保留，不由此次pipeline自动解决。

## 21. 四个 backend 算术候选逐状态复核（尚未应用到生产 RTL）

本节审查 `reports/v51/pending_arithmetic/cfo_manifest.json` 的四个候选及对应 `*.sv.patch`。仅作源码和精确周期代数检查；没有仿真、综合、EDA 或生产文件改写。第20节是先前规划，本节以下实际候选数字覆盖其中5538/6973/Delta187等初算；第17节仍表示应用前生产代码常数，不得混淆。

| 候选 | SHA256 |
|---|---|
| cfo_phase74_core_v2.sv | 528199229C8B56DCD77CE280339C7614FD6089A55C55B0C6E18E815205413321 |
| cfo_fft74_quality_v2.sv | D2E76955CC010F082F7D18B8D1B059064B770F315D2FE04D72E68AF4C5C183E5 |
| cfo_divide_rne64.sv | D7C3ACCCA6FB5495776CA80DE5C8F70BD98EF1A9621CEFDBEA24EA199CA7FA09 |
| cfo_divide_rne64wide.sv | B2989E31DBA16B4550E33933071B6DBD7B18217F59DB1AE5810EB9E346321CCE |

### 21.1 phase 的位向量、状态与最后观测

- CORDIC_SHIFT保存同一iteration下的算术右移x/y；SHIFT不改变x/y/angle/iteration。因此随后CORDIC的y符号选择、41bit加减、饱和与角度更新和原实现一致。每观测多24拍；正常输入接受间隔由26变为53拍，仍远小于自写FFT每窗严格下界4608clk150，不产生观测队列新积压。
- STORE_OFFSET先依据旧previous_angle/unwrap_offset计算offset_next，再在STORE_PHASE使用已更新的offset。DOT阶段读取held_unwrapped和仍未改变的observation/weight；ACCUM最后才递增观测号。末次dot已写入dot_sum后才进入FREQ_START，因此末观测没有被遗漏。
- FREQ_START先检查原dot_bad范围，再把56bit有符号dot_sum扩成72bit。16轮累加正系数15625；最后使用当拍frequency_sum而非旧acc，寄存64bit分子后再请求除法。原范围abs(dot_sum)<2^49保证乘积落在signed64内；扩大中间位宽没有引入新截断或舍入。
- PRED_WAIT先保存成功的residual/quotient，PRED_STORE才写residual_ram并累计residual_sum，切断减法与后续累加串行路径。divider结果在WAIT被消费，STORE使用保持寄存，不依赖已变化的divider输出；最后residual_sum在CENTER读取前完成更新。
- CENTER_PAIR的两项 `(res<<6)+(res<<3)` 与 `(res<<1)-sum`，经SUM得到原 `74*res-sum` 的64bit模运算结果；ABS再取原绝对值。EVAL用当前magnitude和旧max两输入并行阈值比较，严格等价于max<=K；最终m_max仍使用含当前最后元素的maximum_next。
- reset/abort清空新增保持寄存及状态；正常RESULT期间没有后台流水继续修改输出。audit数值和对应index保持原意义，发布周期改变，不宣称周期对齐于旧audit。

不计新divider ROUND_PRE，最后观测于E0接受后：CORDIC/STORE在E52完成，频率除法E70接受/E136取回，74次预测最后PRED_STORE在E5242，74次五拍CENTER最终于E5612发布RESULT。旧尾5272，新增340=24+3+17+74+222。新divider每次再加1拍，频率1次+预测74次，故实际四候选组合的phase尾为5687clk150。

### 21.2 quality 的负数RNE、功率流水和错误冻结

归一化候选:76bit RAM输出先保存，再SHIFT同时保存算术移位结果及guard/sticky/奇偶决定，ROUND执行原+1，CLAMP执行原S20饱和。负值仍对算术右移后的floor商按原tie-to-even规则增1，没有改成对绝对值舍入。exponent合法范围[-21,16]；右移分支只在负指数时执行，normal_shift>=1，故不存在运行时读取guard[-1]。零/正指数走左移分支，inc=0。74个真样点各比原来多3拍，182个补零保持原N_READ/N_SEND两拍，额外总222拍。

功率路径为平方接收寄存→平方和寄存→RAM/peak或energy提交，II=1。kind/index/last/IQ/saturation随两级valid对齐；平方仍取同一S20输入、两个40bit平方之和仍为40bit，energy仍以48bit累计，FFT audit仍是原IQ40+power40。相同功率的峰值仍采用严格大于更新，索引0初始化，保持原tie选择。

最后FFT输出在t接受后，t+1得到平方和，t+2提交power_ram/peak并由F_DRAIN同拍切到S_READ。t+3才读第一个power；此时最终peak_bin和最后RAM写入已稳定一拍。没有提前扫描或漏计最后peak。归一化的最后energy项早在182个补零和FFT运算之前完成，不需要额外整段energy drain。

F_COLLECT发现FFT错误/身份错误时显式清power_v0/v1。该边沿旧v1可以提交此前已接受的有效token，随后RESULT首次可见时已冻结；不存在RESULT held期间继续修改m_quality。其他错误出口位于LOAD/PREPARE或扫描/除法后，功率流水本来为空；abort/reset最高优先清valid。错误时的部分诊断只描述截至停止的前缀，不能把它当作成功全帧数值结果。

MATH_PRE/MATH_SUM把coherent两边和delta两步减法分开，保留64bit位向量截断规则。F_PREP在delta_q16已更新后的下一边沿取fractional_bin；29轮unsigned64 shift-add计算同一常数500000000，按模2^64与原signed64乘法低64bit严格相同，再cast signed送divider。最后用frequency_sum寄存frequency_hold，无末位遗漏。各新枚举22状态用5bit覆盖。

### 21.3 两个 divider 的新边界

两个候选均在第64次DIVIDE之后进入ROUND_PRE；下一边沿读到已更新remainder/quotient，执行原inc和64bit+1并保存rounded，ROUND只做原有符号还原。零分母仍直接RESULT，符号极值的原模2^64行为未改。正常每调用+1拍；RESULT保压、clear优先级与s_ready保持。没有新增跨模块ready组合环。

### 21.4 quality 精确尾拍与实际服务常数

健康非零帧、delta分母>0（两次除法，最坏路径）、无输出结果等待，末观测E0接受后：

| 事件 | 候选周期 |
|---|---:|
| PREPARE / N_CONFIG | E1 / E2 |
| 最后一个真样点向FFT提交 | E372 |
| 第255号补零向FFT提交 | E736 |
| FFT最后一次蝶形写入 | E5856 |
| FFT最后输出接受 | E6368 |
| 最后功率/peak提交 | E6370 |
| 最后扫描S_EVAL | E6882 |
| MATH_PRE / MATH_SUM / MATH | E6883 / E6884 / E6885 |
| delta除法请求 / 结果接受 | E6886 / E6953 |
| frequency初始化 / 29轮累加 | E6954 / E6955..E6983 |
| frequency除法请求 / RESULT发布 | E6984 / E7051 |

quality尾6792→7051，实际Delta=259=222+1+2+2+30+2。phase尾5687不主导，不能把其额外费用叠加到quality尾上。正常观测接收quality仍可每拍接受LOAD_Z；phase II53不会拖慢相距至少4608拍的观测。

保留第17节的CDC/结果join等40拍余量、L4635、Q440、Fmin334520、Fmax334992、Ccfg912，四候选组合对应：

    B = 7051+40 = 7091
    E0 = 356850+259 = 357109
    S = 345216+259 = 345475
    S-N = 11395
    E0+Fmin-2S = 679 > 0
    e_k-b_k <= 368504+G
    d_k-b_k <= 703496+G
    occupied_slots <= 2+floor((G+23357)/4480)
    八槽充分整数条件 G <= 8002
    CFO输出环阻塞 Bout <= 24869+G
    已入环字等待 <= 90469+G
    C2 nextcfg <= 359389+2*Lfir  （仅替换本次CFO费用，其余沿用第17节SFO合同）

若父任务最新静态IP服务合同Lfir=72、G=66+72=138有效，则保守槽上界7，Bout<=25007，已接受字等待<=90607，首粗写→最终tail<=703634；context提前量<=1258时完整bank租约<=704892clk150<2T801792。CFO保守忙期服务P=N+V=359087，rho=334080/359087≈0.93036字/clk150，仍高于5/6。SFO新算术候选若另改E2或context服务，须由SFO审查另加对应项，不把这里的旧C2组合式直接当全新SFO总时长。

物理SFO环峰值仍按65536字，环外读响应至多64字，总pending<=65600<N；在无限长度但允许有限压缩的健康输入流下可能达到这个上限，不误报25007为已证明的整个环峰值。环满的合法回压每个E2帧最多一次vacation，沿用第17节的任意帧数归纳。

若父任务希望额外预留Delta300，则另列B7132、E0357150、S345516、bank归纳余量638、槽八槽条件G<=7961，工程取G<=7900成立。这些是预留，不能替代上面的代码实际Delta259。

### 21.5 静态关闭范围与物理检查剩余项

本次已把CORDIC barrel→add、STORE unwrap→multiply→accumulate、CENTER多层加减→abs→max、normalize读RAM→barrel→RNE→clamp、power平方→求和→累计、frequency常数宽乘→divider绝对值等串行大链拆开。它们不是通过减小数据位宽或改阈值取得的。

仍须授权后真实器件/约束下检查：CORDIC 41bit加减后饱和/累积计数，40x9 DOT乘的DSP映射，phase PRED_START 64bit移位差接divider初始绝对值，PRED_WAIT 64bit residual减法接范围判断，两divider ROUND_PRE比较→64bit增量及DIVIDE比较/减法并行后mux，quality 20x20平方与64bit串乘加法，normalize SHIFT barrel/guard/sticky，FFT256原RAM多端口推断和F_WRITE加/舍入/饱和路径。新增pipeline削减确定的串行级数，但不能替代物理时序、映射、完整核心资源、CDC约束与数值比较证据。

结论限于：四个候选的当前源码静态未见数值/末拍/保压/取消功能缺陷，服务预算闭合于明确G合同；不宣称候选已经应用，不宣称数值测试或实现时序已通过，也不跨越生产写入审批。

## 22. 用户批准后生产应用核对与12个CFO源覆盖（最终应用状态）

`pending_arithmetic/cfo_application.json`记录用户明确批准四份补丁、禁止启动仿真；应用时间为2026-09-18 01:43:13 Europe/Berlin（UTC+02:00）。本次独立只读复核逐一计算生产文件和对应候选SHA256，四者均同时匹配第21节已审候选及冻结manifest，不存在候选外修改。本审查人只更新本报告，没有修改RTL或重跑工具检查。

| 生产源（均在rtl/cfo） | 与已审候选/冻结SHA256 |
|---|---|
| cfo_phase74_core_v2.sv | 两项均匹配：528199229C8B56DCD77CE280339C7614FD6089A55C55B0C6E18E815205413321 |
| cfo_fft74_quality_v2.sv | 两项均匹配：D2E76955CC010F082F7D18B8D1B059064B770F315D2FE04D72E68AF4C5C183E5 |
| cfo_divide_rne64.sv | 两项均匹配：D7C3ACCCA6FB5495776CA80DE5C8F70BD98EF1A9621CEFDBEA24EA199CA7FA09 |
| cfo_divide_rne64wide.sv | 两项均匹配：B2989E31DBA16B4550E33933071B6DBD7B18217F59DB1AE5810EB9E346321CCE |

因此第21节的静态等价、phase5687/quality7051、B7091/E0357109/S345475、d-b<=703496+G、Bout<=24869+G及八窗G<=8002，现在适用于这四份实际生产代码。第17节原B6832/E0356850/S345216及第20节初步尾拍只是历史数字，不可继续作为最新代码预算。G138对应最坏7槽、Bout25007和首粗写至最终tail703634拍；该结论仍明确依赖上游有限服务合同。

同时只读核对现有`static_binding_07/summary.json`：pyslang11.0.0、top=sync_ota_top、candidate_overrides为空、diagnostics958、errors0。这是生产源绑定/类型检查结果；vendor是黑盒stub，XPM仅声明接口，未检查内部体或primitive映射。958条诊断不能写成“0警告”，0错误也不代表完整核心综合、实现时序或数值验证通过。本次未重复该检查。

### 22.1 当前sources_v51.f中全部12个rtl/cfo源的审查索引

以下覆盖表示实质设计/接口/状态/算术和服务分析，不是以文件哈希未变代替审查。原始源名中的a06/a07是复用版本名，实际选择以sources_v51.f为准。

| 源文件 | 本报告覆盖章节 | 已核对重点及仍需物理证据的边界 |
|---|---|---|
| cfo_rotate4.sv | 11.1、14.3、19及19.1、21.5 | 两个独立实例；cfg与active/流水排空互斥；97bit身份与128bitIQ、sat同步；按接受推进相位；step3模2^32等价；ROM/DSP及剩余RNE/sat映射另验。 |
| cfo_coordinate_control.sv | 11.1、14.2–14.3、17.2、19及19.1 | 共享owner和bank保存；两级SFO步长/原点及符号RNE；三次ROUND_PRE已应用；Q440、仲裁上界；65bit比较/减法和符号处理实际时序另验。 |
| cfo_front2048_window_a07.sv | 2、11.1、14.4、19.1 | FEED/WAIT_SUM/HOLD、系数基址、pilot选点、乘加/RNE/累加流水、末窗结果及错误优先；500MHz累加、地址和ROM端口仍需实现。 |
| cfo_fft2048_core.sv | 2、17.2、18.3、19.1 | 内部地址位反转、11层蝶形和7级流水、OUTPUT预取；15449窗口服务和15360严格下界口径；非法LOAD只写被废弃bank、不进入RUN；2ns真实映射/布线另验。 |
| cfo_estimator_link_a06.sv | 14.4、17.2、19.1 | 171bit原子观测CDC、closed/toggle帧信用、复位同步、错误传播、跨帧结果消费；一般S必须计74首窗与后73窗信用边界；真实CDC约束/MTBF另验。 |
| cfo_estimate74_backend_a07.sv | 14.4、19.1、21.4 | phase/quality原子双消费、独立held结果、身份/非零一致性和选择规则；结果稳定；尾按max(5687,7051)并计join余量40；局部控制扇出另验。 |
| cfo_fft74_quality_v2.sv | 19.1、21.2、21.4–21.5、22 | 指数、74真样点与182补零；负数RNE、CLAMP、II1功率token、末功率commit后扫描、coherent/delta和常数串乘、错误冻结；最终7051拍。 |
| cfo_divide_rne64wide.sv | 19.1、21.3–21.5、22 | 64bit分母restoring除法、tie-even、signed恢复、零分母和RESULT保压；新ROUND_PRE每正常调用+1；quality最多两次；宽carry物理路径另验。 |
| cfo_fft256_core.sv | 2、19.1、20.2、21.4–21.5 | 地址/蝶形F_READ/MULT/ADD/ROUND/WRITE及自然序输出，逐级RNE和S20饱和；8*128*5运算与256*2输出周期；旧0BRAM异常多端口RAM映射仍保留为资源重点。 |
| cfo_phase74_core_v2.sv | 19.1、21.1、21.4–21.5、22 | 74身份、CORDIC SHIFT、unwrap、weighted sum、16轮常数乘、75次除法、PRED_STORE、CENTER分拍及最后最大值；II53、最终5687拍。 |
| cfo_divide_rne64.sv | 19.1、21.3–21.5、22 | 32bit分母、64轮restoring、RNE和有符号恢复；ROUND_PRE数值不变，每次+1；phase75次总+75已计入；结果/取消稳定。 |
| ota_cfo_chain_onchip.sv | 14、15.2–15.5、16.2–16.4、17、19.1、21.4 | 双bank所有权、独立coarse/final状态、共享coordinate身份、64项读取信用、广播原子性、无背压两级record/sat输出；成功done需tail检查通过并用独立frame/generation；多帧bank/slot/vacation归纳使用最终常数。 |

CFO域依赖但不位于rtl/cfo的模块也有单独覆盖：`buffer/ota_cfo_window_queue.sv`见13、17.4、18；`common/ota_async_fifo_a06.sv`见13和19.1；`control/ota_sfo_context_join.sv`见9、15.5、19.1；顶层与SFO输出环边界见15–18。它们不重复计入上述12个CFO源，也不因此遗漏跨模块握手/取消路径。

最终限定结论：四份算术变更已按审查版本原样应用；本报告覆盖完整12个CFO源及相关缓存/CDC/顶层接口的静态设计。剩余真实器件综合/布局布线、原生vendor接口和CDC检查、数值及持续吞吐/板测证据仍分别未由本轮静态审查替代。

