# 同步前端 SF003 rev02：核心 DCP 与独立 VHDL CLIP 交付
唯一导入入口：**clip/sync_frontend_clip.xml**。选择该 CLIP 声明并保留整个 clip 目录，由 LabVIEW FPGA 的 Target 编译关联核心与 VHDL wrapper。
状态：核心综合已接受；交付 DCP 独立原生重开通过；本包静态依赖/端口/哈希核对见 STATIC_VALIDATION.json。NI 实际导入、Target整体编译、真实接口时序、板测及持续吞吐尚未验收。

## 导入文件
- clip/sync_frontend_top.dcp：原算法顶层 sync_frontend_top 的完整核心；正确 xcvu11p-flgb2104-2-e，Vivado2021.1，OOC，独立重开黑盒0、器件PAD I/O0。
- clip/sync_frontend_clip.vhd：独立明文纯连线 wrapper，CLIP 顶层 sync_frontend_clip，内部实例名 implementation，组件名 sync_frontend_top。
- clip/sync_frontend_clip.xml：端口与三项实现依赖；已经配齐实际文件，不是待填写模板。
- clip/sync_frontend_clip.xdc：说明 NI 时钟/边界所有权，不附加独立工程 IO 预算。ports.json 给出32个外部端口。
无需预先综合 wrapper 或手工回填后再交另一个 wrapper 顶层 DCP。核心网表绑定由 NI 完整编译完成。

## 核心来源
本包 DCP 采用原成功综合 EDF+43EDN 的 OOC 重导出文件，保持 top=sync_frontend_top，没有重综合 RTL/IP、没有包含 VHDL wrapper。其 SHA256 为553DEBE94BD9B187F15FB9EE8069ED0258B7976B57FF8E98609588139746CFAD。
原综合 DCP 含独立工程时钟/输出延迟预算，作为 evidence/original_synthesis 原样保留；不把它和当前 DCP 同时加入 CLIP。生成链与哈希见 CORE_DCP_PROVENANCE.json。
VHDL仅修订一条说明注释，端口及所有连接保持原样。XML资源声明依据当前综合核心；BUFG新增为0不是验收要求，历史独立实现有5个BUFG。
rev01及失败原始证据保留；当前版本替代其不完整DCP模板和“等待手工回填通过”的发布说明。

## Target VI 与 Host
完整架构、RTL层级、32端口接线、DMA格式和预期结果：docs/LABVIEW_TARGET_INTEGRATION_ZH.md。
125MHz单域，同一复数流四个连续时间样点/拍。Host-to-Target建议U32 FIFO，Q16高半字/I16低半字，每次四点组成输入beat，valid/ready握手。
Host发送未同步原始IQ，不发送frame_start、frame_id、true TO/CFO或truth。参考ROM已在核心里。
输入input/autonomous_stream.mem共15081行128bit；每行右侧U32为最早样点data0。共60324点。为对照已有仿真，FPGA每256个已接受beat暂停8000拍，结果每条背压128拍。
结果由VI原子保存后打包成建议的9个U32，通过Target-to-Host FIFO回Host；当前CLIP本身没有DMA端口，也没有整帧输出。
Host核对四个fine_absolute为15004、26373、37842、49311，CFO结果为-150022、0、150022、-149977Hz，并监视计数、drop、error_sticky和DMA溢出/超时。
首次reset后不额外start时参考epoch=0。具体控制脉冲/背压与清队列要求见接线指南。

## 比较与证据
tools/compare_readback.py <读回CSV路径> 是Host比较入口；CSV格式见reports/reference/autonomous_results.csv。无参数时只比较包内历史RTL结果，不是新板测。
matlab/waveform/load_frontend_waveform.m、matlab/golden/frontend_reference_catalog.m和matlab/comparison/compare_frontend_readback.m为MATLAB入口；历史参考与新增包装运行状态分开，新增包装未在本工程原生运行。
SHA256SUMS.csv覆盖本包除清单本身之外的全部文件。可运行tools/verify_release.py核对静态内容，不调用Vivado或MATLAB。
evidence保存原始通过/失败和历史独立实现边界；不把这些文件额外加入CLIP。
