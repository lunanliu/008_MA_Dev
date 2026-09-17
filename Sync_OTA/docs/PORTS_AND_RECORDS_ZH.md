# OTA 核心/Wrapper 完整端口合同

器件xcvu11p-flgb2104-2-e；默认算法综合顶层sync_ota_top。独立sync_ota_wrapper仅接线，不生成时钟、不实现DDR/DMA、不注入参考答案。

所有非时钟输入上电先置0，reset_request按顺序置1；s_valid/start_valid/cancel/done_ready必须由125MHz域驱动，m_ready由150MHz域驱动。所有核心寄存器在协调复位后初始化；计数/结果仅在本文所列阶段有意义。两个时钟域的诊断不可直接当成同步总线跨域读取：Target在各自域锁存，握手后再用平台CDC/DMA送Host。

Wrapper将非1bit宽度向上扩展到8/16/32/64bit；大于64bit按w0、w1...从最低位分块，尾块也按8/16/32/64补齐。输入填充位写0，输出填充位恒0。精确逐位映射见CORE_WRAPPER_PORT_MAP.json及WRAPPER_PORTS.csv。

|核心端口|方向/位宽|域|Wrapper端口|格式、复位/设值及有效条件|
|---|---|---|---|---|
|clk125|input/1|clock|clk125[1]|NI提供125MHz连续时钟；控制/捕获/外部DDR口。|
|clk150|input/1|clock|clk150[1]|NI提供150MHz连续时钟；重采样输出及CFO。|
|clk500|input/1|clock|clk500[1]|NI提供500MHz连续时钟；内部FFT服务。无需把Host放入500MHz循环。|
|reset_request|input/1|platform async assertion; local synchronous release|reset_request[1]|平台全局复位，高有效；先启动全部时钟，保持至少200个125MHz周期。仅在NI已停止/排空旧DDR事务后使用。|
|start_valid|input/1|clk125|start_valid[1]|配置请求；与start_ready同沿为1时采纳，未就绪保持参数不变。|
|start_ready|output/1|clk125|start_ready[1]|可接新配置；只有IDLE、CFO空闲、DDR桥初始化/排空且无桥错误才为1。|
|capture_base_word|input/64|clk125|capture_base_word[64]|无符号64位，单位128bit字；对应字节地址=值×16，NI须检查实际DDR范围。|
|capture_words|input/32|clk125|capture_words[32]|无符号32位，1..524288个128bit字；固定本次接收长度。0/超限/基址加容量回绕报10。|
|cancel|input/1|clk125|cancel[1]|125MHz高至少1周期；中止当前帧并排空已接受DDR信用，等待done；不复位DDR桥。|
|s_valid|input/1|clk125|s_valid[1]|原始IQ输入有效；与s_ready同沿为1才计一拍。|
|s_ready|output/1|clk125|s_ready[1]|CAPTURE阶段可接受；等待DDR ACK时可为0。|
|s_data|input/128|clk125|s_data_w0[64], s_data_w1[64]|128bit=4复数点，lane0为最低32bit且最早；每点低16=I、高16=Q，S16/Q1.15。保持到握手。|
|done|output/1|clk125|done[1]|本会话完成或已安全取消；保持到done_ready。先检查error125。|
|done_ready|input/1|clk125|done_ready[1]|Host已读取计数/错误/结果后为1一个125MHz周期；随后等待start_ready。|
|busy|output/1|clk125|busy[1]|非IDLE为1，包括完成待确认。|
|stage125|output/6|clk125|stage125[8]|无符号状态枚举，见下表；不是样点序号。|
|error125|output/8|clk125|error125[8]|会话首错8bit，0表示未检测错误；01取消、10配置、23/24 raw存储、30前端未得结果、31..34描述符、50算法、51处理阶段保护、72 DDR桥。结合分项首错。|
|accepted_words125|output/32|clk125|accepted_words125[32]|当前捕获接受的128bit拍数；start时清0；done时应=capture_words（正常）。|
|committed_words125|output/32|clk125|committed_words125[32]|raw写ACK计数；正常捕获完成=capture_words。|
|replay_words125|output/32|clk125|replay_words125[32]|当前/最近一次raw回放已消费拍数；正常最终预装=334215。|
|raw_stalls125|output/32|clk125|raw_stalls125[32]|raw命令或回放输出背压周期累计；32bit，仅作诊断。|
|frame125|output/32|clk125|frame125[32]|实际前端分配帧号，经descriptor绑定；非Host输入。取消清除descriptor时可为0，失败身份以保留frontend_record为准。|
|generation125|output/32|clk125|generation125[32]|raw租约派生generation；与本帧数据绑定。平台全局复位后重新从1开始；不能混入复位前事务。|
|nominal_absolute125|output/64|clk125|nominal_absolute125[64]|相对本次捕获第0样点的64bit名义起点，fine绝对位置向下对齐4；不是DDR地址。|
|frontend_record125|output/288|clk125|frontend_record125_w0[64], frontend_record125_w1[64], frontend_record125_w2[64], frontend_record125_w3[64], frontend_record125_w4[32]|首个实际前端结果的288bit保留记录：epoch32/frame32/candidate32/coarse_abs64/fine_abs64/coarse_Hz32/quality16/status16。|
|ddr_cmd_valid|output/1|clk125|ddr_cmd_valid[1]|DDR命令有效；valid&&ready只接受一次。|
|ddr_cmd_ready|input/1|clk125|ddr_cmd_ready[1]|NI适配器能保存一个完整命令及tag时为1；不能先ACK写入再丢数据。|
|ddr_cmd_write|output/1|clk125|ddr_cmd_write[1]|1写/0读。|
|ddr_cmd_address|output/64|clk125|ddr_cmd_address[64]|无符号64bit，128bit字地址；NI换算×16为字节，检查物理容量。|
|ddr_cmd_tag|output/65|clk125|ddr_cmd_tag_w0[64], ddr_cmd_tag_w1[8]|65bit不透明事务标签，原样回送；bit64归属，低64含lease/serial。不得自行重编号。|
|ddr_cmd_data|output/128|clk125|ddr_cmd_data_w0[64], ddr_cmd_data_w1[64]|写入128bit数据；读命令时忽略，命令受阻期间保持。|
|ddr_rsp_valid|input/1|clk125|ddr_rsp_valid[1]|回应有效；与rsp_ready同沿为1才收走。每个命令必须有一次匹配回应，最早在命令接受下一周期。|
|ddr_rsp_ready|output/1|clk125|ddr_rsp_ready[1]|核心能接受回应；回应未被收走前NI保持tag/data/error。陈旧tag会被计错且不释放当前信用。|
|ddr_rsp_tag|input/65|clk125|ddr_rsp_tag_w0[64], ddr_rsp_tag_w1[8]|完整回送原65bit命令tag。|
|ddr_rsp_data|input/128|clk125|ddr_rsp_data_w0[64], ddr_rsp_data_w1[64]|读命令返回128bit；写ACK该数据忽略。|
|ddr_rsp_error|input/1|clk125|ddr_rsp_error[1]|匹配事务失败=1；数据不得作为有效输入。NI仍须返回应以排空信用。|
|ddr_idle125|output/1|clk125|ddr_idle125[1]|桥无在途/待发命令且返回FIFO已排空、初始化完成。还需控制器/CFO结束才能重用区域。|
|ddr_error125|output/8|clk125|ddr_error125[8]|平台复位前保留：71陈旧tag、72桥FIFO异常、7f非法状态；非0阻止新配置。|
|ddr_commands125|output/32|clk125|ddr_commands125[32]|平台复位以来外部接受命令数，32bit诊断。|
|ddr_responses125|output/32|clk125|ddr_responses125[32]|平台复位以来匹配回应数，32bit诊断。|
|ddr_stale125|output/32|clk125|ddr_stale125[32]|平台复位以来陈旧/不匹配回应数。|
|ddr_request_level125|output/6|clk125|ddr_request_level125[8]|CFO请求FIFO在125MHz读取侧占用；0..32。|
|ddr_response_level125|output/6|clk125|ddr_response_level125[8]|CFO回应FIFO在125MHz写入侧占用；0..32。|
|m_valid|output/1|clk150|m_valid[1]|150MHz最终输出有效；与m_ready同沿为1才计拍。|
|m_ready|input/1|clk150|m_ready[1]|150MHz下游有空间时1；暂停时完整record保持，Host应并行持续读DMA。|
|m_record|output/225|clk150|m_record_w0[64], m_record_w1[64], m_record_w2[64], m_record_w3[64]|225bit={frame32,generation32,beat32,last1,IQ128}。正常334080拍，beat=0..334079，仅最后last=1。|
|cfo_stage150|output/5|clk150|cfo_stage150[8]|CFO内部阶段0..17，见架构/RTL；正常Host done时可能已回IDLE。|
|cfo_error150|output/8|clk150|cfo_error150[8]|保留实际CFO首错直到下一正式metadata：01取消、20/21外存、30/31两旋转、40坐标、60后端、ff内部状态。|
|coarse_beats150|output/32|clk150|coarse_beats150[32]|粗CFO输出被外部store接收的拍数；正常334080。|
|final_beats150|output/32|clk150|final_beats150[32]|最终输出与m_ready握手拍数；正常334080。|
|coarse_saturations150|output/32|clk150|coarse_saturations150[32]|粗旋转I/Q发生S16饱和的分量个数；不是复数点个数。|
|final_saturations150|output/32|clk150|final_saturations150[32]|第二次旋转的S16饱和分量数，单独统计。|
|observation_windows150|output/7|clk150|observation_windows150[8]|已送完样点流的窗口数，正常74；不是独立观测值计数，估计valid须另查cfo_result。|
|cfo_result150|output/499|clk150|cfo_result150_w0[64], cfo_result150_w1[64], cfo_result150_w2[64], cfo_result150_w3[64], cfo_result150_w4[64], cfo_result150_w5[64], cfo_result150_w6[64], cfo_result150_w7[64]|实际499bit估计结果；成功/失败记录保留，见字段表；新CFO上下文或全局复位清除。|
|cfo_committed150|output/32|clk150|cfo_committed150[32]|粗CFO写ACK计数，正常334080。|
|cfo_read150|output/32|clk150|cfo_read150[32]|当前/最近回放消费计数；窗口阶段512，最终回放334080。|
|cfo_stalls150|output/32|clk150|cfo_stalls150[32]|CFO store命令或输出背压累计周期。|
|cfo_window_fifo_level150|output/6|clk150|cfo_window_fifo_level150[8]|150->500窗口样点FIFO写侧占用，0..32。|
|cfo_observation_fifo_level150|output/5|clk150|cfo_observation_fifo_level150[8]|500->150观测FIFO读侧占用。|
|cfo_fifo_error150|output/4|clk150|cfo_fifo_error150[8]|4bit sticky：bit0窗口写overflow、bit1窗口读underflow、bit2观测写overflow、bit3观测读underflow。正常0；新正式CFO context清零。|
|sfo_error125|output/8|clk125|sfo_error125[8]|保留SFO125控制首错，下一start清0。|
|sfo_error150|output/8|clk150|sfo_error150[8]|保留SFO150传输/处理首错，下一metadata清0。|
|context_error150|output/8|clk150|context_error150[8]|正式SFO/CFO上下文首错：41第一context身份/step不合法、42第二context不匹配；下一metadata清0。|
|sfo_diagnostic150|output/256|clk150|sfo_diagnostic150_w0[64], sfo_diagnostic150_w1[64], sfo_diagnostic150_w2[64], sfo_diagnostic150_w3[64]|256bit SFO传输诊断快照，实际属于150MHz；见字段表。|
|sfo_monitor125|output/512|clk125|sfo_monitor125_w0[64], sfo_monitor125_w1[64], sfo_monitor125_w2[64], sfo_monitor125_w3[64], sfo_monitor125_w4[64], sfo_monitor125_w5[64], sfo_monitor125_w6[64], sfo_monitor125_w7[64]|512bit观测快照，125MHz更新；只用于监测，算法配置使用正式context。取消复位时保留最后观测。|
|sfo_monitor150|output/512|clk150|sfo_monitor150_w0[64], sfo_monitor150_w1[64], sfo_monitor150_w2[64], sfo_monitor150_w3[64], sfo_monitor150_w4[64], sfo_monitor150_w5[64], sfo_monitor150_w6[64], sfo_monitor150_w7[64]|512bit观测快照，150MHz更新；正常完成至done确认保留，取消复位时冻结最后观测。|
|first_step150|output/32|clk150|first_step150[32]|实际E1发动机启动握手锁存的无符号Q28步长；有效在E1正式启动后。|
|second_step150|output/32|clk150|second_step150[32]|实际E2启动握手锁存的无符号Q28步长；有效在E2正式启动后。|
|frontend_accepted_samples125|output/64|clk125|frontend_accepted_samples125[64]|前端扫描实际接受样点数，每拍+4；找到首个结果后可停止前端喂数，故不必等于整次capture样点数。|
|frontend_candidates125|output/32|clk125|frontend_candidates125[32]|当前前端会话候选数。|
|frontend_rejected125|output/32|clk125|frontend_rejected125[32]|当前前端会话拒绝数。|
|frontend_drop125|output/32|clk125|frontend_drop125[32]|候选捕获丢弃数，正常目标0；与raw Host接受计数不同。|
|frontend_duplicate125|output/32|clk125|frontend_duplicate125[32]|当前前端会话重复候选数。|
|frontend_confirmed125|output/32|clk125|frontend_confirmed125[32]|当前前端会话确认数。|
|frontend_error125|output/16|clk125|frontend_error125[16]|前端错误标志；session_start/abort会清理其内部会话状态。|

