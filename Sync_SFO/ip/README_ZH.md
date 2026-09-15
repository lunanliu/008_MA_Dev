# IP的唯一可编辑来源

`config/`中的34份XCI是新工程直接引用的配置，已由Vivado 2021.1原生迁移为 `xcvu11p-flgb2104-2-e`。原FLGC XCI另存于 `docs/verification/native_project/baseline/original_ip_xci.zip`，仅作来源证据，不参与构建。

四个FIR的CoefficientSource=Vector，系数内嵌于XCI。原生迁移自动产生实例模板VEO/VHO及XML元数据，这些可重建文件不纳入Git。尚未生成完整仿真/综合输出；没有复制旧DCP、网表、MIF或XSim快照。

`expected_user_config.json`记录用户参数基准；Tcl副本供原生检查读取。改变IP时核对算法、字长、系数和延迟，不能只看器件名称。原生检查结果见 `docs/verification/native_project/`，新器件的功能、时序和吞吐还需后续实际测试。
