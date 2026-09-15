# LINK010R1 测试台兼容修订 1

2026-09-15 总管家授权在原 CFO 恢复范围内修复。原 R1 create 已成功；simulate 在 XSim 2021.1 elaborate 阶段报 43-4412，尚未执行刺激。失败的 41 份产物已封存于 reports/LINK010R1_ELAB_REVIEW_20260915；不重做 create。

唯一科学源变更为 sim/tb/cfo_estimator_link_r1_compat1_tb.sv：两个 clocking block 的显式 input 别名改为同名绑定，更新四个 clockvar 引用，共八处。反变换与原 R1 测试台逐字节相等。两个 #1step、POST #0.010 ns、四态信号类型、刺激、trace、复位审计、数值和周期门槛均保留。RTL、ROM、厂商模型、数据和原验证器均不改。该写法是否解决工具兼容问题仍需 native 证明，静态审查不能代替通过结论。

## 工程与执行边界

仅复用 D:/008_MA_Dev/T11_CFO/vivado/CFO_LINK010R1/CFO_LINK010R1.xpr，在其 sim_1 精确替换旧 TB 为新 TB，保持全部源属性及另外 24 个成员。现存失败模拟后 XPR SHA256 为 5123211F34830D04D27268E252715051FFE5D53C07E75674E15D4D25B356DB0F；成功 create 和失败 simulate 快照各自保留。part 为 xcvu11p-flgb2104-2-e；硬件 top 为 cfo_estimator_link，仿真 top 为 cfo_estimator_link_tb。

只重试失败 simulate 的编译、展开和原矩阵运行。Luna 单写执行 Tcl、wrapper 和 GUI 准入修复；其单独冻结的入口/依赖哈希必须纳入总管家新精确 grant。科学清单不代替执行入口身份。不得重跑已通过 FFT/MATLAB/原 LINK010，不扩充实验矩阵，不综合或实现。未经新 grant 不启动 native。

资源沿用 1 Vivado、0 MATLAB，本组峰值预计 1.5–3 GiB、4 GiB 告警；启动可用内存至少 6 GiB；阶段预计 30–180 秒、硬超时 600 秒。general/synth 8、xelab 16；全局不超过两个计算组，保护 T10 与用户 GUI。私有 Job 和严重内存压力保护沿用原审查包，完整 Job 双重归零后交接。

## 验收

新 verify_link010r1_compat1.py 检查旧 60 份冻结文件、3 份官方依赖、八处等价变换；带 --sources 时，将当次 Vivado 实际 CSV 与封存的原实际 CSV 比较，只允许 TB 路径变化，25 项成员与全部属性必须一致。旧 verify_link010r1.py 继续检查身份、数值 trace 和 reset audit；不将其旧 --sources 判定套给新 TB。原 verify_link010r1_binding.py 必须在运行刺激前及保存结果后校验当次编译/展开的私有 XPM 绑定。若增量编译无法提供完整当次证据，应由 Luna 使用工具支持的当次重新编译设置，不得放宽绑定门。

通过仍要求原门全部满足：22 个完整结果、8 次取消、10 个协议错误、32 次真实输出握手、2056 次输入写入；复位 A/T/C/Z 计数及每时钟 PRE/POST 条件全部通过；无原生 ERROR/FATAL，源/入口冻结无变化，完整 Job 归零。修订仅属链接层行为验证，不代表完整 CFO 链、T11/T12/T13 正式通过或物理时序达标。
