# SF001：独立工程与迁入算术短等价执行包

Astra：01a0a162-c115-7af1-89be-49726f987f84；唯一Luna：01a0a161-e434-7142-8927-1f5314daafd5。范围仅本工程。资源grant=SYNC_FRONTEND_SHARED_VIVADO_20260914，启动时复读总管家resource_slot.json并核对配对。用户已授权，无需重复请示。

## 冻结内容和通过条件

以reports/design/SF001_files.csv为完整文件SHA锁。30个硬件SV、1个迁名TB、15个原始XCI及ROM/数据/工程入口。原样导入与更名分开提交；文件来源/哈希见provenance。正式硬件top本包为to_coarse_ports，仿真top=coarse_baseline_equivalence_tb；完整fine模块同时在同一sources_1中显式登记，暂不声称它已通过新工具验证。不得把本包作为自主捕获或CLIP发布。

本包顺序执行：
1. 验证冻结SHA、目标目录写入读回、全机进程树和可用内存。
2. tools/create_project.tcl创建vivado/Sync_Frontend/Sync_Frontend.xpr，检查PART=xcvu11p-flgb2104-2-e、实际SV集合完全相同、IP_COUNT=15、所有引用在新根或Vivado安装内。
3. tools/run_baseline_smoke.tcl打开同一XPR，原生生成本工程IP并执行SMOKE_ONLY的3例（0、27、29）；原TB的771个metric、6条结果、3对提交及phase/magnitude容差原样保留。必须看到T04_CURRENT_GENERATION_V2_SMOKE_PASS cases=3 case0=0 outage_case0=27 outage_case1=29及无Fatal；exit0不能代替。
4. 关闭后保存XPR、actual_sources、IP状态、全部原生日志、源和IP实际文件清单、IP CONFIG.*属性快照及生成后的part、线程实效记录。冻结原XCI不许改；只在Vivado管理副本里自动迁移/生成目标器件产物，不复用旧DCP。
5. 发布reports/SF001_completion.json，保留成功/失败证据；回交Astra正式复核。本包不综合/布局布线，避免在产品控制尚未加入时重复综合。

## 实际命令

在唯一新目录work/SF001_attempt_<UTC>启动，先记录时间/PID/哈希/空闲内存。工具固定C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat（2021.1）。PowerShell分别调用，不把两阶段放并行：

    & D:/008_MA_Dev/Sync_Frontend/tools/verify_sf001.ps1
    & C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -notrace -source D:/008_MA_Dev/Sync_Frontend/tools/create_project.tcl -log create_project.log -journal create_project.jou
    & C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -notrace -source D:/008_MA_Dev/Sync_Frontend/tools/run_baseline_smoke.tcl -log baseline_smoke.log -journal baseline_smoke.jou

第二阶段前必须确认第一阶段原生树退出。若第一阶段已创建成功但日志收尾失败，重开同一XPR继续，禁止删除成功工程重建。第一次失败保留attempt目录，包装修复另存版本，只执行必要失败阶段。

## 资源与保护

19:36左右现场仅T10 Vivado34768/XSim28856，可用内存约15.2GiB；此为快照，启动必须刷新。本包一个Vivado主树，MATLAB=0。general/synth线程8，xelab16；generate_target在一个主作业中顺序生成，不并行启动15个Vivado。预计创建1–5分钟，IP生成与短仿真5–30分钟；整个包预计10–40分钟，硬保护60分钟。RAM预估主树总峰值8GiB（告警值，非自动kill阈值），包括xelab子进程；严重持续分页/工具OOM/确认停滞时诊断受影响树，不能因小幅估算越线停任务。xelab若资源不够，允许降并发并记录理由，不得无理由固定2。

T10原树不可中断。取消仅对本次记录的根PID及经创建时间/父链确认的子孙；先正常取消仿真/退出工具，若硬超时或确证卡死再定向结束本树。根退出不能证明全树退出，保存后代及最终进程核查，不按名称批量kill。

## 可自行修复与回交

Luna可修复路径、转义、启动包装、日志/私有环境及Vivado属性命令兼容（不改变配置数值/位宽/检查含义）。官方IP若仅因part需重新生成，在项目副本通过官方命令进行并比较全部CONFIG.*参数未变；若工具要求改变算法参数、IP版本、延迟或reset选项，保存证据回交Astra。hash不符、功能数值不符、源集缺件或根本设计问题回交；普通包装错误不用逐次唤醒。

完成或重大障碍按SF001+attempt+event去重通知唯一Astra。无需运行MATLAB/长帧/双频/布局布线。工作期间每15分钟报告；Luna承担原生树监控，Astra派单后停表结束轮次。
