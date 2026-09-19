# 四段控制器设计自审

唯一负责人自审，无第二任务或外部独立复核。先行设计在RTL创建前落盘，pre-change保存104个已有文件身份。原两核与两TB不变，端口映射静态审计见FOUR_STAGE_STATIC_AUDIT.json。

1. 结构：capture的33个端口逐一映射upload，download的46个端口映射read，read其余11个检查器端口按禁用功能固定或open。所有内核端口恰好绑定一次；无新状态机/存储/ready寄存，也无多驱动或跨域逻辑进入RTL。
2. 参数：沿用命令快照、U32 N/M/C、64位乘积检查。N_out已知且四点对齐，N_in不能替代N_out。1280bit默认才能提供默认545.45MSample/s理想写服务；参数化位宽不意味着所有宽度均达到该速率。
3. 状态：capture继承config、loading、done、fault及优先级；download继承config、prefetch、prime、stream、drain、done、fault。取消和DDR失效不受普通暂停阻挡，重启需外部安全许可。新命令不能覆盖忙会话，旧数据清理不靠本核reset假定完成。
4. 数据保持：下载时数据所有权在LabVIEW Current_Array，dma_fire才推进offset/计数；DMA满时数据/first/last保持。尾块补零不发送给Host。四个时钟要求由四个SCTL/CLIP时钟映射落实，新增下载150MHz不产生时钟，也没有新增125->150直连线。
5. 生命周期：Sync结果FIFO写端在Sync域、读端150MHz；结果区不覆盖输入区。capture_done只到写请求接受，download_done只到FPGA侧DMA接受；NI写可见性与Host收齐各有单独条件。输入回放与结果捕获共享DDR时约4GB/s有效载荷需求尚待平台仲裁保证。
6. 资源：两条链路约240KiB有效FIFO载荷，BRAM36规划128、URAM新增计划0，不能当综合利用率。FIFO满时Sync须背压，1024组结果FIFO仅约8.192us的空缓冲时间，不能承诺无限阻塞无丢数。
7. 验证：只新增capture/download两条短测。capture检查实际拼装数组/写地址/填零和4000点1100拍；download实际建8组DMA环形FIFO和独立Host读指针，覆盖背压恢复/计数/尾组/异常。原两成功测试不重跑。
8. 执行：新入口无EDA预检通过，16文件5工具冻结；本轮新窗口已准入，create/capture/download均已通过并完成Job三空收口。准备阶段静态Python端口解析器最末括号识别曾报错，修复后审计通过；当时未启动EDA，不属RTL错误。

静态结论：在文档明确的已知长度、同域NI节点、原子跨域FIFO及可背压合同下，角色复用与四段结构一致。新增两角色功能短测已通过，原两核保持上一轮证据；150MHz物理时序、持续DDR/PCIe速率、NI/板测均未验证。

结果复核：冻结16输入与5工具均未漂移；原始日志各唯一PASS且无断言错误，4RTL/4TB/2约束集真实导出匹配。下载Host独立FIFO读指针逐点核对。参见FOUR_STAGE_VALIDATION_20260917_ZH.md；不据此升级到全链路或物理速率合格。
