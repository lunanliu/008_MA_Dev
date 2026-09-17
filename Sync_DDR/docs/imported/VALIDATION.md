# 验证状态

2026-09-16，本轮新纯VHDL写/读控制器；不继承算法前端或旧DDR VI的编译结论。

| 项目 | 当前状态 |
|---|---|
| 源码与接口独立静态复核 | 已完成；写侧和读侧控制、NI一拍许可、同沿数组语义、命令/排空、计数定义已交叉检查 |
| 两份VHDL测试台 | 已编写并静态核对；存在测试台不等于测试通过 |
| 原生xvhdl/展开/XSim | NOT_RUN；等待项目资源流程准入 |
| 独立Vivado .xpr | 尚未由create_project.tcl生成；提供的是可复现创建入口 |
| MATLAB脚本 | 已静态复核；未启动MATLAB，未声称实际执行通过 |
| NI CLIP导入/新VI编译 | 用户尚未执行，未验证 |
| 150/125MHz实现时序 | 未验证 |
| DDR板上逐点完整性、重复任务、持续500MS/s | 未验证 |

## 原生验证必须满足的条件

- 使用manifest.json锁定的2个RTL、2个TB和脚本。工程实际导出源集与manifest逐项核对。
- 原生编译、展开无错误；write/read分别独立运行，输出目录隔离。
- write日志含唯一DDR_UPLOAD_CTRL_TEST_PASS，read日志含唯一DDR_READ_CTRL_TEST_PASS。
- 两个日志均无assertion failure、Fatal或ERROR，且进程正常结束、未触发watchdog。脚本FINISHED或exit 0单独不是PASS。
- 测试仅验证VHDL和NI握手模型；不验证真实NI DDR控制器或板端服务间隙。

任何执行修复保留原文件和失败日志，新版本另存；不为脚本问题覆盖已经冻结的源文件。