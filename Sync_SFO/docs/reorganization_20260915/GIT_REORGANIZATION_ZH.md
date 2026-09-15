# Git 整理与用户修改保留

根仓库原 HEAD：2d49cf0b402fcc9109e16d1431b6ca8ca9be697a。前端原 HEAD：9b3bb262834b4f752fdb8fe2d2d50954935fd4d8。I16 原 HEAD：194b378f80cbe6d7be72efa11c0dd165d7db8bf6。三个仓库均保持原历史，不合并历史、不设置或推送远端。

本轮以原 index 中已跟踪的文件身份做路径迁移：根的 T10 目录归 Sync_SFO，T11_CFO 归 Sync_CFO。搬迁对应的 index 使用原已跟踪 blob，不将工作区中原有改动全部暂存。根 README、AGENTS、.gitignore 的本轮改动只有独立记录的前置/末尾追加，暂存时应用于原 index 内容；原已有修改仍留在工作区。原 T10 XPR 的未提交修改保留于 Sync_SFO/vivado/T10_SFO/T10_SFO.xpr。

本轮新入口、相对路径修订、导航、核对记录、已核验Wrapper/IP副本作为结构变更纳入本地提交。复用的核心、Wrapper、XPM和阶段XPR明确来自已存在版本，不作为本任务新的算法设计。其他原有未跟踪文件继续保留，不用 git add -A 混入本轮。

前端和 I16 分别在自己的仓库只提交本轮新入口和导航。I16原 README及历史XPR修改保持未提交。原件归档中的Git目录同样保留；它们仅作归档，不作为活动仓库。

最终提交号和保留差异核对见 git_completion.json。没有 reset、clean、删除Git、强制覆盖或推送云端。目录记录脚本是本次操作证据，其中切换前路径已归档，禁止将其当作可重复执行的实验或再次搬迁入口。
