# T11–T13 最终交付边界与已验证核心入口

生效：2026-09-15。来源：总管家任务01a06e5a-ad5f-7bb3-9fb2-a4eb4560bbb7转达的用户最新直接硬要求。本规范覆盖此前自动CLIP打包、XML生成/修补及自动配置包交付安排。旧文件和历史证据保留，不作为继续这些工作的授权。

本次更新仅维护交付规范与工程入口，不代表最终整链已经交付。冻结LINK010按原派单继续；不改源锁、正在使用的XPR、RTL、TB或入口，不扩展实验矩阵，不为文档重跑任何阶段，也不向原Luna另发工作或复核唤醒。

## 最终只交付三类内容

1. **算法核心RTL工程**：可直接在Vivado 2021.1 GUI打开的完整XPR及全部依赖，part固定xcvu11p-flgb2104-2-e，包含约束、IP/ROM初始化、TB、明确source set、核心top、仿真top与已完成功能验证证据。综合顶层必须是算法核心；最终整链使用真正完整CFO算法核心top，不将外围Wrapper设为综合网表顶层。交付源版本/哈希和GUI操作说明，供用户手动综合并导出DCP或其他网表。
2. **独立明文VHDL Wrapper**：与交付核心端口严格匹配，独立文件，可读、可编辑，清楚给出实体、component及port map对应关系。Wrapper与核心的方向、类型、位宽、符号解释和常量映射必须一致。它是外围连接文件，不替代核心综合top。停止Wrapper回填和独立Wrapper综合网表验证；不因整理交付而启动这类运行。
3. **可复现数据与中文操作说明**：输入、预期输出、数据格式、来源版本/哈希和比较方法一同交付。让用户能够逐步设值、装载、发送、读取、比较，并明确成功与失败如何判定。只引用已经完成、适用于该核心版本的功能验证证据，明确行为、综合、物理时序和板级验证各自状态。

CLIP XML与LabVIEW CLIP配置由用户亲自在LabVIEW创建。Agent立即停止新增、生成、修补XML及相关自动CLIP配置包；不自动创建LabVIEW项目。不得以交付需要为由继续上述自动操作。用户的模型、推理强度及速度设置保持不变。

## 当前已完成阶段的GUI入口

下表从各XPR的sources_1.TopModule只读核对。它们是已验收的阶段核心，不是完整CFO链。打开XPR查看不等于新增综合授权；任何后续原生运行仍遵守当时的资源准入和任务授权，运行中的工程不由文档整理任务修改。

| 阶段 | Vivado GUI工程入口 | 核心综合top | 已有证据目录 |
|---|---|---|---|
| 四路复旋转 | [CFO_SYNC.xpr](../vivado/CFO_SYNC/CFO_SYNC.xpr) | cfo_rotate4 | reports/CFO_NATIVE001_REVIEW_20260914 |
| 坐标/相位控制 | [CFO_COORD.xpr](../vivado/CFO_COORD/CFO_COORD.xpr) | cfo_coordinate_control | reports/CFO_COORD003_REVIEW_20260914 |
| 74点相位估计 | [CFO_PHASE74.xpr](../vivado/CFO_PHASE74/CFO_PHASE74.xpr) | cfo_phase74_core | reports/PHASE004R1_REVIEW_20260914 |
| 256点FFT | [CFO_FFT256.xpr](../vivado/CFO_FFT256/CFO_FFT256.xpr) | cfo_fft256_core | reports/FFT005_REVIEW_20260914 |
| 74点完整估计后端 | [CFO_BACKEND74.xpr](../vivado/CFO_BACKEND74/CFO_BACKEND74.xpr) | cfo_estimate74_backend | reports/BACKEND006R1_REVIEW_20260914 |
| 2048点FFT | [CFO_FFT2048.xpr](../vivado/CFO_FFT2048/CFO_FFT2048.xpr) | cfo_fft2048_core | reports/FFT008_REVIEW_20260914 |
| 2048点窗口/导频前端 | [CFO_FRONT2048.xpr](../vivado/CFO_FRONT2048/CFO_FRONT2048.xpr) | cfo_front2048_window | reports/FRONT009_REVIEW_20260914 |

