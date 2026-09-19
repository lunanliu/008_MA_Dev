# Vivado 2021.1 XPM 参数类型兼容修复

2026-09-18，Europe/Berlin（CEST，UTC+02）。基线提交8dfcb7b；用户GUI手动启动synth_1，日志记录02:16:46结束。本任务只分析失败、修源码并做静态检查，没有另起综合/仿真。

## 已确认的根因

首错为`[Synth 8-281] expression must be of a packed type`，位置是实际安装版`xpm_memory.sv:8496`。安装文件与项目vendor副本SHA256相同，故不是两个XPM版本混用。9条错误由一个首错、7条模块展开失败和1条综合终止组成；尚未到布局布线阶段，不能据此判断时序或资源超限。

XPM的`MEMORY_PRIMITIVE`是无显式类型参数；其分派表达式把该值同时与整数1/2/3/4、文字常量比较。新增封装`sfo_uram_frame_bank`把它声明成SystemVerilog动态`string`，传入XPM后不能用于该packed整数比较。`sfo_output_buffer`还有同名typed-string上游桥，仅改最下层会让上游string类型继续传播。

这是本轮重构引入的参数边界兼容性遗漏。此前静态绑定使用XPM接口声明，未展开内部选择表达式，所以0解析/绑定错误没有覆盖此问题。原生展开失败证据保留，不改称静态检查或综合通过。

## 两种方案与选择

- 方案A：两个自有封装都去掉显式`string`，由`"ultra"`/`"block"`文字推导packed参数，保持与安装XPM相同的传参形式。保留现有接口、实例和参数取值，选择此方案。
- 方案B：保留上层string，在XPM边界明确映射成packed[39:0]文字，或按generate分别实例化literal-ultra/literal-block；必须明确拒绝不支持值，不能默默映射错误配置。可行但分支/重复实例更多，对当前两个同长度选项没有必要。

实际改动仅为两个参数声明去掉`string`并加兼容性注释。默认和直接调用仍是ultra；production output buffer仍通过SHARED_RAW_INPUT选择block。raw393216×128、SFO/CFO各335872×128、output ring65536×128均不变；common_clock、read_first、READ_LATENCY_B=2、使能、复位、容量、吞吐及数值路径均不变。每帧周期/缓存预算无需重新计算。

其他PS1_MEMORY_INIT_FILE的string参数传给文件名接口，实际XPM该路径不做这种string与整数的混合比较；本次未无差别修改这些参数。厂商源码和用户GUI保存的XPR均保持原样。

## 修复后证据与下一操作

- `reports/v51/gui_synth_xpm_fix_20260918/failed_synth_runme.txt`：原始失败日志按字节保存。
- `fix_identity.json`和两个`.before.sv`：实际失败与修复身份。
- `syntax.json`：受影响2文件语法0错误、0警告。
- `static_binding/summary.json`：129生产源静态绑定0错误、958诊断保留；XPM仍只检查接口，不能据此宣称原生错误已验证消除。
- 独立审查：`reports/v51/review/xpm_parameter_compatibility_review.md`。

本地修复已经就位，原生综合重跑尚未执行。用户可在Design Runs对失败的`synth_1`执行Reset Run，再Run Synthesis；若Vivado已自动标为过期，按提示重新运行当前源码。失败日志已在reports另存，重跑不会丢失本次根因证据。无须改变三个时钟约束或编辑安装版XPM。重跑成功后才可更新原生综合状态，不能承诺后续阶段一定无其他问题。
