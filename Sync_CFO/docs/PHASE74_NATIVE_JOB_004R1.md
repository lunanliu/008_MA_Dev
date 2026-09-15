# CFO-PHASE004R1：仅修复原生编译词法错误并继续原定短验证

2026-09-14，T11 Astra合并事件PHASE004_COMPILE_REVIEW_CD391FC1后派给唯一原配对Luna。现有T11/CFO恢复授权覆盖本修复，不需要再向用户请求普通RTL修复许可。保持模型/强度/速度，MATLAB0，不启动综合/实现，不操作T10。

## 已复核事实与精确修改

失败完成记录在work/CFO_PHASE004/attempt_20260914T142058600062Z_luna_resume/ATTEMPT_COMPLETION.json，SHA256=CD391FC11D4F7BF8AE857A0EB37154486E7E33F0D901B2C5A2C82695A4B15B5E；清单SHA256=4A365DF0009DE386CAF3E886B34E59BA09BACA54A8BEA684F1B3173714F6AB91。原生15.3447203秒exit1，首错在xvlog解析原core第45/46/49行，没有数学输出，不是算法精度失败。create已经成功并复用，不得重跑。

Astra将三行中七个问号两侧补空白，另存rtl/cfo_phase74_core_v2.sv。旧文件SHA=49C08A1B7FA8860AB418D3D823DDF767A59FDC2877DE682AE1724501F63812D4；v2 SHA=70115D741EFFADDFFA8E1C69767057638CAB6F28DBB9FA6BAD7C36E40A760028。去除空白后全文一致；数字、位宽、运算符、分支顺序及算法均未改变。详见reports/PHASE004_COMPILE_REVIEW_20260914/INDEPENDENT_REVIEW.json及rtl_whitespace_fix.diff。

旧源、旧锁、旧项目入口均保留。新入口vivado/phase74_fix01.tcl只打开已有CFO_PHASE74工程、核对旧12成员，再显式将唯一core文件替换成v2；保存并重新打开该工程，核对新12成员后编译仿真。top仍为cfo_phase74_core/cfo_phase74_tb，part固定xcvu11p-flgb2104-2-e。不调用create_project。新检查器tools/verify_phase74_fix01.py仅改变源锁名为PHASE004R1_SOURCE_LOCK.json，数值/协议检查正文不变。

## 原生准入与唯一命令

先执行C:/Python314/python.exe -I -B -X utf8 tools/verify_rotator.py、tools/verify_coordinate.py、tools/verify_phase74.py、tools/verify_phase74_fix01.py，均只读验证，不能触发旧仿真。新锁docs/PHASE004R1_SOURCE_LOCK.json必须匹配。初次重试前CFO_PHASE74.xpr应为SHA256=401AC5B0C6105AE0564AEBA059E205196F74DF3807DAEC12F7596AA81AD4E92D，该失败后版本已封存到reports/PHASE004_COMPILE_REVIEW_20260914/CFO_PHASE74_before_fix.xpr。若此入口此前已完成源更新，只可凭该次发布的更新后XPR/实际新源集证明后复用，不能凭mtime或同名跳过身份核验。

使用新独立包装版本适配本唯一命令；复用已验证Job保护，禁止修改冻结cfo_native_guard_v3.py或覆盖旧执行包装。所有包装及依赖、真实解释器/Vivado路径版本、实际命令、输入和预算均在任何原生启动前写入EXECUTION_FREEZE。每次尝试独立work/CFO_PHASE004R1/attempt_<UTC>_luna。

C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/phase74_fix01.tcl -log <attempt>/simulate.log -journal <attempt>/simulate.jou -tclargs <attempt>

不再执行create、hold、normal、error、旋转器或坐标仿真。此命令复用已有工程，仅重做受影响编译、此前尚未进行的展开和原定短仿真。输入MEM/常数/参考JSON及TB均保持原锁身份。原始失败的xvlog及编译源列表已另存复核目录；本次需要保留自己的xvlog、xelab和xsim日志，不能只引用下次会覆写的公共运行日志。

脚本在attempt保留更新前/后XPR、before_fix/updated/simulate_actual_sources.csv、simulate_project_identity.txt；源更新后先close/reopen确认已保存，再允许launch_simulation。原实际成员必须是旧锁12个或已审查v2锁12个；不允许旧/新core同时入源、不允许额外未知源。保存最终XPR。若源更新完成后编译仍失败，保留成功更新检查点，下次不重建工程、不覆盖历史失败。

## 验收不变

运行tools/verify_phase74_fix01.py --actual <attempt>/phase74_actual.txt --sources <attempt>/simulate_actual_sources.csv --identity <attempt>/simulate_project_identity.txt，并保存JSON输出。其全部逐节点/逐结果检查须通过：27个唯一74点向量、33个完整结果、6个主动丢弃、5个协议/输入错误、反压150周期、reset/abort各3次；末点至结果≤6000周期，总事务≤11000周期。P/R/C全部中间值和最终234位结果严格一致，错误码顺序1/2/2/3/1。TB源和阈值不能为通过而修改。

原始CFO_PHASE74_PASS、原生exit0、Python数值通过、12个新实际成员和完整Job归零共同支持本模块限定PASS。不存在数据文件或编译/展开失败时必须明确未运行数学，不能用exit0/项目能打开当PASS。scope仍仅CORDIC/解缠/phaseOLS/相位线性门，不包含FFT256质量门及最终模式选择，不包含T11/T12/T13整链、时序或500MS/s持续吞吐。

## 资源、保护与交接

2026-09-14 14:31 UTC实测可用11.57GiB/总31.42GiB，仅T10原Vivado34768及XSim28856在运行。本包最多1个Vivado主作业，与T10合计最多2，所有子进程计入本包预算；MATLAB0。预计4GiB为告警线，轻微越线只记录。启动前重查，建议可用>=6GiB，资源变化须记录预算判断，不挤占T10。general/synth=8经实际PRE钩子，xelab默认/上限16。

唯一原生阶段从Resume起300秒硬限，预计1–3分钟；源修复已经完成，Luna包装适配/冻结/归档预计10–20分钟。Job必须suspended→成功绑定KILL_ON_JOB_CLOSE→Resume；每秒记录完整PID/创建身份、BasicAccounting交叉计数、逐进程PrivateUsage、Job瞬时/峰值、系统余量和CPU/阶段进展。短退出竞态如实记录并重查，不能把持续漏项计0或PASS。严重条件仍为物理可用<0.25GiB即时、<0.5GiB持续30秒，或关键监管失效/明确原生错误；仅收尾本Job，触发后5秒内双重内核查询确认归零。不等待模型临时kill，不碰T10。

普通命令/路径/私有环境修复由Luna在新版本完成，只重试必要失败阶段；任何新的RTL或数学/验收问题交Astra。完整发布完成记录、清单、源/包装hash、前后工程指纹、实际日志和资源；只向本Astra去重唤醒一次，必要时注明已与总管家事件合并，避免两份复核。成功后后续FFT/综合仍需下一审查包，不自动启动。