# 四个 DDR VHDL 控制器

时钟：ddr_upload_ctrl 150MHz；ddr_read_ctrl 125MHz；ddr_capture_ctrl 150MHz；ddr_download_ctrl 150MHz。每批四个U32复样点。

本包rtl/正好四个VHDL。capture依赖upload，download依赖read：导入CLIP时同时包含对应内核，不要漏文件。数据数组及NI FIFO/Memory仍在LabVIEW。不得把clk端口名称理解为自动创建时钟，请将每个CLIP与所在SCTL映射到同一实际时钟源。

请先读docs/LABVIEW_FOUR_STAGE_WIRING_ZH.md（含FIFO配置、全部新增端口、数据分支和反馈接线），再参照docs/DDR_FOUR_STAGE_DESIGN_ZH.md。

默认DDR_WIDTH_BITS=1280。两个150MHz写入器实际理想节拍为40点/11拍，约545.45MSample/s。125MHz回放峰值500MSample/s，150MHz下载峰值600MSample/s；已通过的行为测试不是物理时序/持续DDR或PCIe吞吐证明。

Host提供独立的N_in与N_out、对应M=ceil(N/K)及真实容量C。N必须正数且四点对齐，位宽为编译参数；结果长度未知直到结束的模式未实现。输入和结果DDR区域互不重叠，结果完整捕获并满足NI写可见性后下载。Host在下载进行时读取DMA，按N_out收齐，不能等download_done才开始读取。

reports/内为功能报告和两份原始短测simulate.log；原正向两核保持已有通过版本，未重复运行。未进行综合/实现/NI编译/板测。没有CLIP XML。

本地完整工程：D:/008_MA_Dev/Sync_DDR；GUI：work/four_stage_v1/attempt_01_create/project/DDR_Control.xpr。本包为LabVIEW接入源码包，不含Vivado工程和工具运行目录。
