# SF002 Astra复核

结论：PASS_AUTONOMOUS_SHORT_JOINT_ONLY，源码6755a6e176d133f7259381c4d6067bca7212dbaf。

原生simulate.log四组必需标记齐全，正常finish于5042168ns；结果CSV逐条复读并由独立Python读回比较通过。60324样点/15081输入beat/14570度量，4真帧全部确认，四lane位置与真值精确相同，CFO最大误差23Hz。内部确认编号0..3，候选id2/6/9/12。

候选计数13=4确认+1算法拒绝+4drop+4去重；slot峰值2，最老读历史年龄4336点，加复制预算3200=7536<8192。原测试只给drop总数，不能虚构逐次drop分类；可确认本测试四个真帧未漏检、无多余有效输出，不能外推其它候选速率。模型输入每256beat暂停8000时钟，completion里gap_beats字段单位标错，保留原件并在本复核更正。

唯一vendor reset warning位于20ns初始复位时，主输入未开始，后续无同类警告。日志保留；不据此宣称板级reset验证完成。原始端口没有外部frame_id/frame_start/真实sample_index输入，truth只接被动checker。SF002通过不覆盖综合/实现、持续吞吐、CLIP/NI/板测。

下一步准入SF003：同一34-SV产品top进行FLGB独立OOC综合/125MHz布局布线，成功后完整EDIF+VHDL+XML+XDC导出并在干净目录重读。原行为仿真不重复。
