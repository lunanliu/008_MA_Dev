# V5.1 接口与 Target VI 接线合同

当前生产源：`rtl/control/sync_ota_top_v51.sv`，模块 `sync_ota_top`；独立VHDL实体 `sync_ota_wrapper`。46端口直接一对一映射。当前只有静态接口检查，未运行原生VHDL编译或NI集成。

## 输出无背压

本合同采用用户的明确选择：后级由 LabVIEW Target VI 提供足够吞吐和冗余。核心无 `output_ready`、`m_ready`、`done_ready` 或中间DDR事务口；每个 `output_valid` 拍必须接收。固定两级输出寄存携带IQ、frame、generation、beat、last及内部饱和标志，不含外部停顿FIFO。

150 MHz峰值4个复样点/拍，即600 MS/s、19.2 Gb/s IQ；目标帧平均500 MS/s、16 Gb/s。每帧334080字，连续输出持续2.2272 ms。后级1280位打包属于Target VI；当前核心既不观察其ready，也不因其不足暂停。内部训练、FFT和bank读者仍有本地握手。

数据尾拍与成功通知分离：尾拍先传输，计数/身份与同拍已知错误检查通过后，在150域寄存64位完成身份，之后跨到125域发单拍 `frame_done125`。完成事件不依赖后级应答。发生epoch故障时已输出前缀无法撤销，接收方按frame/generation及fault丢弃受影响的未确认帧。

## 输入段、复位和使用顺序

1. 提供稳定的125/150/500 MHz时钟；统一复位高电平至少32个125 MHz周期是本版本保守接线要求。三个时钟在复位和工作期间均不得停转。释放后等待 `stream_ready`，不要假定固定等待一拍。
2. 在125域发送数据；仅 `stream_valid && stream_ready` 计一次输入，阻塞期间数据与first/last保持。首次字 `first=1`，段末字 `last=1`；单拍段可以二者同为1。valid暂时为0不产生样点，也不结束段。
3. 一个输入段可包含多个连续算法帧。独立段可预先排队，但前端先排空并重新初始化；不承诺不连续段之间零气泡。必须保留前导前至少172点原始保护区及确认帧尾所需样点；已确认窗口长度为334215字。最后候选的局部训练不完整可被拒绝，已确认完整帧缺尾则整epoch错误22。
4. 在150域逐拍接收最终IQ和标签；在125域记录完成事件与首错。不同域的多位诊断通过平台快照/异步FIFO搬运，不逐位同步。持续帧的成功完成仍需无epoch故障。
5. cancel是125域同步控制。取消/故障停止所有在途作业，不自动恢复；先保存诊断及已收帧身份，再统一reset。复位后frame/generation可从零重新编号，Host应开启新的采集epoch以免与上次记录混淆。

`busy125=0`只能在无fault且上游停止产生新字的条件下表示当前处理空闲；有fault时不要等待busy自动归零。上游刚在同一边沿接受的首字，要到该边沿寄存器更新后才能反映在busy中。

## 持续服务的输入合同

全链预算使用1336320复样点名义帧、实际物理SFO在±150ppm、每个真实帧至多一次成功确认、没有额外无界TO漂移：最短raw帧距334029个四点字，保守帧周期400834个clk150。此为物理输入条件，不由估计器范围或严格递增帧ID自动保证。超密假确认保留drop诊断，不承诺任意噪声输入均无候选丢弃。

三个时钟、正常固定配置FIR/FFT服务及各域初始化必须满足静态交付中冻结的合同；首次FFT配置完成前不接受真实FFT数据。独立段的初始化和排空不属于连续段内的零气泡承诺。当前周期/缓存数值是设计上界，不是仿真或上板测量。

## 端口表

