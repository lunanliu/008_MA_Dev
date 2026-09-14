# T09-CLOSED002-R02 输入记录修订

2026-09-08，T09 Astra。只修复复数描述符的持久化及检查点顺序，不改变信号、算法、整数运算、测试含义或验收门槛。原包和失败attempt完整保留。

## 原失败的证据与可接受结论

原包manifest SHA256为9431F2493171DF5B5105EC401C3CC7B47BB924710A8C4E6C5D5D59491B2746B6，64/64输入核验一致。原attempt为reports/t09/execution/T09_CLOSED002/attempt_20260908T205957780Z_luna。

MATLAB原生退出1，MATLAB:json:UnsupportedComplexDataType发生于t09_closed002.m原第83行写input_identity.json。descriptor.artifacts_snapshot内含完整复数前导/导频数组，JSON不能表示此对象。case_001只有0字节input_identity.json，没有完成raw_input.mat、第一遍或第二遍重采样检查点。

精确执行顺序：旧raw_window与实际RTL service_raw的逐整数断言位于原51–56行，已经执行通过；重新生成全帧与旧捕获的差异量在原76行计算，但结果没有发布；零差异断言在原84行，尚未执行。因此不能把新全帧同源输入身份门记为通过。C01/C02/C03准入成功、C04超范围拒绝的upstream_admission.json已完成，保留复用及新包一致性核对。

failure.json SHA256：71A9D6A7AE15A669D97AC27E17649F82B010F2BEE6F65D30D853174E9611E69D。
upstream_admission.json SHA256：3686F022DFA336C0180887F6C325C462AC5B6E72FFD636B3A81D0A8209EF0525。
supervisor_exit.json SHA256：25BCE320F82226662E78DF6A22E0138F86FC4DA83401419B801524DB9F55CBC8。

原生根进程于21:00:34.191098 UTC退出1；退出后自有Job于21:01:29.022550 UTC清零，间隔54.831452秒。清理supervisor125不掩盖原生失败；无硬超时，无其它任务进程接管。

## 新修订

入口改名t09_closed002_rev02.m；运行器改名run_t09_closed002_rev02.ps1；输出根reports/t09/execution/T09_CLOSED002_rev02。唯一Astra/Luna配对不变。

1. 完整descriptor保存source_descriptor.mat，复数快照一字不删；source_descriptor.json及input_identity.json仅保存元数据、MAT路径与SHA256。
2. 在昂贵通道计算之前完成MAT保存、JSON写入、MAT重新加载与isequaln精确回读断言。直接验证本次故障所在的真实描述符，避免跑完通道才发现同类格式错误。
3. 通道计算后的raw_input.mat先于身份JSON及身份断言保存，并记录哈希与差异计数。检查点中的identity_gate_asserted=false表示保存完成，不表示输入门已通过；仍须后续原有零差异及零削顶断言。
4. writeJson先在内存编码，再写临时UTF-8文件，关闭后提交最终文件。编码失败不会留下0字节最终JSON。
5. 运行器检查新增descriptor文件。原生成功码、退出后受控清理码和Job归零仍分开判断。

T06值、同源输入要求、两遍T07整数参考、74导频观察、2倍/4倍插值候选、局部CFO诊断、全部物理公式、<0.1ppm及无饱和目标均未改变。Astra仅静态核对差异并解析PowerShell；MATLAB实际回读与数值运行由唯一Luna负责。

## 必要重试范围

原失败前没有可复用的全帧raw MAT，因此必须重试尚未完成的C01输入生成阶段。C02/C03此前未开始。本包不重跑已完成MATH001矩阵，不启动任何T06/T08 RTL。若后续阶段失败，保留已有检查点与哈希；由Astra冻结下一次复用方案，禁止因日志/发布/交接错误重跑成功数值实验。

保持原三物理案例加一准入拒绝对照，1 MATLAB、0 Vivado，预计5–12分钟，原生硬超时1500秒，清理最多60秒，峰值内存计划8GiB，输出计划1GiB。超限或根本数值问题回交；普通命令/路径/私有环境/包装问题由Luna自行修复并记录。新manifest、DISPATCH为执行依据，原PLAN的数学范围继续有效。
