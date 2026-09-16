# OTA001 A01 独立复核

2026-09-16。结论：store在冻结范围内PASS；descriptor为PASS_WITH_TB_WARNING。两阶段可限定接收并归还本次槽，不重跑。

- 清单自身SHA256及8/8文件长度、SHA256重新核验一致。两个实际XPR器件/设计top/仿真top、原生导出source set均与首包一致。
- 两阶段原生日志各有唯一实际执行PASS行、正常结束标记；result.txt匹配。原生及生成的编译/展开/仿真日志未检出ERROR、Fatal或断言失败。store在1456ns、descriptor在312ns结束；这只表示短TB覆盖范围。
- general/synth请求8、xelab16均有日志回读；未运行综合，因此不能把PRE钩子设置写成真实综合子进程性能证据。
- store覆盖8拍写入、8+3拍回读、单信用、写确认seal、取消排空、异generation响应拒绝、范围/地址回绕拒绝及输出背压。
- descriptor主合法场景使用显式64'd20000000000容量，绝对位置10000000103、局部TO=3和三路独立握手均通过；错误场景按冻结TB逐项检查。

## TB警告的影响

VRFC 10-2659位于descriptor TB第35行：辅助Hz溢出用例将20000000000写成未定宽十进制，XSim报告转换为-1474836480。主合法64位场景在第5行显式定宽，不受影响。第35行仍实际走到error_code=0x34且通过断言，证明该次执行确实检查了Hz超范围拒绝；但这次辅助用例的capture_samples不能当作原意20000000000的证据。故保留PASS_WITH_TB_WARNING和原始编译证据，不修原件、不重跑已通过计算。下一份需要修改的TB使用明确64位常量。

另有20条Runs 36-537（每阶段10条）：线程钩子未加入utils_1，只影响工程归档依赖管理。本包显式路径可执行且哈希已锁定；完整工程创建入口须将钩子加入utils_1，不能依赖这些小测试工程作为最终交付。

## 资源与未覆盖边界

Luna报告两个原生过程正常退出0、阶段收尾扫描无相关进程；Astra当前快照再次未检出Vivado/XSim/xelab/xvlog/MATLAB进程。进程当前为空不替代完整历史子树轨迹，执行责任说明与当前快照分别保留。日志峰值约1131/1130MB是工具报告，不能当整棵进程树总峰值。没有实际DDR、500MS/s吞吐、完整CFO科学原点、真实SFO→CFO整链、综合/实现或板测通过结论。

已知未覆盖：SEALED状态release_frame与replay_valid同拍时ready与内部优先级冲突。最终顶层必须保证互斥或在新生产修订修正ready并做必要定向检查。本包不修改冻结源，不扩大验收范围。

机器复核与证据指纹：[ASTRA_REVIEW.json](ASTRA_REVIEW.json)；当前进程快照：[PROCESS_SNAPSHOT.json](PROCESS_SNAPSHOT.json)。原始完整产物保留work/OTA001/store_a01与descriptor_a01。
