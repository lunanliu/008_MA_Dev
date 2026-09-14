# BACKEND006 编译失败复核与最小修复

create已成功，实际21项工程成员与41文件源锁一致。simulate在RTL编译阶段exit1，首错为cfo_fft74_quality.sv第74行VRFC 10-292；未进入XSim、没有backend74_actual.txt，不能声称后端数值通过。

根因是同一条wire声明混合了带赋值的div_s_valid与不带赋值的div_s_ready/div_m_valid/div_error。Astra另存cfo_fft74_quality_v2.sv，仅将该行拆成两条wire声明，保持各信号驱动与其余全文一致。没有改运算、位宽、常数、TB、向量和验收。

创建13.127秒、失败编译15.210秒；完整Job收尾两查询为空，实际执行包装与冻结hash一致。旧RTL、源锁、失败原始日志及项目XPR均保留。下一包只在现有CFO_BACKEND74工程换入v2后重试编译和从未开始的原定仿真，不重建、不重复旧单元。
