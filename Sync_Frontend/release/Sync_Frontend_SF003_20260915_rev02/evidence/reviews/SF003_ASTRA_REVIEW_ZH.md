# SF003 Astra复核：核心综合交付与 NI 集成边界
日期：2026-09-15；依据用户最新要求收束综合结果，不要求新增BUFG为0，不为BUFG/IO预算重实现。
核心冻结提交：2e968f6e33a82a000326be9e6d9c7c97da9342bc。
Luna completion SHA256：3CE37ADCEDA47DB7499C80A4875DB4ED24C8E2507A7865C9AB38CA17AA04D83B。

## 已接受
- 78项冻结文件逐项SHA一致，46条完成记录中的产物哈希和字节数一致。
- 正确xcvu11p-flgb2104-2-e；实际sources_1与34-SV清单一致，15个IP完成OOC综合，顶层黑盒0。
- SF002的DUT不变；四帧精TO零误差、CFO最大23Hz等限定行为证据继续有效。
- 综合DCP及同次EDF/43EDN完成；ROM非零INIT字段208。
- EDF+43个同次EDN的独立核心和OOC VHDL wrapper链接均零黑盒，实际端口/方向/宽度一致。所有43个EDN从源到package SHA相等。
- 原综合层级报告LUT18770是层级统计口径；重新链接的平面器件利用率为CLB LUT18235、FF18119、RAMB36 58、RAMB18 9、DSP206、URAM0。两者不同LUT计数口径不得直接当逻辑丢失；寄存器/BRAM/DSP一致。OOC wrapper原语表无IBUF/OBUF。
- 原route已完成，40722条routable nets全部路由、routing errors0；WNS2.087ns、TNS0、WHS0.024ns、THS0。这些值仅覆盖当前已约束路径。

## 发布修复与限制
1. 原package的XML仅3个Path，漏列43EDN；Luna原生脚本手动加载了43个，所以“原生链接通过”不等于“XML依赖完整”。release/Sync_Frontend_SF003_20260915_rev01/clip_edif已静态补齐为46个Path，全部相对依赖存在。原package保留不改。
2. 最终retry1_workspace/vivado.log的3条Designutils20-1307说明XDC里的if不受支持，时钟继承断言没有执行。core/wrapper时钟报告确有125MHz，但completion的“完整继承断言PASS”不能照搬。新发布XDC仅声明NI所有权和边界说明；真正断言移到普通Tcl短检查。
3. core_relinked.dcp来自link_design默认非OOC，含582 OBUF、135 IBUFCTRL，不作为NI内部核心DCP交付。原综合DCP仍保留；OOC wrapper_linked.dcp没有这些I/O缓冲。现已从同次 EDF/EDN 完成 OOC 核心 DCP 导出与原生重开，黑盒0、PAD_IO0。后续自建 wrapper 手工回填诊断未完成；按用户纠正和 NI 文档，它不是标准 CLIP 交付必需步骤，不再作为核心综合交付门槛。
4. 原输入约束错误造成134个no_input_delay（133个同步输入+异步reset_n），OOC也无NI边界HD.PARTPIN_LOCS。因此不验收完整同步IO/NI平台时序。5BUFG为已实现结果实际资源，按用户要求不作为零门禁。
5. DRC实际为20条Warning（DPOP-3 8、DPOP-4 11、RTSTAT-10 1）及158条Advisory（AVAL-155 150、AVAL-156 8），合178；原completion笼统写178 warning不准确，本复核更正且原记录不改。
6. NI整个Target VI编译、板测、持续吞吐、新MATLAB包装入口原生运行均未完成，不继承为PASS。

## DCP 收尾与本轮更正
原顶层 DCP 与同网表重导出 DCP 均为 sync_frontend_top / OOC / xcvu11p-flgb2104-2-e。新核心 SHA256 553DEBE94BD9B187F15FB9EE8069ED0258B7976B57FF8E98609588139746CFAD，独立原生重开通过。
初次 read_checkpoint -cell implementation 发生 Project 1-9；retry1 实际在 full-name 解析处退出，Luna 汇总把初次失败列到 retry1，原始回执保留。本轮据实际日志区分。top/implementation 不存在，不能继续猜层级。
自建 wrapper 诊断未完成不等于 NI 导入失败；NI 实际导入/Target 编译尚未执行。撤回 DCP_RELEASE_CHECK_PENDING_SLOT 作为综合交付门槛。
正式结构采用核心 DCP + 独立 VHDL wrapper + XML，NI 编译负责关联；不把 wrapper 顶层 DCP 作为核心交付物。详见 docs/CLIP_NETLIST_INTEGRATION_DECISION_20260915_ZH.md。
共享计算槽已归还 T11，不复用旧 grant，不启动 native。
当前状态：SYNTHESIS_ACCEPTED / CORE_DCP_REOPEN_ACCEPTED / EDIF_WRAPPER_LINK_ACCEPTED / CUSTOM_WRAPPER_DIAGNOSTIC_INCOMPLETE_NOT_A_RELEASE_GATE / NI_TARGET_COMPILE_NOT_RUN。
