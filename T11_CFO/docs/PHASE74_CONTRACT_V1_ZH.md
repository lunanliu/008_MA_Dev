# 74点相位估计路径契约 v1

2026-09-14。对应既定实现门槛4的相位部分，输入为已批准前端的74个复数相关量 z（I/Q各S38，数值绝对值小于2^37）。此模块保留全部74点，不用首尾两点代替拟合。尚未实现FFT256谱质量门、谱峰插值、MAIN/DEGRADED_FFT/INVALID选择；m_phase_linear不能直接当作完整CFO有效标志。

## 算法含义和单位

每个相关量的相位表示该导频符号的公共相位。相邻符号间隔17920个500MHz采样点。频偏使这些相位随时间持续变化，所以对74个时刻的相位拟合斜率即可估计频偏；截距仅是相位起点。

冻结模型先以40位有符号Cartesian坐标、24次移位加减CORDIC求相位，角度单位为turn/Q31。原x<0时先把向量翻转180度，并按原y的正负（0算非负）加±2^30相位；每轮方向由y<0决定，移位取有符号算术右移（向负无穷取整）。每轮x/y按S40饱和，atan常数采用模型相同RNE。

逐点解缠时仅当相邻原始相位差严格大于+2^30，才减2^31；严格小于-2^30才加2^31；恰等于边界时不改。令a[m]为解缠角度，w[m]=2m-73，m=0..73：

- dot = sum(w[m]*a[m])，模型要求abs(dot)<2^49；RTL累加暂存S56。
- phase_q16 = RNE(dot*15625/1239089152)，输出为Hz/S32F16。
- predicted[m] = RNE(phase_q16*m*458752/390625)，单位turn/Q31。
- residual[m] = a[m]-predicted[m]。
- centered[m] = 74*residual[m]-sum(residual)。
- phase_linear = (20*max(abs(centered)) <= 74*2^31) 且CORDIC没有饱和。

RNE为最近偶数舍入，负数同样严格处理；不使用浮点atan或系统FFT作DUT实现。全零输入额外输出m_nonzero=0并强制m_phase_linear=0，频率为0。该全零分支与顶层MATLAB estimate的提前INVALID_ZERO一致；全零时内部CORDIC角度无物理意义，不据此给频偏有效性。

## 实现与接口

cfo_phase74_core包含一套串行CORDIC、74x40bit解缠存储、74x56bit残差存储、一个复用的cfo_divide_rne64和累加/比较逻辑。两片工作区逻辑容量共7104bit，另有24x32bit atan ROM。实际DSP/LUT/BRAM映射及150MHz闭合留待综合门槛，不把这些逻辑位数当实测资源。

输入每点携带frame32/generation32/index7/last及I/Q。首点index必须为0且锁存frame/generation；随后索引严格0..73，只有73号点last=1，同一帧的标识不得变。CORDIC忙时ready为0，上游须保持未接受的输入。每点处理后再接收下一点，完整拟合结束后才输出该帧结果。真实导频间隔较大；整链还须单独验证下游调度、背压和帧切换。

输出包含原frame/generation、nonzero、phase_linear、error、phase_q16、weighted_sum、max_centered和饱和计数；背压期间所有结果保持。error=1为帧/代次不符，2为索引/last不符，3为超出输入数学范围（S38最负值），4为内部数学范围/除法错误。错误结果数值清零；输出被接受后才允许新帧。rst/abort_sync同时清除CORDIC、除法器与事务状态，不清整片RAM，但任何新计算前会覆盖其全部74个有效条目。

内部观察端口只用于逐点核对角度/解缠、预测/残差、中心化残差；它们是不带反压的单周期脉冲，生产调度不能依靠这些调试脉冲。清除期间忽略观察端口，产品ready/valid被屏蔽。

## 验证边界

先复用指定RCFO004十例及RCFO003九例已发布审计，验证完整74点中间值；不重跑MATLAB或产生新的通信信号。额外八组整数单元向量覆盖全零、正负实轴、合法最大幅度、正负解缠、半周严格边界及小整数移位舍入，这些不是新的场景准确度研究。

TB逐项比较74个angle/unwrapped、74个predicted/residual、74个centered及最终结果，并检查等待输出稳定、六次复位/取消（CORDIC中、预测除法中、结果等待中）和五个协议/输入错误。末点接受至结果有效不超过6000周期；完整测试输入事务不超过11000周期。周期门槛用于限制本相位模块尾处理量，不是全链持续500MS/s证明；FFT质量路径和前端FFT时间仍需加入。

工程为独立vivado/CFO_PHASE74/CFO_PHASE74.xpr，top=cfo_phase74_core，sim=cfo_phase74_tb，part=xcvu11p-flgb2104-2-e，Vivado2021.1。旧CFO_SYNC/CFO_COORD及其冻结源不修改。通过后才继续FFT256质量门和最终模式选择，不能把相位路径的成功提前写为T11/T12/T13 PASS。