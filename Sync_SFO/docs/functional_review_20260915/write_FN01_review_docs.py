from pathlib import Path
import json
M=Path('D:/008_MA_Dev/Sync_SFO');A=M/'docs/functional_review_20260915';R=M/'reports/functional_review/FN01'
c=json.loads((M/'wrapper/interface_contract.json').read_text());c['native_wrapper_compilation']='PASS_FN01_XVHDL_2021_1_2008';c['native_wrapper_compilation_evidence']='../reports/functional_review/FN01/published_native_logs/wrapper_xvhdl.log';c['supersedes_frozen_contract']='interface_contract.json (kept unchanged as an FN01 input snapshot)';c['native_wrapper_binding_scope']='VHDL syntax/library analysis only; no standalone wrapper synthesis, mixed-language/netlist binding, NI target compilation or board test.';(M/'wrapper/interface_contract_FN01.json').write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for rel in ['README_ZH.md','docs/SFO_SYNC_MODULE_GUI_ZH.md']:
 p=M/rel;s=p.read_text();s=s.replace('wrapper/interface_contract.json','wrapper/interface_contract_FN01.json');p.write_text(s,encoding='utf-8')
p=M/'README_ZH.md';s=p.read_text();s+='\n## FN01 原生检查结果\n\n2026-09-15：根 XPR 与私有副本均原生打开，283 个实际成员匹配；74 个核心 RTL、2 个测试文件、3 个 XPM 与 59 个 IP 支持文件组成的 138 项编译输入全部符合冻结哈希。行为源编译、展开快照和独立 Wrapper 的 xvhdl 语法检查通过。原生执行约 16 分 47 秒，未推进仿真时间。43 条警告已分类，详情见 [独立验收](reports/functional_review/FN01/ASTRA_REVIEW_ZH.md)。\n';p.write_text(s,encoding='utf-8')
(A/'REVIEW_STATUS_ZH.md').write_text('''# 当前命名版本的验证状态

2026-09-15。功能命名/排版、工程入口和手工 CLIP 交付复核已完成，FN01 原生内容复核通过；进程结束记录正在补齐归档。

| 项目 | 状态与证据 |
|---|---|
| V5_Final 基线 | dd5e8f7a642625f06c4996d17e3642bbadc7d557；后续源码提交 c4d853a，申请提交 9c4f168 |
| 词法、语法结构和端口 | PASS，79/79；328 个继承端口展开；[完整结果](preview_equivalence_v2.json) |
| 条件编译、宏和注释词法 | PASS，完整 raw token 序列核对；仅忽略排版空白及宏体末尾空白 |
| 活动 XPR / 连接 | PASS，120 直接引用、2108 自有命名端口连接；[活动核查](active_static_checks.json) |
| 厂商支持文件 | 163/163 既有原生支持条目哈希相同；[复核](vendor_support_recheck.json) |
| 原生工程打开 / 实际选源 | PASS，根工程只读打开和私有副本各 283 成员；34 个 IP 及版本/参数来源保持 |
| 行为源编译 / 展开 | PASS，生成 sync_sfo_full_frame_tb_behav；138 实际编译输入均匹配冻结哈希 |
| 独立 VHDL Wrapper | 37 核心 / 102 外围端口静态匹配；Vivado 2021.1 xvhdl --2008 语法分析 PASS |
| 新运行功能对照 / FIFO trace | 未运行；未推进仿真时间，32 个预期 FIFO 路径仅保留映射，未声称运行时覆盖 |
| 核心综合 / 实现时序 | 本轮未运行 |
| 持续吞吐 / NI 全目标编译 / 板测 | 未验证 |

完整结论、警告分类及证据入口见 [Astra FN01 复核](../../reports/functional_review/FN01/ASTRA_REVIEW_ZH.md)。本次只用必要的编译、展开和静态等价证明命名整理，没有重新运行已完成的 case6001 全帧仿真。

第一次候选因 Windows 换行及排版搜索限制失败，未写入活动 RTL。第二版统一 LF，补齐 raw token 检查后通过；三个文件末尾多余 LF 后续单独去除，保存前后哈希及证明。活动检查器对 product 关键字端口和 VHDL 嵌套括号的误判已修正，均保留失败记录；没有算法功能修复。

`interface_contract.json` 和 `current_input_manifest.csv` 保留派单前的 539 项冻结身份；当前用户接口合同为 [interface_contract_FN01.json](../../wrapper/interface_contract_FN01.json)，新增字段只记录已经完成的 Wrapper 语法分析。两个合同的全部端口和拼接映射一致。需要重新静态审计时，reproduce_equivalence.py 接收未存在的 work 子目录名，结果写独立目录，不覆盖正式证明。
''',encoding='utf-8')
(R/'ASTRA_REVIEW_ZH.md').write_text('''# FN01 独立复核：Sync_SFO 功能命名版本

2026-09-15。原生工程打开、行为源编译/展开及独立 Wrapper 语法检查通过；进程结束记录待补充归档后封存最终回执。源码提交 c4d853a1987f66f212fd44fcd8e9a42dd00035d2，资源申请记录9c4f168；基线V5_Final dd5e8f7保留。

## 结论与交付

本轮交付 [根核心工程](../../../Sync_SFO.xpr)、[独立明文 Wrapper](../../../wrapper/sync_sfo_manual_wrapper.vhd)、[时钟/接口与 Host 测试指南](../../../docs/SFO_SYNC_MODULE_GUI_ZH.md)。综合 top 为 sync_sfo_top，器件 xcvu11p-flgb2104-2-e，核心默认输出150 MHz保持。Wrapper不作为综合top，用户手工创建CLIP。

| 检查 | 独立核对结果 |
|---|---|
| 静态等价 | 79/79 文件，328 继承端口展开，运算、位宽、宏、属性、时序结构保持 |
| 原生根/私有工程 | 各283实际成员精确匹配，含74核心RTL、34XCI及既有支持文件 |
| 实际编译顺序 | 138项：74核心、2测试文件、3XPM、59IP支持；全部来自私有目录并匹配冻结哈希 |
| 原模块输入 | 539/539 哈希匹配；原根XPR未改写 |
| 私有输入 | 538/539完全相同；仅私有XPR含工具保存的元数据差异，见下节 |
| 编译/展开 | 原生exit0，完成静态展开与仿真数据流分析，生成 sync_sfo_full_frame_tb_behav 快照；未运行时间 |
| Wrapper | xvhdl --2008 exit0，分析实体sync_sfo_manual_wrapper；37核心/102外围端口的静态合同保持 |
| 错误与警告 | 原生ERROR/CRITICAL WARNING均0，43条WARNING逐项分类 |

原生执行17:54:56.441至18:11:43 CEST，约16分47秒；Wrapper18:12:48.586至18:12:50.409，约1.82秒。general/synth请求8，实际xelab命令为 --mt 16。Luna采样最低可用内存10.079 GiB，xelab观察到的工作集最高约5.43 GiB；这是采样高水位，不能称为完整进程树连续测得峰值。

## 43条警告如何处理

| 类型 | 数量 | 解释及本次判定 |
|---|---:|---|
| IP_Flow 19-2162 | 34 | 根工程以read_only打开，日志逐条说明此原因；canonical_ip_status实际locked=1共34个，私有工程locked=0共34个。不是IP参数失配或需要升级的证据 |
| filemgmt 56-3 / 56-2 | 4 | 根/私有新工程的默认生成目录及ip_user_files尚未存在；实际选源完整、私有编译展开成功，未从外部旧源补选 |
| VRFC 10-3380 | 1 | obfault在声明前引用，基线已有同样顺序；本轮不移声明或改时序 |
| VRFC 10-8426 / 10-2821 | 2 | 原版XPM源码的端口初始化/生成块写法提示，厂商源保持 |
| VRFC 10-5021 | 1 | 首次FFT的m_axis_data_tuser未连接，基线已有相同接口用法 |
| XSIM 43-3980 | 1 | 测试台关联数组敏感性特性提示，保持既有测试内容；本次不外推其运行时trace覆盖 |

此判定只接受本轮编译/展开范围，没有静默修补算法或放宽功能门槛。既有case6001完整帧结果保持历史身份；本次没有新的功能仿真PASS。

## 私有XPR差异与汇总修正

独立结构比较共有40项：工程Path 1项；WTXSimLaunchSim从0变2共1项；20个禁用的AutoIncrementalDir地址由工具重写；18个策略文字Desc被工具省略。全部FileSets、top、part和实际源/IP身份保持，AutoIncrementalCheckpoint仍false。私有相对增量路径可能指回原模块位置，但本次没有运行综合/实现或使用增量检查点；该私有XPR仅作执行证据，不作为用户日常交付入口。

Luna原始汇总中的canonical_locked_ip_count=0应修正为34（只读锁定）；其“仅路径/启动元数据”概述在此补全为上述40项。原汇总和原始日志均保留，不覆盖。证据：[IP原始表](canonical_ip_status.tsv)、[结构差异](astra_private_xpr_structure_diff.json)、[实际编译输入](astra_compile_input_audit.json)。

## 证据与边界

原始[原生日志](native.log)、[阶段时间](stage_status.tsv)、[Luna汇总](FN01_EXECUTION_SUMMARY.json)、[展开日志](published_native_logs/elaborate.log)、[Wrapper语法日志](published_native_logs/wrapper_xvhdl.log)已保存。没有启动XSim运行时间、MATLAB、综合或实现。没有新的DCP、CLIP XML或LabVIEW工程。

32个预期FIFO层级已按名字映射保留，编译/展开接受绑定语法；本轮没有运行时FIFO历史，不声称新的trace覆盖、持续吞吐或板上无丢拍。前端288位记录适配、原始全帧保存回放、NI时钟/CDC、DDR/DMA及平台诊断快照仍由集成方落实。

实现时序、持续吞吐、NI全目标编译与板测分别未验证；独立Wrapper语法通过不等于与网表完成NI绑定。云端目标和完整IP资产发布由总管家处理，本次未push。
''',encoding='utf-8')
print('FN01_CURRENT_DELIVERY_STATUS_WRITTEN; FROZEN_INPUTS_UNCHANGED')
