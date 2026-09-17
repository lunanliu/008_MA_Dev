# 本次DDR修改自审（2026-09-17）

本任务作者自审，不是外部独立复核。cwd D:/008_MA_Dev，唯一工程Sync_DDR；原配对停止，旧grant/旧失败目录只读。按用户批准方案完成两核修改；远端VI由用户搭建。

## RTL功能判断

1. 参数快照：命令接受沿锁存N/M/C及读检查选项，CONFIG_CALC登记M*K、N+K-1，再由CONFIG_CHECK判断。C、M、N为unsigned32，乘积/上界为64位，容量比较不会在65536处截断。等价性：N<=M*K<=N+K-1与M=ceil(N/K)相同；另查N>0、四点对齐、M>0、M<=C、C>0。活动期间Host改参数不影响当前任务。
2. 配置状态busy有效，不能Rearm/重入。失败没有DDR请求/H2T读取。run_enable暂停可延迟配置；abort/DRAM失效优先。generation只在配置合法进入工作状态后增加，非法命令不冒充新有效任务。
3. 写端仍由pending区分收集和提交，同一拍不同时修改Pack_Array与提交该数组。group计数宽度由K/4推导，offset单位U32。最后块未使用位置来自清零数组；Done前已提交M块。load_done没有物理写完成含义。
4. 读端保留256块总信用（在途+FIFO驻留），Current_Array另有一块。只按有效握手推进sent/group；首/尾标志来自当前sent与N，非单拍脉冲。N=4时两标志同真；最后组ready=0不会Done。已发DDR响应可在暂停时继续进入FIFO，取消则排空并丢弃旧数据。
5. 优先级与旧接口保持：写端abort先于DRAM失效；读端DRAM失效先于abort；二者均优先暂停。复位/故障不会伪称清空NI事务。扩容不改变既有数据位解释。
6. 两份VHDL仍是控制器，数据保存在LabVIEW，stream_word0..3是观察输入。真正输出数据及其保持由Current_Array寄存器+offset控制，不能只看VHDL端口就以为数据在核内。
7. 接线互斥属于远端Target会话控制；仅给两核接一个任意True的new_session_safe不能产生跨域互斥。新版教程用原子描述符/命令与状态消息避免异步busy交叉。此接线方案尚未在远端VI实装或验证。

## 时钟、资源与物理边界

- 写150MHz、读125MHz，TB时钟与这些数字一致；XDC仍仅为独立上传top的参考约束，不能据此宣称读核或NI整体时序通过。
- 新增参数乘法为编译常数乘法，寄存结果后再比较，没有动态除法或新增长ready链。物理资源/路径仍未综合评估。
- 默认K=40写端理想N/4+M拍；播放器理想N/4交接拍。DDR间隙或ready暂停增加真实耗时，不承诺固定首样本延迟。
- 不新增整帧RAM，波形FIFO深度保持。控制消息FIFO/新增首尾元数据纳入规划余量；不能把64块BRAM计划当作工具报告。没有新增URAM实例。
- DDR_WIDTH_BITS仅编译时可变，改变它必须同步改变NI Memory/数组/FIFO类型，不能运行时改变物理接口。
- U32容量不等于无限段长度，N最多0xFFFFFFFC；实际允许范围还受NI资源和下游Sync合同约束。

## 仍需平台对齐

- 1280bit逻辑元素与7903公开640bit/bank接口的映射。
- 最后写请求接受后，另一时钟域的后发读是否具备写后读可见性保证。NI通用读取顺序说明不足以证明跨访问器写完成；不得用任意等待拍数代替平台保证。
- 实际SCTL时钟、NI节点握手、跨域FIFO和Sync段准备/结束接口。

## 验证证据入口

实际阶段记录见 ../../work/runtime_config_v1/ 各attempt。create已通过5源/3top检查；attempt02写侧xvhdl通过但xelab因重复mt选项失败，写行为当次NOT_RUN。只修复两处Tcl线程属性，V1和V2清单及旧日志分别保留；最终结果在后续验证报告汇总，不由本自审提前宣称PASS。

源码端口清单见 ../DDR_CURRENT_PORTS_ZH.md，运行时/会话接线见 ../../docs/tutorial/LABVIEW_RUNTIME_CONFIG_AND_SESSION_ZH.md。

最终执行结果：create、write、read均通过；见[本次验证报告](DDR_RUNTIME_CONFIG_VALIDATION_20260917_ZH.md)。功能通过不替代上述平台条件。
