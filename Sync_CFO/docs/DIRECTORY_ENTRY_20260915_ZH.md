# Sync_CFO 工程入口与目录迁移

原 T11_CFO 已整体归入 Sync_CFO；文件内容和历史证据保留。此模块尚无已交付的完整 CFO 整链顶层，因此不创建名为 Sync_CFO.xpr 的假整链。请从模块 README 的九个真实阶段工程选择所需范围，不能将阶段通过写成 T11～T13 整链通过。

`rtl/`、`ip/`、`constraints/`、`sim/`、`matlab/`、`docs/`、`tools/`、`vivado/` 保持原内部结构。`work/` 和 `reports/` 保留每次尝试的身份。`archive/pre_reorganization_T11_CFO/` 保存切换前原件。

CFO_LINK010R1 原 XPR 显式引用的三个 Vivado 2021.1 XPM 文件，原样复制到 `rtl/vendor/vivado_2021_1_xpm/`，仅调整 XPR 文件路径；库名、编译标志、RTL、测试台、IP 参数保持不变。其余阶段 XPR 只更新工程自身位置。

冻结审查包、source lock、历史 Tcl/runner 和报告内的旧绝对路径保留原文；它们用于追溯，不能直接作为搬迁后的启动许可或复现实验入口。下一次获准运行前，原任务应依据本轮路径映射另行冻结派单，不能自行更新旧锁来掩盖差异。此前审批受阻的交接与实验不借本轮恢复或转发。

完整 CFO 核心、与其匹配的独立 VHDL Wrapper、最终 Host 接口尚未交付。这里只提供已有阶段的输入与预期数据导航，没有添加占位 RTL 或临时连接。
