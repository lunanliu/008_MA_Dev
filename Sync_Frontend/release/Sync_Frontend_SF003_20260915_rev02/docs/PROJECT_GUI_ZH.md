# 同步前端项目书与GUI使用

当前发布（2026-09-15）：release/Sync_Frontend_SF003_20260915_rev02 为唯一当前交付。原算法顶层核心 DCP、独立明文 VHDL wrapper 与 XML 分别提供，由 NI Target 编译关联；不要求预先生成 wrapper 顶层 DCP。核心原生重开通过；NI 实际导入、整体编译及板测未执行。

本工程从未同步的单条I16/Q16流的四个连续样点中找到前导，估计粗时间偏移、载波频偏及精时间偏移，输出可供下游定位同一段原始数据的接收结果。Fs是500MS/s，逻辑时钟只有125MHz；每拍四点并不自动代表持续吞吐已经合格。

## 数据怎样流动

原始流首先写入32KiB历史环，同时计算间隔1024点的相关度和能量。一个1024点滑窗每前进四点给出一次S&C度量。度量形成连续平台后，检测器提出候选；平台中点减256点得到局部参考锚点。这个锚点来自接收数据，不来自外部frame_start。

捕获控制从真实历史取出候选附近3176点，复制到两份快照中的一个，再连续回放给正式粗同步和精同步核。粗核估计TO/CFO，精核在局部做CFO旋转并搜索PS1相关峰；只有精结果有效才生成本机rx_frame_id。结果不会把原始整帧做CFO补偿，也不解码发射端帧号。

两份快照各实际分配16KiB，总32KiB；加历史32KiB后，新增原始样本存储64KiB。还有1024点检测延迟环、滚动累计历史及既有精核内部缓存，最终以综合资源报告为准，不能只报64KiB代表全设计存储。

## 已验证的范围

SF001：正式迁入粗核3例，771度量、6结果；15个IP迁到正确FLGB，485个CONFIG参数相同。
SF002：60,324输入样点，14,570度量逐点核对；四个未知前置/四lane落点，4帧无复位。精TO零样点误差，CFO最大误差23Hz。13候选=4有效+1算法拒绝+4容量/复制忙drop+4去重，快照峰值2。结果在128拍读停顿中稳定。真实输入中断、会话中止/重启、复位有单独检查。

这个输入在每256beat后暂停8000拍，约只验证了带背压回放场景。没有证明不可反压ADC持续500MS/s、无限候选或任意信道；4次drop必须保留。它们没有造成这四个真帧漏检，不代表其它候选密度下也不会漏检。SF002 completion中的gap_beats=8000实际单位是暂停的逻辑时钟周期，不是丢失的样点beat。

SF002在20ns出现一次厂商divider底层aresetn最小周期警告，位于初始复位阶段；主输入尚未开始，后续四帧及会话操作未出现同类警告。保留该原生日志，不改厂商模型、不开警告屏蔽。此仿真启动警告不证明板级复位合格，板级必须按下述复位合同。

## 用Vivado GUI打开

源工程 GUI 入口是 D:/008_MA_Dev/Sync_Frontend/vivado/Sync_Frontend/Sync_Frontend.xpr；本交付包不复制整个源工程。器件必须显示xcvu11p-flgb2104-2-e，Design Sources顶层sync_frontend_top。sim_1/coarse_baseline_equivalence_tb是已通过基座测试；sim_autonomous/sync_frontend_tb是自主捕获测试。不要另建递归扫描RTL的工程。

Sources里有34个自有硬件SV、15个管理IP及参考ROM。IP保留厂商原名以可追溯；自有模块按功能命名。Report IP Status须15/15 Up-to-date。IP配置基线在ip/，实际FLGB管理副本在工程.srcs；不能把历史FLGC DCP换进来。

实现阶段新增standalone_io_budget.xdc（同步输入/输出各1ns最大预算、0ns最小预算）；clk125.xdc声明8ns单时钟。它们只用于独立模块测量，不是NI外壳最终时序约束。thread PRE脚本请求general/synth8；IP构建实际jobs按准入文件，本机其它工具内存也要计入。运行成功后优先打开已有Synthesized/Implemented Design查看Timing Summary、Utilization、Clock、CDC和DRC，不因查看报告重新计算。

## MATLAB、输入与读回

matlab/waveform/load_frontend_waveform.m读取本地连续流，返回精确I16/Q16数值及输入清单；matlab/golden/frontend_reference_catalog.m提供正式历史浮点/定点参考函数入口及来源。历史函数自身仍使用原名以对应证据，有限窗坐标参数必须按各函数定义传入。数学DDS量化模型不能冒充厂商DDS逐位模型。

sim/data保存原始粗核短波形、精核捕获区、原参考及合并后的连续stream/truth。prepare_autonomous_fixture.py逐字检查两份基线的重叠样点后拼接，额外前置/噪声/假重复序列有固定seed及SHA。truth只供被动checker使用。

实际四条RTL结果在reports/reference/autonomous_results.csv。板上读回保持相同CSV列和顺序，可用tools/compare_readback.py或matlab/comparison/compare_frontend_readback.m检查。Python脚本已对该原生结果通过；新MATLAB包装入口尚未在本工程执行，旧算法参考验收与包装测试状态分开。

## 下游T10连接

每次输入握手，采集端也应把相同四点写入自己的原始数据bank，并记录(epoch,accepted_sample_base)。前端只保留前导快照，结果读走后不提供全帧缓存租约/读端口。下游从外部原始bank按epoch与fine_absolute定位；不能向raw入口提供已做全帧CFO补偿的数据。

可关联rx_frame_id→下游frame_id、result_epoch→generation、cfo_hz→粗CFO记录，粗/精坐标必须使用同一epoch内原点。旧T10接口部分坐标仅32位，前端给64位；适配器须选定可表示的局部原点并检查范围，不能直接截断高32位。原根T10 CLIP是旧150MHz边界，当前T10迁移/完整帧工程属于另一配对；本工程没有修改或验证二者直连。125MHz前端与任何不同域的下游必须通过受审查的消息/数据FIFO，不可逐位同步多位结果。

## 交付与板测责任

当前 release 的 clip 目录提供核心 DCP、独立纯连线 VHDL、CLIP XML 和说明 NI 时钟所有权的 XDC。核心 DCP 已独立重开、零黑盒；发布文件另做静态端口、依赖及哈希检查。自建 wrapper 回填诊断不是发布前置门槛。正确FLGB后布线时序独立报告；NI整目标编译、真实时钟、DMA/DRAM吞吐和板测由用户完成，不外推独立OOC报告。
