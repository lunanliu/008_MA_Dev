# CFO 坐标换算控制器契约 v1（2026-09-14）

本文件是已批准算法的 RTL 落地，不重新选择 CFO 算法，也不改变冻结 MATLAB 源。输入是已知的频率码和两级 SFO 坐标；输出为 cfo_rotate4 的 32 位 phase0 / step。它本身不估计 residual CFO。

## 为什么要换算

重采样改变了“第 n 个输出样点对应原始时间的哪里”。相同 CFO 在不同采样坐标下，每一步应补偿的相位不同；帧起点不为零时，还要带入初相位。粗 CFO 使用原始时间坐标，后端测出的 residual CFO 使用第二次重采样后的坐标。直接把 Hz 当作 NCO 相位码，或忽略帧起点，会产生错误。

输入握手锁存 frame/generation、coarse/residual、frequency_code、step1_q28、step2_q28、raw_origin_q28。Fs 固定 500000000。coarse 频率为 S32/F8，residual 为 S32/F16；两级步长为正 U32/F28，原始起点是有符号 54 位承载的 Q28 整数且绝对值小于 2^53。frame/generation 原样随配置输出；下游仅在 m_valid && m_ready && m_ok 时装载旋转配置。错误结果只用于报告，不可作为有效配置。

## 与冻结 MATLAB 完全相同的数学

令 Q(x,d)=RNE(x/d) mod 2^48，x 非负，RNE 为最近偶数舍入。D=step1*step2。

- origin = sign(raw_origin) * Q(abs(raw_origin)*2^44,D)，单位 Q16 输出样点。
- coarse step48 = -sign(f)*Q(abs(f)*D,Fs*65536)。
- coarse phase48 = -sign(f)*sign(raw_origin)*Q(abs(f)*abs(raw_origin)*4096,Fs)，最终取模 2^48。
- residual step48 = -sign(f)*Q(abs(f)*2^32,Fs)。
- residual phase48 = -sign(f)*sign(origin)*Q(abs(f)*abs(origin)*65536,Fs)，最终取模 2^48。
- 32 位 step = signed RNE(step48/65536) 的低 32 位；phase0 = RNE(unsigned phase48/65536) 的低 32 位。

顺序保持 MATLAB parameters() / divProduct()：先在 48 位域完成除法与最近偶数舍入，再缩到 32 位。不能直接用一个除法合并两次舍入。商保留低 48 位的行为同样保留；大幅失真的任意描述符即使通过算术范围检查，也不因此获得物理场景许可。

错误优先级：1=frequency_code 为 -2^31 或 raw_origin 为 -2^53；2=任一步长为 0；3=D>=2^62；4=模 2^48 后 step 幅值 >=2^47。错误结果所有数值为 0，frame/generation/mode 保留。范围检查与冻结 MATLAB assertion 等价，不宣称验证描述符来源真实性。

## 实现与流水边界

一个串行 32x64→96 位移位加法器复用三次；一个 112/64 位恢复除法器复用三次，保留 48 位模商。除数<2^62 保证 65 位余数移位/比较不溢出。每个有效描述符约 435 周期，仿真验收上限 512 周期。150 MHz 下 512 周期为 3.414 微秒，是每帧一次的控制开销；这一理论数值不代表时序已闭合或整链吞吐已验收。96 位加法路径的实际频率和资源须后续综合证明。

输出有独立 ready/valid，反压时全部字段不变；忙时不接收第二份描述符。rst 或 abort_sync 同步清除正在计算或等待输出的事务，同时组合屏蔽当拍 ready/valid；解除后只允许新一代事务。不凭帧号猜测或重建缺失坐标。当前 T10 接口尚需正式绑定这些来源字段，本包不修改 T10。

## 本包证据与限制

367 个冻结算术向量：216 组来自 RCFO003/004 已发布 MATLAB 32/48 位控制参数，Python 任意精度整数参考逐组一致；151 组补充正负非零起点、SFO 步长、两级舍入半值、模回绕与 7 个非法描述符。没有生成新信号，没有启动 MATLAB，没有重新扫描算法。

TB 先执行 367 组，再在 ratio/origin/step/phase 运算中及输出等待中分别复位/取消；6 次被丢弃事务不准输出，随后新 generation 恢复，共应记录 373 份正确结果。检查输入忙、输出反压、结果不变、错误码、无重复、无迟到结果及最大延迟。原旋转器 20480 复样本通过证据直接复用，不重新运行。

独立工程为 vivado/CFO_COORD/CFO_COORD.xpr，hardware top=cfo_coordinate_control，sim top=cfo_coordinate_control_tb，part=xcvu11p-flgb2104-2-e。旧 CFO_SYNC 工程及其源锁保持。CFO_COORD 是本次模块里程碑工程；FFT、74 点估计后端、整帧存储复用及完整链路仍有后续门槛。