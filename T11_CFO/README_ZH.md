# T11–T13 独立 CFO 工程

本目录面向 Vivado 2021.1、xcvu11p-flgb2104-2-e，数学采样率500 MHz，硬件数据口4路、150 MHz。2026-09-14按用户最新恢复授权开发；不调用旧runner，不修改T10，不启动CLIP。

## 当前可用内容

- 已批准完整黄金/自定义bit-true模型在 matlab/golden、matlab/bittrue、matlab/waveform。
- 唯一主参数为 docs/CFO_MAIN_CONTRACT.json；原算法报告为 docs/ALGORITHM_BASELINE_ZH.md。所有789份迁移文件逐文件比对源/目标SHA256，见 docs/MIGRATION_SOURCES.json。原文件保留。
- 已发布RCFO003/004大波形、逐点整数和统计在 sim/reference；迁移约1.665 GB。它们是已完成MATLAB证据，不是本工程的RTL结果。
- 首个实现是 rtl/cfo_rotate4.sv：四路复旋转、32位模相位、1024项S16/F14 ROM、RNE及S16饱和，保存帧号/generation/beat/last。输入配置为已换算相位字；粗CFO坐标换算控制器尚未纳入此里程碑。
- 工程由 vivado/create_project.tcl 显式创建 vivado/CFO_SYNC/CFO_SYNC.xpr；硬件top cfo_rotate4，仿真top cfo_rotate4_tb。当前只是补偿核里程碑，不冒充完整CFO顶层。创建成功后可在GUI打开同一XPR。禁止扫描目录自动加源。
- 首轮短向量涵盖2个已发布波形片段、正负CFO、正负RNE中点、饱和、背压、复位/abort及坏帧标识。每个数值case为2个OFDM符号。完整估计器、全帧回放及物理验证待后续里程碑。

## 验证与工作分工

Astra设计、冻结包与独立验收；唯一配对Luna执行/监控。新Vivado入口general/synth请求8线程并安装真实run PRE钩子；xelab/build jobs默认/上限16。MATLAB新入口自动计算线程，但必须取得既有中央串行槽的精确准入。当前首包不运行MATLAB。

source_lock由Astra冻结，执行前校验；工具还必须读取Vivado实际导出的源集与该清单比较。exit 0、文件齐全或源一致不能替代逐点数值、时序和持续吞吐验收。修复保存新版本及实际hash，不原地改已派包，不重跑已成功阶段。

读 docs/ARCHITECTURE_AND_MEMORY_ZH.md 了解缓存寿命、量化边界和吞吐待证条件；读 docs/IMPLEMENTATION_GATES_ZH.md 了解实现顺序。首批具体命令与保护条件见 docs/ROTATOR_NATIVE_JOB_001.md。本工程未声称正式T11、T12、T13 PASS。

## 本地版本管理

使用父工程D:/008_MA_Dev的Git，仅登记本目录源码、参数、清单与小型证据。sim/reference大波形在本机完整保存并由迁移清单校验，不将1.665 GB原始数据当作普通Git源码；跨机器复制时须按清单另外交付。work、Vivado生成缓存和仿真波形不进入源版本。首次本地提交在源包检查后执行；不暂存父目录T10改动、不推送远端。