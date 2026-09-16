# 当前实现进度 A03

OTA001已独立限定验收：store PASS；descriptor PASS_WITH_TB_WARNING；具体槽已归还，成功计算不重跑。报告见reports/OTA001/ASTRA_REVIEW_ZH.md与LUNA_EXECUTION_RECEIPT_A01_ZH.md。

新增ota_cfo_chain包含真实坐标控制、两次独立cfo_rotate4（各自RNE/S16饱和）、一份NI外存区域的事务管理、74个2048点窗口串行调度、真实FFT2048/820导频求和/跨域/相位OLS及FFT256质量后端、残余配置与最终整帧回读通路。没有将粗旋转和最终旋转合并，没有用参考答案代替估计器。新ota_async_fifo采用写时钟同步XPM reset与双域复位完成握手。

两级SFO的正式context端口现已贯穿resampler→sfo_two_pass_transport→sync_sfo_top；REQUIRE_CONTEXT_ACK=1时成功配置与实际engine启动及上下文接收绑定。ota_sfo_context_join按同一frame/generation组合两级实际step和帧元数据。最终OTA顶层尚未创建，生产实例必须显式启用该参数；此处不宣布SFO→CFO整链已运行。

完成静态语法检查：新增CFO/FIFO/join、四份SFO发布/绑定修改及三个OTA002 TB。发现并修复join中误用SV关键字first_match；未启动额外Vivado探针。OTA002准备三个独立短阶段：实际descriptor/CDC、4×74已发布观测的真实后端、新完整CFO树展开及粗旋转/取消控制冒烟。详见docs/jobs/OTA002_ZH.md。

后续依次：OTA002复核→完整主调度/外存桥/前端与SFO连接→完整核心IP/XPR/约束/端口→必要2～4符号实际IQ分段与顶层检查→真实核心综合、资源及DCP→独立明文VHDL、输入/预期与Host/Target指南。全帧行为、持续吞吐和真实板测不伪称已验证。
