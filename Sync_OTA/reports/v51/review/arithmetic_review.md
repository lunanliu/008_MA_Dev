# V5.1 残差LS与除法RNE结构优化独立静态审查

本报告审查主开发者拟定的电路结构，并不把尚未执行的编辑脚本当作RTL事实。唯一RTL开发者为主任务；本review只写本文档，未修改RTL、运行仿真、编译、综合或实验。

当前读取的基线：

- rtl/sfo/residual_estimation/sfo_residual_ls74.sv，304行，SHA256 C3A1CB3073748C3607534D266A38B6ED7ED6DB0CD143CCB387F8C7525F18BC75。
- rtl/sfo/residual_estimation/sfo_residual_div_u80_u49_rne.sv，92行，SHA256 D600F457C3C5821A9B7349FE4AEBC2370D02909C4E3A8C171CDBA630C4F88D7A。
- 交叉核对sfo_residual_peak_interpolate.sv、sfo_residual_delay_backend4.sv、sfo_residual_estimator4.sv与sfo_schedule_review.md最新§17。

目标器件xcvu11p-flgb2104-2-e，计算域125MHz/8ns，持续原始输入指标仍500MS/s。LS每真实帧只在74个delay收齐后进行一次帧尾计算，适合用低吞吐共享算术换取清楚的寄存器边界。新增尾部服务计入150MHz调度预算，不放宽任何算法精度、时钟或332999保护阈值。

## 1. 现有代数与必须保持的有限字长含义

令M=74，输入d_k为signed24/Q16，w_k=2k−73，k=0..73。sum(w)=0，D=sum(w²)=135050，M×D=9993700。现有LS:47、203–216收集：

    SD=sum(d_k)，SWD=sum(w_k×d_k)，SD2=sum(d_k²)。
    SSE_num=9993700×SD2−135050×SD²−74×SWD²。

:243–247的两级相减是该式的精确整数实现；本次不改变减法顺序、SSE_LIMIT、quality/rmse门槛或符号解释。beta_numerator=2×SWD为signed41，ppm分子为abs(beta)×1000000×2^18，分母为BETA_DENOMINATOR−beta；符号由negative_ppm单独恢复。该分母不是BETA_DENOMINATOR本身，不能因为改串行而省掉减beta。ppm计算完成后，step仍基于已经舍入的ppm，再以abs_ppm×16/15625作第二次RNE；不能把这两个舍入合并成另一个公式。

point_square的signed24×signed24完整48位非负积、weight的signed9×signed24完整33位积不在本次串行化范围。全部24位输入的74点累加也落在当前40/40/54位容量内；现有next_sum扩一位溢出检查仍保留。选择串行化帧尾六个宽乘法不要求把每点流水算术一起改动。

## 2. 六次乘法的位宽与符号独立核查

| 操作 | 输入解释 | 完整宽度/原目标 | 固定迭代数 | 截位结论 |
|---|---|---:|---:|---|
| SD平方 | abs_sd是U40 | U80/wide_square | 40 | 98位结果[97:80]恒0 |
| SWD平方 | abs_swd是U40 | U80/wide_square或等价保存寄存器 | 40 | 同上；不得在首平方仍待缩放时覆盖它 |
| SD平方×135050 | U80×U18 | U98/term_sd | 18 | 98位全保留 |
| SWD平方×74 | U80×U7 | U87，零扩展至term_swd[97:0] | 7 | 高11位恒0 |
| SD2×9993700 | U54×U24 | U78，零扩展至term_sd2[97:0] | 24 | 高20位恒0 |
| abs(beta)×1000000 | U41×U20 | U61/ppm_product | 20 | 98位结果[97:61]恒0 |

abs_sd/abs_swd由signed40取负后赋U40，负最小值−2^39对应合法unsigned magnitude 2^39，不能把该最高位误当负号。beta先在41位内精确左移一位，负最小值−2^40的abs_beta同样为合法U41 magnitude 2^40。移入共享乘法器时必须零扩展，而非符号扩展。迭代乘数右移必须是逻辑移位；迭代计数须至少6位以容纳40。

