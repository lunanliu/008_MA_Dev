# SF002 冻结执行包

唯一执行Luna=01a0a161-e434-7142-8927-1f5314daafd5；Astra=01a0a162-c115-7af1-89be-49726f987f84。授权同步前端自主捕获，资源grant仍SYNC_FRONTEND_SHARED_VIVADO_20260914；每次启动复核resource_slot.json、本机最多2 Vivado/本对1、无MATLAB。原T1034768/28856不可中断。

## 冻结与命令

源码/输入见reports/design/SF002_files.csv及docs/SF002_DESIGN_ZH.md。原SF001 verify仍通过；本包新增4个硬件SV、2个TB、连续输入与独立truth。科学源码/输入/checker不能由Luna修改。沿用已经生成成功的15个FLGB IP，不重复SF001、不重新综合或生成成功IP。

唯一XPR为vivado/Sync_Frontend/Sync_Frontend.xpr。硬件top由原基座更新为sync_frontend_top，新增sim_autonomous fileset、仿真top=sync_frontend_tb，保留sim_1的SF001证据。脚本导出实际sources_1并严格比对34个SV；15个IP及ROM保持原绑定。复制已冻结ROM到新仿真cwd只是数据准备。truth路径只进入sync_passive_checker，驱动/DUT无frame_id、frame_start或真实sample_index输入。

先在新work/SF002_attempt_<UTC>验证所有文件SHA，记录原生版本、内存/进程树/脚本SHA和本次真实命令，然后运行：

    & C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -notrace -source D:/008_MA_Dev/Sync_Frontend/tools/run_autonomous_short.tcl -log autonomous_short.log -journal autonomous_short.jou

原生执行只跑这个入口，对应同一真实XPR；禁止另拼隐藏编译源集。若Tcl属性/路径命令兼容有错误，可另存私有包装修订并保持设计语义；SV编译/科学数值/协议错误保留证据交回Astra，不改RTL或TB绕过。

## 完成门

必须同时看到SF002_PASSIVE_CHECK_PASS frames=4、SF002_FRONTEND_MAIN_PASS、SF002_SESSION_CONTROL_PASS、SF002_AUTONOMOUS_SHORT_PASS及正常finish/退出，无Fatal/科学checker错误。逐点独立S&C算术/阈值、4个未知lane位置、有效内部帧号0..3、精TO零样点误差、CFO≤1000Hz、假候选拒绝、结果128拍背压、会话中断/中止/重启/复位均不得跳过。保存autonomous_results.csv、完整simulate.log、xelab/xvlog日志、actual_sources、IP状态和XPR。executable exit0不是PASS。

总输入60324样点=15081beats，块间固定8000拍停顿，全部4帧不复位；真值仅被动检查。预计首编译2–10分钟，仿真3–15分钟，总5–25分钟，硬保护60分钟。内存主树峰值估算8GiB（告警），20:05 UTC约14.8GiB可用；启动重读。general/synth8、xelab16；本包无综合run启动，build jobs上限16保留；资源不足可调xelab并记录原因，不无理由固定2。

第一次确定性错误立即保存具体周期/数据/坐标/候选及worker状态并结束失败attempt；不能等900000周期TB保护才检查。正常结束需确认本次原生树归零；取消先正常工具退出，必要时仅按本次PID/父链/创建时间定向收尾，不按进程名kill。保留成功阶段和所有失败记录，不重跑SF001或别的任务。只修必要失败阶段；不因发布/日志问题重仿真。

完成/重大障碍按SF002+attempt+event去重回交Astra；报告期间由Luna持续监控。发布reports/SF002_completion.json，状态PASS_PENDING_ASTRA_REVIEW或明确失败。尚不授予持续吞吐、综合/实现/CLIP及板测PASS。
