# 当前命名版本的验证状态

2026-09-15。功能命名/排版、工程入口和手工 CLIP 交付复核已完成，FN01 原生内容与进程结束复核均通过，最终证据已归档。

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
