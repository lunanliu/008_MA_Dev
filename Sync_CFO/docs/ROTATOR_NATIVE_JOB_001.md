# CFO-NATIVE001：四路旋转器原生工程与短仿真准入

Astra于2026-09-14冻结并直接准入；由唯一T11 Luna执行。本包没有MATLAB、不调用旧runner、不修改或接管T10。恢复授权来自总管家在当前T11线程转达的用户最新指令；不要求再次申请普通Vivado准入。所有中央状态/绑定/AGENTS写入仍由总管家负责，本包不改。

## 唯一构建身份

- 根：D:/008_MA_Dev/T11_CFO
- 工具：C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat（已核实文件存在；native日志须显示2021.1）
- Python：C:/Python314/python.exe，调用固定 -I -B -X utf8；仅标准库。
- XPR：vivado/CFO_SYNC/CFO_SYNC.xpr，part xcvu11p-flgb2104-2-e，hardware top cfo_rotate4，sim top cfo_rotate4_tb。
- 参数：docs/CFO_MAIN_CONTRACT.json；相位字及输入见sim/vectors/ROTATOR_VECTOR_MANIFEST.json。
- 源/输入SHA256：docs/ROTATOR_SOURCE_LOCK.json；包括明确fileset列表。派单后不得原地改，必要执行修复另存版本及新指纹，RTL/算法/TB测试含义变化须反馈Astra。
- 本次所有依赖均在独立根目录；provenance中的T10只读副本不进入编译。

## 执行顺序与具体命令

由Luna在本包work/CFO_NATIVE001下创建独立attempt_<UTC>。这是输出目录参数，不改变源集或实验设计；启动前记录实际绝对路径、每个命令、执行包装/输入hash和资源快照。每个阶段有独立log/jou。以下路径均相对本包根，绝不从旧root启动。

1. 只读预检：`C:/Python314/python.exe -I -B -X utf8 tools/verify_rotator.py`。核实无现存同任务进程/XPR启动记录，以免重复启动。若XPR已成功创建，保留并从实际源集核查阶段继续。
2. 原生建工程：`C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source vivado/create_project.tcl -log <attempt>/create.log -journal <attempt>/create.jou`。
3. 检查**实际工程导出**：Python同入口增加 `--actual reports/rotator_native/actual_sources.csv`。锁定表与实际源集必须一致；不能自动改清单使通过。
4. 原生短仿真：同Vivado命令结构，source改为 `vivado/run_rotator.tcl`，日志 `simulate.log`/`simulate.jou`。脚本打开同一XPR，实际展开、数据加载、run all；不以固定0ns结束。
5. 只读逐点核查：Python同入口增加 `--actual reports/rotator_native/actual_sources.csv --results vivado/CFO_SYNC/CFO_SYNC.sim/sim_1/behav/xsim --native-log <attempt>/simulate.log`。保留完整原生xvlog/xelab/xsim日志及CSV，复制完成的原始输出到attempt稳定证据目录，不能复制活动WDB冒充完成。
6. 原生取消检查：同Vivado命令结构，source `vivado/cancel_probe.tcl`，日志 `cancel.log`/`cancel.jou`。看到CFO_CANCEL_PROBE_READY后等待2–5秒，按本次拥有的Windows Job/准确子进程树取消。须证明所属树归零且T10保持；禁止按名字kill。这个探针只验证新入口在打开工程后的取消，不声称覆盖运行中XSim或所有IP生成阶段；后续入口变化按需补受影响检查。

任何已成功阶段不重复运行。普通路径、命令参数、私有工作目录、包装/监控问题由Luna自行修复并保存新版及原始错误，验证后继续；算法、RTL、向量/验收意义、实际源集身份问题反馈Astra。不得用预期向量或外部相位真值替代未来估计器；当前旋转核相位配置本来就是本里程碑输入。

## 资源、时间与异常保护

2026-09-14 09:08:15 UTC快照：物理内存31.421 GiB、空闲16.554 GiB；可见1个Vivado主进程（T10保留），未见MATLAB/xelab/xsim。快照不替代启动时核实，且此处没有读取或控制T10进程。

- 全机最多2个Vivado主作业，本T11最多1个；create/sim/cancel严格串行。MATLAB本包0个。
- general.maxThreads=8、synth.maxThreads=8；xelab并发16。所有后续build jobs默认/上限16，通过本工程真实run PRE钩子传递；本包无综合。
- 预算：本CFO native树预计峰值≤4 GiB（告警线），其他已占用约14.9 GiB已计入，总预计约18.9 GiB；启动空闲建议至少6 GiB。若实时不足，Luna记录数据后等待资源或按内存依据下调xelab并发，保留实际参数和新执行锁；不无理由固定2线程。
- 预计建工程0.5–3分钟、编译展开及全部短仿真1–5分钟、取消及证据1–3分钟，总计3–11分钟。
- 硬超时：建工程300秒，仿真900秒，取消探针60秒，总包25分钟；各取消后清理60秒。TB自身100000cycle硬限。超过设计时间保护不等于算法INVALID，完整失败证据保存。
- 运行期轻微超4 GiB只告警，不终止。真正严重内存条件：系统可用物理内存<0.5 GiB持续30秒，或<0.25 GiB即时，优先按本次所属Job取消CFO；不终止T10。若T10资源变化导致不满足启动预算，先等待，不占第三个作业。
- 明确native错误或首个数值/握手错误立即停止该失败阶段，保存原日志；不继续耗时做同一失败计算。活跃编译子进程不能仅凭无日志被判卡死；相同阶段无可见进展且累计子树CPU不增加超过180秒才按无进展处理，记录最后真实仿真时刻/阶段/接受计数/进程状态。
- 最终父进程退出码、所属全树归零、日志完成标识、逐点结果、取消证据分别报告。预算快照、native实际线程、峰值/耗时须保留。

## 通过条件与交接

4个case各1280beat、合计20480复样本逐bit/元数据/饱和标识一致；case2恰5040个分量饱和，其他0；case3同时覆盖相位地址RNE半格及正负乘积RNE中点。case0真实接受输入/输出连续II=1；其他case出现背压且blocked输出稳定。reset与abort各明确丢弃4个未输出beat，新generation无旧数据；错误帧序号与错误采样数触发指定fault；输入长度/首尾/未知态/config核对均完成。

还须实际XPR/source set/part一致，取消探针所属进程树清理成功，独立核查器通过。仅表示四路补偿算术与协议里程碑，不表示CFO估计器/全帧/资源/150 MHz时序/持续500 MS/s通过。

Luna完成或遇根本设计问题后只唤醒本Astra一次，附attempt/冻结与实际版本、命令、结果、峰值/耗时、释放证据及首次错误。运行期间唯一Luna监控并按15分钟模板报告；Astra派单后停止本线程工作报告并结束轮次。不得向其他任务借执行者，不创建开发子线程。