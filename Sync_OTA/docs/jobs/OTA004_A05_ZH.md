# OTA004/A05：取消复位修复，同一短smoke后核心综合

## 范围、前置与执行
根D:/008_MA_Dev/Sync_OTA，Vivado2021.1，Sync_OTA.xpr，真实算法top sync_ota_top，器件xcvu11p-flgb2104-2-e。唯一Astra 01a0ac17-f298-7201-848c-58d09e90ebb4派唯一Luna 01a0ac17-4f21-7be3-8690-540c11497b1e。须总管家新的A05具体grant，A04已归还不得复用。

A04 prepare限定通过：45真实IP/4生成MIF、3头文件、127旧RTL/135定义、独立Wrapper语法、生成依赖身份和完整树已独立核验。复核reports/OTA004/A04_STAGE_REVIEW.json。保留成功prepare，A05不允许prepare、不重生成IP、不重编Wrapper。A04 smoke虽exit0/自有marker，但12条XPM_CDC_SYNC_RST和6条XPM_FIFO_RESET使其NOT PASS；71个已记录进程身份完整树已关闭，synth尚未启动。无完整帧算法/实现/板测通过声明。

本次只运行smoke→synth。入口tools/vivado/run_ota004_a05.tcl，监管仍tools/monitor_ota004_a03.ps1。新独立目录work/OTA004/smoke_a05、synth_a05；失败另编号，成功不重跑。IP列表继续ip/sources_a04.f，官方/私有XPM与4MIF身份审计保持；128生产RTL显式列表rtl/sources_a05.f，136个唯一module/package。只选新sync_ota_top_a05.sv、新增ota_algorithm_reset_guard.sv及sim/tb/sync_ota_smoke_tb_a05.sv；旧源码/测试台全部保留不同时选入。

根XPR只替换旧顶层/TB源成员并加入1个复位保护模块；top名字、75个核心端口/111个Wrapper端口、算法/数值/IP/向量/各域时钟不变。已有生成件及MIF全部复用。A05 actual_sources/headers/include_dirs/IP/boundary JSON/4MIF/compile order仍严格审计，smoke实际绑定必须为新root与真实全算法，无测试替身入综合。

## 本次缺陷及修复边界
原顶层在所有COMPLETE都撤销SFO reset，用于保留正常完成诊断；取消完成/非法配置也被误释放，Host ACK进入IDLE立即重新assert，产生约1拍低脉冲，触发真实XPM断言。新条件仅在stage17且error125==0的正常完成保留release；取消/非法配置保持assert。两个完成分支和done ACK后必须观察迟到结果，不能提前finish。

总管家补查的PRELOAD_BOOT极早取消也必须覆盖：六个sfo_record_cdc_fifo的reset_request直接来自顶层，不能用sfo_domain_reset内部64拍高保持代替证明。新ota_algorithm_reset_guard在固定且持续运行的125/150/500MHz条件下，assert至少16个125MHz周期、每次release后至少128个125MHz周期（1024ns）再允许重新assert。取消时控制器立即停止输入/描述符，DDR/CFO排空继续；复位保护等待期间不放行新的数据。控制器接收bridge_idle还需algorithm_reset_stable，故取消完成/重新接收必须等保护结束。正常COMPLETE读诊断不改变，done ACK后assert也遵守保护。全局reset优先，仍要求NI协调排空与充分保持，不能把该保护理解为可任意停钟/反复全局短脉冲。

间隔依据为本冻结sfo_record_cdc_fifo外部4级reset同步、XPM reset内部2级双向同步及有限状态往返；不依赖FIFO数据宽度或内容。并在同一短TB中使用该真实guard与4个真实sfo_record_cdc_fifo/XPM实例，覆盖125→150/150→125和depth32/1024。在release后的第一个半拍提出取消，必须仍维持至少1024ns的low，并在重新assert当刻所有4个FIFO的wr/rd reset_active均已清零。任一busy未清、短脉冲或XPM error均FAIL；不是只检查计数常量。

