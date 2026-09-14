# CFO-GUARD002 独立复核（2026-09-14）

结论：正常/错误退出传播和自动 Job 取消时限通过；逐进程身份与瞬时资源统计未通过。原始三组计算均不重跑。本复核以原始日志、单调时间和最终 V2 清单为依据，逐项 hash 核验记录见 INDEPENDENT_REVIEW.json。

hold 的真实 READY 到自动触发为 3.1168282 秒，触发到内核返回空 Job 为 0.1370426 秒，总计 12.7289969 秒。正常/错误分别保留 exit 0/7。因 Job 句柄取消与 PID 解析是不同路径，错误的列表解析不否定这些已记录的取消证据。

缺陷是 ProcessIdList 使用 ULONG_PTR，而 v2 用 4 字节步长读取。三个模式分别有 9/9/12 个采样出现 PID 0，真实 Vivado PID 均漏掉，瞬时私有提交量因此为 null。v2 未将此作为验收失败，不能将其包装 PASS 当作完整监管 PASS。微软结构定义：https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_process_id_list 。

原配对 Luna 修正 v3 包装与 Win32 类型声明；先做纯解析核查，再在下一包只增加一次受影响的 hold 遥测探针。该探针通过后才能启动新控制器计算；不回放已通过的旋转器仿真。T10 没有被本次复核操作。