LINK010已派原Luna执行创建及行为仿真，工程位置为vivado/CFO_LINK010/CFO_LINK010.xpr，冻结核心top=cfo_estimator_link，simtop=cfo_estimator_link_tb。实际结果已独立复核：数值/协议通过，但FIFO复位契约与XPM诊断尚未闭合，当前交付表不将它列为已验收版本。不得为迎合交付目录重建、修改或复制正在使用的工程来替代冻结实验。

最终完整CFO核心top及匹配VHDL Wrapper尚未交付。上述分阶段XPR不能冒充最终整链；最终入口须绑定完成整链验证的真实核心版本，并保留相应约束、IP、TB和功能证据。

CFO_SYNC只对应cfo_rotate4复旋转单核，CFO_LINK010只对应cfo_estimator_link连接里程碑；两者均非完整CFO链。各自TB、输入/预期文件、配置和比较含义见[CFO_SYNC与LINK010入口及验证数据](CFO_STAGE_ENTRY_DATA_20260915_ZH.md)。最终整链核心达到既有验证要求并定版接口后，再交付精确匹配的独立明文VHDL Wrapper和Host手册，不因工程名提前宣称整链交付。

## 中文说明必须回答的操作问题

端口表按最终核心逐个展开，不能只给信号分组概述。每个端口写清：名称、输入/输出方向、Verilog和VHDL类型、位宽、signed/unsigned、定点格式、物理单位、所属时钟域、复位值，以及用户应该驱动它还是观察它。对输入端口给出具体设值、设值时间和允许范围；仅当接口明确允许时，说明未使用时可以接的常量。

时钟/复位说明包括频率、有效边沿、异步/同步语义、复位极性、持续时间、释放顺序、busy期间行为和何时能够开始输入。完整列出IQ复数顺序、lane顺序、每个打包字段的位段、大小端和Host文件字节顺序；用一组实际输入数据同时展示原值、十六进制编码与一拍端口数据。不能把不同阶段的171/177位观测记录、530位估计结果与波形接口混作同一DMA格式。

valid-ready按发送端、接收端分别解释：在哪个时钟沿算接收；valid=1且ready=0时哪些字段必须保持；何时可以前进到下一拍；帧边界、frame/generation、last及错误/取消后的重启方法。对有界背压、缓存容量和持续速率，只写已完成证据支持的范围。

Host操作按以下顺序形成可直接照做的步骤：选择并校验输入/预期输出文件；加载配置与帧参数；按格式打包并发送DMA；按期望长度和帧号读取结果；解包、比对字段和样本；定位第一个不一致的位置。说明超时、长度不符、溢出/下溢、重复/丢失、INVALID/DEGRADED及协议错误分别如何识别。预期为bit true时按整数/逐位比较；若某项允许误差，必须列出数值、单位、适用条件和已批准来源。

Host/DMA端点、寄存器地址、LabVIEW映射和实际可执行步骤须与最终核心及用户亲建的LabVIEW配置一致。当前没有冻结的项目专用信息应明确标为尚未确定，不编造端点、地址或所谓已完成板级操作。说明可以教用户如何手动填写，但Agent不代为创建CLIP XML或LabVIEW项目。

## 后续整理与验收原则

交付清单为每个文件标明用途和对应核心版本，明确源文件、独立Wrapper、输入、期望输出及已完成报告。操作说明中的GUI顶层选择须与XPR读回一致；Wrapper不得成为综合顶层。相对路径/依赖完整性与端口对应关系可在静态整理时核查，但本次文档要求不授权任何额外原生实验或冻结实验重跑。

用户可在交付完成后按说明自行打开核心工程，查看Design Sources/Simulation Sources、确认part/top/约束/IP，再手动运行综合及导出所需网表。具体导出步骤随最终选定核心工程和工具版本验证后写入交付说明，不在本次说明中声称已完成新的综合或网表验收。