三个SSE项是U98；先补两个0再转signed100，现有两次减法才对所有这些宽度的数值都安全。最大负和大于−2^99、最大正值小于2^98，因此signed100足够；不能改成signed98后直接相减。ppm_product原61位经{1'b0,ppm_product,18'd0}拼为80位分子，仍完整；denominator_calc必须保留signed50减法及原正值/高位检查。

结论：保留原目标寄存器和上述扩展方式时，共享U98乘法不会新增舍入、饱和或有效数据截断。这是代数/位宽证明，不是新RTL与参考数据的数值比较测试。

## 3. 共享shift-add电路及状态边界

采用acc[97:0]、shift[97:0]、multiplier[39:0]、remaining至少6位与操作/返回状态。每次作业先寄存清零acc、零扩展被乘数、完整乘数及固定迭代数。第i次迭代保持：

    acc_i=A×(B mod 2^i)，shift_i=A×2^i，multiplier_i=B>>i。
    acc_next=acc_i+(multiplier_i[0]?shift_i:0)。

所有项非负，任何有效部分和不超过完整积，而完整积宽度最大98，因此98位累加不丢失有效位。最后一次迭代必须捕获acc_next，不能捕获旧acc；remaining==1时完成的是最后一位。最后边沿同时左移shift可能丢弃不再使用的高位，这不影响结果，但该shift绝不能参与下一作业。

推荐顺序可为SD平方→SD缩放→SWD平方→SWD缩放→SD2缩放→原SUB_SD/SUB_SWD→ppm准备/缩放。若改成先做两平方，必须增加第二个平方保存寄存器，不能让wide_square先被SWD覆盖再计算term_sd。constant/magnitude必须在作业启动边沿冻结，WAIT不得依赖会变化的live选择信号。

数值门槛检查与乘法完成相隔原有寄存器边沿：先写term，再做100位SUB_SD；再做SUB_SWD；下一拍PREP_PPM才读取sse_numerator。不得同拍非阻塞赋值sse_numerator又用其旧值判断。ppm_product结果写入后再由SET_PPM读取拼接分子，负号及denominator_calc与同一个frame保持。

这一结构大约增加196位acc/shift、40位multiplier、计数/控制共约245个局部FF（可复用现有保存寄存器，实际净值以综合为准），一个98位加法器，不新增BRAM/URAM；宽乘法器具体节省多少DSP/LUT不能在未综合时伪报。125MHz每个迭代路径只应是本地寄存器→一位选择→98位加法→本地寄存器；绝对值或SSE比较不应与该加法串接。

至少两方案比较：A把40位和80位运算拆为DSP支持的limb乘积，加寄存器和平衡树，延迟更短但消耗更多并行乘法资源和布线；B本次选择共享完整精度串行乘法，每帧多约1.3us而保留明显的控制/数据寄存边界，更符合低频帧尾任务。98位加法仍须实际125MHz时序检查；若其真实路径失败，可把低49位/高49位带进位拆成两拍，每轮多一拍，再计149拍，不使用无依据多周期约束或降频。

## 4. 除法末迭代、RNE判据与加一的三段边界

现有divider:34–41、80–87把最后的50位trial比较/条件减、50位RNE比较和81位加一连在一拍。改法应严格是：

