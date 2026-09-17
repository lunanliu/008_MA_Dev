# OTA004/A03：完整真实工程、短顶层控制与一次核心综合

## 范围与配对

PROJECT_SPEC已授权完整系统、必要短检查、核心综合与手工上板交付。本包由Astra 01a0ac17-f298-7201-848c-58d09e90ebb4派唯一Luna 01a0ac17-4f21-7be3-8690-540c11497b1e；必须先取得总管家新的OTA004/A03具体grant。OTA001～003授权均已归还，不得复用。

仅prepare -> smoke -> synth串行，1个Vivado主作业、0 MATLAB；无实现/布局布线、无完整帧算法重跑、无74后端重复、无NI工程或XML。目标D:/008_MA_Dev/Sync_OTA/Sync_OTA.xpr，唯一算法综合top sync_ota_top，器件xcvu11p-flgb2104-2-e，Vivado2021.1。Wrapper不作综合top。

## 已冻结的真实设计

输入清单OTA004_A03_source_lock.json逐项记录长度/SHA256。127项生产RTL、135个唯一module/package定义、45个唯一真实IP；生产CFO只选ota_cfo_chain_a02.sv，不能把旧A01同名module一并加入。A02补失败后端结果留存和既有FIFO诊断；root首错/监测域/完成保持见IMPLEMENTATION_A05_ZH.md。OTA002/003共69项旧冻结输入已重新核对未改。

三个NI提供时钟125/150/500MHz。官方XPM仅用于综合，私有link010r1三件仅用于仿真；保留原有两项精确translate_off修正，算法和综合内容未改。完整top已连接真实前端、初次SFO估计/E1/残余SFO估计/E2、两个独立CFO旋转和真实74观测估计，Host无偏移真值配置端口。

75个核心端口对应111个常用宽度Wrapper端口，见PORTS_AND_RECORDS_ZH.md及CORE_WRAPPER_PORT_MAP.json。顶层/新增CFO/TB Verible语法、命名端口、Python AST、Tcl结构和PowerShell解析已检查；这不是原生展开或综合PASS。

## 命令与输出

入口tools/vivado/run_ota004_a03.tcl；监管tools/monitor_ota004_a03.ps1继承已验证PID+创建时间树逻辑，按2026-09-17用户最新指令将12GiB作为告警参考，不作为启动拒绝线，并记录系统提交余量、分页速率、分页文件及完整子树内存/CPU/IO与工具日志进展。每阶段新目录work/OTA004/<stage>_a03，失败另编号，成功阶段不重跑。

具体grant通过并新建独立目录后，示例：
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:/008_MA_Dev/Sync_OTA/tools/monitor_ota004_a03.ps1 -Stage prepare -Attempt D:/008_MA_Dev/Sync_OTA/work/OTA004/prepare_a03 -Source D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota004_a03.tcl -HardSeconds 2400

smoke阶段同样2400秒；synth阶段7200秒。各阶段实际HardSeconds不得超过包级剩余预算。首启记录后180分钟为全包硬截止，贯穿包装重试。保存每条实际命令/私有修复哈希和绝对UTC期限。

prepare在根目录创建完整XPR，用import_ip生成Sync_OTA.srcs受管副本，原ip/config冻结XCI保持不变。重复进入只打开已有XPR，不删除重建、不force已成功目标。smoke/synth均打开这一XPR并重新审核part/top/源集；每阶段保存actual_sources.tsv、actual_ips.tsv、真实编译成员哈希。失败的可变.sim日志/PRJ/bat/Tcl归档到本次attempt，禁止为补记录重跑成功计算。

## 阶段门槛

|阶段|动作|判定与范围|
|---|---|---|
|prepare|创建/打开根XPR；导入45个IP，generate_target all（不force）；完整源集/功能IP参数核对；独立xvhdl --2008编译明文Wrapper|OTA004_PROJECT_PREPARE_PASS。全部实际RTL与列表相符，IP无锁定，受管XCI只准RUNTIME_PARAM差异；独立Wrapper语法exit0。实际编译文件必须存在并记录哈希。|
|smoke|完整真实核编译/展开；精确XPM与关键真实模块绑定检查；运行sync_ota_smoke_tb|OTA004_REAL_TOP_SMOKE_PASS。三次原始写，第三次外部ACK待定时cancel；禁止提前done/start_ready，回应排空后仅一次完成，恢复可接新配置；无晚到最终输出；长度0拒绝且无DDR流量。真实所有核参与展开，但只测控制，不声称全帧数值链路通过。|
|synth|45个IP中仅尚未完成的OOC runs，随后一次完整核心out_of_context综合，flatten_hierarchy=none；open_run并导出|OTA004_REAL_CORE_SYNTHESIS_COMPLETE。核心run完整、0 blackbox，frontend/sfo/cfo/control/ddr及CFO两旋转/前端/后端真实层次存在；DCP/EDIF、资源/层次、时钟、CDC、综合时序/check_timing报告齐全。资源和时序如实报告，负裕量不得改为timing PASS；不启动实现补救。|

exit0不是充分条件。保留唯一阶段marker、result.txt、原生和子作业日志；原生日志不得有未解释ERROR/FATAL/断言失败。厂商普通警告保留分类，不全局屏蔽。若完整真实核首次编译暴露实质RTL/IP/数值问题，保留首错并回本Astra，暂停依赖后续阶段。参考/模型不得代替生产算法核。综合网表里发现真实资源超限、关键层次消失或黑盒属于设计问题；不自改核规模或门槛。

