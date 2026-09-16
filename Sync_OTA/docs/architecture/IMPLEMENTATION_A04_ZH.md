# A04：真实主链连接与有限离线调度

状态：RTL与依赖已写入，静态语法通过；新连接尚待原生短检查。最终XPR/DCP尚未生成。

## 主流程

sync_ota_top实体化真实sync_frontend_top、sync_sfo_top（REQUIRE_CONTEXT_ACK=1）、ota_cfo_chain及ota_ddr_bridge；Host没有TO/CFO/SFO真值输入。ota_capture_controller接受有限capture_words，写完且收到全部ACK后扫描。首个前端结果锁定后停止向前端喂数，继续排空扫描回放；前端结果等候保护262144个125MHz周期。真实descriptor校验全区间，SFO复位释放128周期，再预装334215个beat。raw坐标为-172+4*b，frame/gen与统一描述符一致。

只有最后SFO输入已被接受、raw_store重新SEALED，才释放外部原始租约，并分别发布frame/CFO/fine及正式上下文。实际两级SFO发动机配置握手必须由context_join消费；第二级启动与CFO接受两级步长绑定。DDR基址在同一完整metadata记录中跨域，正式CFO配置不读取debug。

## DDR与取消

地址单位为128bit字；同一区域容量为max(capture_words,334080)，默认最大capture_words=524288。默认离线捕获上限8MiB。DDR桥全机接口只有一个在途信用，原始125MHz请求与CFO150MHz请求采用记录FIFO和轮流优先仲裁；外部tag为65bit：归属1bit加原store的generation32/serial32。请求被接受后字段保持不变，匹配回应才释放信用；陈旧tag被计数并报错，不转交、不释放当前信用。

取消只复位/清除算法上下文，DDR桥只服从平台全局reset_request。控制器等待raw信用、CFO内部store和桥全部排空，才完成取消。CFO完成通过独立记录FIFO返回，取消保持期间只发一次，解除后再确认内部COMPLETE，避免重复完成或过早重新开始。全局复位必须由NI与DDR端协调，不能单独丢掉在途事务。DDR异常后需先服务未回信用，再做协调复位；仅空闲不代表历史树/事务完整。

## 离线保护与原门槛

当前单信用DDR路径会对SFO输出施加服务等待。OTA实例的SFO PROCESSING_LIMIT_CYCLES明确设为536870912（150MHz约3.58s），每个OTA非捕获处理阶段保护1073741824（125MHz约8.59s）。捕获和取消排空不靠盲超时丢数据：Host停止可发cancel；DDR无回应会停留在取消排空直到补回应或平台协调复位。以上是有限离线调度保护，不是旧400896周期门槛的修改验收。旧工程和其400896默认值不变；OTA不声称通过该连续服务预算，也不声称持续500MS/s。

## IP/源集

rtl/sources.f明确列出完整生产源，禁止递归选源。ip/sources.f列出45个唯一真实XCI。49个来源XCI原件在docs/provenance/ip_originals；4个重名IP只有PREFHDL/OUTPUTDIR差异，功能参数一致。新副本只规范化输出目录和首选Verilog，系数内嵌未改；详见OTA_IP_SOURCE_LOCK.json。前端PS1及残余SFO相位ROM也已逐字节复制。生产综合采用官方XPM；私有仿真修改仅在sim/vendor内。

## 验证与待处理

OTA002三个冻结功能范围已接收；backend74历史进程树缺口保留，见reports/OTA002。OTA003仅验证新增DDR桥、有限帧控制和两符号真实坐标/双旋转衔接。有限帧控制TB的FE/SFO/CFO为明确标注接口服务，地址范围不缩短、数学算法不在此TB运行。双旋转TB使用已有5120样点与独立整数参考，不声称真实SFO/CFO估计数值闭环。完整74观测不重跑。

后续必须完成：最终XPR打开/完整真实核编译展开、独立VHDL Wrapper、完整核心综合/DCP、Host/Target板测资料。审查发现CFO原A01的早期backend_bad分支未锁存失败结果详情；成功路径无影响，最终冻结前以新版本修复并保留A01冻结源，不改旧实验输入。对新顶层还须完成完整端口和CDC审查。布局布线、持续吞吐、NI集成及板测未验证。
