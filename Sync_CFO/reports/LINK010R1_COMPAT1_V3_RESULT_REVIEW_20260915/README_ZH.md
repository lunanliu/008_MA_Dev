# LINK010R1 compat1 v3 结果复核

当前结论：数值/协议证据通过，复位 PRE 观测证据阻断，不能验收整个 LINK010R1。仿真已正常结束，不需要因解析器报错直接重做已经成功的计算。

本次只运行一次 simulate，耗时 57.608 秒、native exit 0，43 个累计 Job 进程最终完整归零，私有 XPM 运行前后与事后检查通过。65 份原始产物逐一校验并独立保存；原 completion 的 BLOCKED_AFTER_SIMULATE 状态保持原样。

数值记录含 2056 次写入、2022 次读出、22 个完整结果、10 个协议错误、8 次取消和32次真实输出握手。原冻结验证器已走完身份及数值/协议断言，随后在 reset-audit 解析处失败；测试台 PASS 不能替代后续独立复核。

## 为什么不是简单修解析器

250 个 epoch=x 都位于 PRE，其中249个按独立事件时间属于初始epoch，另1个属于下一epoch；另有5个已知编号落后。更关键的是10条PRE复位相关位与标称采样时间矛盾。

一个明确反例：epoch3请求发生于2586002022 ps，10 ps后的A记录已确认复位有效；但标称2586002999 ps采样的PRE仍记为未复位，2586003010 ps的POST才记为有效。请求比PRE早977 ps，不能按原规则将它视为采样窗口内的新变化。这不是正常初始化，也不能靠统一补0或跳过该行解决。原始记录中所有X/Z均保留。

2926条Q、9条A、17条T、9条C及配对覆盖齐全，9次恢复均有对应POST见证。这些记录有独立价值，但不能补出不可信PRE的真实值；当前并未证明DUT本身错误。

## 现存波形与建议

另保存47,290,549字节的原始WDB，SHA见WDB_PRESERVATION.json。尚未打开其内部信号，不能断言其中没有所需历史；没有找到已确认的Vivado 2021.1既存WDB完整历史导出接口。[open_wave_database静态查看说明](https://docs.amd.com/r/2021.2-English/ug835-vivado-tcl-commands/open_wave_database)来自相邻版本；[open_vcd](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/open_vcd)与[log_vcd](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/log_vcd)是运行时捕获，不应冒充已保存WDB的离线历史导出。

建议准备最小被动观测修订：epoch和位向量打包成同一个显式64位wire供原#1step采样，在原10 ps等待结束后读取稳定PRE快照和POST，再执行原门。保留刺激、时钟、RTL、输入和全部阈值；候选尚未实现或证明有效。若获准，只需对同一链接层矩阵做一次修正观察后的simulate，复用成功create；不重做MATLAB、前端FFT或全CFO链。新原生运行必须重新冻结并取得新grant，旧grant不可复用。

WDB作为本地原始证据保留，不纳入普通Git源码。详细门、矛盾逐行记录和原始哈希见INDEPENDENT_REVIEW.json及RAW_AUDIT_TIME_CONTRADICTIONS.json。
