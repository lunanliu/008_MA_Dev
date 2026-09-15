# T10 RTL迁移说明

目标目录为D:/008_MA_Dev，目标器件为xcvu11p-flgb2104-2-e，面向远程Windows 11/Vivado 2021.1 GUI。真实XPR已由Vivado创建、关闭并重新打开；34个canonical IP已完成原生器件适配。Astra最终独立复核仍在收尾，尚未运行新工程的编译、展开、仿真、综合或实现，也没有进行GUI点击验证。本工程不包含CLIP/MMCM包装，原D:/007工程保持不变。

## 唯一源码与目录

74个真实核心SV唯一来源是旧工程reports/t10/design/T10_FULL023/package/rtl；其原先与CLIP同核心的身份已核对。rtl/common保存公共包及T03/T05依赖，rtl/t06至t10按模块分组，Farrow/g3归t07。rtl/include包含3个头文件。rtl/sources.f明确列出核心源集，不按同名文件搜索或回退到旧工程。

rtl/vendor/xpm保存冻结Vivado 2021.1的3份XPM原文件和许可头；工程关闭自动XPM_LIBRARIES，避免重复定义。sim/tb保留原测试台及被动FIFO观察器，算法、数值门槛、时钟、复位和供数没有因迁移改变。输入仍为frame6001：SFO=-150ppm、粗CFO=+100kHz、TO=0、无噪声单径。测试台直接产生125/150/500MHz时钟，输出150MHz。

sim/data保存raw.mem（334215拍）、r1.mem（334098拍）、r2.mem（334080拍）、delay.mem/delta.mem（74点）及t09_pilot_phase.mem。前三个MEM为四路I/Q16打包的128位数据。provenance.json中的旧MAT绝对路径仅作溯源；仿真不读取原MAT，不需运行MATLAB。

## 已完成的原生创建与IP适配

当前唯一活动IP来源是ip/config下的34份XCI，全部原生retarget到xcvu11p-flgb2104-2-e。tools/vivado/create_project.tcl直接read_ip这些文件；已保存XPR也以相对路径引用它们。没有一套可独立编辑的旧FLGC配置与另一套.srcs新FLGB配置并行充当来源。

原生保存与重开记录中，34条IP的IPDEF、路径、器件/封装/速度/温度及锁定状态一致，1071条参数记录after与reopened逐条一致。该结果说明本次保存/重开没有改变这些配置；最终与源配置的独立验收仍以Astra复核为准。

upgrade_ip自动产生了34份.veo、34份.vho和34份.xml。这些是本次工具生成的实例模板及元数据，不能写成“没有产生任何文件”；本次没有调用generate_target，也未生成并验证可仿真的完整IP输出产品。旧DCP、综合网表、stub、生成HDL、缓存及XSim快照未被复制为新工程的实现依据。四个FIR系数以CoefficientVector内嵌于XCI，后续MIF等输出由Vivado生成，不借旧生成文件替代。

实际证据位于work/native_project_20260914T001342964Z_luna：config_after.csv/config_reopened.csv、ip_after.csv/ip_reopened.csv以及files_after.csv/files_reopened.csv。器件适配和工程创建已发生，不再属于“仅有静态创建脚本”的状态。

## 原生尾部异常与保留证据

同次运行在完成保存、关闭、重开及回读后，尾部JSON报告的Tcl括号格式错误使root_returncode=1。owned_exit.json记录自有Job已归零、无超时；不能把退出1改写成完整原生成功。

原native_complete.json和原Tcl均保留。已另存native_complete_repaired.json及TCL_REPAIR_RECORD.json，离线修正报告格式，没有重新运行Vivado。修复后的状态仍是PENDING_ASTRA_REVIEW，报告修复不替代最终复核。

## GUI使用入口与尚未执行的步骤

已存在的工程为vivado/T10_SFO/T10_SFO.xpr，可交由远程Vivado 2021.1打开；硬件顶层t10_two_pass_system，仿真顶层t10_full023_tb。也可在Tcl Console执行source <新工程根>/tools/vivado/create_project.tcl创建或打开。创建脚本不退出GUI、不自动综合或启动长仿真，默认运行时间0ns。源码、XCI和MEM通过项目内相对位置关联。

后续经批准生成IP输出并完成原生检查后，操作者可执行source <根>/tools/vivado/start_simulation_0ns.tcl。该脚本将编译/展开、复制6个MEM、保存实际编译顺序、打开0ns仿真并添加选定波形；它拒绝混用已有结果。这个步骤尚未执行，MEM运行时读取、编译展开、波形显示和GUI交互均不能记作已验证。仿真运行期间不调用Python或MATLAB。

constraints/t10_root_clocks.xdc为当前活动的三个根时钟声明。constraints/reference_synth016中的production_clocks.xdc和production_crossing_constraints.tcl仅保留旧综合约束作为参考，没有加入活动约束集；它们不授予新FLGB器件或NI集成资格。当前工程没有完整板级引脚、I/O与CDC物理验收，新器件综合/布局布线及上板仍未完成。

## 离线检查与冻结清单

原始docs/provenance/RTL_COPY_MANIFEST.csv保留139条迁移快照及原source_sha256，不作为当前完成验收的默认清单。总管家负责在原生与文档收尾后冻结docs/provenance/RTL_FINAL_MANIFEST.csv；离线验收默认要求该最终清单存在，并独立保留74个核心SV对原源字节的检查。最终清单不自包含自身或动态运行日志。

validate_gui.py已经增加精确源码成员检查：逐行读取实际完整路径，要求74核心、2个TB和3个本地XPM；拒绝外部同名源、注释伪源、额外核心、重复、路径穿越和链接。其他生成IP源码只可来自本工程明确允许的IP范围；路径成员检查不替代厂商生成文件版本、参数和内容身份审计。9项临时文件正反例已通过，见docs/verification/source_membership_tests.json。

check_prefix.py保留RUN001转义实例名修复及原数值/良性逐边沿谓词，同时已经固定完整32个FIFO、64个域绑定的准确集合。旧RUN001仅覆盖11个FIFO的轨迹回放不再认可为完整绑定通过。6项离线检查器测试已通过，见docs/verification/prefix_checker_tests.json；这是检查器测试，不是新FLGB仿真。结果区分轨迹末尾、算法事件和完整封口，不把已有局部记录称为连续全段覆盖。

tools/analysis的Python仅在仿真完成后进行独立检查，EVM计算另需NumPy。GUI保存日志不等于旧batch封口回执或完整进程清理证明；逐点<=1LSB、固定拍数、74窗口、估计值、因果顺序、FIFO和未知错误拒绝规则仍保留。原FULL023/RUN001未完成全帧；已有输入参考、同源74核心、此次器件适配和工程重开都不等于新器件全帧、持续吞吐或T10总体通过。
