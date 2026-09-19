# 20%余量重构：先看这里

2026-09-18 CEST，V5.1_System_Modify。

**代码与静态审查已完成，20%时序余量尚未经过新布局布线验证。** 本轮27份活动RTL有修改；129份源集一致，顶层静态绑定0错误。未运行新仿真、综合或实现，也未提交Git。

目标按实际约束计算：普通125/150/500MHz分别至少+1.600/+1.333333334/+0.400ns；2ns CDC max-delay至少+0.400ns。精度、频率、持续输入和最终无背压保持。

主要变化是分段存储与局部命令、重采样分级选窗、宽运算分拍、FIFO预取和局部控制。保守raw峰值343571/393216字、CFO窗7/8；新增延迟已计入多帧预算。URAM仍848/960，旧SLR0局部资源密集问题必须看新版布局；BRAM可能比旧实测增加，未假称资源已变宽裕。

当前GUI若一直开着，先在此工程Tcl Console执行：

```tcl
source {D:/008_MA_Dev/Sync_OTA/tools/v51/configure_timing_margin20.tcl}
```

它只配置下一次实现。随后重新综合，再布局布线。读impl_1下新margin20_日期_时间_PID目录中的 **nominal_summary.rpt** 判断真实余量；tightened_summary是额外20%目标的实现视图。不要拿旧DCP或仅重新实现的旧网表评价本轮代码。

- [结构、备选、逐拍边界、周期与资源](../../../docs/v51/TIMING_MARGIN20_DESIGN_ZH.md)
- [每帧周期表](frame_cycles.csv)
- [闭式周期与缓存预算](final_static/cycle_memory_budget.json)
- [全部端点及实际约束分类](endpoint_margin_classification.csv)、[模块统计](module_margin_summary.csv)
- [精确代码版本](change_manifest.json)、[顶层静态绑定](semantic_final/summary.json)

数值比较、厂商原生展开、新资源/时序、持续硬件吞吐与NI集成均为未验证；静态代数等价依据已写入设计文档。