## 状态/打包字段

stage125：0 IDLE、1 OPEN、2 CAPTURE、3 SEAL、4 SCAN_START、5 SCAN_REQUEST、6 SCAN、7 WAIT_FRONTEND、8 ADAPT、9 ADAPT_WAIT、10 PRELOAD_BOOT、11 PRELOAD_REQUEST、12 PRELOAD、13 RELEASE_RAW、14 PUBLISH、15 PROCESS、16 DONE_WAIT、17 COMPLETE、18 CANCEL_DRAIN、19 CANCEL_RELEASE。

每个IQ beat中lane n位于[32*n+31:32*n]。二进制文件按little-endian UInt32顺序存最早样点；字内I低16/Q高16，Q1.15。DDR和最终输出均保持这个样点顺序。

m_record：IQ[127:0]；last[128]；beat[160:129]；generation[192:161]；frame[224:193]。Wrapper的w2 bit0=last、bits32:1=beat、bits63:33=generation低31位；w3 bit0=generation最高位、bits32:1=frame，其余0。

cfo_result150：frame[498:467]，generation[466:435]，error[434:431]，mode[430:429]，estimate_valid[428]，最终Hz S32/F16[427:396]，phase估计Hz S32/F16[395:364]，FFT估计Hz S32/F16[363:332]，spectrum/linear/consistent[331:329]，质量[328:132]，详情[131:0]。必须联合error=0及estimate_valid=1解释频率；mode不能单独当通过标志。

