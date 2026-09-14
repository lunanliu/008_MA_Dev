# 在Vivado里接手工程

## 1. 打开与检查

使用Vivado 2021.1打开项目根目录下 `vivado/T10_SFO/T10_SFO.xpr`。如果是从Git恢复且尚未生成工程，在Vivado的Tcl Console中执行：

```tcl
source D:/008_MA_Dev/tools/vivado/create_project.tcl
```

复制到其它目录后，替换上述路径。脚本应创建同一正式工程，不自动启动长仿真。已有工程的真实验证状态见[迁移检查](verification/MIGRATION_CHECKS_ZH.md)。

打开Project Settings，确认器件为 **xcvu11p-flgb2104-2-e**。在Sources窗格检查：

- Design Sources下的硬件顶层：`t10_two_pass_system`。
- Simulation Sources下的测试台顶层：`t10_full023_tb`。
- Constraints中的时钟约束；125/150/500 MHz是核心的三路输入时钟。
- IP Sources中34个IP及其状态；不能让旧FLGC生成网表替代新的FLGB配置。

展开硬件层级可看到T06第一次估计、T09第二次估计和transport内的两次重采样/缓存。文件路径按功能分组，层级由模块实例关系决定，不要求所有模块塞进一个大文件。

独立工程没有NI引脚和板级时钟发生器约束。不要直接把它当成可下载到PXIe-7903的完整板级设计。

## 2. 第一次仿真之前

### 后续作业统一使用16 jobs

按2026-09-14用户要求，综合/实现的Launch Runs窗口中Number of jobs统一选16。脚本对应 `launch_runs synth_1 -jobs 16`；它控制同时调度多少个run，包括适用的独立IP综合run，不等于一个run强制使用16个CPU核心。

仿真准备使用16个xelab并行子编译任务。新建/打开项目脚本及0ns仿真入口会应用这一设置。对已经直接在GUI打开的项目，请在当前尝试结束后、下一次启动前执行：

```tcl
source D:/008_MA_Dev/tools/vivado/configure_parallel_jobs.tcl
```

该文件只设置展开并行数并定义 `t10_launch_runs`，不会启动综合或仿真。随后可在GUI选择16 jobs，或执行 `t10_launch_runs {synth_1}`；实现可用 `t10_launch_runs {impl_1} -to_step route_design`。GUI的下拉选择与脚本参数分别生效，不能把修改脚本描述为已热修改用户正在运行的GUI进程。

单作业内部的 `general.maxThreads` 是另一项设置，本次16 jobs要求没有把它设成16，也没有修改其既有值。16是允许的并行上限，不保证CPU始终满载或一定比8更快。内存不足、交换到磁盘和任务间依赖可能降低速度；发现实测问题须报告，不静默改小用户指定的作业数。

本次只更新已审阅的两个启动入口及新增配置文件的指纹；用户GUI保存的XPR和生成产物保留现场，不并入这次配置提交。正式数值验收前，仍需冻结那次实际使用的工程及输入，不能用初次迁移的XPR指纹代替后来GUI修改后的版本。此次配置经过Tcl结构和参数传递检查，未启动新的Vivado作业或测试16 jobs的性能。

### Elaboration在做什么

编译先读取并检查各个RTL文件；展开（elaboration）把顶层下面的模块实例连接起来，代入参数、展开generate循环、匹配端口和位宽，并绑定FFT/FIR/FIFO等仿真库。随后工具优化仿真模型，生成并编译本机可执行代码，再链接XSim内核，得到可运行的仿真快照。最后才由XSim按测试台的时钟、复位和输入推进仿真时间。

窗口显示“Hierarchical elaboration completed”只表示层级展开这一步完成，后面的代码生成和链接可能仍在进行。它不是硬件综合，也不是正在计算整帧信号。T10包含74份核心RTL、34个IP和大量存储/FIFO模型，首次完整准备可能明显慢于后续复用；具体慢在哪一步应看这次elaborate.log，而不能仅凭窗口文字断言卡死。

`xelab --mt 16`主要作用于上述并行子编译，不能据此保证真正逐拍运行的XSim也能用满16个逻辑核心。不要为了提速关闭数值检查或厂商断言。

