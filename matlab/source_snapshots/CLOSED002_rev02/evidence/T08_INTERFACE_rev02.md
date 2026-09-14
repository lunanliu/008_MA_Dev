# T08 第一遍重采样模块接口合同 rev02

状态：按2026-09-08用户两符号验证范围完成模块验收。生产默认N=1,336,320；短帧完整事务测试N=5,120。生产默认综合网表只观测两符号前缀，不据此声明全帧或系统资格。当前实现为descriptor rev02，本文替代rev01过期状态及6拍配置描述。

## 输入到输出

cfg 是一个原子描述符。T06 正常结果 status 必须恰为0x4800，value作为有符号ppm×2^18；结果frame_id与上下文frame_id必须一致。T06自身不输出generation，调用者将其绑定到捕获上下文的generation，两份generation必须相同。不得用context-ready占位记录代替真实T06完成结果。

TO 是相对于原始帧坐标零点的整数偏移，范围[-101,101]。T05绝对fine_start若作为TO来源，应先减去所绑定raw frame的坐标零点；这里的TO不能同时应用到数据裁剪。q0是原始采样单位的Q0.28小数，当前只接受冻结验证的0或0.5。该接口限制不是连续小数域的科研通过声明。

step = 2^28 + sign(ppm_q18) × RNE(abs(ppm_q18) ×16 /15625)。只接收±150ppm以内的T06数值，step只能在[268395191,268475721]。配置路径中的常数除法及相位乘法为精确整数分拍运算；不改变已冻结的RNE数值。003验证该实现，004/005通过150MHz内部OOC布局布线时序。

用Q=2^28，o=nominal_first，r=raw_first，phase0 = (53+4TO-4r)Q +4q0 +(4o-215)step。
对于生产o=0、r=-172，退化为T07公式(741+4TO+4q01)Q−215step。对于局部测试o=5120、r=4948，phase相对第一块增加20480(step−Q)。算术核不再次应用TO，不接受外部phase，不执行skip33。

输入transaction固定从r=o−172开始，长度N+540，必须声明可用区间完整覆盖[r,r+N+539]。四lane低位在先，每拍lane_valid=0xf，s_raw_index为该拍lane0绝对原始坐标，必须r+4×beat，beat从0递增，last只在最后一拍为1。旧R0文件多出来的132点仅由fixture导出器一次移除，不进入生产接口。

descriptor对首末Farrow窗口执行保守真实context检查：RNE后的first_base−107≥0，last_base+2<4(N+540)。107来源于上采样FIR组合支撑0..106及Farrow左一抽头。正step和单调RNE使端点足以包住中间窗口。缺context拒绝，不能wrap/repeat/补零。

## 输出和T09消费

内核保留物理索引31..30+(N+72)，pack4一次连续重排。m_sample_index= o−36+4×beat，包含[ o−36,o+N+35 ]；前9拍与后9拍为guard，中间N/4拍为nominal。每拍四个lane均有效，两个mask互斥且并集为0xf。m_first/last标识整个含guard事务，m_nominal_first/last标识nominal段。frame_id/generation贯穿输出和完成记录。

数据和所有metadata在valid且非ready时保持；只在握手计数。abort/reset明确撤销当前未完成流，不保证撤销边界跨越的valid保持。任何下游已收到的失败帧前缀必须以完成失败作废；本模块不持有整帧回滚存储。成功完成前仍不能把一帧声明为可用。

T09需求保持为只读相同frame/generation的nominal区域，A128 FFT窗口（payload起点−128..+1919，等价CP起点+384..+2431），74个pilot-bearing payload符号。T09决定访问方式，本模块不冻结bank地址/仲裁；guard不是额外payload。频域exp(+j2πk/16)补偿由下游按实际FFT bin执行一次。

## 失败和恢复

合法描述符从接受到结果可见为96拍，003验证上限100拍；明显非法字段直接返回失败。配置结果可见与首个数据输出是不同事件。不接受下一配置直到本帧完成被取走。状态与错误码：0x10估计身份不匹配，0x11无效T06结果，0x12ppm越界，0x13TO/q0非法，0x14长度，0x15raw/nominal坐标，0x16available范围，0x17相位/实际窗口支撑，0x18控制状态。

运行期复用错误：1中止、2pack/FIFO掩码不变量、3阶段计数溢出、4输入frame/generation/beat错误、5输出顺序/last、6尾部未排空、7零step、8处理看门狗、9内核状态；新增0x20输入raw坐标/lane/last错误。导致错误的已接受边沿也被计数。首个错误保持，随后本核复位32拍，产生一个失败完成，取走后HALT。配置拒绝不启动核，直接一个失败完成并HALT。

completion一旦发布，在背压下（含abort）保持成功标志、身份和错误不变。只有全局本模块rst能从失败HALT恢复；要求rst至少32拍，使复用FIR及流水线充分复位。reset可在配置/运行/背压/完成期间撤销事务并清除所有计数，下一配置重新绑定身份。不接管别的模块。

PROCESSING_LIMIT_CYCLES默认400896，从内核清零/启动起算，包含输入饥饿和输出背压。超时是本模块安全上限，不是性能PASS；任意无限背压不承诺成功。首包短仿真为30000拍，另测生产默认计数配置的描述符。成功条件同时要求各级接受数、pack数、输出数及101拍quiet tail全部匹配。

## 证据与使用边界

- T07冻结算术和IP参数直接复用；第一遍6组、444个规定FFT窗口全部低于-45dB，最差-51.120104dB。这是既定信号/参数域的算法证据，不是本次短PSF重新测得的EVM。
- 003：126组描述符、3次数值短帧、11次预期错误事务及3处配置中途复位通过；包含完整短事务尾部/guard/连续帧/背压/恢复。
- 009：默认完整N生产综合网表，-150/+150ppm各两符号长度5120点，包含36点前guard；每例10312个I/Q分量逐整数一致，1280 nominal拍连续、最大空拍0。生产帧completion未运行到终点，短前缀用模块reset结束。
- 150MHz内部OOC物理：setup+0.099ns、hold+0.010ns，72275 LUT、48826 FF、768 DSP；顶层IO/reset边界时序和板级不在该范围。
- 输出有效段实测4点/周期，按150MHz为600MS/s；case10/12从配置到首个nominal分别287/338拍，各记录147拍输入反压。不得将有效段速率换算成跨帧整链保证。
- 用户已取消新增全帧长仿真门。生产full-N长度/端点依靠源码合同与短完整事务覆盖，不声称本封装全帧仿真PASS；原006中断与007取消原样保留。
- T09按相同frame/generation消费nominal；T10负责跨阶段bank、双遍调度、CDC与整链500MS/s。T08 PASS不等于T06估计精度问题解决。

当前规格、源码/IP冻结清单与验收入口见T08_FINAL_ACCEPTANCE_AND_HANDOFF_ZH_20260908.md及交付包manifest.json。
