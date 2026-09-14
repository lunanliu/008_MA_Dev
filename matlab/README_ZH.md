# MATLAB 与定点参考入口

先阅读 [中文使用指南](../docs/MATLAB_REFERENCE_GUIDE_ZH.md)。

在 MATLAB 中进入本目录，运行 `p = setup_t10_reference(); info = inspect_full023_reference();`，只查看已保存数据清单，不生成新波形。

- `data/full023_case6001/`：FULL023 实际使用的冻结参考。
- `source_snapshots/`：唯一指定的来源快照；其中旧 PS1/supervisor 是追溯材料，不是新工程启动入口。
- `provenance/`：原任务书、来源及复核记录。

不存在单一整条 T10 MATLAB bit-true 顶层；实际参考由 MATLAB 信号/整数重采样、已有 T06 结果、Python T09 定点运算及 AMD 官方 FFT 模型组成。本次仅复制和静态校验，未运行数值或 RTL 实验。