## 并行、内存与保护

general.maxThreads=8、synth.maxThreads=8，所有IP/core run PRE钩子设置并回读；xelab=16；core launch jobs=16（一个core run）。IP并发4，上限16的下调有资源依据：本机物理约31.4GiB，A01冻结时可用约12GiB；2026-09-17 00:33UTC重新采样约21.66GiB、提交余量83.53GiB、分页文件64GiB；已有SFO完整展开单xelab采样峰值5,827,182,592bytes，完整OTA更多IP/核，不能把16个Vivado子进程的内存漏掉。记录全部子树工作集与全机可用内存；不只统计launcher。

请求独占本对1主作业槽；预估整树6–12GiB，16GiB为告警而非自动kill；12GiB仅为物理内存告警参考，小幅不足直接启动，不因这条线等待；估算小幅越线不终止。明确错误、确证停滞或持续严重系统压力才干预；结合系统提交余量、真实持续分页、全部子树内存和实际工具进展判断。物理可用低于1GiB或提交余量低于1GiB仅发紧急复核标记，不能单凭阈值自动kill。若持续60秒严重资源压力且伴随工具无进展/实际内存错误，由Luna保留证据后按本次已核验PID+创建时间树保护；CPU/IO/日志进展作为判断线索，日志静止本身不等于卡死。不得停止其他任务/用户GUI，不重启电脑、不改全局环境或用户分页文件。必要时允许Luna降低IP并发并记具体内存依据，只属运行资源修复；不得提高超过本次准入。

预计prepare 5–20分钟、smoke 5–20分钟、synth 20–90分钟，合计30–130分钟；每20分钟复核进度，工作期每15分钟按模板报告。硬保护prepare40分钟、smoke40分钟、synth120分钟、全包180分钟。退出后必须等完整已记录进程树关闭；未关闭不得交接完成。普通包装/路径故障另存版本自修，修改判断谓词时必须证明与本任务书同义，禁止为得到PASS放宽；能用已有日志静态核查的先静态核查。

## 交接

向本Astra交启动/结束、源锁复核、实际源与生成依赖哈希、IP参数身份、Wrapper编译、smoke日志与计数、每个IP/core真实run线程回读、DCP/EDIF身份、全部资源/时钟/CDC/综合时序和完整树关闭。Luna不修改中央槽；Astra复核后请总管家归还。最终板测数据/Host指南由Astra整理，不把本包变成NI板测或持续500MS/s资格。

## A02限定修复与A01保留

总管家在A01准入前发现3份必需头文件漏拷；A01未启动，原入口/检查器/清单/任务书原样保留，禁止执行旧A01。A02仅修复独立工程头文件闭合，不改RTL算法、TB、IP参数、阈值、并行/内存/时间预算。该依赖修复完整保留；A03仍须新的具体grant，12GiB仅告警，按用户最新内存策略启动。

三份头文件来自同一已选Sync_SFO完整版本rtl/include，逐字节匹配其20260915已发布current_input_manifest.csv；复制与来源身份见docs/provenance/OTA004_A02_INCLUDE_SOURCE_LOCK.json。文件包含原IP延迟宏，原样保留，禁止猜常量、删include或引用原工程绝对路径。rtl/headers_ota004_a02.f是3个显式工程成员；sources_1与sim_1均仅用本工程rtl/include。头文件作为Verilog Header，不独立编译或设全局include。

A02原入口run_ota004_a02.tcl与检查器verify_ota004_a02_project.py保留；A03仅另存run_ota004_a03.tcl与verify_ota004_a03_project.py更新源锁引用。实际工程每次导出actual_headers.tsv及actual_include_dirs.tsv，并核对3成员、FILE_TYPE、综合/仿真可见性、两个文件集唯一搜索路径；扫描精确127生产RTL、指定TB和6份XPM中的include递归依赖，拒绝缺失、歧义、动态未审查引用或未锁定头文件。独立记录头文件长度/SHA256和引用边，不能以compile_order可能不单列头文件为由漏审。全部A03冻结输入每阶段核验；实际IP/模块/XPM门槛沿用A01。

## A03：用户明确更新内存启动策略

2026-09-17总管家转达用户直接要求：原12GiB物理内存线小幅不足直接启动，机器有充足虚拟内存；不得因此排队等待。A02刚已派发但未准入/未启动，故保留其210项冻结输入，另冻结A03；依赖修复、RTL/TB/IP和所有功能门槛均不变。A03监管只将12GiB硬throw改告警，新增可用物理/系统提交量及上限/提交余量/分页文件/真实换入换出、子树私有内存/CPU/IO、原生日志时间/大小记录；计数读取失败记录不可取得，不伪造0，也不因可选计数采集失败杀作业。

硬超时、完整树身份与收尾逻辑保持。严重压力由Luna根据真实资源与工具进展综合判断；轻微物理内存不足或整树超过估计只警告，不停止/重跑；不更改分页文件、不关闭别的应用。原1 Vivado/0 MATLAB、8/8/16、IP jobs4/core jobs16及40/40/120/180分钟预算保持，资源仍须总管家A03具体grant。
