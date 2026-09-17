# 前端根目录工程入口

新的日常 GUI 入口为 [Sync_Frontend.xpr](../Sync_Frontend.xpr)，核心 top 保持 sync_frontend_top，器件保持 xcvu11p-flgb2104-2-e。由原 vivado/Sync_Frontend/Sync_Frontend.xpr 的磁盘版本复制，仅改变位置和相对路径。

用户已打开的原工程原位保留，本轮没有关闭、保存或替换其 GUI 状态。新入口使用独立的根目录 Sync_Frontend.srcs 副本及独立生成目录；RTL、约束和原工具保持相同源版本。用户在原 GUI 中尚未保存的编辑不包含在新入口中，保存后若需转移应另行比较，不能覆盖。

仿真输入路径改为相对默认 XSim 工作目录（Sync_Frontend.sim/<simset>/behav/xsim）的 ../../../../sim/data。输入文件、测试参数与测试含义不变。本轮未运行仿真。

独立 Wrapper 位于 [wrapper/sync_frontend_clip.vhd](../wrapper/sync_frontend_clip.vhd)；手工输入、预期和端口说明仍在 [原手工交付入口](../handoff/Sync_Frontend_20260915_manual/README_ZH.md)。

[I16 示例](../examples/README_ZH.md)独立管理，与生产同步核心源集完全分离。此前 release、失败记录、XML 历史文件均保留身份；本轮不生成或修补 CLIP XML。
