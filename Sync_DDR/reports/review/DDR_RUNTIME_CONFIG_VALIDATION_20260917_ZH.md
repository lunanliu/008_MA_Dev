# DDR运行时容量与四点回放：修改和短验证结果

2026-09-17，时间采用本机CEST（UTC+02:00）。本任务独立实施和自审，未委派其他任务。

**结果：两份RTL已修改，静态自审完成；当前工程创建、写控制器行为测试、读控制器行为测试通过。** 这是独立NI接口/数据通路模型的控制器证据，不是远端Target VI、实际DDR硬件或端到端Sync链路验收。

## 修改内容

- 新增U32 ddr_capacity_words，移除固定2048上限；65536不是新上限。N/M/C启动时锁存，64位计算并分两拍核对长度/容量，拒绝无效配置。
- 新增编译参数DDR_WIDTH_BITS，默认1280；分组、组计数位宽、打包/播放偏移由字宽推导，每次仍4个U32。改变位宽需要重新编译和修改LabVIEW数据类型。
- 新增stream_first/stream_last，与四点数据按valid/ready握手。尾组未被接收时不完成，背压期间保持数据、位置和首尾标志。
- 保留单打包缓冲和256块预取；无双缓冲、无同段边写边读。上传/回放互斥、有效段描述符和CDC接线由新版Target VI说明给出，实际远端VI仍由用户搭建。
- 两个CONFIG状态增加启动准备时间，合法后才递增generation。busy包含检查阶段，原状态码不改，仅追加新码。用户不应依赖原先一拍启动假设。

## 实际执行与证据

| 尝试 | 本机起止时间（CEST） | 结果 |
|---|---|---|
| attempt01 create | 19:31:29—19:31:46 | PASS；实际5源、3个top精确匹配 |
| attempt02 write | 19:32:27—19:32:48 | xvhdl成功；xelab重复mt参数失败；该次行为NOT_RUN |
| attempt03 write | 19:39:46—19:40:17 | PASS |
| attempt04 read | 19:40:28—19:41:11 | PASS |

整体固定截止19:46:29 CEST，重试没有重置。V1到V2只变更create_project.tcl和simulate.tcl的线程属性：采用本机已注册的mt_level=16，清空额外mt。原始失败日志保留，成功create没有重跑，RTL/TB/XDC在资源运行期间未修改。

两条成功原生日志分别只有一次DDR_UPLOAD_CTRL_TEST_PASS / DDR_READ_CTRL_TEST_PASS，无ERROR/FATAL/FAILURE或失败断言；实际xelab调用均只有一次--mt 16。各阶段exit0且所属Kernel Job连续三次为空。日志保留HLS默认路径缺失和空IP生成目录的环境警告；本工程无HLS/IP实例，不能把这些警告表述成RTL功能失败。

- [机器可读结果与实际命令](../operations/VALIDATION_RESULT_20260917.json)
- [写原生simulate.log](../../work/runtime_config_v1/attempt_03_write/native_logs/simulate.log)
- [读原生simulate.log](../../work/runtime_config_v1/attempt_04_read/native_logs/simulate.log)
- [工程实际源集](../../work/runtime_config_v1/attempt_01_create/actual_sources.txt)
- [工程实际顶层](../../work/runtime_config_v1/attempt_01_create/actual_tops.txt)
- [V2冻结清单](../operations/FROZEN_INPUTS_V2.json)

## 通过的核心检查

| 检查 | 实际覆盖 |
|---|---|
| 完整窗口写入 | N=1336860，M=33422；每个实际提交的样本位模式、地址、尾部零填充均由外部scoreboard检查；尾字20点真实+20点填零 |
| 大于65536的实际读取 | C=131072，M=65537，N=2621480；顺序请求地址0..65536，成功交接655370批四点，无丢失/重复/重排 |
| 配置合法性 | 容量为0、容量不足、N不四点对齐、M与N不匹配被拒；启动后改N/M/C不改变任务 |
| 高位U32 | 写侧0xFFFFFFFC样点、0x06666667字配置合法接受后立即取消；这是配置范围检查，不是实际搬运了全部最大长度 |
| 段边界 | 每次交接验证first/last；N=4双标志重合；普通背压和最后组暂停保持，恢复后准确完成 |
| 可编译字宽 | 默认1280执行主用例，640各执行一个短组/尾块及4点段用例；并非穷举全部合法字宽 |
| 既有状态与协议 | 正常第二次启动、持高命令不重触发、忙时拒绝、暂停/恢复、取消排空、DDR失效、请求/返回/FIFO计数等 |
| 理想回放 | 在模型连续供数且ready持续有效时，检查N/4成功交接拍且无气泡；非实际板卡持续吞吐保证 |

写、读是两份独立模型测试；没有把写模型的真实硬件结果送进读模型，更没有运行同步算法或MATLAB。写时钟激励约150MHz、读125MHz只表示行为激励，不能当作物理时序闭合。

## 使用与剩余边界

- [修改后写RTL](../../rtl/ddr_upload_ctrl.vhd)、[修改后读RTL](../../rtl/ddr_read_ctrl.vhd)
- [新版Host/Target接线](../../docs/tutorial/LABVIEW_RUNTIME_CONFIG_AND_SESSION_ZH.md)
- [完整端口表：写33、读57](../DDR_CURRENT_PORTS_ZH.md)
- [设计自审](RUNTIME_CONFIG_SELF_REVIEW_20260917_ZH.md)

默认输入例子：C=65536、N=1336860、M=33422。Host实际配置不得超过Memory分配，N还受U32和Sync自身合同约束。每个复样点U32位模式不变；数据数组在LabVIEW，stream_word0..3是检查输入。

远端接入仍需确认1280bit逻辑元素与NI接口的映射，以及最后写请求接受后跨访问器的读回可见性保证。load_done只表示请求全提交；WRITE_DRAIN不能用固定延迟或常数True代替平台保证。跨域控制FIFO、Sync段准备及实际NI节点握手尚未在本地验证。

综合、布局布线、NI编译、板测、持续吞吐均未验收；未生成CLIP XML，未修改其他四个Sync工程或历史证据，未推送远端。总管家确认资源于本机2026-09-17 19:44:55 CEST归还，中央owner=NONE、grant=null，V1/V2 grant均不可复用。其复核确认15项冻结身份、唯一PASS、实际线程参数及Job闭合；只接收FUNCTIONAL_BEHAVIOR_PASS。中央记录未由本任务修改，本轮不再启动EDA。
