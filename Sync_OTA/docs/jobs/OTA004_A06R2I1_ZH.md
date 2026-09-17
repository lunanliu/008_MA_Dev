# OTA004 A06R2I1：独立只读DCP身份诊断申请

状态：AWAITING_SEPARATE_USER_AUTHORIZATION_AND_MANAGER_RESOURCE_GRANT。2026-09-17用户本轮仅授权接收回执、静态审查及提交方案；本文件和冻结完成均不授予启动权限。原A06R2作业不得自动重跑，旧grant不可用于本诊断。

## 唯一目的和输入

仅确定run_ota004_a06r2.tcl:16中current_design.NAME与current_design.PART的真实返回值、对象语义及原比较结果。原入口不改，不接受替代身份，不进行报告恢复。

固定DCP：D:/008_MA_Dev/Sync_OTA/work/OTA004/synth_a06r1/sync_ota_synth.dcp；187800130 bytes；SHA256 AC2E40A1B04CEE538F76BC5028CC8E2C3836459742D260488E231D6DD436F33E。
原预期NAME=sync_ota_top（来自RTL顶层合同和A06R1 sources_1.TOP/-top，尚未证明是design.NAME）；原预期PART=xcvu11p-flgb2104-2-e（来自器件合同、A06R1 current_project.PART/-part）。都保持原字面值，不跟随观测值更改。

## 诊断步骤与原门槛

1. 核对新锁定清单及原339项输入、工具身份；记录独立预检。新attempt必须为空；启动日志及准入记录置于attempt外。
2. Vivado2021.1实际进程general/synth8/8，仅一次open_checkpoint固定DCP，无-part/-ignore_timing等覆盖，无open_project。
3. 保存current_design的返回对象。分别调用get_property NAME与PART，两个查询独立catch，不用原OR短路阻止第二项取证。
4. 在任何身份通过/失败判定前保存：对象、查询状态、原始实际值、原预期值、每项完全相等比较结果。identity_observation.tsv采用UTF-8十六进制保留对象/值原字节，native.log同时打印Tcl列表可读值；写后flush。
5. 只读列出design属性名，并读取存在的CLASS、TOP相关、REF_NAME、DESIGN_MODE属性作为辅助证据。该上下文不替代原NAME/PART判定；不存在属性不猜值。
6. 仍用原两个ne条件及OR表达式判断；任一不等仍记录wrong existing DCP design identity并exit1。属性查询失败也exit1。观测完成与身份检查通过分开，EXPECTED mismatch不当作PASS。
7. 关闭design，原样记录close状态，再离线核对输入哈希；监管器核实整个PID+creation树归零。只读完成后结束，不继续黑盒、CDC/Gray/时序报告，不调用旧R2后半段。

只有取得证据后，Astra才决定另存新报告脚本或追查上游DCP选择；不得因诊断exit0自动启动后续作业。

## 冻结文件与命令

- tools/vivado/run_ota004_a06r2i1.tcl：独立身份入口。
- tools/vivado/audit_ota004_a06r2i1_identity.tcl：两属性独立记录与原条件重放。
- tools/verify_ota004_a06r2i1_inputs.py：前后只读输入核验。
- tools/monitor_ota004_a06r2i1.ps1：仅identity、精确新Source与新目录、上限600秒；$nativeNames之后运行监管段与已审A06R2相同。
- docs/jobs/OTA004_A06R2I1_source_lock.json：独立清单；哈希见对应DISPATCH记录。

待用户单独批准、总管家给新grant和绝对截止后，唯一原Luna执行以下模板；占位符不得直接启动：

```powershell
& 'C:/Users/lunan/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File 'D:/008_MA_Dev/Sync_OTA/tools/monitor_ota004_a06r2i1.ps1' -Stage identity -Attempt 'D:/008_MA_Dev/Sync_OTA/work/OTA004/identity_a06r2i1' -Source 'D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota004_a06r2i1.tcl' -AbsoluteDeadlineUtc '<NEW_GRANT_ABSOLUTE_DEADLINE>' -HardSeconds 600
```

只开一次，不自动重试。准备空目录后再启动；监管器拒绝非空旧目录、错误stage/source、路径穿越、哈希不匹配和超限时间。新grant建议首次启动窗口10分钟+native最多10分钟，整体固定20分钟含等待；具体绝对时间由总管家在单独批准后填写。不得继承或延长旧预算。

## 资源与取消

单Vivado/0MATLAB，预计4—6分钟，原生硬上限10分钟且受新绝对截止约束，general/synth8/8，build/IP jobs0。原DCP打开175秒、全阶段203秒、Vivado日志峰值7628.020MB，申请报告进程约8—10GiB作告警；物理内存小幅不足结合提交余量继续，不关用户应用、不改分页。

运行段保留累计PID+creation、进程树内存/提交/分页/日志进展监控；根退出后继续跟踪后代，末3采样空才收尾。硬截止、取消按冻结监管仅处理所属身份，禁止按名字批量kill。明确分配失败、持续严重系统压力或确证停滞才按规则干预。已有用户GUI保持。

## 明确不在本次授权内

不重综合、不重IP、不仿真、不implementation、不恢复9查询或Gray/CDC报告、不改RTL/接口/数学/125-150-500MHz、不写DCP/EDIF、不改名/改part、不删除或放宽原身份门槛。报告格式问题只离线修复，不能重新开DCP。

## 交回资料与接收范围

identity_observation.tsv、原native.log/jou、runtime_identity、identity_precheck/postcheck、close_status、失败信息（若有）及完整process_summary/tree。必须分别说明：观测是否完整、原两项比较结果、原guard是否仍HOLD、原DCP/冻结输入是否不变、全树是否关闭。取证完成不等于报告恢复或工程身份/时序验收。

离线验证包括8项Tcl模拟对象/语法/只读边界检查、13项monitor预检。只验证记录先于判定、两项查询独立、原门槛保持和参数保护；不证明Vivado实际NAME/PART或原生API执行通过。
