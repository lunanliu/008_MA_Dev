# GUI仿真完成后的离线检查

仿真期间不调用Python/MATLAB。本目录保留原FULL023验收算术和转义实例名修复，运行完成后再分析保存的文件。FIFO检查绑定当前完整核心的32个FIFO、64个时钟域观察点；旧RUN001中仅11个FIFO的回放不能作为当前核心通过证据。日志里的最后时间戳仅表示已观察到的事件，不代表仿真已完整运行到该时刻之后。

先关闭/停止XSim并保存完整原生日志（含厂商错误上下文和T10_FULL023_PASS结束标记），不要只复制Tcl命令历史。不要将旧result.txt/CSV混入新仿真目录。推荐使用tools/vivado/start_simulation_0ns.tcl，它在开始前拒绝已存在的结果，并导出实际编译顺序；直接点GUI运行也必须另外保存compile_order.txt供审核。

本轮离线检查使用Python 3.12.14；第二步另需NumPy。示例路径中的<...>由操作者替换，不需要旧D盘工程：

```text
python tools/analysis/validate_gui.py <新工程根目录> <XSim运行目录> <完整原生日志> <不存在的复核输出目录>
python tools/analysis/report_evm_gui.py <新工程根目录> <XSim运行目录> <第一步复核输出目录>
```

同一目录保留result.txt、data.csv、events.csv、points.csv、xpm_trace.csv、compile_order.txt。检查器仍逐点验证<=1LSB、固定拍数、74窗口/估计、帧身份/因果顺序、FIFO逐边沿谓词及未知错误拒绝。原始日志未含时间/实例上下文时拒绝，不能通过删去厂商ERROR使结果通过。

GUI保存日志替代了旧batch管道封口文件，输出明确声明没有证明batch封口或进程树清理。目标Part/IP原生复核也需独立保存。检查通过仍为PENDING_ASTRA_REVIEW、T10_PASS=false，不代表新器件时序、持续吞吐或上板验收。新工程若经批准改动文件，应保存新版本和更新来源清单，不修改旧实验原件。完整路径适配diff见migration_diff.patch。

原生FLGB retarget后，原始RTL_COPY_MANIFEST.csv保留迁移源身份，不覆盖其原source_sha256。检查器默认读取docs/provenance/RTL_FINAL_MANIFEST.csv，也可用第五个路径参数指定经审查的后续版本清单。最终清单必须覆盖全部原迁移输入；检查器按最终哈希验证活动文件，同时单独确保74个核心SV仍与最初冻结源逐字节相同。缺少最终清单时直接拒绝，不回退到原复制快照。编译清单还须包含完整、唯一、位于本项目内的74核心、2个TB和3个XPM源；不按同名文件猜测来源。
