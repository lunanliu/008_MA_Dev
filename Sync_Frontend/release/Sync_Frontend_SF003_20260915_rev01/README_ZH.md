# 同步前端 SF003 综合交付
状态：综合与EDF/EDN+VHDL独立链接已完成；本目录正在完成DCP直接关联复核，暂未宣布最终发布通过。
本机日期2026-09-15；冻结核心提交2e968f6e33a82a000326be9e6d9c7c97da9342bc，器件xcvu11p-flgb2104-2-e，Vivado2021.1。
用户已明确新增BUFG无需为0；不为此重实现。

clip_edif保存完整EDF、同次43 EDN、VHDL、补齐依赖的XML、端口表和平台边界XDC。
clip_dcp_template仅是DCP包XML模板，等待DCP只读导出/关联完成，不应把该单文件当完整包导入。
checkpoints保留原综合DCP；physical_evidence保存已有route及全部限制，供证据查看，不作为NI直接实例化网表。
独立core_relinked.dcp含非OOC链接产生的物理I/O缓冲，未放入交付核心；完整EDIF+EDN的OOC wrapper没有这些缓冲。
原生报告中的时钟XDC if断言没有执行，新的DCP收尾脚本将在普通Tcl中检查真实继承时钟。不得宣称原有断言已通过。

架构、全部端口、Host DMA输入和结果打包见docs/LABVIEW_TARGET_INTEGRATION_ZH.md。
四个lane是同一复数流的四个连续样点。输入是未同步I16/Q16，每U32高Q低I；Host不发送truth。
input/autonomous_stream.mem为板测输入；reference中的truth仅给Host比较，不进入FPGA。
matlab提供本地历史参考及包装入口，新增MATLAB包装未在本工程原生执行；包内sim/data、reports/reference和reports/provenance保留原相对路径，入口可定位。

实现证据：WNS2.087ns/WHS0.024ns、TNS/THS0，只覆盖已约束路径。133个同步输入漏input delay，另reset_n异步；OOC未验证NI外部路由。5BUFG仅作实际资源记录。DRC20条Warning+158条Advisory（合178），不是178条同等级Warning。
NI整个Target VI编译、板测、持续吞吐及整帧补偿不包含在本地验收内。不要将standalone_io_budget.xdc搬入NI。

计算槽现属T11_T13，本包没有新Vivado运行授权。DCP检查需总管家安排下一空阶段，当前不启动。