sfo_diagnostic150从低到高每32bit：bank0写stall、bank1写stall、E1周期、E2周期、bank0 outstanding峰值、bank1 outstanding峰值、输出缓存峰值、raw缓存峰值。它原本就是150MHz信号；本顶层没有把它直接假称125MHz。

|32bit槽（低位为0）|sfo_monitor125|sfo_monitor150|
|---|---|---|
|0|raw接受beat|E1接受beat|
|1|状态位：fault/qbusy/initial_halted/seen2/seen1|E2接受beat|
|2|首次估计S32/Q18 ppm|输出送CFO接受beat|
|3|首次quality/status|正式E1 step|
|4|首次frame|正式E2 step|
|5|残余估计S32/Q18 ppm|E1周期|
|6|残余step Q28|E2周期|
|7|残余frame|output/E2/E1/raw首错|
|8|残余generation|bank1/bank0/150首错|
|9|首次估计elapsed|raw峰值|
|10|FFT output/input计数|输出峰值|
|11|weight/observation计数|halt/bank提交/阶段位|
|12|残余结果高详情|raw累计写|
|13|残余point计数|bank0消费计数|
|14|残余请求计数|bank1消费计数|
|15|细节/initial_error/125error|输出占用|

首次估计和残余估计的数值槽仅在seen1/seen2与对应状态有效时解释。快照是监测用途；不构成Host向核心反向填写估计值的接口。
