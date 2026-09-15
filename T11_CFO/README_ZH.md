# T11–T13 独立 CFO 工程

本目录面向 Vivado 2021.1、xcvu11p-flgb2104-2-e，数学采样率500 MHz，硬件数据口4路、150 MHz。2026-09-14按用户最新恢复授权开发；不调用旧runner，不修改T10，不启动CLIP。

## 用户最新交付要求（2026-09-15）

最终交付仅包括：以算法核心为综合top的完整Vivado GUI工程、与其接口匹配的独立明文VHDL Wrapper、可复现输入/预期输出与易懂中文操作说明。CLIP XML和LabVIEW CLIP配置由用户亲自创建。Agent停止XML新增/生成/修补及自动CLIP配置包、Wrapper回填/独立Wrapper综合网表验证，不自动创建LabVIEW项目。

详见[最终交付边界与已验证核心入口](docs/DELIVERY_BOUNDARY_20260915_ZH.md)。该规范覆盖旧自动CLIP交付安排；历史保留。原LINK010结果与冻结包保留；当前复位修订LINK010R1另建工程和审查包，按独立资源准入执行。最终完整链路top尚未交付，不能用外围Wrapper或阶段子核替代。

## 2026-09-15 当前里程碑

FRONT009窗口前端已独立复核通过：82,026条pilot记录、98个z结果逐点一致，包含一个真实帧全部74窗口系数行，调整后服务周期15448。此前旋转核、坐标控制、74点相位、FFT256、估计后端及FFT2048已完成各自有限范围行为验收；详见各reports目录，不代表完整T11/T12/T13通过。

下一最小步骤LINK010已完成RTL、保存证据向量与静态审查，已按docs/LINK010_NATIVE_JOB_010.md冻结39份工程/证据文件与3份官方XPM依赖，源验证和资源helper静态检查通过；已完成原Luna执行和独立复核，当前为数值/协议通过但FIFO复位契约阻断。它把171位窗口观测消息通过500→150MHz XPM FIFO送到已冻结74点后端；四类结果、协议错误、背压、取消恢复及32次真实输出握手均纳入验证平台。输入复用FRONT009实际z与BACKEND006R1已有向量，不重跑MATLAB/FFT2048。原生结果为22完整帧、8取消、10错误、32真实握手逐位一致；异步置位直接驱动要求同步的FIFO.rst，且18条XPM诊断待精确闭合，因此LINK010尚未验收。详见[独立复核](reports/LINK010_REVIEW_20260915/README_ZH.md)。

复位修订LINK010R1已完成静态审查并冻结：只调整FIFO同步复位与两域恢复握手，增加被动边沿审计，保留原数值/协议矩阵。新包含60个冻结文件、3个官方依赖、25个工程成员；尚无R1原生通过结论。详见[修订契约](docs/LINK010R1_CONTRACT_ZH.md)、[执行审查包](docs/LINK010R1_NATIVE_JOB.md)和[静态审查](reports/LINK010R1_STATIC_REVIEW.json)。该工程已成功创建；首次simulate在XSim展开测试台时失败，尚未运行RTL刺激。41份产物已[封存复核](reports/LINK010R1_ELAB_REVIEW_20260915/README_ZH.md)。当前[compat1最小修复](docs/LINK010R1_COMPAT1_CONTRACT_ZH.md)仅更换八处clocking绑定写法并通过逐字节等价审查，复用已创建工程，只重试失败simulate；新清单为68份文件、3份官方依赖、25个工程成员。执行入口v3已补齐必需冻结记录保存成功门并通过定向静态复核；[精确仿真准入包](reports/LINK010R1_COMPAT1_V3_ADMISSION_PACKAGE_20260915.json)已获仅simulate的新grant，并通过成功的派单工具回执交给原Luna执行和监控；原生结果尚未收到。

共享槽以总管家resource_slot.json的即时授权为准；用户GUI编辑态不占计算组，但全部子进程内存计入准入；当前已切换至Sync_Frontend，按原Luna的会话感知准入逐次核查。T10持续受保护。缓存、两次全帧旋转、综合和物理CDC/时序尚待后续门限，不以接口行为仿真替代。

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