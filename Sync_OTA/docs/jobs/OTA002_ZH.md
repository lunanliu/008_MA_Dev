# OTA002 A01：正式上下文、复位/74观测与真实CFO控制链

2026-09-17。承接OTA001限定结果。本包是总任务五组风险验证中第3组（描述符/CDC/复位）、第4组（完整74观测）、第5组的一项CFO局部控制检查；不新增广泛扫参或全帧长仿真，也不替代最终完整OTA顶层检查/核心综合。

## 三个独立阶段，首错停止

| 顺序/参数 | 实际设计top / TB | 必查输出 | 边界 |
|---|---|---|---|
| context | ota_sfo_context_join / ota_context_boundary_tb | 真实两级descriptor计算的Q28步长；三次配置、两次消费、一次取消；214位跨域逐位一致、背压稳定；FIFO.rst仅在writer边沿改变、异步停流、重新接收无旧记录 | descriptor合法输入是TB合成服务输入，不是整个SFO估计科学结果；正式resampler发布端口贯通目前为静态检查，待全工程展开 |
| backend74 | cfo_estimator_link / ota_backend74_tb | 4组已发布输入，每组全部74条；296条CDC read逐位比对、4个完整530位结果逐位比对；取消9条未完成输入后恢复；输出背压稳定及FIFO同步reset边沿 | 复用FRONT/BACKEND/LINK已发布观测，不重新算MATLAB/FFT2048；不恢复原T11作业、不继承其未闭合R1观测门 |
| cfo_control | ota_cfo_chain / ota_cfo_control_tb | 展开完整真实CFO算法树；零频配置下3拍真实粗旋转写值/地址正确；存在DDR信用时取消并排空；完整帧估计前无最终输出；恢复配置ready | DDR响应为TB服务模型；只检查控制和真实粗旋转，不称全帧CFO数值闭环；无算法黑盒进入设计源 |

每阶段result.txt只在全部检查完成后生成唯一对应PASS：OTA002_CONTEXT_PASS、OTA002_BACKEND74_PASS、OTA002_CFO_CONTROL_PASS。首次$fatal立即停止该阶段；已经通过的阶段保留，不为其他失败重跑。三阶段分别创建全新小型XPR，器件xcvu11p-flgb2104-2-e，工具Vivado2021.1；这些不是最终Sync_OTA.xpr。

## 精确入口与源集

唯一入口tools/vivado/run_ota002.tcl，三个stage按表顺序串行。工具C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat，工作目录本工程根。分别使用work/OTA002/context_a01、backend74_a01、cfo_control_a01；失败包装修复另存a02等，不能覆盖原件。

```powershell
& 'C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat' -mode batch -source 'D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota002.tcl' -log '<attempt>/native.log' -journal '<attempt>/native.jou' -tclargs '<stage>' '<attempt>'
```

执行前核对OTA002_source_lock.json中全部科学输入/入口字节与哈希。Tcl实际导出sources_1/sim_1/utils_1及library/used-in属性并与明确列出的文件集比较。无需XCI生成：本次CFO算法FFT为已发布可综合RTL；6份ROM逐项指定。run_threads.tcl已加入utils_1，并挂PRE钩子；general/synth请求8、xelab16。

所有仿真SV绑定ota_xpm私有库。综合用rtl/vendor/xpm三份官方原始HDL；仿真用sim/vendor/link010r1三份副本，CDC/Memory逐字节相同，FIFO只保留既有两处translate_off断言修正：EMPTY检查下一周期为1（不要求再发生上升沿）；WAKEUP_TIME=0时不实例化零长度sleep断言。已通过verify_link010r1_models.py精确证明，其可综合内容与官方完全相同。没有全局禁用XPM断言或错误白名单。实际展开后、刺激前运行verify_ota002_binding.py，核对真实PRJ仅选这三份私有模型、ota_xpm优先于xpm、关键模块实际展开为ota_xpm.xpm_*、本地库真实存在，失败不得运行刺激。

## 预算与保护

申请1 Vivado主作业、0 MATLAB；三阶段串行。预计每阶段1～4分钟，整包3～12分钟，工具启动较慢可20分钟；阶段硬保护20分钟、整包60分钟。context仿真时刻100us、backend74为2ms、cfo_control为1ms硬TB保护。估算3～6GiB、8GiB告警（不是轻微超线终止），启动前建议可用至少8GiB并计全部子进程。默认xelab16，资源不足可以降低并保存入口修订和原因；general/synth8由真实回读确认。

必须取得总管家新的明确OTA002/A01槽才启动；OTA001旧grant已归还不可复用。Luna启动前刷新槽/哈希/工具进程/内存。取消仅限核实的本作业PID+创建时间+完整树；用户停止、明确错误、严重具体资源压力、确证停滞或超时按审查流程收尾。此次从启动即持久化父子进程树及创建/结束时间；正常退出和整树关闭分别记录，不以runner退出或当前空快照代替历史监控。不动用户GUI/旧工程/全局环境。

普通命令、路径、私有环境、监管包装问题由唯一Luna自修保存新尝试；RTL、TB检查含义、数据、算法门槛、超时保护变化交Astra。原生/编译/展开/仿真日志不得有ERROR/FATAL/断言失败；唯一PASS、实际选源/绑定、前后源锁、正常退出和进程树关闭共同为候选通过条件。科学结论由Astra独立复核，完成后申请总管家归还中央槽；Luna不改中央槽。

## 已知后续设计项

- 最终OTA主调度与生产XPR、Frontend/SFO IP闭合、端口/Wrapper及板测资料仍未完成。
- 原SFO处理保护400896周期包含下游停顿；单信用离线DDR会延长E2输出等待。尚未改变默认值或声称原性能门通过，下一主调度需明确有限离线超时与原模块服务门的关系。
- OTA001 release/replay同拍风险不改原件；本CFO FSM使用互斥WINDOW_REQUEST/FINAL_REQUEST与RELEASE状态，不同时驱动。最终主控制同样必须互斥。
- 科学原点/常相位、完整帧精度、真实DDR吞吐、综合/最终NI时序仍分别未验证。本包不将4×150MHz写成500MS/s持续资格。
