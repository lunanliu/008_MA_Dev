# CFO_SYNC 与 LINK010 的入口、验证数据及功能边界

2026-09-15，文档补充；不启动或重跑任何实验。工程名称不表示整条CFO链已经完成。

## CFO_SYNC：只包含四路复旋转核

GUI入口：[CFO_SYNC.xpr](D:/008_MA_Dev/T11_CFO/vivado/CFO_SYNC/CFO_SYNC.xpr)。综合top为cfo_rotate4，仿真top为cfo_rotate4_tb，TB是[sim/tb/cfo_rotate4_tb.sv](D:/008_MA_Dev/T11_CFO/sim/tb/cfo_rotate4_tb.sv)。

该核接收外部给定的32位初相与步进控制字，对每拍4个复数样本做复旋转、RNE和S16饱和，并处理帧元数据、背压及取消。它不估计CFO，也不包含完整帧存储、窗口观测前端或整条CFO估计与补偿链。项目名中的SYNC不应被解释为“同步整链已完成”。

以下文件均位于D:/008_MA_Dev/T11_CFO/sim/vectors/，由ROTATOR_SOURCE_LOCK.json及ROTATOR_VECTOR_MANIFEST.json标识版本。

| 用例 | 波形输入 | 预期波形输出 | 预期逐分量饱和标志 |
|---|---|---|---|
| 0 | rot_case0_input.mem | rot_case0_expected.mem | rot_case0_sat.mem |
| 1 | rot_case1_input.mem | rot_case1_expected.mem | rot_case1_sat.mem |
| 2 | rot_case2_input.mem | rot_case2_expected.mem | rot_case2_sat.mem |
| 3 | rot_case3_input.mem | rot_case3_expected.mem | rot_case3_sat.mem |

配置文件是rotator_configs.svh，其中给出各case的phase_table/step_table；输入/期望每文件1280行，每行128位，表示一拍4个复数S16样本。TB将它们加上frame/generation/beat/last组成225位记录，并比较8位饱和标志。四个case共20,480个复样本。实际结果日志名为rotator_actual.csv，摘要为rotator_summary.csv；已有复核目录reports/CFO_NATIVE001_REVIEW_20260914。应使用已封存attempt的结果，不因本说明再次启动该TB。

此处是补偿算术核的有限范围功能证据，不代表带估计器的端到端CFO补偿、完整帧回放或板级吞吐通过。

## LINK010：观测值跨时钟和估计后端连接里程碑

冻结工程位置：D:/008_MA_Dev/T11_CFO/vivado/CFO_LINK010/CFO_LINK010.xpr；由原Luna的已派任务创建/使用。本说明不改动或另开该运行工程。综合top为cfo_estimator_link，仿真top为cfo_estimator_link_tb；TB是[sim/tb/cfo_estimator_link_tb.sv](D:/008_MA_Dev/T11_CFO/sim/tb/cfo_estimator_link_tb.sv)。

输入是窗口前端已经算好的74条z观测记录，经过500MHz→150MHz原子FIFO和帧协议检查后进入已冻结74点估计后端。本步骤不从整帧IQ重新运行2048点FFT，不包含完整帧样本存储和两次全帧旋转，也不把估计输出当作已经完成的波形补偿。

以下文件均位于D:/008_MA_Dev/T11_CFO/sim/vectors/，由LINK010_SOURCE_LOCK.json标识版本。

| 文件 | 用途与比较对象 |
|---|---|
| link010_input.mem | 四个case各74条正常输入，共296条177位前端记录；第一case为FRONT009保存的实际74窗口z，其余复用已验收后端向量 |
| link010_read.mem | 与正常输入对应的171位FIFO读侧预期记录，用于检查跨时钟后字段、顺序和完整性；它不是Host波形输出 |
| link010_result.mem | 四个case各一条530位完整结果：499位估计后端记录及31位链接错误/前端错误/饱和统计元数据 |
| link010_error_input.mem | 十种协议错误各一条终止输入；错误前缀由TB使用正常case0生成 |
| link010_error_read.mem | 十条终止错误的FIFO读侧预期记录 |
| link010_error_result.mem | 十条530位预期错误结果 |
| link010_config.svh | case数与错误case数配置 |
| link010_cases.json | 输入、读侧预期、最终预期及已保存来源哈希的完整描述；四种mode依次MAIN、DEGRADED、INVALID、ZERO |

已有静态检查见reports/LINK010_VECTOR_CHECK.json、reports/LINK010_STATIC_REVIEW_20260915.json。原生实际trace文件名link010_actual.txt：W为接受的前端输入，R为FIFO实际消费，F/E为待交付正常/错误结果，H为真实输出握手，D为取消丢弃。tools/verify_link010.py依据冻结预期逐条比较；正常/错误结果必须有H退休记录。固定矩阵为22完整帧、8取消、10协议错误、32次真实结果握手。它包含多次恢复用例，因此次数不同于四个唯一输入case。

LINK010已派原Luna执行；在实际completion、trace、原生进程树归零和独立复核完成前，不能写为行为验收通过。该里程碑即使通过，也只证明上述连接与估计后端范围，不证明完整CFO波形链、物理CDC或布局布线时序。

## 最终整链交付的门限

最终交付必须使用达到既有验证要求的完整CFO算法核心top，不能以cfo_rotate4、cfo_estimator_link或外围Wrapper替代整链。只有该最终核心及接口定版并通过相应既有验证后，再交付与它精确匹配的独立明文VHDL Wrapper、可复现数据和Host中文操作手册。

Host手册应围绕最终接口说明端口设值、时钟复位、IQ/打包顺序、valid-ready背压、装载/DMA发送/读取/比较和成功失败判定；本文件中的内部177/171/530位观测与诊断记录不能被直接宣称为最终Host DMA协议。CLIP XML及LabVIEW CLIP配置仍由用户创建。

本补充不改变LINK010源锁、XPR、入口、原生任务或实验矩阵；不为规范交付新增Wrapper回填/综合网表验证，也不重新派单或唤醒原Luna。