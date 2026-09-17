# 四模块 DDR 回环交付包

先打开 `docs/tutorial/LABVIEW_ZERO_TO_ROUNDTRIP_ZH.html`，这是可离线浏览、打印的零基础接线手册；同名 `.md` 是文字原稿。按照章节 0～11 完成透明回环后，再按第 12 节连接真实 Sync。

## 四份 VHDL

| 文件 | 作用 | 实际目标时钟 | 导入依赖 |
|---|---|---|---|
| rtl/ddr_upload_ctrl.vhd | Host→DMA→输入 DDR | 150 MHz | 本文件 |
| rtl/ddr_read_ctrl.vhd | 输入 DDR→四点回放→Sync | 125 MHz | 本文件 |
| rtl/ddr_capture_ctrl.vhd | Sync 结果 FIFO→结果 DDR | 150 MHz | 还须加入 ddr_upload_ctrl.vhd |
| rtl/ddr_download_ctrl.vhd | 结果 DDR→DMA→Host | 150 MHz | 还须加入 ddr_read_ctrl.vhd |

这四个文件实现控制逻辑。NI FIFO、DDR Memory、数组数据寄存器、时钟及总会话逻辑由 LabVIEW 按教程连接，不是导入后自动生成完整 Target VI。没有生成 CLIP XML 或远端 VI。

每次有效交接为四个 U32 复样点，每点 I 占低 16 位、Q 占高 16 位。DDR_WIDTH_BITS 默认 1280，是编译期参数；Host 提供运行时 N/M/C。输入 DDR 与结果 DDR 是独立分配区域，同一区域先写完整段再读，不做同区边写边读或双缓冲。

## 先跑这一个数据例子

- 输入：`examples/roundtrip_604/input_u32.csv`，604 个 U32，无表头。
- 参数：N_in=N_out=604，M_in=M_out=16；C_in/C_out 填各自 NI Memory 的实际元素容量，至少 16。
- 暂时把 Sync 位置接成透明直通；按教程先配置资源、提交整段描述符，再送 H2T 数据，Host 持续接收 T2H。
- 期望：收齐 604 点，错误 0；I 为 0～603，Q 恒为 4660；首末 U32 为 0x12340000/0x1234025B。两个 DDR 各 16 个元素，四点交接各 151 次，DDR 尾部填零不返回 Host。
- `expected_u32.csv` 是期望；`simulated_host_received_u32.csv` 是这次原生 XSim 实际生成的模拟 Host 接收文件。两者不可充当真实板卡接收数据。
- 可选比较：在解压目录执行 `python scripts/compare_roundtrip.py 你的接收文件.csv`。

## 已验证与待对齐

四控制器串联的 604 点行为回环通过，含结果 FIFO 和 DMA 回压测试。详见 `reports/review/DDR_ROUNDTRIP_VALIDATION_ZH.md` 与 `reports/native/simulate.log`。原生产 RTL 未为本次回环改动，原已成功角色短测没有重跑；执行窗口已正式归还。

真实 NI 写请求被接受后，何时允许另一读接口读取同一 Memory，仍需按远端版本的接口保证对齐。`load_done/capture_done` 不能被擅自解释为物理 DDR 写入栅栏，教程两处 WAIT_*_VISIBLE 不可接常 True。NI 编译、板测、真实 Sync、物理时序和持续吞吐均未由本次仿真证明。

完整引脚索引：`reports/DDR_CURRENT_PORTS_ZH.md`（Upload/Read），`docs/tutorial/LABVIEW_FOUR_STAGE_WIRING_ZH.md`（Capture/Download及接线）。同目录硬件设计文档保留容量、背压和时钟边界。`SHA256.json` 列出交付包每个有效文件的校验值。
