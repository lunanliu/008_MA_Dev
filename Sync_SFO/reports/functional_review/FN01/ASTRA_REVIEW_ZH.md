# FN01 独立复核：Sync_SFO 功能命名版本

2026-09-15。原生工程打开、行为源编译/展开及独立 Wrapper 语法检查通过；16项补充证据哈希核对一致，进程结束复核和最终归档已完成。源码提交 c4d853a1987f66f212fd44fcd8e9a42dd00035d2，资源申请记录9c4f168；基线V5_Final dd5e8f7保留。

## 结论与交付

本轮交付 [根核心工程](../../../Sync_SFO.xpr)、[独立明文 Wrapper](../../../wrapper/sync_sfo_manual_wrapper.vhd)、[时钟/接口与 Host 测试指南](../../../docs/SFO_SYNC_MODULE_GUI_ZH.md)。综合 top 为 sync_sfo_top，器件 xcvu11p-flgb2104-2-e，核心默认输出150 MHz保持。Wrapper不作为综合top，用户手工创建CLIP。

| 检查 | 独立核对结果 |
|---|---|
| 静态等价 | 79/79 文件，328 继承端口展开，运算、位宽、宏、属性、时序结构保持 |
| 原生根/私有工程 | 各283实际成员精确匹配，含74核心RTL、34XCI及既有支持文件 |
| 实际编译顺序 | 138项：74核心、2测试文件、3XPM、59IP支持；全部来自私有目录并匹配冻结哈希 |
| 原模块输入 | 539/539 哈希匹配；原根XPR未改写 |
| 私有输入 | 538/539完全相同；仅私有XPR含工具保存的元数据差异，见下节 |
| 编译/展开 | 原生exit0，完成静态展开与仿真数据流分析，生成 sync_sfo_full_frame_tb_behav 快照；未运行时间 |
| Wrapper | xvhdl --2008 exit0，分析实体sync_sfo_manual_wrapper；37核心/102外围端口的静态合同保持 |
| 错误与警告 | 原生ERROR/CRITICAL WARNING均0，43条WARNING逐项分类 |

原生执行17:54:56.441至18:11:43 CEST，约16分47秒；Wrapper18:12:48.586至18:12:50.409，约1.82秒。general/synth请求8，实际xelab命令为 --mt 16。Luna采样最低可用内存10.079 GiB，xelab观察到的工作集最高约5.43 GiB；这是采样高水位，不能称为完整进程树连续测得峰值。

## 43条警告如何处理

| 类型 | 数量 | 解释及本次判定 |
|---|---:|---|
| IP_Flow 19-2162 | 34 | 根工程以read_only打开，日志逐条说明此原因；canonical_ip_status实际locked=1共34个，私有工程locked=0共34个。不是IP参数失配或需要升级的证据 |
| filemgmt 56-3 / 56-2 | 4 | 根/私有新工程的默认生成目录及ip_user_files尚未存在；实际选源完整、私有编译展开成功，未从外部旧源补选 |
| VRFC 10-3380 | 1 | obfault在声明前引用，基线已有同样顺序；本轮不移声明或改时序 |
| VRFC 10-8426 / 10-2821 | 2 | 原版XPM源码的端口初始化/生成块写法提示，厂商源保持 |
| VRFC 10-5021 | 1 | 首次FFT的m_axis_data_tuser未连接，基线已有相同接口用法 |
| XSIM 43-3980 | 1 | 测试台关联数组敏感性特性提示，保持既有测试内容；本次不外推其运行时trace覆盖 |

此判定只接受本轮编译/展开范围，没有静默修补算法或放宽功能门槛。既有case6001完整帧结果保持历史身份；本次没有新的功能仿真PASS。

## 私有XPR差异与汇总修正

独立结构比较共有40项：工程Path 1项；WTXSimLaunchSim从0变2共1项；20个禁用的AutoIncrementalDir地址由工具重写；18个策略文字Desc被工具省略。全部FileSets、top、part和实际源/IP身份保持，AutoIncrementalCheckpoint仍false。私有相对增量路径可能指回原模块位置，但本次没有运行综合/实现或使用增量检查点；该私有XPR仅作执行证据，不作为用户日常交付入口。

Luna原始汇总中的canonical_locked_ip_count=0应修正为34（只读锁定）；其“仅路径/启动元数据”概述在此补全为上述40项。原汇总和原始日志均保留，不覆盖。证据：[IP原始表](canonical_ip_status.tsv)、[结构差异](astra_private_xpr_structure_diff.json)、[实际编译输入](astra_compile_input_audit.json)。

## 证据与边界

原始[原生日志](native.log)、[阶段时间](stage_status.tsv)、[Luna汇总](FN01_EXECUTION_SUMMARY.json)、[展开日志](published_native_logs/elaborate.log)、[Wrapper语法日志](published_native_logs/wrapper_xvhdl.log)已保存。没有启动XSim运行时间、MATLAB、综合或实现。没有新的DCP、CLIP XML或LabVIEW工程。

32个预期FIFO层级已按名字映射保留，编译/展开接受绑定语法；本轮没有运行时FIFO历史，不声称新的trace覆盖、持续吞吐或板上无丢拍。前端288位记录适配、原始全帧保存回放、NI时钟/CDC、DDR/DMA及平台诊断快照仍由集成方落实。

实现时序、持续吞吐、NI全目标编译与板测分别未验证；独立Wrapper语法通过不等于与网表完成NI绑定。云端目标和完整IP资产发布由总管家处理，本次未push。

## 进程结束与当前可测试范围

Luna补充的16项既有文件均已重新核对长度和SHA256。18:37 CEST的独立进程检查中，记录的FN01启动器、Vivado、xelab与其当前可追踪后代均无残留，原用户Vivado GUI保留。Wrapper短时子进程PID未记录，结论同时依据成功结束日志和当前原生工具进程清单；不声称捕获所有历史瞬时PID。

工程、独立Wrapper、case6001测试资料及Host操作指南已具备，可以开始手工CLIP集成准备。实际板测还须完成核心综合及网表导出、NI接口绑定与全目标编译，并落实125/150/500 MHz时钟、复位、DDR/DMA喂数和结果捕获。连接同步前端时还须实现288位记录适配和整帧raw IQ回放；本轮没有实现这两项。

最终判定见 [机器可读复核](ASTRA_NATIVE_REVIEW.json)，文件身份见 [最终证据清单](FINAL_EVIDENCE_MANIFEST.json)，进程记录见 [Luna补充证据](FN01_PROCESS_CLOSURE_EVIDENCE.json) 和 [Astra独立核查](ASTRA_PROCESS_CLOSURE_CHECK.json)。共享执行槽由总管家登记归还，本任务不改中央锁。
