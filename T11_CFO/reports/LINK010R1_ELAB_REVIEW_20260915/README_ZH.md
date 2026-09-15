# LINK010R1 展开失败复核

工程创建通过；XSim在测试台第84行clocking block展开失败，尚未运行任何测试刺激，不能判定R1数值、协议或复位检查通过。create耗时14.645秒，失败的simulate入口耗时19.381秒；两个私有Job的PID与active accounting均归零，外部身份保护通过。

41份原始产物已逐份校验并复制封存，原manifest与失败attempt保持不变；当前XPR及日志以后即使在获准修复时更新，此处仍保留失败前的确切字节。现有成功create须复用，不为补日志重建。

报错为XSIM43-4412 Initial value not supported yet。clocking输入别名是待核实的兼容性候选，报错行本身未单独证明是哪项clocking特性不受支持。新TB语法修订只允许保持#1step、观察时刻、原刺激和验收门限；本报告不授予新native启动。