确认没有其它任务正在写同一个工程或结果目录，并检查本次允许的测试范围和预计耗时。原完整帧用例可能运行数小时，本轮工程复制/打开不自动授予这次长运行。

通过Report IP Status检查IP状态，按已批准的新工程流程生成必要输出。IP输出与仿真缓存是可重建产物，本次不会把旧机器的编译快照作为唯一依赖搬过来。

`sim/data`包含输入和参考。仿真在Vivado的`.sim`工作目录执行，不能假设它与项目根目录相同。必要的复制已写入 `tools/vivado/start_simulation_0ns.tcl`；纯GUI方式的文件部署必须和它一致，并先核查数据加载。

## 3. 打开仿真和查看波形

在已经批准编译/展开的条件下，可以在Vivado Tcl Console运行：

```tcl
source D:/008_MA_Dev/tools/vivado/start_simulation_0ns.tcl
```

该入口负责明确的编译、展开和文件部署，把仿真打开到0ns；它不是完整帧测试通过。随后在GUI的Run For里推进指定时间。不要把首段运行结果自动理解为整帧结果。

也可以使用Flow Navigator中的Run Simulation → Run Behavioral Simulation；但必须保证仿真设置、数据部署和记录方式与上述入口一致。不要选择综合后或布局布线后的仿真来代替行为仿真。

`tools/vivado/setup_waves.tcl`用于添加关键分组。先看时钟/复位，再看输入的valid/ready、帧号和计数，之后看T06结果、E1输出、T09点和最终输出。只有valid与ready同时为1才算传输一拍。

如出现未知值X、输入文件加载错误或断言失败，保存原始日志和第一处发生的位置。不要通过隐藏该信号或关闭原厂断言来得到表面通过。

## 4. 结果保存与离线分析

| 需要保留 | 作用 |
|---|---|
| xsim日志、编译/展开日志 | 查启动和运行错误 |
| data.csv、events.csv、points.csv、xpm_trace.csv | 查数据、估计和FIFO行为 |
| result.txt（只有完整结束才产生） | 完成标记；必须与其它证据一起检查 |
| WDB和WCFG | 回看已记录波形及恢复窗口分组 |
| compile_order.txt、IP状态及Git提交号 | 确认使用了哪个设计和哪套输入 |

原生运行结果默认在 `vivado/T10_SFO/T10_SFO.sim/sim_1/behav/xsim`。每次新尝试先保存旧结果到独立结果目录；不能保留旧result.txt让新尝试误判完成。启动脚本会拒绝已有关键结果，提醒先归档。

离线检查工具位于 `tools/analysis/`，用途和具体参数见[RTL迁移说明](RTL_MIGRATION_NOTES_ZH.md)。它们不要求仿真中在线启动MATLAB；独立Python环境仍需满足自身依赖。检查器必须看完整日志，不忽略未知错误。

`validate_gui.py`默认要求已冻结的 `docs/provenance/RTL_FINAL_MANIFEST.csv`，不会使用最初的复制快照作为当前输入清单。其参数依次为项目根目录、此次仿真目录、保存的完整原生日志和一个尚不存在的复核输出目录；可额外给出明确的新最终清单。`report_evm_gui.py`随后读取同一复核目录，补充误差统计。源码或IP再次修改时必须审阅差异并更新对应版本的清单，不能自动生成新哈希来掩盖变化。

长仿真默认不记录全部IP内部节点和所有存储器内容。需要调查某个内部错误时，在下一次必要的测试之前添加相关记录。WDB没有记录过的历史不能事后补出。

## 5. 搬到远程机器

复制完整项目根目录，保持内部相对结构；带上隐藏`.git`可保留版本历史。另一种方式是Vivado的Project Archive加上显式列出的MATLAB/数据/文档，但要确认归档没有遗漏运行时输入。

使用本地磁盘独立目录；两台机器不要共同写一份活动`.runs/.sim`。先确认远程Vivado、XSim和VU11P器件支持，再在新路径打开工程，检查IP并做短测试。远程Windows 11与NI附带Vivado 2021.1的组合仍需现场短测，不能凭本地打开成功宣称远程通过。

仿真结果可以带回本机，用Vivado的Open Static Simulation打开WDB。静态回看不需要重跑，但也不能恢复中断时的动态执行状态。
