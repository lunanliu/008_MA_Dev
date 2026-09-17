# A05：完整工程准入前的最终源/端口修订

状态：代码/工程脚本/Wrapper及顶层短冒烟已准备，OTA004原生检查与综合尚未执行。

- 生产RTL列表127项；135个module/package定义唯一；算法核心sync_ota_top，器件xcvu11p-flgb2104-2-e，45个唯一真实IP的器件参数逐项一致。
- 生产CFO改为rtl/cfo/ota_cfo_chain_a02.sv，同名module只选这一文件。原A01及OTA002/003冻结输入全部保留；A02在原来提前失败分支锁存实际backend_word，并引出已有窗口/观测FIFO占用及四项sticky错误。快域错误先在500MHz锁存，再经XPM各自同步到150MHz；不跨域采样多bit占用。
- 正式metadata/步长握手维持。新增SFO监测输出只用于诊断，不给算法喂配置。原diagnostic实际属于150MHz，明确命名sfo_diagnostic150；125/150监测在本域保持，不冒充跨域原子快照。
- 正常COMPLETE时延后SFO复位到Host确认完成后IDLE，使计数可读。取消仍立即复位算法并排空DDR；保留此前的SFO监测及首错。CFO首错也在root保持到下一正式metadata。
- 独立明文wrapper/sync_ota_wrapper.vhd逐位映射75个核心端口到111个LabVIEW常用宽度端口，不加入算法综合顶层；精确映射和时钟/有效条件见docs/PORTS_AND_RECORDS_ZH.md。
- OTA004入口先创建根Sync_OTA.xpr并import_ip为受管副本；冻结XCI原件不改。实际RTL、IP参数、编译成员及哈希要与清单核对。真实完整top短冒烟只测复位/捕获/待ACK取消/唯一完成/恢复/非法配置，不运行长帧算法。
- 随后仅一次完整核心OOC综合（保留层次），要求真实关键层次和0 blackbox，导出DCP/EDIF及资源、时钟、CDC、综合时序。不得启动实现、重新全帧仿真或扩展扫参。IP子作业4并行是基于当前约12GiB可用内存和既有SFO xelab峰值约5.83GB的工程预算；general/synth每进程8、xelab16、core launch jobs16。

已验证范围：OTA001、OTA002、OTA003各自专项；详见独立接收记录。未验证范围：本A05真实整合原生展开、Wrapper语法、完整核心综合/最终网表、NI/物理实现/持续吞吐/板测。后者须按实际新结果更新，不能从源代码存在推导为PASS。
