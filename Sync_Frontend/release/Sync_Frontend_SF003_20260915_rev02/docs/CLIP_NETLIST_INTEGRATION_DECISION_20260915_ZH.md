# NI CLIP 网表与 VHDL wrapper 的交付边界更正
日期：2026-09-15。依据用户本轮纠正及本轮查阅的 NI 官方文档。

结论：当前 SystemVerilog 前端采用原算法顶层核心 DCP + 独立明文 VHDL wrapper + CLIP XML。不要求先在独立 Vivado 工程里综合 wrapper、手工填入核心并再导出一个 wrapper 顶层 DCP。NI Target 编译负责把这些源和平台逻辑关联起来。

## 官方依据与本工程选择
- [NI Creating or Acquiring IP](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/creating-or-acquiring-ip-fpga-module.html)：CLIP 顶层为明文 VHDL；Verilog 先编译成网表，再由 VHDL 实例化。wrapper 也用于把不受 LabVIEW 支持的端口宽度适配成支持的类型。
- [NI Integrating Third-Party IP](https://www.ni.com/docs/en-US/bundle/labview-fpga-module/page/integrating-third-party-ip-fpga-module.html)：Vivado CLIP 列出 DCP 支持；CLIP 与 VI 数据流独立并行执行，IPIN 按 VI 数据流执行。
- [NI How To Utilize Xillinx IP In LabVIEW FPGA](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA0VU000000DK2X0AW&l=en-US)：适用硬件列出 PXIe-7903；可导入已综合 DCP 或 EDIF，包括含外围 HDL 的 SystemVerilog 工程。让 NI 重综合单个 Xilinx IP 时推荐 XCI。工具版本与目标器件应匹配。
- 因本工程是已综合的完整自主流处理层级，选择 DCP + VHDL + XML 是本工程建议，不声称 NI 对所有非 VHDL IP 一律只推荐 DCP。EDF + 完整依赖 + VHDL 也是可用路径；现有 43 个 EDN 必须随 EDF 保留。

## 两个不同的顶层
1. 原算法工程 top=sync_frontend_top，综合得到核心 DCP。保留其核心接口。
2. CLIP top=sync_frontend_clip，文件为独立 sync_frontend_clip.vhd，component 名为 sync_frontend_top。VHDL 只声明/实例化组件，不在文本里嵌入 DCP 二进制。CLIP XML 把 VHDL 与核心网表一起列为依赖，NI 编译工具绑定组件和网表。
3. wrapper 将 128-bit IQ 拆成四个 U32 端口，将 288-bit 结果拆为 U32/U64/U16 字段，并映射时钟、握手和诊断接口。算法及缓存仍在核心中。
4. 最终 NI 编译会综合 wrapper 与 VI/平台逻辑并关联预综合核心；这与“预先把 wrapper 再综合成要交付的核心 DCP”是两件事。
5. 同一核心不同时加入 DCP 与 EDF 两份定义；原独立工程 IO 预算不直接当作 NI 实际边界约束。

## 本轮证据和对前次判断的纠正
- 原综合 DCP：work/SF003_attempt_20260914T211953Z/sync_frontend_synth.dcp，SHA256 EEE1C76628EA07E6D1324FC14D2621F88CEF810E046E6F3D83F4CE0011133D89。
- 同网表 OOC 重导出核心 DCP：work/SF003_DCP_check_20260914T223135Z/clip_dcp/sync_frontend_top.dcp，SHA256 553DEBE94BD9B187F15FB9EE8069ED0258B7976B57FF8E98609588139746CFAD。它来自原 EDF/EDN 的链接，不是重新综合 RTL，也不是 wrapper 顶层 DCP。
- 本轮静态检查两份 DCP 的 dcp.xml，均 Top=sync_frontend_top、Part=xcvu11p-flgb2104-2-e、OutOfContext=1、DisableAutoIOBuffers=1、Vivado 2021.1。静态身份检查不替代原生检查。
- Luna 已报告后一份核心 DCP 原生重开通过、黑盒0、PAD_IO0；资源 DSP206、RAMB36 58、RAMB18 9、FF18119。
- 自建脚本随后综合了只有一个核心黑盒的 VHDL 壳，再手工执行 read_checkpoint -cell。初次使用 implementation 时遇到 Project 1-9 structural-netlist 错误；后续 top/implementation 不存在。该诊断没有生成最终 dcp_wrapper_linked.dcp。
- 此失败只说明这条自建手工链接流程未完成，不构成“NI 不支持这份 DCP”的证据。把它设为核心综合交付的必过门槛，是前次复核范围设置错误，现撤回。
- wrapper 顶层检查网表若产生，也只能作为另一个顶层的验证产物，不能替代承诺的 sync_frontend_top 核心 DCP。仅有未填黑盒的 wrapper 综合壳更不是完整核心网表。
- 原始失败日志、冻结脚本和 Luna 回执保留；原综合/EDF+43EDN/OOC wrapper 已有证据不重跑，BUFG 新增为0不作为门槛。
- 当前：原顶层综合已验收，核心 DCP 与独立 wrapper 已存在；NI 工程的实际导入、Target 整体编译、板测仍未执行。现有 release rev01 是前次静态打包快照，其中 DCP 模板及“待手工回填通过”的旧说明以本文件更正为准，不能把模板单文件当完整导入包。
- 共享 Vivado 槽已归还 T11，本轮无新 native 运行。后续不再追逐 wrapper 顶层 DCP 作为交付物。

当前完整发布：release/Sync_Frontend_SF003_20260915_rev02；唯一 CLIP 导入入口 clip/sync_frontend_clip.xml。rev01 为保留的旧快照，新的三项实现依赖已配齐。NI Target 编译仍未执行。