## smoke门槛
保持原真实核心展开、3次RAW写、第三响应待定时cancel、禁止提前done/start_ready、单次完成、恢复可用、length0无DDR流量、无晚到最终输出。增加：
- 整段capture/cancel/reject（没有SFO处理授权）有效SFO reset连续为1。
- 取消done ACK和非法配置done ACK均返回可用IDLE，并再观察80拍。
- 同TB的上述4个真实FIFO极早取消检查必须完成。
- startup在8/16/24/32ns采样：全局reset为1、前端quality-divider公开estimator_reset_n为0、accepted_words=0。
- unique OTA004_RESET_GUARD_PASS、OTA004_EARLY_CANCEL_RESET_PASS及原OTA004_REAL_TOP_SMOKE_PASS。新tools/verify_ota004_a05_sim_result.py必须给OTA004_REAL_SMOKE_STRICT_PASS，不能仅靠exit0或TB marker。

原生Error/Fatal/Critical Warning及任何运行期XPM复位断言一律FAIL，无白名单。厂商SIM_ASSERT_CHK启动提示按说明保留。唯一已定位的FPO普通warning仅允许最多一次、精确20ns、frontend/fine_confirmation/quality-divider内部i_fpo/check_reset，且上述4点公开输入复位稳定、零接受数据证据全齐；这是1600ns全局复位保持窗口内的内部初始化提示，与2816–2860ns的18条运行期错误分开。若时间/实例/次数不同或输入证明不足则FAIL，不屏蔽模型/断言。新严格检查已用旧smoke日志验证会拒绝18条错误。

## synth门槛
smoke严格通过才启动未完成IP OOC及一次完整core综合。general.maxThreads=8、synth.maxThreads=8通过所有真实run PRE回读，xelab16；IP jobs4、core jobs16，全机最多2主Vivado/1 MATLAB、本对1 Vivado，本包0 MATLAB。IP并发4保留按整树6–12GiB历史估计与单SFO xelab约5.83GB峰值的资源决策，可因当前具体压力降低并记依据，上限不提高。

核心out_of_context、flatten_hierarchy=none；open_run后0 blackbox，frontend/sfo/cfo/control/ddr、两独立CFO旋转/真实前后端必须存在。输出DCP/EDIF、资源及层次、时钟、CDC、综合时序/check_timing报告。负时序如实报告，不开展实现优化循环，不当作物理/持续吞吐/NI/板测PASS。若实际资源超限、缺核/黑盒或算法问题即停止并回Astra。

## 时间、资源和异常
首native已于2026-09-17T00:44:33.0452158Z发生，全包绝对截止仍2026-09-17T03:44:33.0452158Z（05:44:33 CEST）。A05不重新起180分钟。smoke最多2400秒，synth最多7200秒，每次实际HardSeconds≤绝对截止剩余秒数；预计smoke10–20分钟、synth20–90分钟，实际受剩余预算约束。

示例（grant通过且新目录已建）：powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:/008_MA_Dev/Sync_OTA/tools/monitor_ota004_a03.ps1 -Stage smoke -Attempt D:/008_MA_Dev/Sync_OTA/work/OTA004/smoke_a05 -Source D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota004_a05.tcl -HardSeconds 2400。当前PowerShell可按已验证私有运行环境启动，实际命令留证。

12GiB只告警，小幅不足直接启动；16GiB整树估计告警不是kill条件。记录完整子树、系统提交余量、真实分页及工具进展，严重压力结合具体证据干预；不改分页文件、不关其他应用、不重启。不按估算偏差/报告问题重算成功阶段。普通路径/包装/审计格式问题由Luna另存版本自修并记录hash，不修改数学/RTL/向量/门槛。实质问题回本Astra；进程树按PID+创建时间完整收尾，runner退出或当前native0不能替代历史树证据。

交完整实际源/IP/MIF/绑定/strict smoke/全部真实run线程/网表与报告/全树关闭。Astra复核后由总管家归还。工作与监控期15分钟表格报告，空闲停表，Astra派单后结束轮次。无新全帧或参数扫参、MATLAB、NI工程/XML、板测授权扩张。
