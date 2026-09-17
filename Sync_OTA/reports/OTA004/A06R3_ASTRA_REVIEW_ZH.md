# A06R3 本轮接收与独立离线复核

本次原 Luna 已成功向原 Astra 回传完整工程路径、哈希、命令、报告及进程证据，通信成功这一事实已确认。采用125723Z新准入；旧125152Z窗口未执行。13:01:05Z—13:09:36Z原生采集耗时约8分31秒；9阶段均CODE0。Astra逐项核对进程树314条记录/4个PID+creation身份，与summary集合一致，末3采样为空，无超时、取消或剩余孤儿。总管家负责中央槽归还。

## 接收结论

**完整证据已接收，可用于后续真实时序修复；原严格总闸FAIL仍保留，整体不标PASS。** 没有重开DCP或重跑成功综合。离线适配版本R1的格式失败和R2结果均单独保存，原执行入口、科学锁、原始报告及失败记录没有修改。

- 340个科学文件及5工具身份通过；DCP内容/器件/真实核心层级及零黑盒通过。
- 真实design.NAME为checkpoint_sync_ota_synth，design.TOP为sync_ota_top，project/design PART均为xcvu11p-flgb2104-2-e。旧把design.NAME等同RTL top的前提确实不成立；不能据旧守卫失败认定选错DCP。
- CDC299明细/9时钟块与冻结基线逐条一致；CDC1/13为零，12条CDC10仍仅接收既审精确复位端点；182条Warning保持OPEN。
- 六FIFO、24个Gray宏、128个目的位、512原查询对象、24份bus-skew完整核验。适配只处理真实报告中的get_cells表达式与折行，不改变scope、pin/cell集合、datapath_only或数值条件。
- 9组116路径已逐条核对TSV与原生报告的端点、时钟、slack、requirement及required/arrival/slack数值闭合；不是只检查完成标记。报告信息足以支持当前路径设计分析，不等于穷尽2587个失败端点。
- 12项离线正/负例检查通过，涵盖错误scope、端点集合、重复目的位、数值变化、截断、额外行和时序端点/底部缺失，不能把格式修复当成允许缺证据。

## 原生警告逐类保留

| 原生信息 | 事实及本次处理 |
|---|---|
| 2条Vivado12-4439 Critical | to集合574978/149471过大，提示性能/OOM风险；本轮查询完成、无OOM或截断、内存提交余量充足。原零critical闸继续FAIL，不新增豁免；不为消除历史日志重跑成功数据 |
| 9条Vivado12-1072 | -of_objects组合下-path_type/-input_pins被忽略，不能声称这些请求选项已生效；已直接逐条验证现有原生路径内容。后续报告入口应使用兼容参数 |
| 84条Timing38-127 | 原时钟周期在1000周期搜索内无共同周期；保留OPEN，不能仅凭此报告宣称所有CDC安全。Gray本次仅按已审精确端点与有效约束证据判定 |

AMD 2021.1 文档规定report_bus_skew的-cells限定层级、-no_detailed_paths输出摘要；原生文本必须按实际格式解析：[report_bus_skew](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/report_bus_skew)。report_timing的-of_objects消费已取得的路径对象：[report_timing](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/report_timing)。本机12-1072对选项实际被忽略的日志事实优先保留。

## 后续设计方向

综合未布局clk125 WNS+2.410ns（0失败）、clk150 -2.358ns（2240失败）、clk500 -1.279ns（347失败）。真实150MHz主路径穿过CFO一致性乘比较并传播到ready/存储使能；500MHz主路径穿过FFT索引变换、系数地址加法和BRAM选择使能。准备A07最小RTL修订，采用另存源码和明确源集，保留全部A06冻结输入；做受影响运算等价、流水对齐、多帧背压/取消短验证，再对新RTL做真实完整核心综合及分域复核。新的原生验证须另取具体准入。LabVIEW编译/布线、持续吞吐与板测均未通过宣称。

## 证据

- [R2离线逐项结果](A06R3_OFFLINE_EVIDENCE_REVIEW_R2.json)
- [保留的R1格式适配失败](A06R3_OFFLINE_EVIDENCE_REVIEW_R1.json)
- [12项格式正负例](A06R3_NATIVE_FORMAT_STATIC.json)
- [原生现场](../../work/OTA004/report_a06r3/native.log)
- [剩余交付清单](../../docs/SYNC_OTA_REMAINING_20260917_ZH.md)
