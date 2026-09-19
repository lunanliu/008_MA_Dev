# DDR写入与读回：纯VHDL控制器和独立LabVIEW测试方案

2026-09-16；PXIe-7903-DDR1280；每个IQ样本32bit，DDR每元素40个U32。

**这是两份直接导入CLIP的VHDL源文件，不需要先生成DCP。** NI原生FIFO、DDR节点和数组移位寄存器保留在LabVIEW；频繁分支、状态跳转、计数、预取、换块、停顿统计和编号数据比较放入VHDL。

## 从哪里开始

1. [独立测试VI搭建和验收指南](BOARD_TEST_GUIDE_ZH.md)：先看它，含两个SCTL、两种测试模式、Host步骤与500MS/s判断。
2. [上传控制器接线](UPLOAD_GUIDE_ZH.md)：对应已经搭好的R2.1第8节，原模块保留方式与每条Select接线。
3. [读控制器端口及接线](READ_PORTS.md)：DDR Request/Retrieve、预取FIFO、Current_Array和四点输出的完整端口表。
4. [原生验证状态](VALIDATION.md)：源码、仿真、NI编译和板测分别列出，不能互相替代。

| 导入用途 | 唯一源文件 / entity |
|---|---|
| 上传CLIP | [rtl/ddr_upload_ctrl.vhd](rtl/ddr_upload_ctrl.vhd)，ddr_upload_ctrl |
| 读回CLIP | [rtl/ddr_read_ctrl.vhd](rtl/ddr_read_ctrl.vhd)，ddr_read_ctrl |

两核无相互entity依赖，每个CLIP分别只导入其对应源文件。纯VHDL-93、IEEE标准库、std_logic/std_logic_vector端口，不需要独立Wrapper。测试台、Tcl、XDC、MATLAB文件不导入CLIP；不提供CLIP XML，由用户手工创建。

本目录rev02是写、读两核的统一交付目录；开发草稿rev01原位保留。原R2.1/R2.2指南、算法工程以及用户VI均未修改。

## 本版本边界

- 正常完成后可在安全条件满足时直接再次装载、再次读回，不需要重新下载FPGA。
- 读侧Abort会进入DRAIN：收完未决DDR返回并排空预取FIFO，再允许恢复。DRAM就绪丢失和Target Reset不等同于安全排空。
- 输入DMA和返回Host的DMA不由控制器自动清理；异常恢复先停止生产者并处理旧数据。
- 可用硬件编号比较验证数据完整性，或把全部原始波形读回Host逐点比较。
- 硬件周期计数计算本次有限波形的有效速率；实际CLIP整合、NI时序闭合和板测仍须完成。
- 这是独立DDR测试VI方案，不包括把Sync_Frontend算法串入读回通路。DDR闭环通过后再做算法连接。

[官方支持依据：NI外部IP导入与CLIP端口映射](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA03q000000x0jiCAA&l=en-US)。纯VHDL可直接导入，但最终FPGA VI仍需要LabVIEW编译。