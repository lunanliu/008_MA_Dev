# CFO-GUARD002：只修复执行保护，不重跑旋转计算

2026-09-14 Astra根据CFO-NATIVE001独立复核派发给唯一原T11 Luna。本包在用户直接恢复授权内，只验证已授权原生入口的正常/错误/自动取消。已有20480复样本限定功能PASS保留。禁止新MATLAB、RTL仿真、综合、IP生成、算法/向量/门槛变更；后续计算须先解决本包执行缺陷。

## 为什么必须修

原取消进程最终退出，但首次强制收尾在原生启动超过60秒后才请求，并因只读$PID变量失败，后续引号/编码修复再次延迟。记录只有最终tree_empty，不能声称满足60秒时限；也缺少独立自动时限/严重内存保护与完整子树资源采样。详见reports/CFO_NATIVE001_REVIEW_20260914/README_ZH.md及INDEPENDENT_REVIEW.json。Luna须补一份原attempt只读审计附件说明实际修复时间，保留所有原文件，不能改成无失败PASS。

## 执行修复范围（由Luna自行实现）

允许你在本工程tools/写新的独立监管入口，例如cfo_native_guard_v2.py或.ps1，并在本次attempt保存具体版本、源码hash、解释器版本/路径、实际命令、输入、保护条件和输出目录后直接执行。普通执行包装由Luna负责，这不是算法/RTL修改。不得调用旧CFO runner、改全局环境、借用T10监管器的活动文件或多层拼接临时shell命令。

监管必须在原生进程恢复运行前将其加入**本次独占Windows Job对象**（先挂起创建、AssignProcessToJobObject成功后再恢复），设置KILL_ON_JOB_CLOSE；加入失败则终止尚未运行的本次子进程并停止准入。利用该Job句柄管理自动结束及全部后代，不按进程名kill、不以父PID消失判断全树归零。若该机制受系统限制，停止此入口并给出具体证据，不能退回无保护直接启动。

保护逻辑必须随独立监管进程持续运行：单调时钟deadline、每秒资源/Job活动进程计数、异常finally收尾、结束后Job ActiveProcesses=0及完整原生退出码。无需等待模型下一条消息，也不能在到期后再拼接未经验证的kill命令。不能使用$PID、$HOME等系统变量作循环变量。日志展示写入失败不得取消正常计算；关键监管/记录失败须明确报告并按本次Job保守收尾。

资源记录至少包含每秒系统可用物理内存、本次Job活动进程数/IDs、Job峰值私有提交量（若API口径可用）和采样瞬时私有提交量、所属树CPU或阶段进展、单调时间。不能把父进程WorkingSet当作全树峰值；某项不可取得明确标记，不伪造0。监控程序自己的占用另记或说明未包含。

## 冻结原生探针与命令

根D:/008_MA_Dev/T11_CFO。原生工具C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat；Python若采用则C:/Python314/python.exe -I -B -X utf8，仅标准库。使用正确的Windows参数传递及独立stdio文件，不把编码脚本嵌入数层shell。监管器只启动如下三个命令，依次串行：

`vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/guard_probe_v2.tcl -log <attempt>/<mode>.log -journal <attempt>/<mode>.jou -tclargs <mode>`

mode依次normal、error、hold。探针只打开现有CFO_SYNC.xpr、核对part/top、读取本地线程设置后产生明确ready标识；不会编译/仿真。normal正常exit0；error记录CFO_GUARD_EXPECTED_ERROR并exit7，验证错误退出传播；hold等待10分钟但必须被外部监管自动结束。

执行前运行原有tools/verify_rotator.py（只读身份检查）；39个原冻结成员必须仍相同，17实际源集记录保留。新探针和本JOB身份见docs/GUARD002_SOURCE_LOCK.json。当前XPR动态指纹8EE3459986419C34B42B4261A0E38B2D5C670B47E25E33D80B46074CD4EE8063；若有变化先解释实际source/配置差异，不自动更新锁。新监管源码不由这份预先的探针锁覆盖，必须在任何原生启动前另出EXECUTION_FREEZE，包含其所有依赖hash；只允许本节冻结的三条原生命令，不扩大测试集合。

## 资源、时间与真正保护

T10保留1个Vivado，T11最多1个，主作业全机最多2；三个模式严格串行，本包MATLAB0。general/synth8；本包没有xelab或build，16上限不构成额外作业。预算按原生父进程历史1131.988MB并计全部子作业，先保留原4GiB预计告警线；启动系统空闲建议>=6GiB。轻微超4GiB只告警，真正严重压力为可用物理<0.5GiB持续30秒或<0.25GiB即时，自动结束本次Job并记录原因，绝不操作T10。

每个normal/error从恢复原生进程起60秒硬限，超过即Job自动结束并标失败。hold从观察到真实READY起3秒触发TerminateJobObject；即使READY未到，仍受原生启动60秒绝对期限。触发到Job活动数归零最多5秒（含采样误差），超过为FAIL。必须记录launch/ready/trigger/zero四个单调时间和UTC；达到hold预期触发不是正常exit0，应记录TERMINATED_EXPECTED与实际退出码。不能将“sleep3秒”当作ready至触发的实际时长，工具等待和模型思考不可计为受控3秒。

本包原生预计1–3分钟；包装实现及静态核对预计10–25分钟，不设到点抢跑。包的原生三个阶段合计最多5分钟，阶段结束后再处理报告，不将报告耗时混入计算。关闭监管窗口、取消、超时或任何异常须通过已绑定Job回收自己的后代；最终核对T10仍在且PID/创建身份未被操作。

## 验收与后续

1. normal保留真实exit0和成功标识，作业树归零。
2. error保留真实exit7和错误标识，包装不得吞错报正常成功，作业树归零。
3. hold有真实READY，实际ready→触发为3秒左右（允许每秒轮询1秒误差，即3–4.5秒），触发→全树零≤5秒，且从启动到终止≤65秒；证明动作来自独立监管器，非模型临时kill。
4. 全程资源采样、所有实际源/命令/包装指纹、原始日志、异常记录齐全，没有CFO计算重跑或T10干预。

完成后发布新的ATTEMPT_COMPLETION和完整清单，明确各模式状态与原NATIVE001缺陷，不覆写历史。只唤醒本Astra一次复核。本包通过后才准入后续坐标控制器/估计后端的计算任务。你实现执行包装及自修普通问题，不能改变上述三个探针含义/时限/范围；若确需调整设计，停止该失败阶段交回Astra。