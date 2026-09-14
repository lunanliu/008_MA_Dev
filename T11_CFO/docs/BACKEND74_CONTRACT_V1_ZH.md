# 74点CFO估计后端契约 V1

本阶段接收前端已经提取的74个S38复数导频观测z，不直接接收整帧S16采样。真实相位支路和真实FFT质量支路并行处理同一批z；两路结果都完成且frame/generation一致后，输出最终频偏及模式。前端FFT2048、导频相乘/LoS提取、整帧缓存和补偿回放仍是后续范围。

## 输入、输出和并行关系

顶层cfo_estimate74_backend，clk/rst/abort_sync；输入frame32、generation32、index7、last、I/Q各S38。仅允许绝对值<2^37，最小S38码视为非法输入。输入s_valid&&s_ready必须同时被两条支路接受，禁止某条支路单独提前取走样本。索引0..73，last仅在73。相位支路沿用已验收的cfo_phase74_core_v2.sv及原32位分母除法器，不改变其运算。

输出m_valid是记录传输有效；m_estimate_valid才表示频偏估计可用于补偿。m_mode编码：0 INVALID、1 MAIN_PHASE、2 DEGRADED_FFT、3 INVALID_ZERO。无效估计仍正常交付一条记录，频偏为0且estimate_valid=0，不能把0Hz解释为已经确认没有频偏。频偏为S32/Q16 Hz，数学Fs500MHz，导频间距17920个名义样本。

输出总线包括frame/generation、error、mode、estimate_valid、chosen/phase/FFT频率及spectrum/linear/consistent标志；m_quality197与m_phase_detail132是诊断数据。所有字段在m_valid&&!m_ready时保持，两条支路仅在同一次结果握手一起释放。reset/abort同时取消两路、内部FFT和两个除法器，不让旧帧结果混入新帧。

错误1为中途帧/代号不一致，2为索引/last，3为最小S38码；4为内部FFT/除法或范围错误，5为合并时两路标识/nonzero矛盾。输入错误输出保留锁定帧标识，所有估计/诊断数值为0。内部错误4/5说明设计/控制异常，需上层reset/abort处理，不作正常捕获范围失败。

## 归一化和FFT

max=max(abs(real(z)),abs(imag(z)))。非零时ex=16-ceil(log2(max))，范围-21..16；逐分量以RNE缩放后S20饱和，前74点送入已验收FFT256核，其余182点补零。全零直接给INVALID_ZERO，不执行FFT支路，但合并仍等待相位支路完成。

FFT每级RNE/2和S20夹紧不变，twiddle S18/F17的正1仍为131071。质量核共享一对20x20平方运算计算输入能量与FFT输出功率，功率U40，74点能量U48。峰位置取自然序第一个最大值；次峰搜索排除主峰左右各4个bin，包括循环索引边界。

相干性：5*256^2*peak >= 74*energy；无歧义性：4*secondary <= peak。两个条件成立且归一化/FFT饱和数均0，才置spectrum。比较使用整数乘加，不先计算浮点比例。

令l/r为主峰左右相邻功率，d=2*peak-l-r。d>0时delta=RNE((r-l)*32768/d)，限制在[-32768,32768]；否则delta=0。峰序号>=128时减256得到有符号bin。fftCode=RNE((bin*65536+delta)*500000000/4587520)。新增cfo_divide_rne64wide用有符号64位分子和无符号64位非零分母；65位余数，64轮恢复除法加RNE，零分母报错。旧除法器保持冻结。

## 选择规则

consistent = abs(phaseCode-fftCode)*4587520 <= 500000000*65536，即两者相差不超过一个FFT bin。

1. spectrum、phase_linear、consistent均真，且abs(phaseCode)<=851968000，选择MAIN_PHASE及phaseCode。
2. 否则若spectrum为真且abs(fftCode)<=851968000，选择DEGRADED_FFT及fftCode。
3. 否则INVALID；全零单独INVALID_ZERO。851968000是13000Hz的Q16代码。

相位线性门沿用上一阶段0.05turn的中心化残差限制；没有把DTP截距当成CFO。两种候选值均由本次RTL输入算出，不从参考文件驱动估计值或有效标志。

## 验证边界

整数参考复用冻结的相位/FFT运算，已与19组原MATLAB审计的17,575个新增归一化/频谱/模式标量匹配。28组向量包括19组已发布数据、8组原整数边界和1组单点相位离群的降级单元例；模式分布为INVALID4、MAIN22、DEGRADED1、ZERO1。新增离群例只用于覆盖模式分支，不是新信道性能试验。

原生包验证38次完整结果，10次取消和5次输入错误；reset/abort各在原始收集、归一化、FFT输出、新除法执行中、合并输出待收这5处测试。正常输出背压合计154拍。每条归一化观测和每个FFT复数/功率均逐点比较，最终499位结果（含诊断）全位比较。新宽分母除法器另有14例，包括>2^32与接近2^64分母、正负RNE中点、INT64最小值和零分母。

验收预算：末点接受至合并结果<=7600拍，完整测试事务<=12000拍；这只是本阶段行为边界。逻辑存储新增z缓冲74x76位、功率256x40位，另包含既有FFT/相位存储；实际资源、150MHz时序、G=30000周期全链预算和持续500MS/s均未资格化。不得以此声称FFT2048前端、全帧或T11/T12/T13整体验收完成。