| 端口 | 方向 | 位宽 | 时钟与含义 |
|---|---|---:|---|
| `clk125` | 输入 | 1 | 输入、前端、初始/残余SFO控制；8 ns |
| `clk150` | 输入 | 1 | 共享缓存、两次重采样、CFO旋转、最终输出；6.666666667 ns |
| `clk500` | 输入 | 1 | FFT工作域；2 ns |
| `reset_request` | 输入 | 1 | 统一高有效复位；三个时钟持续运行，域内同步释放 |
| `cancel` | 输入 | 1 | 125 MHz 同步取消；终止整个在途epoch，撤销后仍需统一复位 |
| `stream_valid` | 输入 | 1 | 125 MHz；仅valid&&ready接受 |
| `stream_ready` | 输出 | 1 | 125 MHz；仍须遵守输入握手 |
| `stream_data` | 输入 | 128 | 125 MHz；4×32位复IQ，最低lane最早，每lane低16位I/高16位Q，二补码S16 |
| `stream_first` | 输入 | 1 | 125 MHz；独立传输段第一拍为1，握手前保持 |
| `stream_last` | 输入 | 1 | 125 MHz；独立传输段末拍为1，握手后才结束；与算法帧无关 |
| `read_done` | 输入 | 1 | 125 MHz；信息输入，不参与段结束判定，不能替代stream_last |
| `output_valid` | 输出 | 1 | 150 MHz；每个高电平拍均无条件传输，不接受后级背压 |
| `output_data` | 输出 | 128 | 150 MHz；4×S16复IQ，布局同输入 |
| `output_frame` | 输出 | 32 | 150 MHz；算法帧ID |
| `output_generation` | 输出 | 32 | 150 MHz；输入段generation |
| `output_beat` | 输出 | 32 | 150 MHz；帧内字号0..334079 |
| `output_last` | 输出 | 1 | 150 MHz；beat334079；只表示数据尾拍，成功还须对应frame_done且无fault |
| `busy125` | 输出 | 1 | 125 MHz；输入/段未结束、已创建帧未完成或同步CFO忙；故障后可能保持1 |
| `fault125` | 输出 | 1 | 125 MHz；整epoch粘滞故障，只能统一复位清除 |
| `error125` | 输出 | 8 | 125 MHz；首个顶层错误，下面列分类 |
| `ingress_stage125` | 输出 | 3 | 125 MHz；0空闲/1初始化/2输入/3排空/4段关闭 |
| `accepted_words125` | 输出 | 64 | 125 MHz；实际同时转交前端和raw的字数，不是上游刚进入128字FIFO的计数 |
| `frames_created125` | 输出 | 32 | 125 MHz；已发布raw租约数，跨段累计 |
| `segments_started125` | 输出 | 32 | 125 MHz；已启动段数，跨段累计 |
| `segments_completed125` | 输出 | 32 | 125 MHz；前端排空且终端floor已发布的段数，不等于该段所有算法帧输出完成 |
| `frame_done125` | 输出 | 1 | 125 MHz单拍；经过尾拍校验及完成CDC，当前已知故障/取消优先；无done_ready |
| `done_frame125` | 输出 | 32 | 125 MHz；最近从完成FIFO取出的帧ID，frame_done高时读取 |
| `done_generation125` | 输出 | 32 | 125 MHz；最近完成FIFO记录的generation |
| `completed_frames125` | 输出 | 32 | 125 MHz；实际取出完成记录数；epoch故障后不得独立用它判成功 |
| `frontend_candidates125` | 输出 | 32 | 125 MHz；当前/最近输入段候选数；正常镜像延迟1拍，故障冻结 |
| `frontend_rejected125` | 输出 | 32 | 125 MHz；当前/最近段质量拒绝数；故障冻结 |
| `frontend_dropped125` | 输出 | 32 | 125 MHz；当前/最近段容量/历史/末尾不足丢弃数；故障冻结 |
| `frontend_confirmed125` | 输出 | 32 | 125 MHz；当前/最近段确认数；故障冻结 |
| `frontend_error125` | 输出 | 16 | 125 MHz；live前端错误镜像并在poison前冻结；006f掩码为fatal，位4/7为诊断 |
| `sfo_error125` | 输出 | 8 | 125 MHz；SFO控制域错误 |
| `sfo_error150` | 输出 | 8 | 150 MHz；SFO数据域错误 |
| `context_error150` | 输出 | 8 | 150 MHz；锁存的首个上下文配对错误 |
| `cfo_error150` | 输出 | 8 | 150 MHz；CFO首错 |
| `coarse_beats150` | 输出 | 32 | 150 MHz；跨帧累计粗旋转接受字数，32位自然回卷 |
| `final_beats150` | 输出 | 32 | 150 MHz；跨帧累计实际输出字数，32位自然回卷 |
| `coarse_saturations150` | 输出 | 32 | 150 MHz；跨帧累计I/Q饱和次数 |
| `final_saturations150` | 输出 | 32 | 150 MHz；跨帧累计最终I/Q饱和次数 |
| `cfo_window_words150` | 输出 | 13 | 150 MHz；XPM窗口字占用遥测，有状态可见延迟，不能用于逐字信用判定 |
| `cfo_windows150` | 输出 | 7 | 150 MHz；当前/最近配置帧已捕获窗口数 |
| `cfo_result150` | 输出 | 499 | 150 MHz；最近499位估计记录，自带frame/generation；不是done帧原子快照 |
| `sfo_diagnostic150` | 输出 | 256 | 150 MHz；既有SFO诊断总线；多位跨域读取须快照/CDC，不可逐位同步 |

## 顶层首错与诊断

- 01：用户取消；02：入口FIFO异常。
- 10/11/12：前端结果epoch/status、原始坐标或频率/ID范围不合法。
- 20/21/22/23：输入段first协议、字序/计数、确认帧缺尾或非法状态。
- 30：前端致命错误；读 `frontend_error125`，位0检测计算、位1期限、位2协议、位3算术/IP、位5历史越界、位6估计结果失败。位4历史不足和位7段尾训练不足为候选诊断，不直接终止epoch。
- 40：SFO控制错误；60：元数据或完成CDC异常；80：150域故障上报。更具体原因查看相应模块错误口。

计数器与`cfo_result150`是状态观测，不是自动配对的一帧报告。46端口位宽与完整映射见 `reports/v51/final_static/wrapper_ports.json`。历史A07 Wrapper保存在 `wrapper/history`，不能与V5.1新顶层混接。
