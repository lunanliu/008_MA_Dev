# OTA002/A01 Astra 限定复核

复核时间：2026-09-17 01:01 CEST。状态：三个冻结功能阶段 PASS；backend74 保留历史进程树证据缺口。

- 源锁 SHA256 `f0655da779236dc40026c06e9b63b0a6f8e0b0769447321a0883dd2b1ae4ef95`，41/41 长度及哈希一致。实际源集分别 12、20、28 项，全属于冻结清单。
- context：实际第一/第二 SFO descriptor 产生 context；原子握手、背压、取消清旧帧及 FIFO 写时钟同步复位通过。
- backend74：4 组各 74 项输入；296 项出 FIFO 数据和顺序逐项比较，4 个 530 bit 最终结果逐位比较；9 项部分序列取消、结果背压稳定性通过。
- cfo_control：真实 CFO 前后端和两个旋转器原生展开，3 个粗 CFO IQ beat 的外部写事务及待 ACK 取消排空通过。未执行完整帧粗/残余两次旋转数值闭环。
- 修复 Tcl 只调整根路径及另存 verifier 路径；parser 支持 PRJ 注释/续行。修复版模块名 startswith 比原正则的末尾边界较宽，Astra 已独立重新应用原精确边界检查，三阶段均通过；未据修复脚本的自报直接接收。
- 三阶段真实私有 XPM 绑定通过；综合原版与仿真私有版使用标志正确；8/8/16 并行参数有实际日志回读。原生日志和 XSim 下属日志无错误/断言失败，PASS marker 各唯一。
- backend74 的监控脚本 `$pid` 与 PowerShell 自动变量冲突，未完整保存历史子树；原生 PASS 可独立复核，但不能宣称完整历史树关闭。保留补录与原失败目录，不重跑算法补监控记录。context、cfo_control 有正常退出和记录树关闭。01:01 左右本机独立扫描无活动 Vivado/XSim/MATLAB 工具进程；此扫描仅证明当前状态。

机器可读证据见 ASTRA_REVIEW.json，复核脚本为 tools/review_ota002.py。具体资源 grant `SYNC_OTA_OTA002_A01_20260916T221248Z` 可由总管家归还；不得用于新作业。

下一步为完整 OTA 主控制、DDR 跨域/复用、实际 IP 依赖及工程连接。最终 XPR/DCP、完整 OTA、实现时序、持续吞吐、NI 集成、板测均未接收。
