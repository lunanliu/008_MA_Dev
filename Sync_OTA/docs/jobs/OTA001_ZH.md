# OTA001：新增外存事务与前端描述符短检查

状态：设计冻结后申请具体槽。仅本任务唯一Luna执行；未授权时不能启动Vivado。此包属于总任务五组风险检查中的缓存/调度及描述符部分，不是完整OTA通过。

## 不可混淆的工程身份
生产目标仍为未来的 Sync_OTA.xpr / sync_ota_top。这个首包创建两个小型、明确命名的测试工程，实际设计top分别为ota_frame_store和ota_frontend_descriptor；TB中的外部存储模型只是NI Target响应服务模型，不进入生产source set。无MATLAB、无旧任务恢复、无综合或布局布线。原三个工程保持只读。

Vivado：C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat（2021.1）；器件xcvu11p-flgb2104-2-e。执行目录固定本工程根；下面参数均作为独立参数传递，不构造二次shell代码。

```powershell
& 'C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat' -mode batch -source 'D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota001.tcl' -log '<attempt>/native.log' -journal '<attempt>/native.jou' -tclargs store '<attempt>'
& 'C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat' -mode batch -source 'D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota001.tcl' -log '<different-attempt>/native.log' -journal '<different-attempt>/native.jou' -tclargs descriptor '<different-attempt>'
```

每阶段分别在work/OTA001/store_a01与descriptor_a01创建全新输出目录。先store、再descriptor；首个功能/数值错误立即停止该失败阶段并交Astra，不继续运行后段来掩盖错误。普通命令/私有环境故障由Luna修复，新尝试目录保存原失败。通过阶段不重跑。入口支持单独执行受影响阶段。

## 输入与门槛
- source_lock.json逐项SHA256核对；Tcl从实际创建XPR导出源集并与两项明确输入比较，不能自比较清单冒充实际源集检查。
- 存储TB：8拍序号数据，全长/子范围两次回读共11拍；每拍值、顺序、索引、last检查；请求停顿及输出停顿；最后写响应前seal不可发布；读者存在时释放无效；取消排空；跨generation错误响应不归还信用、不输出；越界和64位地址回绕拒绝。
- 描述符TB：大于32位的实际绝对位置、相对TO=3、负150000Hz→F8，三路独立背压只接收一次；epoch/status/保留范围/F8溢出拒绝；取消清空。
- TB全局超时200us/20us仿真时刻；任何首错$fatal。只有完整检查后写result.txt。原生退出0还须两个对应PASS标记、无ERROR/FATAL、实际工程身份/源集正确、源哈希未变，并保留全部原生日志。Luna交证据，最终是否通过由Astra复核。

## 资源与保护
一个Vivado主作业，两个阶段串行；0 MATLAB。general/synth请求8，run PRE钩子实际回读；xelab16。每阶段预计2～6分钟，两阶段约4～12分钟，工具启动较慢时可达20分钟。每阶段墙钟保护20分钟，整包45分钟。估算峰值3～6GiB，8GiB仅告警；启动前核查实际全机余量及所有子进程，建议空闲不少于8GiB；资源不足下调实际xelab并另存入口修订/原因，不能改变科学源。

停止依据：用户停止、首个明确设计/数值错误、原生致命错误、具体作业严重系统资源压力、超过本包硬时间。日志暂不增长或轻微估算越线不直接终止。保留实际PID/创建时间与父子树；取消只针对本作业已核实的树，优先关闭自身仿真/工具，必要时按精确树终止；不得按进程名批量kill或动用户GUI。结束核对整棵树，不把runner退出视作全树结束。核对成功阶段完成标记后只修交接，不重算。

执行记录应包含命令及版本、源/入口哈希、实际线程、进程树、开始结束时间、峰值内存、通过/失败标记、首错和完整日志路径。本线程等待执行时停表；Luna按15分钟表格维持运行监控，完成一次回传Astra并请求归还具体槽。
