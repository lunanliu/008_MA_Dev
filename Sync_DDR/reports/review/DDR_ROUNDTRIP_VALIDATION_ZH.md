# 四控制器透明回环运行结果

2026-09-17。本轮新增一次四核相连的XSim行为验证，结论PASS。四个生产RTL不修改；上一轮四个角色测试不重跑。Sync位置为透明直通，不能把本结论称为Sync算法或真实板卡回环通过。

## 实际运行与数据

链路：Host模型 -> Upload150 -> 实际写入的输入Memory数组 -> Read125 -> 有限125/150结果FIFO -> Capture150 -> 实际写入的结果Memory数组 -> Download150 -> 有限DMA FIFO -> Host模型。

两个读响应均取自上游实际写入的Memory变量，未用期望函数替代DDR返回。Host接收文件由VHDL textio在成功出队时写出，受控runner逐项与冻结期望CSV比较，另用交付的Python比较工具独立核对。

| 项目 | 实际结果 |
|---|---|
| Host接收长度 | 604个U32，2416字节有效数据 |
| 与原始输入逐点比较 | 0错误、无缺点/多点、顺序一致 |
| 首/末U32 | 0x12340000 / 0x1234025B |
| 输入DDR / 结果DDR | 各写16个元素，地址0..15 |
| DDR末块 | 4点有效、36个零，零不输出Host |
| 两读侧交接 | 各151组四点 |
| 结果FIFO反压 | 暂停capture填满有限FIFO；Read125停止推进并保持当前四点，恢复后继续 |
| DMA反压 | Host停读填满有限DMA；Download150保持，恢复后逐点收齐 |
| 提交完成与实际收齐 | download_done出现时DMA仍有数据，Host随后继续读至604 |
| 原生标志 | DDR_ROUNDTRIP_TEST_PASS恰好一次 |
| 编译/展开 | xvhdl、xelab通过；xelab --mt 16，general.maxThreads=8 |
| 诊断/收口 | 无ERROR/FATAL/断言失败；两阶段exit0且所属完整Kernel Job末三次为空 |

关键文件：
- work/roundtrip_v1/attempt_02_roundtrip/native_logs/simulate.log
- work/roundtrip_v1/attempt_02_roundtrip/native_logs/host_received_u32.csv
- examples/roundtrip_604/simulated_host_received_u32.csv（逐字节复制原生接收文件，标明是仿真数据）
- reports/operations/ROUNDTRIP_VALIDATION_RESULT_20260917.json
- examples/roundtrip_604/SIMULATION_EVIDENCE.json

实际接收CSV SHA256：FEC8B6B5054368F51E59041E6FEC1730B6F897695F067F832D63D78A7CDF0DA2。

## 工程与资源窗口

新工程work/roundtrip_v1/attempt_01_create/project/DDR_Control.xpr，明确4RTL、5TB、2独立约束集，11项实际成员/6top匹配冻结清单。只运行sim_roundtrip，其他四个sim fileset保留可浏览但未运行。

冻结FROZEN_ROUNDTRIP_V1.json的21输入及5工具哈希执行后全部一致。预算起点21:15:38.3635811 CEST，真实首次根PID28236创建21:15:38.4127366 CEST；固定整体截止21:25:38.3635811 CEST。create于21:16:01.0829445完成收口，roundtrip于21:16:59.6851395完成收口。无原生失败/重试；完成后申请总管家归还，不再启动EDA。UTC原生日志保持原样，报告显示CEST UTC+02:00。

环境提示为HLS路径缺失、未使用的默认.gen目录不存在，以及外部threads_pre.tcl钩子未列入utils_1；本次不使用HLS、不生成IP、不运行综合。复制完整本地工程时保留scripts目录；接入包只交付四RTL与教程/数据，不声称是Vivado Archive。

## 设计自审及限制

四个实例实际时钟分别150/125/150/150MHz；NI节点的下一拍ready许可在所属域反馈一次，当前数组保持和实际交接分离。输入和结果Memory独立，读取前在模型中等待明确可见性条件。测试同时检查数据流、计数、内存内容和Host独立出队结果，没有放松功能门槛。

这条测试的异步FIFO是容量/原子数据契约模型，不含物理Gray同步器或亚稳态；TB按本域边沿发命令，未执行真实Host/Target会话消息实现。仿真用的3周期写可见性只是模型参数，不是远端NI推荐等待值。实际NI写后读保证仍须按远端版本/接口确认，Error输出不等于写完成。

604点是运输链路测试，不是OFDM帧。用实际Sync时，必须按其输出合同设置N_out，并比较同步参考输出，不能期待与输入原样相等。生产RTL已知长度、每次四点的限制不变；未知长度last驱动写入未加入。

本轮不执行综合/实现、NI编译、板测、MATLAB或远端发布；不更改其他工程/模型设置，不新建任务或worktree。真实150/125MHz时序、DDR/PCIe持续吞吐、真实CDC/NI硬件及Sync算法均未由本测试验收。

## 零基础交付

从docs/tutorial/LABVIEW_ZERO_TO_ROUNDTRIP_ZH.md开始：导入四CLIP、配置时钟/Memory/FIFO、四段含分支接线、会话命令与启动次序、Host数据构造/接收/逐项比较、正确结果和故障定位。更详细新增端口清单在LABVIEW_FOUR_STAGE_WIRING_ZH.md。所有604点输入/期望/实际模拟接收文件在examples/roundtrip_604。

## 最终资源收口

总管家于2026-09-17 21:19:18 CEST正式归还窗口；grant已关闭且不可复用。回执为SYNC_DDR_ROUNDTRIP_V1_RESOURCE_RETURN_20260917.json，SHA256为FA08024A6C29096281B73E564883218B16563DE508FBDA0F8B4CFC62D586C073。此后只整理文档和交付包，没有重启EDA。
