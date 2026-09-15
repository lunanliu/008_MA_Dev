# LINK010R1 compat2：仅被动观测可靠性修订

2026-09-15 本轮仅获本地准备与静态复核授权。不启动 native，不创建或重建工程，不派发执行任务，不跨任务回传结果；后续执行需要新的审查入口和精确 grant。原始证据及 WDB 保持原样，不将尚未确认的 WDB 历史导出接口当作前置阻塞。

## 为什么需要这项修订

compat1 v3 已完成一次57.608秒的链接层仿真，数值/协议及私有XPM绑定证据通过，但独立复位审计失败。它不仅有250个未知阶段编号，还存在5个已知编号与时间不符，以及10条PRE外部复位位与标称时刻矛盾。最小反例是复位已比PRE样点早977 ps，PRE仍记录旧复位位。详见 reports/LINK010R1_COMPAT1_V3_RESULT_REVIEW_20260915/INDEPENDENT_REVIEW.json。

因此，给未知编号补0、跳过行或放宽时间窗不能恢复原验收结论；原记录仍保留为失败证据。目前没有由此证明DUT错误。候选解释是clocking输入更新与同一时间槽内的消费顺序不一致，具体仿真器机制尚未确定。

## 唯一科学源变更

新建 sim/tb/cfo_estimator_link_r1_compat2_tb.sv，保留compat1文件不动。

将原32位integer阶段编号和原32位四态观测向量连接为一条显式64位wire，两个clocking block各仅采样这一条输入，仍用原 default input #1step。监视器在原触发时刻记录edge_ps，在原有唯一的 #0.010 ns 等待结束后，读取该clocking输入的稳定64位快照，拆出PRE编号及PRE位向量，同时读取直接POST，然后对这些值执行原检查。

PRE检查的执行时刻移到原POST检查时刻，但其输入仍应为clocking #1step采样值，不得用当前直读信号替代PRE。PRE时间标签仍为edge−1 ps，POST为edge+10 ps。阶段编号与位向量来自同一快照，保留X/Z，不重建编号，不补造旧样本。此实现是待原生验证的候选；静态等价性不证明XSim已正确采样。

## 必须保持的边界

- RTL、ROM、厂商XPM、输入向量、原数值模型和所有原验证器逐字节保留。
- fast时钟首上升沿1000 ps、周期2000 ps；slow首上升沿3750 ps、周期6666 ps；时钟相位、激励和请求持续时间不变。
- 原PRE禁读写门、POST释放顺序/credit门、真实变化时间窗、capture及16拍尾采样、A/T/C/Z记录与全部计数不变。
- Q仍为八列，PRE/POST时间、十进制编号、domain/phase、changed及32位二进制文本格式不变。
- 原verify_link010r1_reset.py不改；仍要求真实变化支持、完整配对、9次请求/恢复、8次FIFO复位置位与9次撤销、18段逐域恢复区间无缺样及恢复见证。原始未知值或时间矛盾仍会失败。
- 原矩阵保持22个完整结果、10个协议错误、8次取消、32次握手和2056次输入写入；不新增探针或矩阵，不重复数值算法研究。

## 本地冻结和未来工程使用

当前已创建工程为 D:/008_MA_Dev/T11_CFO/vivado/CFO_LINK010R1/CFO_LINK010R1.xpr，其compat1结束快照SHA256为73FD63F5F06F69DEDFFB88CF7351A0E8D607667385A2C4083B8987FD7546B1BF。目标part仍为xcvu11p-flgb2104-2-e，硬件top=cfo_estimator_link，仿真top=cfo_estimator_link_tb。

候选源集仍为25个成员，仅sim_1的compat1 TB路径替换compat2；另外24项及六列源属性不变，以封存的实际Vivado源表作为比较基线。当前本地准备不打开或修改XPR。科学锁中的候选源集不意味着实际工程已经选中compat2。

只读兼容检查器通过固定SHA绑定已静态审查的新TB，并比较候选实际源表；原数值/身份/reset-audit验证器和私有XPM绑定验证器继续使用，不放宽门。后续如获授权，原Luna仅需准备复用成功create的simulate入口，并单独冻结其命令、入口依赖及预算；不得复用旧grant，不重跑MATLAB、前端FFT或完整CFO链。

交付状态只能写本地准备和静态复核，不写native PASS、复位验收完成或完整T11/T12/T13完成。
