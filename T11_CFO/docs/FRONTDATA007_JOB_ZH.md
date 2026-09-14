# CFO-FRONTDATA007：只读提取已发布前端审计

2026-09-14，T11 Astra派给原T11 Luna 01a076f0-d8c0-72a0-8371-cb2ff29c1b28。目标是为已批准CFO前端RTL提供可追溯输入/参考；本包不运行MATLAB、Vivado、旧runner、FFT仿真或新的信道/算法扫描，不修改任何RTL、参考MAT/JSON或既有向量。

前置后端已独立PASS_LIMITED_74_POINT_BACKEND，报告reports/BACKEND006R1_REVIEW_20260914/INDEPENDENT_REVIEW.json。下一前端结构预算见docs/FFT2048_FRONTEND_ARCHITECTURE_PREP_ZH.md；尚无前端/整帧/物理通过声明。

## 固定来源与输出

根D:/008_MA_Dev/T11_CFO。准确来源由docs/FRONTDATA007_SOURCE_LOCK.json指定，沿用19组已发布case：RCFO004的1/3/11/21/31/41/51/61/71/81，RCFO003的1..9，后者仅NCO32_ROM10_C16F14主配置。不要按mtime、目录近似名称或其它配置替换。

从各自bit_audit.mat或bit_NCO32_ROM10_C16F14_audit.mat读取以下完整数据集（保存原HDF5形状、dtype、实虚分量顺序，不凭猜测转置）：

- /ba/front/pilot_fft_codes：60680个复数，MATLAB逻辑820x74，S26。
- /ba/front/pilot_coeff_codes：60680个复数，S18/F17。
- /ba/front/pilot_product_codes：60680个复数，S28/F21。
- /ba/front/z_codes：74个复数，绝对值<2^37。
- /ba/estimator/z_codes：74个复数，必须与front.z及此前已提取phase74_published同case的z精确一致。

同时保留同case原结果JSON的coarse_parameters、front统计、estimate关键字段和frame/条件上下文；不要求补造原来没有的可选label/scope。记录每个MAT/JSON的原始bytes和SHA256、使用的decoder/库/解释器/脚本hash、实际命令。

另仅对RCFO004 case001/003/081，从input_i16.bin（小端I16/Q16交错，每复数4字节）直接复制74段：首样本25984+m*17920，每段2048点。输出每case的raw_windows_i16.bin（606208字节），按m=0..73拼接，附原始全局首样本、字节偏移和逐段hash。这是未做粗CFO补偿的原输入，标签必须明确；不要把它当作FFT入口已补偿样本，也不要在本数据包重算旋转/FFT。带上原coarse_parameters即可供Astra下一步建立整数输入。

每次独立work/CFO_FRONTDATA007/attempt_<UTC>_luna。完整结果放在该attempt的published子目录，最后写FINAL_MANIFEST.json/status=COMPLETE；下游只读已完成且hash一致的发布。不要覆盖既有sim/vectors/phase74_published/fft256_published或任何旧产物。case JSON可以紧凑整数组I/Q，必须保留shape与flatten-order说明；不得降精度、补0、插值或重生成任何已发布字段。

## 解码器和允许的执行修复

可复用tools/extract_phase74_published.py的已验证HDF5类型/复数解码作为只读参考，另存tools/extract_frontdata007_v1.py等新读取器。Astra已确认现有NI hdf5.dll读取较大压缩front数据会报deflate filter未注册；小型phase数据能读取不能证明压缩数组也可读。

优先使用本机已经存在且支持该格式的读取器；不得安装全局包、修改全局环境或启动MATLAB。若需用H5Dread_chunk读取原始chunk并用Python标准库zlib解压，必须读取并验证真实filter pipeline/filter-mask、chunk坐标/shape和边缘有效范围；只支持实际识别且可正确还原的过滤器。不得直接跳过过滤器、猜字节序或把读取错误当缺失字段。保存失败尝试与新版本；修改读取器/包装属于执行修复，不能改数据含义和下面数学检查。

所有执行脚本及依赖在执行前记录hash并另存原字节副本。冻结后修复另名v2，不原地覆盖；成功读取的来源/输出校验后复用，补失败字段或报告，不重复已成功原生计算。若现有库仍无法可靠解码，保留具体失败与部分状态交Astra，不擅自借用MATLAB槽或生成伪参考。

## 必须通过的一致性检查

1. 所有浮点存储的码值必须严格等于其整数值，且满足上面位宽；不得靠round掩盖读数错误。
2. 对每个导频，按已冻结算术验证H：实部RNE((Fr*cr-Fi*ci)/2^17)，虚部RNE((Fr*ci+Fi*cr)/2^17)，再夹紧S28。RNE为最近偶数；每个已发布H必须精确相等。
3. 按每窗口820项求和得到front.z，并与estimator.z以及phase74_published的74点逐一一致。原HDF5维度与MATLAB列顺序须明确映射；不把总体总和相等当作逐窗口正确。
4. 统计全部精确系数对集合与各case系数矩阵hash，明确是否相同。不要预先假定8项；若确为8项且矩阵一致，再报告可否无损用3位索引表示，保留原S18系数表。
5. 核对CSV payload_pilot_cells.csv的74符号、每符号820项及实际k顺序；保留CSV源hash。这是索引证据，不替代MAT系数。
6. 三个raw窗口文件长度、段数、全局范围、原字节切片和hash准确；不使用最终补偿文件代替原input_i16.bin。

以上只是对已有整数数据的一致性复核，不重新运行CFO算法性能试验。需报告提取case数、全部字段数、逐点匹配数量、整数范围/系数集合、原始来源和发布清单。

## 资源和交接

本包MATLAB=0、Vivado=0，只允许一个受控Python数据读取过程，不接管T10进程。启动前记录当前余量；按case顺序读取/序列化，避免同时保留19例全部大矩阵。Python私有内存1GiB为预计告警线，输出预计<250MiB；越过估计仅记录，不因小幅越线重做成功读取。严重可用物理<0.25GiB即时或<0.5GiB持续30秒时按本包自己的进程收尾，不能操作T10。

数据读取/校验实际命令、输入hash、资源和300秒运行保护先冻结；预期单次读取/校验<1分钟，读取器适配/归档10–25分钟。若解码器修复需更长，这属于代码准备，不暗中延长已启动进程保护。仅操作本包精确进程；不要因为未使用Vivado而省略实际耗时/峰值与退出状态。

完成保存DATA_PREP_COMPLETION.json与FINAL_MANIFEST.json（包括所有产物hash、decoder/命令、检查结果、无MATLAB/Vivado说明）。仅向原T11 Astra 01a076f1-ad1b-7d33-a29c-4ea34ae84d01去重回传一次，不经总管家中转，不自动启动FFT2048 RTL、综合或其它试验。未完整可靠解码时标明未完成，保留原件。