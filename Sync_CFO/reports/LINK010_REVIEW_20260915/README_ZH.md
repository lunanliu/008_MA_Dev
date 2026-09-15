# LINK010 独立结果复核

结论：**数值与协议有限范围通过，当前链接层RTL因FIFO复位契约问题仍不能验收。** 原始gate保持BLOCKED_AFTER_SIMULATE，不将报错简单屏蔽为PASS。

| 项目 | 已有证据 |
|---|---|
| 输入/读侧记录 | W2056、R2022逐条符合冻结预期，取消时未消费记录按场景核对 |
| 完整/错误/取消 | 22完整帧、10协议错误、8取消、32次真实输出握手；四种mode均覆盖 |
| 数值与元数据 | 全部530位输出与冻结预期一致；21个突发恢复/正常帧触发full与背压 |
| 行为周期 | 最大后端尾延迟6792慢周期；真实前端节奏用例最大总计1150366快周期；输入背压合计99481快周期 |
| 原生执行 | create12.424秒；simulate44.778秒；均自然退出，Job PID列表空且accounting=0 |
| 封存一致性 | simulate52个artifact全部哈希一致；42项冻结源/官方依赖不变；T10及用户GUI保护复核通过 |

create原生成功，原wrapper仅因ready标记贴近自然退出、未采到ready后的稳定遥测而失败。保存的11份采样已观察到该native PID；Luna以另存v2包装复用成功检查点，只运行simulate，没有重建工程。原失败记录保留。create清单引用的活XPR已被后续simulate保存；其原始哈希与封存CFO_LINK010_create.xpr一致，不能用当前活XPR反推旧清单损坏。

实质问题在rtl/cfo_estimator_link.sv：异步置位的rst_fast直接连接XPM_FIFO_ASYNC.rst；[UG9742021.1](https://docs.amd.com/r/2021.1-English/ug974-vivado-ultrascale-libraries/XPM_FIFO_ASYNC)规定该输入必须同步wr_clk。数值仿真通过不能证明这个复位接口满足硬件契约；早先静态审查遗漏此项，当前明确纠正。

18条XPM断言需单独处置。S-6/S-7各一次位于首个时钟采样，sleep硬0、WAKEUP_TIME=0却仍展开零长度序列。16条S-4使用下一拍rose(empty)，不能覆盖empty已经为1的合法情况；场景与该缺陷吻合，但没有逐沿导出的内部empty/busy证据，不能宣称每一条都已确证误报。详细时间和限制见XPM_ASSERTION_STATIC_REVIEW.json。它们与上述真实复位契约问题分开记录，不全局关闭SIM_ASSERT_CHK、不忽略所有ERROR。

compile-only XPM绑定探针不完整：用户RTL编译日志没有预编译库源；elaborate明确绑定xpm模块，xsim.ini指向安装目录预编译库。日志嵌入旧.t10work路径的3份源码均与冻结官方文件逐字节一致。本报告保存运行库指纹，但不把这些事实提升为已独立证明二进制到源码的完整构建链。

下一最小修复范围：为FIFO提供写时钟域同步复位，同时保留外部异步立即停流；检查两域busy期间禁止读写及取消后的信用恢复。另行给XPM三条诊断精确的逐沿证据/检查器处理和运行库来源核验。保持估计算法、向量与数值门限；新版本单独命名，旧源码、XPR、成功create/仿真及失败gate均保留。仅在最小受影响包冻结并获得新的manager资源grant后才运行，不能复用已回收旧grant。

本次复核只读取并复制已保存证据，没有启动MATLAB/Vivado、重算FFT/估计器、修改冻结实验或生成XML/Wrapper。完整CFO波形链、物理CDC、综合/时序和正式T11/T12/T13仍未验收。
