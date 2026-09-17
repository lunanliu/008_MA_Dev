# CLIP时钟、端口与板测步骤

当前最终交接：handoff/Sync_Frontend_20260915_manual/README_ZH.md。完整工程 top=sync_frontend_top；独立 VHDL 与测试数据见该交接目录。CLIP XML/配置由用户手工创建，旧 rev01/rev02 自动包不作为最终使用入口。

唯一逻辑时钟clk125=125MHz，由NI提供并在SCTL中选同一时钟。核心与OOC包装网表未实例化MMCM/BUFG；独立布局阶段插入5个控制网络BUFG，不构成新采样时钟域，没有500MHz逻辑域。所有数据/控制必须在该时钟域；reset_n可异步拉低，内部两级同步释放。保持reset_n低至少4个时钟，释放后等待input_ready，不能仅按固定延时假定初始化完成。

VHDL顶层sync_frontend_clip；所有端口/宽度/方向和含义见 handoff/Sync_Frontend_20260915_manual/ports.json；XML 由用户根据此接口在 LabVIEW 手工创建。输入input_data0时间最早，各U32为Q16高半字/I16低半字，均二补码。input_valid与input_ready同时为1才接受全部四点；valid等待时数据保持，不能逐lane接收。加载块边界不发送session_start；valid空拍表示暂停，不改变相邻有效样点的关系。

session_start、session_abort、stream_gap均为单拍控制。start开始新连续代次；abort丢弃在途状态并关闭接收；gap声明真实采样丢失，丢弃旧代次并重新预热。它们不能每拍保持高，否则epoch每拍增加并持续清空。每次边界的当前拍不接受输入，epoch内样点计数从0重启。不可反压源在input_ready低时丢数据必须由采集桥明确标记gap；前端不能知道未呈现的采样点。

result_valid时原子读取result_epoch/rx_frame_id/candidate_id/coarse_absolute/fine_absolute/cfo_hz/quality_q1_15/result_status，再拉result_ready确认。ready低时字段保持。rx_frame_id是本机确认顺序，每代次从0开始；candidate_id包含拒绝候选所以不连续。CFO单位Hz，I32带符号；quality为Q1.15；status高半字类型3、bit11有效。有效短测试记录status=0x3800。

粗/精absolute以该epoch第一次接受样点为0，精TO含lane内落点，不能除4后丢掉余数。live诊断不是result握手快照：accepted_samples、epoch、candidate_count、rejected_count、capture_drop_count、duplicate_count、confirmed_count及slot占用均是当前时刻；跨时钟读取这些量需要统一快照消息。

error_sticky位：0连续度量算术/IP异常；1原粗/精deadline；2原粗/精协议/服务异常；3原核算术/IP异常；4历史龄期容量拒绝；5实际历史读过期或读未来；6worker无结果超时。计数/错误按epoch清零，读取错误后应保留上位机诊断再重启。capture_drop_count记录容量/复制忙拒收，即使error_sticky为0也不是无限捕获资格。

板测最小流程：
1. 用户根据独立 VHDL 和自行导出的核心网表在 LabVIEW 创建 CLIP 声明；配置时钟为125MHz，生成NI工程的真实器件为xcvu11p-flgb2104-2-e。先做NI完整编译，检查时钟/CDC、资源及所有时序，不搬入standalone_io_budget.xdc。
2. 复位并等待ready。从sim/data/autonomous_stream.mem每行四个U32连续装载；每256行暂停8000个125MHz时钟以重现已验证加载条件。truth文件不进入硬件。不中途复位，sink每条结果故意暂停128拍。
3. 记录四条结果，预期(epoch,id,fine,CFO)=(0,0,15004,-150022),(0,1,26373,0),(0,2,37842,150022),(0,3,49311,-149977)。允许CFO与注入真值的差不超过1000Hz；精TO必须逐点相等。参考quality为29212/32768/28791/28348。
4. 核对accepted_samples=60324，confirmed_count=4，候选13、算法拒绝1、drop4、去重4、slot峰值2、max_history_age=4336，error_sticky=0。板端若传输节奏变化，服务/drop计数可能不同；原生对照须先复现节奏，不能改计数门掩盖真实丢失。
5. 再验证中途gap、abort/start以及reset，确认旧代次结果不泄漏；最后再设计真实ADC连续输入及DMA/DRAM压力验证。这些NI平台/硬件步骤由用户执行，尚未通过。
