# 本机工具性能规范

2026-09-14用户要求：使用工具支持且本机承受得住的最高性能。适用于今后综合、布局布线、仿真及MATLAB运行；替代只改16 jobs却保留单作业2线程的旧配置。

本机实测为Ryzen 9 5900HX：8物理核、16逻辑处理器，约31.42 GiB可用物理内存总量。逻辑处理器共享部分核心资源，不等于16个完整物理核。空闲内存随GUI和其它程序变化，不能用总内存代替启动时的余量。

## 配置与含义

| 项目 | 后续设置 | 真正控制什么 |
|---|---|---|
| Vivado通用内部线程 | `general.maxThreads 8` | 按官方支持上限8配置；参数接口接受更大数值不等于该数值受到支持 |
| 综合内部线程请求 | `synth.maxThreads 8`，与general共同设置 | 本机2021.1脚本取两者较小值；实际阶段并行以原生日志为准 |
| 综合/实现并发作业 | 默认/上限 `-jobs 16` | 同时调度多少个独立run；不等于一个设计用16核 |
| 仿真展开子编译 | 默认/上限 `xsim.elaborate.mt_level 16` | xelab生成模型后的并行子编译；不控制逐拍运行的XSim全部步骤 |
| MATLAB数值计算 | 不带 `-singleCompThread`，`maxNumCompThreads('automatic')` | 本机R2024a正常启动与automatic回读均为8；不等于所有代码都能并行 |
| MATLAB并行池 | 不自动创建 | `parfor/parpool`属于另一个任务并行层，须明确数据隔离、许可证和内存预算 |

线程/作业数是上限，不是CPU持续占用率。综合、布局布线和仿真都有串行部分；增加并行参数不能保证按核数等比例提速，也不能把XSim逐拍运行变成16核运行。

## 每次启动的规则

1. 核对工具版本、当前运行进程、空闲物理内存和已有同类作业峰值；把实际jobs、展开并行数、内存总预算和硬超时记入本次运行记录。
2. 轻量独立IP作业可使用16 jobs；完整T10的历史综合曾占约8.34 GB，不能让16份这种作业同时挤进32 GB机器。为系统和现有GUI保留余量，按各子作业峰值合计估算。没有峰值证据时不靠过量并发试探内存极限。
3. 资源不足时允许降低实际jobs或串行重型MATLAB/Vivado阶段，并记录原因和实际值。默认1 MATLAB槽指同时运行一个MATLAB进程，绝不要求它只用一个CPU线程。不要为“满载”而让两个重型工具争抢内存、产生大量磁盘换页。
   启动前的内存估算用于选择并发数；运行中轻微超过估算只告警并记录，不能把预估值直接作为杀进程阈值。告警线与真正的保护条件分别冻结；真正保护依据系统可用内存严重不足、持续异常增长、明确故障或无进展，不为小幅越线中断并重复安排已在运行的工作。
4. 首次实际运行核对原生线程声明、阶段耗时及峰值内存；只在这些证据支持时调整下一次配置。不为比较并行数重复完整帧实验，不降低检查或验收要求来提速。

2026-09-14 03:10 CEST快照：空闲10.09 GiB；Chrome私有常驻约3.67 GiB，Word约0.02 GiB。关闭不用的应用后应重新测量，而非继续沿用关闭前的预算。不要把多进程的共享内存重复相加；约2.27 GiB的Java进程已核实属于Vivado。完整记录在验证目录的 `application_memory_snapshot.json`。

## Vivado操作入口

在下一次启动前、当前工具尝试结束后，在已打开工程的Tcl Console执行：

```tcl
source D:/008_MA_Dev/tools/vivado/configure_parallel_jobs.tcl
t10_prepare_build
```

随后使用GUI的Launch Runs，Number of jobs以16为上限，按本次资源预算选取。脚本方式为 `t10_launch_runs {synth_1}` 或 `t10_launch_runs {impl_1} -to_step route_design`，默认16；有预算依据时可显式 `-jobs 2`。仿真并行需下调时调用 `t10_set_elaboration_jobs 8`，同一会话再次加载配置会保留该选择；新会话默认16。

`t10_prepare_build`只为已经启用独立综合检查点的IP定义缺失run，再安装钩子；不启动综合。新加IP之后再执行一次。`run_threads.tcl`作为各run支持的 `STEPS.*.TCL.PRE` 钩子，在实际子进程内设置线程并打印PID及回读值。发现已有不同用户钩子会保留并报冲突，必须审阅如何串接后再运行。

搬到远程或更换目录后，重新source新位置的配置并执行prepare。可读取且字节相同的旧性能钩子可更新路径；旧路径失效时，先在Run Properties核对并清除本工程旧性能钩子，再应用新路径，保留其它用户钩子。普通文件修改不能热更新已经启动的Vivado进程。这里不修改安装目录或全局Vivado设置；后续新建工程也须采用同样的项目内钩子机制，不能仅在创建工程的父进程设置参数。

## MATLAB历史限制与修正

只读审计在T09 CLOSED002 rev02、T09 CLOSE036、T11 RCFO004的实际执行记录中发现 `-singleCompThread`。所以部分旧MATLAB实验确实被人为限制为单计算线程；这不是本机只能单核，也不是Codex模型线程设置。

新入口 `matlab/setup_t10_reference.m` 会调用 `configure_compute_threads.m`，回读自动线程数、MATLAB版本和并行工具箱许可证可用性，不启动并行池或数值实验。若启动时已带单线程参数，应结束该会话后用正常方式重新启动，而非假设函数能撤销启动限制。

冻结快照及旧启动记录保留原字节。新运行直接使用新入口和明确的算法函数，不调用快照中的旧PS1监管器。MATLAB内建矩阵运算、部分FFT等可受益；普通有先后依赖的循环不会自动变成并行。Python定点快照的进程内OMP/OpenBLAS限制是另一问题，不作为MATLAB全局限速证据。

## 验证与参考

配置探针结果见 `docs/verification/performance/`：同一小探针已完成综合、布局布线、报告和MATLAB配置查询，place/route原生日志均确认最多8 CPUs。最终续跑157.245秒，进程组工作集峰值5.415 GiB，系统可用最低12.901 GiB，越过4 GiB告警后正常完成。先前4 GiB越线被误作硬停止条件的记录保留，4 GiB现改为告警，续跑复用已有成功检查点；不重跑MATLAB、综合或已完成的优化。即使小探针完整成功，也不证明T10综合、时序、整帧仿真或具体加速倍数通过。用户GUI保存的XPR及IP生成产物保持现场，未并入本次配置修改；下一次正式作业仍须冻结当时实际工程。

- [AMD Vivado 2021.1实现指南：多线程](https://www.amd.com/content/dam/xilinx/support/documents/sw_manuals/xilinx2021_1/ug904-vivado-implementation.pdf)
- [AMD Vivado 2021.1 xelab命令选项](https://docs.amd.com/r/2021.1-English/ug900-vivado-logic-simulation/xelab-xvhdl-and-xvlog-xsim-Command-Options)
- [MathWorks计算线程与automatic设置](https://www.mathworks.com/help/matlab/ref/maxnumcompthreads.html)
- [MathWorks：数值线程与并行池的资源关系](https://www.mathworks.com/help/parallel-computing/optimize-parallel-pool-for-multithreaded-computations.html)
