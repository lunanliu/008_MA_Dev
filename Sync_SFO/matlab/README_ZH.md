# MATLAB 与定点参考入口

先阅读 [中文使用指南](../docs/MATLAB_REFERENCE_GUIDE_ZH.md)。

在 MATLAB 中进入本目录，运行 `p = setup_t10_reference(); info = inspect_full023_reference();`，只查看已保存数据清单，不生成新波形。

后续启动MATLAB不用 `-singleCompThread`；`setup_t10_reference()` 会恢复当前会话的自动计算线程并在 `p.compute` 中记录回读值。不会自动创建并行池。历史快照中的单线程启动参数只作追溯，不能照搬到新作业；详见[性能规范](../docs/TOOL_PERFORMANCE_ZH.md)。

- `data/full023_case6001/`：FULL023 实际使用的冻结参考。
- `source_snapshots/`：唯一指定的来源快照；其中旧 PS1/supervisor 是追溯材料，不是新工程启动入口。
- `provenance/`：原任务书、来源及复核记录。

不存在单一整条 T10 MATLAB bit-true 顶层；实际参考由 MATLAB 信号/整数重采样、已有 T06 结果、Python T09 定点运算及 AMD 官方 FFT 模型组成。本次仅复制和静态校验，未运行数值或 RTL 实验。
