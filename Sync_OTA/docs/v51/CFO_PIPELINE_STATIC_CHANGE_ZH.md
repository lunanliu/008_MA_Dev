# CFO 150 MHz 后端分拍设计包

范围：cfo_phase74_core_v2.sv、cfo_fft74_quality_v2.sv、cfo_divide_rne64.sv、cfo_divide_rne64wide.sv。代码候选与逐文件diff、输入/候选SHA256在 reports/v51/pending_arithmetic/cfo_manifest.json。用户明确批准四份补丁后，已按候选哈希应用到生产源集，见 cfo_application.json；不运行仿真，不改算法、精度、阈值、FFT结构或频率。

## 所选结构与备选

| 原路径 | 方案A | 方案B | 选择与原因 |
|---|---|---|---|
| CORDIC动态移位→加减→饱和 | 增加SHIFT寄存 | 全改展开CORDIC | A，24轮与顺序完全保留，每观测新增24拍仍远低于相邻观测间隔 |
| unwrap判决→加法→加权乘法→累加 | offset/phase/product/accumulate分拍 | 将整体大表达交给综合器重定时 | A，明确寄存边界、保持逐点舍入/宽度 |
| CENTER 74倍残差−总和→abs→max | 两组并行加减→和→abs→max分拍 | 复用通用串乘 | A，常数74只有三项，分拍直接且无需乘法器 |
| 频率常数宽乘法 | 全宽串行移位加法 | DSP部分积流水 | A，每帧尾仅一次，phase16轮/quality29轮，保留全位宽/模语义并减少常驻宽乘法 |
| RAM读取→动态规范化→RNE→饱和 | LOAD/SHIFT/ROUND/CLAMP分拍 | 使用组合归一化大函数 | A，74个真样点收费，182个零填充保持旧两拍 |
| 平方→功率加和→能量累计/峰值 | II1三边沿token流水 | 暂停FFT，串行处理每点 | A，避免新增256倍服务间隔；kind/index/last/IQ/saturation随数据一起寄存 |
| 余数比较→商加一→取负 | 新ROUND_PRE商寄存 | 重排负数RNE公式 | A，两个divider各增1拍，保留原精确语义 |

## 数据所有权与同时事件

quality正常化后仍在N_SEND等待FFT ready，ni/nq及index稳定。能量/FFT共用功率流水，每个接受边沿保存kind、index、IQ、last与累计饱和数；最后FFT接受后进入F_DRAIN，等待最后功率真正提交才进入S_READ。错误边沿撤销所有未提交power valid；可以保留同拍提交的更早正确记录作为诊断，下一拍RESULT必须稳定。reset/abort清全部valid，不能让旧token写到新帧。

phase在offset决定后才更新previous_angle，随后保存unwrapped、加权积和dot_sum；观测序号一直保持到累加结束。最后观测累加先完成才启动频率除法。PRED_STORE单独累计残差；CENTER保持index直到完整max更新。审计端口随真实提交边沿移动，不承诺旧周期，但顺序和值不变。

## 数值推导

- phase串乘为signed72，16轮正系数15625。原dot_bad要求abs(dot)<2^49，因此完整积严格在signed64范围，取低64与旧乘法等价。
- quality串乘保存低64位，每轮在模2^64下移位相加，等于原signed64结果的位型；真实fractional_bin×500000000范围小于2^53，转换回signed64无溢出。
- 20位有符号IQ的两项平方和小于等于2^39，40位power保留全部有效位。峰值相等时仍保留先前较早bin。
- CENTER将((64R+8R)+2R−sum)重新结合为(64R+8R)+(2R−sum)，各项在64位模整数域等价；只在最终值上取绝对值。max(a,b)≤K等价于a≤K且b≤K，以并行比较去掉max后再比较。
- 两divider保留64轮商/余数计算；ROUND_PRE采纳最终寄存余数，保存完整RNE商，随后恢复符号。不合并两次舍入、不提前放ready。

## 周期与全链回代

独立CFO reviewer按实际候选状态逐边沿推导：末观测接受为E0，phase在5687clk150发布结果（含75次divider新增拍）；quality在7051clk150发布结果，比旧6792增加259，quality仍是主导路径。phase正常观测服务II=53，小于观测间距的严格下界4608。

quality关键边沿：最后FFT输入E736，FFT最后输出E6368，最后功率提交E6370，最后扫描E6882，delta结果E6953，frequency请求E6984，RESULT E7051。原生仿真尚未运行，这些是源码推导。

新的保守控制常数：B=7091、E0=357109、S=345475、Fmin=334520、Fmax=334992、coarse配置/仲裁912，单位均clk150。

- 双bank反馈归纳余量E0+Fmin−2S=679>0；最终输出不积压的独立下界336384>Fmax。
- 八窗占用≤2+floor((G+23357)/4480)；G≤8002即可满足8槽。按锁定FIR服务合同Lfir=72、G=66+Lfir=138，峰值上界7槽。
- CFO无消费间隙Bout≤24869+G=25007clk150。E2生产一帧期间最多跨一次该间隙（输出ring及在途容量65600<N334080）。
- CFO单bank从首粗旋转写入至最终尾拍≤E0+Fmax+(S−334080)+G=703496+G=703634clk150。注意E0和S同时增加，不能只收费一次259。
- E1 commit≤345088clk150；E2 nextcfg≤359533、bankfree≤359428。残差预算9600及两次cfg32拍代入后SFO双bank寿命≤714180<801668，余87488拍。E2资格抖动20473加359533<400834，无上一E2作业积压。
- raw联合条件仍为Dcfg+Lfir≤59691，正常固定准入32及Lfir72充裕；没有通过放宽输入吞吐、时钟、精度或丢弃合法数据换取预算。

## 资源与未有证据

预估phase额外约650FF，quality约1.1kFF，宽divider约64FF；不新增BRAM/URAM，实际LUT/DSP变化待综合网表。每拍算术边界已明确，但真实6.666666667ns布线、扇出、时钟关系仍需STA，不能以静态解析或预计FF数量宣称时序通过。

静态候选绑定：reports/v51/static_candidate_binding_06，129源完整顶层绑定0错误，厂商内部为真实stub/接口边界，非原生展开。独立CFO和frontend reviewer分别检查周期和数值/握手；最终以实际候选SHA256对应审查为准。