1. 第80轮只把next_quotient、next_remainder保存到寄存器，退出DIVIDE；busy继续为1。
2. ROUND_PRE用这组最终寄存器及保持的divisor计算round_up=(2r>d)||((2r==d)&&q[0])，寄存round_up。
3. ROUND_EMIT将{1'b0,q}+round_up送m_rne，发布同一q/r/tag/zero字段和m_valid，busy才清零。

关键是ROUND_PRE必须使用第80次完成后的q/r，不能沿用现有基于next_quotient/next_remainder的组合wire再无意做第81次除法。新的ROUND阶段不能继续落进“else if(busy)”除法循环，remaining到0之后必须停止移位/递减。2r用50位保存，divisor补0扩50位；81位加法保留可能的进位。RNE仍为ties-to-even，与正负ppm恢复完全分离。

正常请求握手时s_ready仍要求!busy且旧结果可消费。ROUND两级保持busy，因此不会在最终q/r尚待RNE时接纳新请求覆盖divisor/tag。m_valid发布后、m_ready为0时所有输出必须稳定；原“消费旧结果与接纳新请求同拍”的能力可保持。divide-by-zero原即刻结果路径保持m_quotient/remainder/rne=0、m_divide_by_zero=1、busy=0，不必为它强制追加80或2拍。reset必须清busy、m_valid、ROUND状态/valid和round_up，防止旧结果重现。

备选只加一级ROUND寄存，仍把50位比较与81位加一串在一拍；虽比旧末拍短，但不如两级把宽运算分清，本次选两级是合理时序结构选择。

## 5. 正常、错误、abort及背压语义

- LS:161–187优先级是reset→DONE处理→IDLE配置→活动态abort。活动串行乘法期间abort仍应立即fail_frame(4)，清有效结果、ppm归0、step归2^28、quality清零；不得等149轮完成才取消。
- DONE时abort原本不撤回已发布的结果，m_ready控制消费。若新共享乘法器单独带busy/valid，活动态abort须同时取消子事务；若作为同一LS状态机的MUL态，退出MUL后不得继续异步/后台写term。新frame的首个launch重新初始化所有共享操作数和计数。
- COLLECT的tag/index/upstream错误、ACCUM溢出、负SSE/分母非法及两次除法身份/范围错误均保留原错误码。rmse失败或quality无效原本输出estimate_valid=0，不等同直接跳过所有后续数学，应保留现有行为。
- cfg_ready只在IDLE，s_ready只在COLLECT。新增帧尾拍数不扩大允许接纳的新frame/新point数量，没有新增FIFO或CDC，数据所有权仍是一帧独占。
- LS idle timeout只统计COLLECT连续静默，串行帧尾期间idle_count不递增是原有语义；外层残差frame_age仍统计计算时间，不能因新增MUL态误把它标记为source_wait。
- peak_interpolate:158–172只等待div_ready/div_valid，没有硬编码“80拍后取结果”，因此除法结果延后两拍在接口上兼容。其abort通过divider rst立即取消；DONE保持结果的语义同LS。

## 6. 独立周期核对：必须包括共享divider的第二实例

六乘法149个迭代边沿。每次PREP/REQ/RESP各至多1拍则共167拍，替代旧SQUARE_SD、SCALE_SD、SCALE_SWD、PREP_PPM的4拍，净增≤163个clk125。实现可以更少，但新RTL形成后应按实际FSM逐边沿核对，不能漏掉operand寄存后一拍才被消费的转换。

实际divider有两个生产实例：ls74:98和peak_interpolate:77。每次RNE拆拍净增2，LS末尾两次除法增加4；每个peak插值最多增加2。于是：

| 服务边界 | 新增上界 |
|---|---:|
| LS第74点接受后的帧尾 | 163+4=167 clk125 |
| 最后一个peak之前至全帧残差完成 | 163+4+2=169 clk125 |
| 74个peak全部额外计算拍简单累加 | 74×2=148 clk125；不能把整帧总工作量只记成+4 |
| 旧R9200按最后窗尾部增加 | 9200+ceil(169×6/5)=9403 clk150 <9600 |

初次发现共享影响后已交叉询问SFO独立reviewer；其最新sfo_schedule_review.md§17.2已明确包含peak每窗+2、LS两次+4，并把Caux=632+ceil(Xa/4)修为634+ceil(Xa/4)。沿用每级≤3732拍、双slot无积压的充分条件时，Xa门槛必须从12400降为12392个clk500，main Xm≤10512不变。该“降低门槛”是新电路增加服务时间后的IP可接受条件收紧，不是放宽性能要求。

在实际IP满足这个收紧条件时，每个aux仍≤3732拍，前73窗增加的两拍由各窗服务预算吸收，不产生149拍末尾排队；最后窗才收费+2。若真实Xa不满足，应做有限74窗队列递推，不能继续引用无积压条件。SFO reviewer对frame_age采用不扣除pure_producer_wait的更强wall-time界ceil(5×C1/6)+末窗tail，该界已涵盖窗口运行期间全部计算占用；若另用旧“active拍数求和”证明，仍必须显式增加148拍。

直接由旧末窗界7651clk125代入：新≤7820clk125，转150域加10拍为9394；采用更保守旧整界9200再加203得到9403，所以R9600仍有197拍150域余量。延长R并不表示自动满足双bank/raw约束，主任务需在同一调度式将9200统一替为9600，同时保持Tmin400834、ntrain≤2及原raw期限，不偷偷复用已花掉的余量。

## 7. 审查结论与实施后应核对的有限事项

拟议共享U98乘法与两级RNE方案在代数、signed/unsigned、累加宽度和静态服务预算上可行，优于把六个低频宽乘法继续压在单周期路径。共享peak除法的逐窗影响已与SFO报告一致收口，没有要求创建猜想驱动的仿真实验。

这是一份设计可行性结论；当前基线文件仍是旧实现。代码落地后只需静态核对上述明确风险：最后累加保存新值、平方中间量生命周期、全部操作数零扩展、COUNT40宽度、ROUND不再迭代、busy/valid跨两拍保持、abort优先和旧结果隔离、真实FSM新增拍数≤所列上界、全部调用者预算同步更新。原数值模型对比、原生功能以及125MHz路径/资源尚未在本review执行；不得把本报告称为这些层级PASS。
审查记录时间：2026-09-18 01:22:12 +02:00，Europe/Berlin。

## 8. 实际待应用RTL候选逐diff复核

本节取代第7节“尚未有实际候选可核对”的阶段状态：已读取reports/v51/pending_arithmetic/sfo_tail.patch、manifest.json、两份实际候选全文及docs/v51/SFO_ARITHMETIC_STATIC_CHANGE_ZH.md，逐项比对基线和变更；仍未应用生产源码、未运行编译/仿真/EDA。

实际文件SHA256与manifest完全一致：

- pending_arithmetic/sfo_residual_ls74.sv：38B8CACBBAB1A23155EDD20937F0C661AC041628D097B2FB5C7E0CBC9C59F58E，共341行。
- pending_arithmetic/sfo_residual_div_u80_u49_rne.sv：936B8AF63564CFD242855EEAC6EBCE17360B6BEC06ADC65E94D2B67B1047385A，共99行。

### 8.1 LS候选的具体状态与位宽核查

候选:33–36新增状态16、17、18仍落在原5位state内；:72–78是U41 factor、U98 shift/acc、6位remaining，无signed移位。六个launch位于:238–260及:286–298：40、18、40、7、24、20迭代，零扩展分别58+40、18+80、58+40、18+80、44+54、57+41，都恰为98位。

:263–276只在MUL_ITERATE写共享累加器，remaining旧值为1时将mul_sum新和写目标并离开迭代；没有丢最后一位。目标值按SD平方→term_sd→SWD平方→term_swd→term_sd2依次保存；wide_square直到term_sd已经落库后才复用，覆盖风险关闭。mul_remaining在末轮减为0但同拍离开MUL态，下一launch再装有效正数，不存在正常状态下继续减至63的问题。

:279、283仍是原100位两级SSE减法；:287读取前一状态已寄存的sse_numerator；:289–296在PPM乘法启动时保存rmse、sign及50位denominator_calc；:273把新ppm_product保存，下一状态:304才拼80位numerator，NBA顺序正确。40位abs负最小值和41位abs_beta均以0扩展，:268/270截80位和:273截61位只丢前述证明恒零的高位。

:171–197完全保留DONE/IDLE/abort优先级。abort在任何新增MUL态先执行fail_frame(4)，case不会继续运行；共享寄存器可保留旧数据但没有独立后台valid/worker，它们只在MUL态被使用。下一帧第一条launch会重装factor/shift/count/kind且清acc，故不要求为了取消再把全部250位同步清零。COLLECT/ACCUM、质量阈值、错误码和分母/ppm/step检查未变。

### 8.2 divider候选的具体RNE与握手核查

候选:41–43已经改为最终寄存remainder和quotient_shift的RNE判据，避免继续引用第81次next值。:92–94第80轮保存Q/R并设round_phase=1；下一拍:81–84只保存round_up_q；再下一拍:85–90发布Q/R/RNE/tag并清busy。ROUND两个分支不更新remaining/Q/R，因此末轮不会重复执行。

s_ready仍由:35的!busy及输出槽可用控制，ROUND期间busy保持1，不能覆盖tag/divisor；:61允许旧结果消费，与:62新请求可同拍；:63重新清round_phase。divide-by-zero:64–71沿原快速结果语义；reset:46–59包括新增phase/up寄存。输出持有期间busy=0且m_valid=1，若m_ready=0则既无新请求也无busy运算，所有输出稳定。LS和peak的父模块均在abort或IDLE/DONE复位divider，无新增旧响应跨frame的路径。

### 8.3 实际候选周期可收紧为157拍尾部增量

候选没有额外的独立REQ/RESP或PREP/WAIT往返：6次launch各1拍，149个MUL_ITERATE边沿，六次乘法总155拍；相对旧四个数学状态4拍，净新增151个clk125。其余LS状态数量不变。LS两次divider新增4拍，最后peak新增2拍，故最后窗IFFT尾部至全帧结果实际候选净新增157clk125，低于设计包保守169。

保守R9600无需因此降低；由旧末窗7651+157=7808clk125，换算150域加10拍为9380拍；若以旧统一R9200再加ceil(157×6/5)=189，则9389<9600。保持169的设计上界也仍满足9403<9600。实际每窗peak+2以及Xa≤12392、frame_age全链wall-time条件依第6节执行，不因LS实际少12拍而撤销这些条件。

### 8.4 候选结论

对上述两份已核验hash的待应用代码，未发现必须修改的代数、位宽/符号、末轮累加、状态转移、abort或背压功能问题；新增正常尾部周期在已冻结保守预算内。可作为主开发者申请应用这一具体补丁的独立静态依据。此结论限这两个候选hash；生产应用后的身份核对、静态工具绑定和以后授权的数值/原生/物理时序证据仍各自记录，不把本review当作工具运行或应用成功证明。
候选复核时间：2026-09-18 01:23:35 +02:00，Europe/Berlin。

## 9. CFO四份实际候选的独立数值与接口复核

本节读取reports/v51/pending_arithmetic/cfo_manifest.json所列四个实际候选全文与各自.sv.patch，并查生产调用者cfo_estimate74_backend_a07.sv。候选尚未应用；本review没有修改RTL、运行仿真或EDA。四核位于CFO后端clk150域，目标周期约6.667ns，本节不能沿用前文LS的125MHz/8ns物理周期。

### 9.1 候选身份

| 待应用文件（均在pending_arithmetic目录） | 实读SHA256 |
|---|---|
| cfo_phase74_core_v2.sv | 528199229C8B56DCD77CE280339C7614FD6089A55C55B0C6E18E815205413321 |
| cfo_fft74_quality_v2.sv | D2E76955CC010F082F7D18B8D1B059064B770F315D2FE04D72E68AF4C5C183E5 |
| cfo_divide_rne64.sv | D7C3ACCCA6FB5495776CA80DE5C8F70BD98EF1A9621CEFDBEA24EA199CA7FA09 |
| cfo_divide_rne64wide.sv | B2989E31DBA16B4550E33933071B6DBD7B18217F59DB1AE5810EB9E346321CCE |

实际hash均与manifest一致。只对这些候选版本作下述结论。

### 9.2 phase：CORDIC、unwrap与dot拆拍不改变值

phase:111新增CORDIC_SHIFT从当前x/y/iteration做signed算术右移并寄存；下一拍CORDIC才使用这组shifted值及同一迭代的y符号/atan，x/y/angle在SHIFT期间保持。每次CORDIC更新后iteration加一再返回SHIFT，第23轮直接进入STORE_OFFSET，故仍恰24次迭代与24次饱和计数，不是48次迭代。

:116先按旧previous_angle及当前angle求offset_next并保存，同时更新previous_angle；:118在下一拍用新unwrap_offset加当前angle。它与旧同拍的angle+offset_next逐位相同。此前difference组合wire在previous_angle更新后改变，但STORE_PHASE已经不依赖difference，故不会把unwrap误抵消。

:118保存held_unwrapped，:122以同一observation的signed9权重乘signed40值得到完整signed49；:124再符号扩展到signed56累计。observation在STORE_ACCUM完成后才递增，因此权重、RAM索引与audit不能跨点。第73点最终dot_sum在进入FREQ_START之前已完成寄存，dot_bad读取的是全74点和。

phase:128–135以signed72 acc/shift和正U16因子15625执行16轮；负dot先按符号扩展至72位，factor只逻辑右移。末轮保存frequency_sum新值。dot_bad保证abs(dot_sum)<2^49，而15625<2^14，真实乘积绝对值严格小于2^63，取低64位保持完整signed64值；无需依赖“高位截断碰巧正确”。中间72位足够保存全部signed部分积。

PRED_WAIT:150–152先做原商/残差范围检查，再保存held_prediction/held_residual；PRED_STORE:156–159才写RAM、累计和并产生audit。同一work_index在这两拍保持。原signed56 residual_sum加signed56 residual与新两个signed56寄存相加的宽度和模语义相同。

CENTER_PAIR/SUM将旧((r<<6)+(r<<3)+(r<<1)−sum)重组为((r<<6)+(r<<3))+((r<<1)−sum)。所有中间量均signed64，即使按一般位向量解释，模2^64加减具有结合性，最终bits不变；正常实际phase/residual范围还远低于64位溢出界。CENTER_ABS保存U64绝对值；CENTER_EVAL用max(old_max,magnitude)更新结果。原max<=T严格等价于old_max<=T且magnitude<=T，因此并行两比较保持线性阈值和原饱和/非零条件。

phase/预测/center审计各在真实写入或判定边沿产生一次valid，index和value均来自同一个保持的work_index/observation。其时间相对旧实现延后，逐点值与顺序不变；不能拿审计valid的旧绝对拍号作为等价要求。

### 9.3 quality：四阶段归一化与符号舍入

quality:132–134仍排除S38负最小值，所以maximum<2^37；block_exponent范围为−21..16。N_CONFIG:144–147先锁定normal_left、6位shift及sticky mask；右移分支只会有shift≥1，左移包括e=0。因此normalized_shift中的wide[shift−1]不会在合法右移路径访问负下标，mask=(1<<(shift−1))−1与旧函数相同。

N_READ先保存RAM字；N_SHIFT返回signed64算术移位基值及原guard/sticky/tie-even增量；N_ROUND以signed64加0或1；N_CLAMP采用原S20正负阈值。对于负数，算术右移给向负无穷取整基值，再按原guard/sticky/最低位加一，保持原nearest-even含义。没有把signed负数误当绝对值舍入，也没有合并clamp与别的舍入。只有74个真值经过新增三拍，182个补零仍N_READ→N_SEND。

N_SEND处ni/nq在FFT不ready时保持，normal_audit_valid和normal_saturations只在真实FFT握手时更新。质量指数、frame/gen在整帧期间稳定，新增变量移位寄存不会更换所属帧。

### 9.4 power II=1流水、尾写入与错误隔离

两个S20平方是完整signed40非负值，各自不超过2^38；两项和最大2^39，存U40完整。74次能量累加落在U48内。候选:113–123将每次握手依次推进：

| 相对边沿 | 动作 |
|---|---|
| E | 接受normal或FFT样点，保存两个平方及kind/index/last/原IQ/sat |
| E+1 | power_v0推动两平方求和，全部metadata同步推进到stage1 |
| E+2 | power_v1写energy或power_ram，更新peak/sat并发FFT audit |

该流水每拍能接一个FFT点，不引入每点两拍停顿。FFT audit拼接的是随该token保存的原IQ与同一token功率，不再错误引用当前FFT端口数据。

最后FFT样点接受后状态进入F_DRAIN；只有最后token在E+2真正写power_ram、更新最终peak_bin/sat的同一边沿才切换S_READ。E+3才读取power_ram[0]，E+4才按最终peak_bin评估，故最后RAM项与峰值均先于扫描生效，不依赖RAM读写同址模式。

F_COLLECT错误分支:174同拍清power_v0/v1且进入RESULT；同一边沿此前已经有效的旧stage1正确token仍可能提交，这属于错误发现前已接纳的正确前缀。错误输入本身没有入管，下一拍两个valid均0，RESULT期间不会再被旧token改变m_quality。stage0算出的数据寄存可以保留，但valid被清后不能提交。全局rst/abort_sync分支清所有新valid、metadata及算术寄存，阻断旧帧流入新帧。正常结果进入RESULT之前power早已排空。

原错误策略是整epoch停止/复位。FFT接收中发现协议错误后，不应脱离这个合同独立强制重启下一帧而不清底层FFT；本次候选没有引入这种重试行为，也没有新增单帧删除。

### 9.5 quality常量运算、模乘法与插值

MATH_PRE/SUM分别保存peak×(2^18+2^16)、energy×(64+8)+energy×2，以及(2peak−left)−right，与旧coherent和delta分母逐位相同。U40功率、U48能量使这些系数运算均落在64位；delta差值左移15仍落signed64。最后scan点的left/right/secondary在进入MATH_PRE前已更新，未读取旧邻居值。

quality:212–219用U64 shift/acc执行29位常数500000000的位串乘。对负fractional_bin，这是模2^64的乘法：把signed64原码视为U64后，连续移位加法的低64位与旧signed64乘法的低64位严格相同。最后$signed(frequency_hold)恢复原位模式。正常signed_bin∈[-128,127]，delta∈[-32768,32768]，因此abs(fractional_bin)<2^24，乘500000000的绝对值小于2^53，真实结果本身也落在signed64范围。这里允许中间U64模回绕；不能把它与LS的“所有中间无符号数都不回绕”证明混用。

第29轮保存frequency_sum新值后再进入F_START，divider采样的是寄存分子，未把最后加法组合接到divider。delta分母<=0仍直接置delta0再计算频率；有效分母的RNE/±32768夹持与最终S32检查保持。

### 9.6 两个signed divider的ROUND_PRE

两个候选均保持64次restore。最后DIVIDE寄存Q/R，新增ROUND_PRE以该Q/R计算ties-to-even的幅值加一并保存rounded；ROUND单独按negative恢复符号。原33/65位doubled足够表示2×remainder，因为有效余数严格小于32/64位分母。abs(signed64)最大2^63；对非零分母，rounded仍不会溢出64位，负最小值/分母1返回原signed64最小值。

RESULT的m_quotient/m_error保持至m_ready，s_ready仅IDLE；没有提前接纳新事务覆盖rounded。zero denominator仍立即置error进入RESULT，新增ROUND_PRE不介入；clear优先清state/rounded并组合屏蔽s_ready/m_valid。phase调用者m_ready固定1且仅对应WAIT读取valid，quality在D_WAIT/F_WAIT读ready，均不依赖固定66拍计时；额外一拍接口兼容。生产源码搜索确认这两个divider分别只有phase和quality实例，没有遗漏第三个生产调用者。

### 9.7 周期与资源口径

此次quality实际有N_SHIFT、N_ROUND、N_CLAMP三个额外真样点状态，故归一化净增222拍，而不是旧初步方案的148拍。再加N_CONFIG1、power尾排空2、MATH_PRE/SUM2、F_PREP+29轮乘法30、两次divider ROUND_PRE2，共净增259clk150，低于目标300。其余FFT256、power输出II、RAM扫描两拍/点均不变。

phase每观测CORDIC多24拍、STORE多3拍；正常观测间隔足以吸收前73点这部分服务，末观测多27拍。此外frequency串乘17、75次divider各1拍、PRED_STORE每点1共74、CENTER每点多3共222，末端增量约415拍。但后端取phase/quality两路完成的max，不能把这415再加到主导quality259上，也不能宣称phase本身只增300。CFO主审负责按完整边沿口径确认phase仍在quality之前完成，并回代B/E/S、G=138时7/8窗口及raw/SFO/CFO共同服务界。

新状态均改为5位枚举，phase与quality各21/22态可表达。新增数据多为局部FF、串乘加法和功率寄存，不增加帧RAM容量/CDC。四类结构分别比较了动态移位与算术串接/拆拍、宽常数乘/DSP分块或位串乘、power串行三态或II1流水、合并RNE与符号恢复/分开寄存；实际候选选择后者中的有界低占空比或II1流水方案，与其吞吐职责相符。

这些是结构预算，不是150MHz物理时序保证：CORDIC加减后饱和、49位dot乘、64/72位串行加法、normalize动态shift与guard/sticky、ROUND_PRE的余数比较加幅值进位仍各有真实寄存器间路径，后续按授权真实STA核对，不增加无依据false_path或放宽时钟。

### 9.8 本轮结论

对§9.1四个候选hash，独立逐diff/全文审查未发现必须修正的数学、signed/模运算、normal/FFT power/audit对齐、最后写入后扫描、错误清pipeline、结果背压或abort问题。当前数值结论是静态逐操作等价与边界证明；没有执行数值实验、RTL仿真、原生展开或资源/时序工具。可将本节作为这四个具体候选的独立应用前依据；周期最终B/E/S口径与8槽结论由CFO周期review交叉定版。
CFO候选复核时间：2026-09-18 01:34:29 +02:00，Europe/Berlin。

### 9.9 CFO周期交叉定版与本次交接

CFO独立周期reviewer已提供逐状态定版，核对本节增量一致：phase=5272+24+3+17+74+222+75=5687拍；quality=6792+259=7051拍，quality仍主导且领先phase尾部1364拍。含40拍CDC/join余量的B=7091；E0=357109，S=345475。

完整bank寿命不能只增加一次259：E0与S各含这次增量，因此d−b≤703496+G。Bout≤24869+G只收费一次；窗口槽上界2+floor((G+23357)/4480)，八槽充分条件G≤8002。实际设计G=138时需7/8槽，Bout≤25007，bank寿命≤703634。此口径与cfo_output_review.md§21一致，替代本节先前“由CFOreview最后定版”的待交叉状态。

主开发者另报告static_candidate_binding_06为零错误；本review未运行或重跑该工具，只作为主任务报告的静态绑定证据记录，不升级为原生Vivado展开、仿真、综合或时序证据。本文不代替生产应用权限判断，也不把其他两个SFO文件的单独批准扩展到CFO。四份CFO候选仍按§9.1的明确hash作为审查对象。