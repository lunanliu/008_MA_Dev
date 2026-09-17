# OTA004 A06R2 身份阻塞静态审查

2026-09-17；仅静态接收和诊断方案准备，未运行Vivado/MATLAB。用户要求先审查，后续只读身份诊断单独授权。

## 结论

A06R2第16行确实把Vivado design对象的NAME直接当成RTL顶层模块名。该等同关系没有从A06R1的原生对象属性取证，不能用于证明RTL顶层身份。AMD2021.1文档明确区分design的参考名称与设计顶层。此处是已确认的语义假设问题；但现有日志不含实际NAME/PART，尚不能将本次失败最终归因于某一个具体值，不能猜测实际NAME是netlist、Design或其他名称。

保留原检查和所有现场。未修改预期值、替换DCP或重新综合。建议只执行一次单独批准的A06R2I1取证，取得实际属性后再决定新版本报告入口怎样修正，或追查DCP选择。

## 第16行的完整逻辑

```tcl
if {[get_property NAME [current_design]] ne "sync_ota_top" || [get_property PART [current_design]] ne "xcvu11p-flgb2104-2-e"} {error "wrong existing DCP design identity"}
```

| 项目 | 实际查询对象 | 硬编码预期值 | 预期来源与缺口 |
|---|---|---|---|
| NAME | 无参current_design返回的当前design对象 | sync_ota_top | 这是PROJECT_SPEC_ZH.md:7与A06R1源集TOP/综合-top的RTL模块名；没有已记录的design.NAME属性证明两者相等 |
| PART | 同上，若执行到右操作数 | xcvu11p-flgb2104-2-e | 固定器件合同；A06R1从current_project读取PART，综合命令也使用此part；R2改成从design读取，未记录返回值 |

左、右任一不等即抛同一错误；只有两者都完全相等才继续黑盒、CDC、时序、Gray检查。Tcl带花括号表达式中的逻辑OR会短路：NAME不等时，右侧get_property PART可完全不执行。离线Tcl9.0.4用原第16行与模拟查询验证了这一语言行为；这不是Vivado实际属性测试。

第15行open_checkpoint成功后才进入此判定。原入口不使用-part覆盖或-ignore_timing，不设置design名称。failure.txt说明执行到了显式error，并不包含两项实际属性。黑盒检查及report_identity等输出尚未到达；打印在日志里的脚本源代码不是已执行成功的证明。

## A06R1生成链与本次输入一致性

1. tools/vivado/run_ota004_a06r1.tcl:27分别检查current_project.PART和sources_1.TOP；第141行设TOP=sync_ota_top，第160行输出真实工程身份。
2. docs/provenance/OTA004_A06R2_core_runme.log:17记录真实命令：synth_design -top sync_ota_top -part xcvu11p-flgb2104-2-e -flatten_hierarchy none -mode out_of_context。
3. A06R1入口第208行open_run synth_1；第209—213行检查黑盒及指定真实层级；第214行write_checkpoint到work/OTA004/synth_a06r1/sync_ota_synth.dcp。
4. work/OTA004/synth_a06r1/native.log:8624明确记录该路径的checkpoint已生成。随后导出的EDIF和报告不能替代design.NAME读取。A06R1第228行身份字符串位于Gray失败之后，不能当作该行已成功执行的证据。
5. 原DCP 187800130字节，SHA256 AC2E40A1B04CEE538F76BC5028CC8E2C3836459742D260488E231D6DD436F33E。本次离线实算仍匹配冻结清单与回执。
6. 仅用Python zipfile读取DCP内dcp.xml，元数据Top=sync_ota_top、Part=xcvu11p-flgb2104-2-e、Vivado2021.1/build3247384、OutOfContext=1；原字节另存A06R2_DCP_METADATA_STATIC_20260917.xml。它支持文件内容身份，不能冒充open_checkpoint后get_property NAME/PART的返回值。
7. A06R2 native.log的Loading part行为与此器件一致，open_checkpoint完成约175秒；整个执行约203秒。它降低误选器件的疑点，但仍不是实际PART属性取证。

因此，现有证据支持“打开了锁定的A06R1 DCP”，未发现路径或文件替换。design.NAME/RTL TOP混用是首要待实证原因；仍保持身份验收NOT_PROVEN。

## 接收和现场保留

回执SHA256 D629551EABA08BA0A39BB9D0D46BF4B3281E915FB7B2E9AD85725399CF0CD7B4。回执关联15项文件哈希、本轮339项冻结输入与5项工具哈希匹配。进程树132条记录、3个PID+creation身份与summary集合完全一致；末3采样全空，exit1、未超时。详见同名JSON。

旧A06R2 source lock、Tcl、monitor、DCP/EDIF以及整个失败目录均保留。此静态审查不恢复报告、不放行Gray/CDC、不改变时序结论。也不使用旧grant的剩余时间启动诊断。

## 独立诊断与后续分支

可审查方案为 docs/jobs/OTA004_A06R2I1_ZH.md；仅新增identity-only脚本。先分别记录查询对象、实际NAME/PART、原预期值、查询状态与各自相等结果，再保留原完全相等条件，错误时仍返回失败。另记录design可用属性名和存在的CLASS/TOP/REF_NAME/DESIGN_MODE等只读上下文，不将其作替代通过条件。

- NAME不等、PART相等，且DCP内容/顶层证据保持一致：据实际对象语义设计新版本顶层身份检查；不得简单删除NAME检查或把预期随意改成观测名称，不自动继续报告。
- PART不等、属性不存在/查询失败、对象不是预期design，或元数据/哈希冲突：保留HOLD，追查属性对象、DCP来源和选择；不改part、改文件名或重综合掩盖问题。
- 两项都相等却旧现场失败：比较进程、脚本、DCP哈希及上下文差异，不宣称旧失败消失或直接重跑。

## 官方依据

- [Vivado2021.1 current_design](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/current_design?contentId=n4Jg9DzLBUpDQ4Sd5pXvgQ)：返回当前design对象。
- [Vivado2021.1 open_run](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/open_run)：-name是打开后的design参考名称，与顶层及内部逻辑无关。
- [Vivado2021.1 open_checkpoint](https://docs.amd.com/r/2021.1-English/ug835-vivado-tcl-commands/open_checkpoint?contentId=bOYAgfzhN~7TPpEAdSvmqQ)：新建内存工程并初始化design；不从DCP文件名推定design.NAME。
