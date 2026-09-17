# SF003 DCP交付短检查（等待新资源grant）
本包只补用户关心的DCP+VHDL导入路径和实际可执行的时钟检查。SF003原综合、15IP、route、SF001/2全部复用；禁止重跑。
任务：唯一Luna 01a0a161-e434-7142-8927-1f5314daafd5；Astra 01a0a162-c115-7af1-89be-49726f987f84。
截至冻结时共享槽属于T11_T13。没有总管家新grant不得启动；不打断当前T11阶段。启动前核对全机计算组和真实资源。

命令：
C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -notrace -source D:/008_MA_Dev/Sync_Frontend/tools/check_dcp_release.tcl -tclargs D:/008_MA_Dev/Sync_Frontend/release/Sync_Frontend_SF003_20260915_rev01 <全新work/SF003_DCP_check_UTC目录>

冻结输入清单：reports/design/SF003_DCP_RELEASE_CHECK_files.csv。先SHA核对，不用旧包漏列依赖XML；按新包edn_files.txt的43项加载，不跨attempt混选。
general.maxThreads8、synth.maxThreads8在此单原生进程中回读；无IP子综合、xelab或多个run队列，jobs16上限不需要用虚构并发填充。预计3–8分钟，峰值约3GiB告警，硬保护15分钟，按实际严重压力/错误/停滞保护；本包不得影响T10/用户GUI。只运行一次必要流程，成功阶段报告失败仅补报告。

阶段：
1. 读取同次EDF+43EDN，link_design -mode out_of_context，零黑盒、无IBUF/OBUF设备pad、主DSP/BRAM/FF数量核对；在不添加standalone时钟或IO预算条件下导出sync_frontend_top.dcp。
2. 关闭项目，在新上下文open_checkpoint该保存DCP并核对结构。这一步证明实际DCP可独立重开，不拿ZIP可读冒充。
3. 新上下文仅综合纯连线VHDLwrapper壳，再read_checkpoint -cell将DCP填入唯一sync_frontend_top黑盒。核对零黑盒、无pad I/O、资源一致和32端口；不改变原计算。
4. create_clock仅在检查环境clk125上建立8ns测试时钟，普通Tcl get_pins/get_clocks/if检查真实继承。发布XDC没有if、不制造平台时钟、不复制OOC IO预算；NI最终时钟约束仍由Target负责。
5. 保存DCP包、包装链接DCP、资源、实际端口、原生日志、约束、哈希和完整所属进程树退出证据。BUFG实际数量记录，无零BUF门禁。
6. 普通命令路径/属性兼容可私有修订。资源计数差异先解释来源，不通过修改期望值隐藏丢逻辑；禁止改DUT、算法、采样/时钟、输入测试含义。

交回：reports/SF003_DCP_RELEASE_CHECK_completion.json，标明独立DCP重开/DCP填入wrapper/普通Tcl时钟检查各自结果。由Astra校验并将最终DCP包发布到同一release目录；本检查不代表NI Target VI已编译或板测。