# LINK010R1 复位契约修订

本次只修复 LINK010 跨时钟链接层的复位。原 LINK010 数值/协议通过，但 FIFO.rst 接法不符合官方同步要求，原结果保留为 NUMERIC_PROTOCOL_PASS_RESET_CONTRACT_BLOCKED。R1 待新原生验证，不能继承原仿真为 R1 PASS。

## RTL与数据边界

硬件top仍为cfo_estimator_link，新增文件rtl/cfo_estimator_link_v2.sv。端口、171位FIFO记录、530位结果、所有错误码、74点估计和模式选择不变。原LINK010_CONTRACT_V1_ZH.md的输入、逐位数值、计时、背压、丢弃和退休门限全部沿用；其复位接法段落由本节替代。计数<=18仅是原验证的保守上界，不把它当物理RAM容量证明。

reset_async或abort_async仍异步立即停止s_ready、FIFO读写及m_valid。FIFO专用fifo_reset经4级clk_fast同步置位和释放，INIT=1；原各域4级异步置位/同步释放器保留。快域须先观察fifo_reset与wr_busy共同为1，再等待两者为0；完成标志同步到慢域，慢域确认rd_busy已低后返回ready确认，快域收到确认才开放下一帧。扩展busy期间清理后端、帧状态及credit，封锁XPM双阶段复位中rd_busy短暂变低的间隙。

连续时钟为前提，输入reset脉冲须满足实际器件最小宽度并被同步宏捕获；不声称任意窄脉冲或复位未结束时重新发起的脉冲均有效。本次不扩大reset刺激矩阵，也不将其作为任意时刻密集取消或物理CDC资格证明。

## 私有仿真模型与选源

官方Vivado2021.1 XPM_FIFO_ASYNC说明rst须同步wr_clk：[UG974](https://docs.amd.com/r/2021.1-English/ug974-vivado-ultrascale-libraries/XPM_FIFO_ASYNC)。三份官方HDL列为显式仅综合依赖。sim/vendor/link010r1中的CDC与MEMORY副本字节完全一致；FIFO仅在synthesis translate_off内修两处断言：EMPTY_CHECK S-4检查下一周期empty确为1，允许它此前已为1；sleep检查仅在WAKEUP_TIME>0时实例化，避免本设计sleep=0、WAKEUP_TIME=0的零长度序列。所有其它检查保留，无全局DISABLE_XPM_ASSERTIONS，无错误白名单，不改安装目录。精确diff及verify_link010r1_models.py证明仅这两处修正、可综合内容逐字节相同。

新工程CFO_LINK010R1所有实际仿真SV使用私有cfo_xpm库。XPM_LIBRARIES为空不能保证Vivado不自动加入-L xpm，因此编译展开后、run all前必须核对：实际编译仅使用三份私有XPM源；-L cfo_xpm先于任何-L xpm；所用XPM模块均展开为cfo_xpm.xpm_*，没有xpm.*；本地库目录存在。工程导出包含LIBRARY和USED_IN属性，离线校验重复核对上述门。该路径仍待真实Vivado验证。

## 验证与验收

沿用原四个正常向量、22完整帧、10协议错误、8次丢弃、32次真实结果握手、W2056及逐前缀R核对；不重新计算MATLAB、前端FFT或期望CFO。原首帧15448快周期输入节奏、21次突发FIFO满/背压、全部530位结果、最后输入到输出<=7800慢周期、首输入到输出<=1170000或45000快周期门限不变。新增独立reset audit记录真实两域复位/忙/empty/恢复握手和FIFO读写，必须验证9次恢复、运行中FIFO复位同步边沿以及异步停流。

exit0、数值PASS、静态身份一致均不足以单独通过R1。须数字trace、reset audit、无原生ERROR/FATAL、私有源/绑定、完整Job归零、冻结源与原八工程字节不变、外部进程保护共同通过。仍不覆盖整帧两次旋转、全CFO链、综合、布局布线或500MS/s持续服务资格。
