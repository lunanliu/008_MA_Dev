# SF001 Astra复核

2026-09-14。结论：PASS_BASELINE_MIGRATION_ONLY。

独立Git路径为D:/008_MA_Dev/Sync_Frontend。51df108eea0938fcc8db124c8c7a1653db635800可在此仓库正常解析；父仓库bad object是仓库选错，不是本地提交丢失。

已复读原生baseline_smoke_retry1.log：3例、771 metrics、6 records、3 pair commits；vendor phase差0 LSB，ideal phase最大3 LSB（原门4），magnitude差0 LSB。正常finish于22780ns，Vivado正常退出。实际sources_1为30 SV、15 XCI及ROM；sim_1为原迁名TB。XPR存在，part=xcvu11p-flgb2104-2-e。

IP CONFIG快照前后文件SHA均8b59b67370a43e402b357d8f15776e199e3c3bd4e41831f8c523df74968786c4，485项相同；15 IP报告Up-to-date/FLGB。官方retarget是目标器件迁移，未改变算法配置，原XCI仍通过冻结验证。首次锁定失败及Tcl比较包装错误证据保留；未因收尾问题重跑成功计算。

后续独立sim_autonomous fileset避免覆盖SF001原生sim_1日志。SF001不能证明连续捕获、fine集成、综合实现、吞吐、CLIP或板测通过。
