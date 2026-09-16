# OTA003/A01：DDR桥、有限调度、两符号双旋转

## 授权与边界

本任务Astra/Luna固定配对及PROJECT_SPEC授权下的新短检查；原生启动仍需总管家新的具体grant。OTA001/OTA002均已归还，不可复用。Astra 01a0ac17-f298-7201-848c-58d09e90ebb4；唯一Luna 01a0ac17-4f21-7be3-8690-540c11497b1e。

仅允许bridge -> capture -> dual_rotation串行，一个Vivado主作业、0 MATLAB；不综合、不实现、不运行完整OTA算法或旧项目。三个阶段对应原五组风险里的存储/CDC/片段衔接，不能新增广泛扫参。静态语法、Python oracle --check、PowerShell解析已完成；新PRJ解析已用三份OTA002真实日志离线验证精确模块边界，不以重复编译试解析。

## 输入/源集/命令

冻结源锁OTA003_source_lock.json，每项长度及SHA256须启动前/结束后核对。入口tools/vivado/run_ota003.tcl逐项指定源；actual_sources.tsv必须与入口期望完全一致。器件xcvu11p-flgb2104-2-e。官方XPM只用于synthesis标志，仿真只选sim/vendor/link010r1三件，库ota_xpm优先；verify_xpm_binding.py检查真实PRJ/elaborate，bridge还要求确切fifo/CDC实例。capture及dual_rotation未实例化FIFO，明确用none模式，只核验实际编译源及禁止安装版XPM绑定，不假称FIFO展开。

每次独立新目录work/OTA003/<stage>_a01；失败重试另编号，不改冻结输入。示例调用（获具体grant并建立新目录后）：

powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:/008_MA_Dev/Sync_OTA/tools/monitor_native_job.ps1 -Stage bridge -Attempt D:/008_MA_Dev/Sync_OTA/work/OTA003/bridge_a01 -Source D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota003.tcl -HardSeconds 1200

capture及dual_rotation只替换Stage与独立Attempt目录。监管脚本内部使用Vivado2021_1绝对路径启动batch，并保存原生log/jou、stdout/stderr、PID+创建时间进程树、整树工作集和最低可用物理内存。Start-Process隐藏窗口。不要再用PowerShell保留变量$PID作循环名。启动前脚本保守要求无其他受控计算exe及至少8GiB可用；如全机状态变化，与具体准入协调，不擅自改全局限制。

## 阶段与通过条件

|阶段|设计top / TB|新增风险与必须结果|
|---|---|---|
|bridge|ota_ddr_bridge / ota_ddr_bridge_tb|125/150异步时钟，两个来源各2次请求；单外部信用；含归属位的完整命令在背压下稳定；4条匹配回应准确路由，1条陈旧回应消耗但不归还信用、不送给错误来源；最后FIFO空。唯一OTA003_DDR_BRIDGE_PASS。错误寄存器71是该负向测试的预期，不是放宽门槛。|
|capture|ota_capture_controller / ota_capture_controller_tb|真实ota_frame_store+ota_frontend_descriptor；第一次在写ACK待定时取消，确认不提前done/start_ready；第二次generation=2写334215beat、扫描334215beat、SFO预装334215beat，每地址/序号检查；完整局部坐标-172+4*b；最后读者退出、外存租约释放后才允许3份descriptor和metadata独立背压握手。唯一OTA003_CAPTURE_CONTROL_PASS。FE/SFO/CFO为明确标注接口服务，只验证调度，不运行全帧算法、不声称算法PASS。|
|dual_rotation|cfo_rotate4 / ota_dual_rotation_tb|实际两个cfo_coordinate_control及两个cfo_rotate4；既有5120样点（2符号），非零origin、两个非unity步长；独立有理数oracle精确配置及两个1280beat数值/标签比较，输入与输出背压，无晚到/重复。唯一OTA003_DUAL_ROTATION_PASS。原理配置是专项注入，未声称本TB实际估出SFO/CFO；生产无参考真值输入。|

三个TB全有时间保护、$fatal首错和唯一result.txt。bridge和dual TB上限1ms仿真时间；capture保留真实地址范围，上限100ms仿真时间，计算核为服务模型所以不属于旧全帧算法长跑。原生exit0只代表正常结束，必须日志marker、result、无非预期断言错误、选源及本表计数一起成立。capture冻结源不包含真实大算法，dual为真实短数值核；最终完整top工程展开另包。

## 资源/保护/交接

general.maxThreads=8、synth.maxThreads=8，经utils/PRE进入子进程；xelab=16，回读并记录。请求1 Vivado /0 MATLAB，预估整树3–6GiB，8GiB告警，启动可用至少8GiB。估算小幅越线不停止；明确错误、持续严重内存压力或证实停滞才干预，并保存证据。预计全包3–15分钟（capture范围计数可能占大头），20分钟检查进度；各阶段硬保护20分钟，整包从首启起60分钟。超过预算只处理本次PID+创建时间身份核验的树，不按名字kill；不能仅以launcher退出声明子树关闭。若工具正常结束而报告出错，只修复记录，不重跑成功阶段。

Luna只修复命令/路径/私有包装，另存版本及差异；不得改RTL、测试条件、向量或阈值。根本设计/结果问题保留失败并回本Astra，停止后续依赖阶段。全部完成后交实际源集、输入复核、原生日志、唯一结果、首启和deadline、完整子树及关闭证据；用本任务工作期15分钟报告，空闲停表。新任务启动与维护都不得改原三工程。

## 后续

本包未包含sync_ota_top完整真实核展开、XPR/DCP、NI或板测；主连接及IP准备详见IMPLEMENTATION_A04_ZH.md。OTA002四组完整74观测不重跑。
