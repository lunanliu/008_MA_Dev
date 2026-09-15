# 打开核心工程、手动综合和导出

本交付的GUI工程在[core_project/vivado/T10_SFO/T10_SFO.xpr](../core_project/vivado/T10_SFO/T10_SFO.xpr)。它与原已验工程XPR逐字节一致，核心、IP配置、初始化输入及辅助脚本按冻结清单复制；原用户XPR没有修改。副本只做静态依赖检查，本轮没有重新启动Vivado打开、综合或仿真。

## 1. 搬到远程机器

复制整个T10_SFO_20260915_manual文件夹，保持core_project内部层次。源文件条目使用相对$PPRDIR路径；XPR头部Path保留原保存位置元数据，不能只复制XPR一个文件。若GUI提示迁移保存，在远程副本中保存，不覆盖原工程。

[项目复制清单](../evidence/project_copy_manifest.json)给出149项源/来源文件及指纹；[交付文件清单](../FILE_MANIFEST.csv)给出全部本包文件指纹。34个XCI是IP配置，四个FIR的系数内嵌其中。IP生成HDL、OOC DCP、XSim快照及旧作业目录不作为移交依赖，需要时由远程Vivado从XCI生成。未复制原work目录。

本地验证工具为Vivado 2021.1。LabVIEW 2026Q1是用户环境信息，不能据此推定远程FPGA Compile Tools具体版本、IP加密兼容性或已安装器件支持；用户在远程核对这些条件。没有携带旧FLGC综合网表冒充新FLGB产物。

## 2. 在GUI核对工程

打开XPR后检查：器件xcvu11p-flgb2104-2-e；Design Sources顶层t10_two_pass_system；Simulation Sources顶层t10_full023_tb；OUTPUT_CLOCK_MHZ使用默认150；RTL核心74个；XPM3份、TB/观察器2份、34个IP、6个MEM及当前有效时钟XDC。精确条目见core_project/rtl/sources.f及core_project/ip/ip_names.txt。

核心下有真实T06、T09、两套重采样实例及片内缓存。硬件综合顶层始终为算法核心；本包Wrapper在wrapper目录，未加入核心工程源集，不取代综合top。

在Report IP Status检查34个IP。需要生成时使用IP Sources里的Generate Output Products并保留全部所需输出；不要升级参数或套用其它器件的缓存。

当前有效约束为[t10_root_clocks.xdc](../core_project/constraints/t10_root_clocks.xdc)，只声明125/150/500 MHz三路根时钟。完整I/O预算、平台时钟派生和CDC实现约束尚未闭合。reference_synth016里的旧约束仅供审阅，未自动启用，不能把其外部I/O false path直接作为NI平台时序约束。

## 3. 用户手动综合核心

先在副本GUI中设置Synthesis的More Options为`-mode out_of_context`，让核心作为将被上层实例化的模块综合，避免把大量数据端口变成芯片顶层I/O buffer。保留core top和150参数。OOC不是Wrapper独立综合，也不是布局布线完成。

性能配置可在该副本的Tcl Console执行下面两行，把当前目录替换为远程路径：

```tcl
source D:/your_copy/T10_SFO_20260915_manual/core_project/tools/vivado/configure_parallel_jobs.tcl
t10_prepare_build
```

它设置general/synth线程8并安装run PRE钩子；build jobs及xelab上限16，实际jobs按远程内存设置。随后由用户点击Run Synthesis启动所需IP及核心综合。这些是用户操作步骤，本轮没有代为执行。

综合完成后打开Open Synthesized Design，检查端口与[核心端口表](INTERFACE_ZH.md)一致；检查资源、错误、未解析IP黑盒和时钟报告。若IP未解析，应先在同一工程完成所需IP生成/综合并解析依赖，再导出；存在未解析黑盒时不能当成完整可交付网表。

## 4. 从已打开的综合设计导出

下面只在用户已经打开正确综合设计后执行，目录名每次用新名字：

```tcl
set export_dir [file normalize [file join [get_property DIRECTORY [current_project]] exports T10_core_run01]]
if {[file exists $export_dir]} {error "Preserve existing export; choose a new directory"}
file mkdir $export_dir
write_checkpoint [file join $export_dir t10_two_pass_system.dcp]
write_edif -security_mode all [file join $export_dir t10_two_pass_system.edf]
report_utilization -file [file join $export_dir utilization.rpt]
report_timing_summary -file [file join $export_dir synthesis_timing.rpt]
```

DCP用于Vivado保存/调试；它不自动等于NI CLIP可直接使用的文件。EDIF及必要IP依赖与明文Wrapper一起按用户NI编译工具支持的格式导入。`-security_mode all`把需要加密的单元一同导出，避免默认multifile模式生成旁文件后只拷贝主EDIF；仍应以实际导出日志和未解析单元检查为准。不要使用会把存储初始化改成固定值的`-logic_function_stripped`。本包没有新的DCP/EDIF，不宣称远程网表链接已经通过。

用户在LabVIEW创建CLIP，明文顶层选t10_sfo_manual_wrapper，内部component名字必须对应t10_two_pass_system。选择网表绑定时不要同时导入同名RTL实现造成重复定义；选择源级导入时必须满足全部SV/IP及混合语言依赖。本包默认说明“核心网表+独立Wrapper”路线，实际NI支持由远程编译确认。

## 5. 仿真和现有证据

完整行为结果已经独立通过，不需要为获得交付包再跑一次。当前通过证据见[复核报告](../evidence/T10_RUN03_INDEPENDENT_REVIEW_20260915_ZH.md)。源码或输入真正改变后，仿真由明确任务另行安排。

若用户以后操作GUI行为仿真，测试台仍为t10_full023_tb；6份MEM必须位于实际XSim运行目录。副本tools/vivado/start_simulation_0ns.tcl负责部署文件并打开到0ns，但它会编译/展开，不是只读按钮。它生成的原生compile_order可能包含MIF；原validate_gui.py只识别HDL，不应直接忽略报错，更不能因此重跑已完成仿真。RUN03如何保留完整列表并单独核对4份MIF，见复核报告。

副本带来的早期ip/README及迁移说明属于冻结来源记录；本文件和根README是本次交付操作入口。历史报告中的源路径、哈希以及PENDING字段保留原含义。运行依赖均在core_project内，原机上的历史证据路径不是远程必须存在的运行目录。

参考：[AMD OOC下层网表流程](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Creating-a-Lower-Level-Netlist)、[Vivado 2021.1 write_edif](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/write_edif)。
