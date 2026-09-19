# Vivado2021.1 XPM参数兼容性独立审查

审查日期：2026-09-18，Europe/Berlin（CEST，UTC+02:00）。已只读确认保存的failed_synth_runme.txt第1112行为Synth 8-281 expression must be of a packed type，定位安装版xpm_memory.sv:8496的P_MEMORY_PRIMITIVE；随后Synth 8-6156沿XPM、frame_bank、shared_raw、hub和SFO层级传播。本人只读检查实际安装XPM及生产调用链，未重跑综合/仿真；该首错不能再用此前黑盒静态绑定零错误来否认。

## 1 根因和完整影响链

实际安装文件C:/NIFPGA/programs/Vivado2021_1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv的SHA256为E72758E6794B1F7AD00428FEEEACC4F90A38B0500583B2CA93CA2EBA12BA01BD。其sdpram入口采用无显式类型的parameter MEMORY_PRIMITIVE="auto"，P_MEMORY_PRIMITIVE却同时比较MEMORY_PRIMITIVE==1/2/3/4与若干文字别名。这是为整数码和packed文字常量兼容而写的接口；把显式SystemVerilog string参数直接传入后，原本合法的packed/integer比较变成string与integer混合，Vivado在参数常量展开时拒绝。逻辑OR中存在另一个正确文字条件不使非法操作数类型自动合法。

初读生产sfo_uram_frame_bank:4为parameter string MEMORY_PRIMITIVE="ultra"，:33原样传XPM，是直接触发桥。另一个生产sfo_output_buffer:5也声明相同string并传给bank。仅改bank为untyped不足以完整处理影响链：其override可以继续从output_buffer继承string类型；两处都应修复。本项已在审查中即时通知父任务。

## 2 两方案与不变量

| 方案 | 静态结果与取舍 |
|---|---|
| A：两个自写MEMORY_PRIMITIVE参数均去掉显式string，保留同一文字默认值/调用 | 首选。当前全部调用是5字符ultra或block，推断packed文字，与安装XPM入口惯例匹配；差异最小，没有新增硬件或控制状态。 |
| B：保留上层string，在bank边界转换为明确packed[39:0]的ultra/block常量，或generate两个文字参数实例 | 对当前两值可行；需显式处理不支持值，避免静默选择错误primitive。generate会复制实例配置文本，维护时更易不一致；没有本轮需要保留强类型API的证据，故不首选。 |

已枚举全部RTL中的bank调用：shared raw默认ultra/393216×128；SFO intermediate默认ultra/335872×128；CFO两bank默认ultra/335872×128；legacy raw仍使用ultra；输出缓存仅由two_pass_transport:768传SHARED_RAW_INPUT?"block":"ultra"，输出深度65536。不存在动态运行时改变primitive或其他当前传入值。

两方案都保持MEMORY_SIZE=BEAT_WIDTH*DEPTH_BEATS、宽度、深度、地址、common_clock、read_first、READ_LATENCY_B=2、regceb、reset和读写使能；没有新增拍数、数据截断或银行所有权改变。因此§21的raw343561、SFO寿命714180、CFO窗口7/8等服务/容量式不因这次类型修复而变化。该结论不保证新的完整综合一定不会遇到后续其他问题。

## 3 其他string桥的核查

非vendor RTL除上述两处外，显式string参数均属于PS1_MEMORY_INIT_FILE/MEMORY_INIT_FILE文件名传递链：sync_frontend_top→to_fine_estimator→to_fine_core→fine_partitioned_corr_engine→fine_ps1_reference_rom→XPM sprom。实际XPM对MEMORY_INIT_FILE与none等字符串比较，后缀检查使用显式32'转换后与.mem文字比较；没有MEMORY_PRIMITIVE式的未转换string==integer混合比较。因此未找到这一首错的第二类文件名触发点，不建议为此泛删文件名string类型。

## 4 父任务最小修复后的只读确认

父任务已采用A；再次读取两文件，分别在bank:5与output_buffer:6为parameter MEMORY_PRIMITIVE="ultra"，并有兼容Vivado2021.1参数分派的注释。修复后SHA256：

- sfo_uram_frame_bank.sv：10AD078CA6034605A123F1CB4723435E84A45B0AD4360726D8AF09668AF381F1。
- sfo_output_buffer.sv：DA2B702AD873D85CD05FFE4DC49B83AF6119A548AC9BDA48980400C2F3D19CA6。

这关闭了本次确定的两级参数类型设计缺口。此前static_binding使用vendor黑盒接口，不展开安装XPM内部混合比较，所以零错误不能覆盖该边界；报告保留这个检查范围失配。本人仅补本报告，没有改RTL、运行仿真或启动新综合，完整工具修复确认由用户/父任务的既有授权流程完成。

## 5. 实际diff与静态证据收口

逐一用git diff --no-index比较gui_synth_xpm_fix_20260918内两份*.before.sv和当前生产文件，两个diff均且仅包含：删除parameter声明中的string关键词、增加一行兼容性注释。没有其余RTL表达式、端口、实例参数、存储形状或时序行为变化。before/after哈希与fix_identity.json一致。

已读取同目录syntax.json，两个受影响文件均0错误/0诊断；读取static_binding/summary.json，实际生产candidate_overrides为空、0错误/958诊断。这些是父任务保存的静态结果，本人没有重新执行检查。vendor_boundary仍是黑盒IP/XPM接口声明，不能将该项静态检查当作安装XPM本体已重新通过Vivado综合。

本轮最初依据旧单报告写入授权追加到sfo_schedule_review.md的4181字节已移至本独立报告。恢复前逐字节确认旧文件前133451字节与git HEAD:Sync_OTA/reports/v51/review/sfo_schedule_review.md完全相同，未改此前正文；恢复后再次逐字节确认完全相同。本报告为新问题的追加证据，不修改旧冻结审查结论或先前实验记录。

结论：参数类型冲突的根因及两级传播已静态确认，首选最小修复已按两文件实际diff复核；没有通过修改安装XPM、存储资源、数值精度或延迟掩盖错误。新的原生综合及仿真未由本审查启动，完整工具修复结果仍应以随后真实Vivado运行为准。