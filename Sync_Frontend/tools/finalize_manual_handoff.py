from pathlib import Path
import re,json,csv,hashlib,shutil,struct
from datetime import datetime,timezone
root=Path(r"D:/008_MA_Dev/Sync_Frontend")
out=root/"handoff/Sync_Frontend_20260915_manual"
assert not out.exists(),"Preserve previous handoffs."
out.mkdir(parents=True)
def copy(src,rel):
 p=out/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,p);return p
def write(rel,s):
 p=out/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding="utf-8");return p
latest="用户最新交付范围（2026-09-15）：仅交付完整 Vivado 核心 RTL 工程（top=sync_frontend_top）、独立明文 VHDL wrapper、可复现输入/预期输出及中文手工操作说明。CLIP XML 与 LabVIEW CLIP 配置由用户亲自创建；Agent 不新增/生成/修补 XML，不创建 LabVIEW 项目，不做 wrapper 回填或独立 wrapper 网表验证，不为交付重跑冻结实验。"
p=root/"AGENTS.md";s=p.read_text(encoding="utf-8");s=s.replace("# 同步前端执行规则","# 同步前端执行规则\n\n"+latest,1)
s=re.sub(r"9\. 发布包含[^\n]*","9. 最终交付为可直接 GUI 打开的完整核心 RTL/XPR（含约束/IP/TB/既有功能验证证据）、匹配的独立明文 VHDL wrapper、输入/预期结果及逐端口和 Host/Target 手工测试说明。XML/CLIP 配置由用户在 LabVIEW 创建；不作为 Agent 必交项或门槛。独立时序与 NI 板级验收分开，用户负责后续 LabVIEW/板测。",s)
p.write_text(s,encoding="utf-8")
p=root/"docs/WORK_ORDER_ZH.md";s=p.read_text(encoding="utf-8")
s=s.replace("# 同步前端：自主捕获、独立Vivado工程与CLIP交付","# 同步前端：自主捕获、完整核心工程与独立 VHDL 接口交付\n\n"+latest,1)
s=s.replace("→ CLIP交付。","→ 用于用户手工 CLIP 集成的完整工程、VHDL 接口及测试资料交付。")
s=re.sub(r"导出VHDL包装、CLIP XML、完整EDIF[^\n]*","最终仅交付：①可直接在 Vivado GUI 打开的完整 RTL 工程，算法核心为综合顶层，约束/IP/TB/已完成证据齐全，用户可手动综合导出 DCP/其它网表；②按核心接口提供独立明文 VHDL wrapper；③可复现输入、预期输出及中文手工测试说明。静态核对实际选源、端口、依赖、SHA；不要求 Agent 生成 XML 或配置 LabVIEW，不以 wrapper 为顶层生成交付网表，不重跑已冻结实验。",s)
s=s.replace("本任务优先交付可导入且证据明确的CLIP；","本任务交付上述三类资料，用户亲自在 LabVIEW 创建 CLIP XML/配置；")
p.write_text(s,encoding="utf-8")
# The independent wrapper's logic is unchanged; only the explanatory comment is generalized.
v=(root/"release/Sync_Frontend_SF003_20260915_rev01/clip_edif/sync_frontend_clip.vhd").read_bytes()
v=v.replace(b"Pure wiring wrapper around the complete EDIF core.",b"Pure wiring wrapper around the complete synthesized core.")
(out/"sync_frontend_clip.vhd").write_bytes(v)
copy(root/"release/Sync_Frontend_SF003_20260915_rev01/clip_edif/ports.json","ports.json")
copy(root/"sim/data/autonomous_stream.mem","input/autonomous_stream.mem")
copy(root/"sim/data/autonomous_manifest.json","input/autonomous_manifest.json")
copy(root/"reports/reference/autonomous_results.csv","expected/autonomous_results.csv")
lines=(out/"input/autonomous_stream.mem").read_text().splitlines()
assert len(lines)==15081
words=[]
for s in lines:
 assert re.fullmatch(r"[0-9A-Fa-f]{32}",s)
 beat=int(s,16)
 words.extend((beat>>(32*k))&0xffffffff for k in range(4))
assert len(words)==60324
assert all("".join(f"{v:08X}" for v in reversed(words[4*i:4*i+4])).lower()==s.lower() for i,s in enumerate(lines))
write("input/iq_u32_hex.txt","".join(f"{v:08X}\n" for v in words))
(out/"input/iq_u32_le.bin").write_bytes(struct.pack("<"+"I"*len(words),*words))
expected=list(csv.DictReader((out/"expected/autonomous_results.csv").open(encoding="utf-8-sig")))
result_words=[]
for row in expected:
 c=int(row["coarse_absolute"]);f=int(row["fine_absolute"])
 result_words.extend([int(row["epoch"]),int(row["rx_frame_id"]),int(row["candidate_id"]),c&0xffffffff,c>>32,f&0xffffffff,f>>32,int(row["cfo_hz"])&0xffffffff,(int(row["status"],16)<<16)|int(row["quality"])])
assert len(result_words)==36
write("expected/results_u32_hex.txt","".join(f"{v:08X}\n" for v in result_words))
write("expected/diagnostics.json",json.dumps(dict(accepted_samples=60324,confirmed_count=4,candidate_count=13,rejected_count=1,capture_drop_count=4,duplicate_count=4,snapshot_peak=2,max_history_age=4336,error_sticky=0,required_schedule="Pause 8000 FPGA clocks after each 256 accepted beats; result stall 128 FPGA clocks; initial reset without session_start"),indent=2)+"\n")
entry="当前最终交接：handoff/Sync_Frontend_20260915_manual/README_ZH.md。完整工程 top=sync_frontend_top；独立 VHDL 与测试数据见该交接目录。CLIP XML/配置由用户手工创建，旧 rev01/rev02 自动包不作为最终使用入口。"
for name in ["LABVIEW_TARGET_INTEGRATION_ZH.md","PROJECT_GUI_ZH.md","CLIP_INTERFACE_BOARD_TEST_ZH.md"]:
 p=root/"docs"/name;s=p.read_text(encoding="utf-8")
 s=re.sub(r"当前(?:更正|发布|更新)（2026-09-15）：[^\n]*",entry,s,count=1)
 s=re.sub(r"\n当前完整发布：[^\n]*","",s)
 if name=="PROJECT_GUI_ZH.md":
  s=s.replace("当前 release 的 clip 目录提供核心 DCP、独立纯连线 VHDL、CLIP XML 和说明 NI 时钟所有权的 XDC。核心 DCP 已独立重开、零黑盒；发布文件另做静态端口、依赖及哈希检查。自建 wrapper 回填诊断不是发布前置门槛。","最终交接提供完整核心工程、独立 VHDL wrapper 和输入/预期结果。用户可在原算法顶层手动综合和导出网表，并亲自在 LabVIEW 创建 CLIP XML/配置。既有核心综合与重开证据保留，自建 wrapper 回填不是前置门槛。")
 if name=="CLIP_INTERFACE_BOARD_TEST_ZH.md":
  s=s.replace("见clip/ports.json，XML同源生成。","见 handoff/Sync_Frontend_20260915_manual/ports.json；XML 由用户根据此接口在 LabVIEW 手工创建。")
  s=s.replace("1. 导入完整clip候选文件；确认XML时钟为125MHz，","1. 用户根据独立 VHDL 和自行导出的核心网表在 LabVIEW 创建 CLIP 声明；配置时钟为125MHz，")
 p.write_text(s,encoding="utf-8")
 copy(p,"docs/"+name)
p=root/"docs/CLIP_NETLIST_INTEGRATION_DECISION_20260915_ZH.md"
s=p.read_text(encoding="utf-8");s=s.replace("# NI CLIP 网表与 VHDL wrapper 的交付边界更正","# NI CLIP 网表与 VHDL wrapper 的交付边界更正\n\n"+latest+"\n当前入口：handoff/Sync_Frontend_20260915_manual/README_ZH.md。下文记录本日较早对技术接入方式的核查；其中 Agent 自动提供 XML 的发布安排已被最新要求取代。",1)
s=re.sub(r"\n当前完整发布：[^\n]*","",s);p.write_text(s,encoding="utf-8")
p=root/"reports/SF003_ASTRA_REVIEW_ZH.md";s=p.read_text(encoding="utf-8")
s=s.replace("日期：2026-09-15；","当前交付范围：完整算法顶层 XPR/RTL + 独立 VHDL + 输入/预期结果/手工指南；XML 由用户创建。旧自动包保留为历史，当前入口 handoff/Sync_Frontend_20260915_manual/README_ZH.md。\n日期：2026-09-15；",1)
s=s.replace("正式结构采用核心 DCP + 独立 VHDL wrapper + XML，NI 编译负责关联；","技术关联由 NI 编译完成；Agent 最终交付完整工程、独立 VHDL 和手工测试资料，用户自行创建 XML；")
p.write_text(s,encoding="utf-8")
copy(p,"evidence/SF003_ASTRA_REVIEW_ZH.md")
for name in ["SF001_ASTRA_REVIEW_ZH.md","SF002_ASTRA_REVIEW_ZH.md","SF002_completion.json","SF003_completion.json"]:
 copy(root/"reports"/name,"evidence/"+name)
ports=json.loads((out/"ports.json").read_text())
portnotes={
"clk125":"接用户在LabVIEW配置的125MHz自由运行时钟；同域SCTL",
"reset_n":"先0至少4拍，再1；等待input_ready=1",
"session_start":"通常0；新会话才单拍1；首次对照不发送以保持epoch=0",
"session_abort":"通常0；用户中止时单拍1",
"stream_gap":"通常0；实际丢样/采样不连续才单拍1；DMA暂空不发",
"input_valid":"通常0；四点齐全后1，等ready握手前保持",
"input_ready":"接输入保持状态机，只在valid和ready同为1时推进四点",
"result_valid":"监视整条结果有效，驱动VI快照状态机",
"result_ready":"仅当VI能原子接收整条结果时1；初次复现每条结果等待128拍",
}
for k in range(4):portnotes[f"input_data{k}"]=f"接第4b+{k}个U32；Q16高、I16低；未valid可置0，背压时保持"
for p in ports:
 portnotes.setdefault(p["name"],"输出，不由Host赋值；按接线指南读取"+("，单位Hz" if p["name"]=="cfo_hz" else ""))
table="|端口|方向|LabVIEW类型/位宽|初始/运行连接|\n|---|---|---|---|\n"
for p in ports:table+=f'|{p["name"]}|{p["direction"]}|{p["datatype"]}/{p["bits"]}|{portnotes[p["name"]]}|\n'
write("PORT_SETTINGS_ZH.md","# 32个独立VHDL端口的手工连接\n方向相对核心；各字段单位、坐标、符号与错误位说明详见 docs/LABVIEW_TARGET_INTEGRATION_ZH.md。CLIP配置由用户在LabVIEW创建。\n\n"+table)
write("README_ZH.md","""# 同步前端最终交接：完整核心工程、独立 VHDL 与手工测试
本次交付只包含三项：完整 Vivado 核心工程、独立明文 VHDL wrapper、输入/预期输出及中文操作说明。CLIP XML 和 LabVIEW CLIP 配置由用户亲自在 LabVIEW 创建。

## 1. 完整核心工程
唯一工程入口：D:/008_MA_Dev/Sync_Frontend/vivado/Sync_Frontend/Sync_Frontend.xpr。
保留 D:/008_MA_Dev/Sync_Frontend 整个项目目录，不能只搬走 .xpr。本交接目录是附件入口，不是第二个裁剪后的 RTL 工程。
Vivado2021.1，器件xcvu11p-flgb2104-2-e，综合top必须为sync_frontend_top。34个硬件SV、15个管理IP、ROM、2个XDC、基座和自主捕获TB已在工程中。
在GUI打开XPR，检查Design Sources顶层与器件。需要手工导出时，使用原核心Run Synthesis/Open Synthesized Design，再File→Checkpoint→Write导出DCP；不要把sync_frontend_clip设为综合顶层。已有综合证据保留，不必为查看结果重跑。
当前独立工程约束用于OOC测量，存在已记录的输入delay遗漏，原DCP还含独立输出预算；不能直接当NI完整接口时序证明。用户在NI工程确认实际时钟与约束。详见docs/PROJECT_GUI_ZH.md及evidence/SF003_ASTRA_REVIEW_ZH.md。

## 2. 独立 wrapper
本目录sync_frontend_clip.vhd，entity=sync_frontend_clip，内部component=sync_frontend_top、实例名implementation。不加入原算法工程综合源集，也不预先综合成wrapper顶层DCP。
PORT_SETTINGS_ZH.md逐端口给出方向、类型、位宽、初始值及驱动/监视方法；ports.json为同一接口的机器清单。wrapper只做端口拼拆与连线，不包含DMA、时钟生成或同步算法。

## 3. Host/Target 手工对照步骤
A. 用户创建CLIP配置，加入独立VHDL与自己从核心导出的完整网表；在Target VI中配置125MHz同域SCTL、输入保持寄存器、结果快照/序列化状态机和两条DMA FIFO。不要逐位跨域传输结果。完整设计说明见docs/LABVIEW_TARGET_INTEGRATION_ZH.md。
B. Host把input/iq_u32_le.bin按“小端、U32、无文件头”读成60324元素数组；或把input/iq_u32_hex.txt每行8位十六进制按U32解析。两者是同一输入。发送顺序不变，Q16高半字、I16低半字；例I=-1/Q=2的U32为0x0002FFFF。
C. 清理输入/结果DMA及VI残留半包；start/abort/gap=0、input_valid=0，reset_n=0至少4个125MHz拍，再置1并等待ready。首次对照不发session_start，期望epoch0。
D. Host通过Host-to-Target U32 FIFO发送全部数组。FPGA成功读满四点后锁存为data0..3，data0最早；valid=1且ready=1才接受。背压时四字及valid保持；FIFO暂空只令valid=0，不发gap。每256个已接受beat暂停8000个FPGA拍，在FPGA计数，不用Host sleep控制。
E. 第一次对照每条result_valid出现后让result_ready保持0共128拍，再原子保存全部结果字段并确认一次。将快照按9个U32序列化到Target-to-Host FIFO：epoch、rx_frame_id、candidate_id、coarse低32、高32、fine低32、高32、CFO的I32位型、(status<<16)|quality。FIFO满时保持未发送字，不丢弃或重复确认结果。
F. Host按9字组包，跨DMA块保留不足9字的尾部；CFO按I32重解释，粗/精位置合成U64。expected/results_u32_hex.txt是相同打包的四条参考记录，共36字；expected/autonomous_results.csv是可读字段，status列为十六进制。
G. 正确对照有4条结果，fine_absolute=15004/26373/37842/49311，CFO=-150022/0/150022/-149977Hz；对注入真值CFO最大误差23Hz，判据<=1000Hz，精TO零样点误差。质量和status逐项参考CSV。
H. 监视accepted_samples=60324、confirmed_count=4、candidate_count=13、rejected_count=1、capture_drop_count=4、duplicate_count=4、snapshot_peak=2、max_history_age=4336、error_sticky=0，以及两条DMA超时/溢出、输入beat数15081、结果丢包数0。诊断是live值，应由VI统一快照读取。改变发送节奏会改变服务/drop计数，先复现已验证节奏再扩展。
I. Host导出与expected/autonomous_results.csv相同列的CSV，可运行D:/008_MA_Dev/Sync_Frontend/tools/compare_readback.py <CSV绝对路径>。不带参数只比较历史RTL结果，不是板测。
任何精TO错误、CFO误差越门、结果缺失/重复/乱序、错误位或DMA数据丢失均不能算本次对照通过。停止加载并保存结果/计数/错误现场，再复位，避免抹掉原因。
truth、真TO/CFO、frame_start、frame_id与外部真实样点索引都不发送给FPGA。PS1参考已经在核心ROM。每个lane是同一条流的连续时间样点，不是四路天线。

## 已有证据与边界
SF001基座迁移、SF002自主连续流限定短测试、SF003核心综合已有证据。上述4帧是带暂停/背压的限定验证，不是任意信道、ADC持续500MS/s或板级吞吐资格。
历史独立实现WNS2.087ns、WHS0.024ns、TNS/THS0，仅覆盖已约束路径；133个同步输入漏input delay，另有异步reset输入。5BUFG按实际资源保留，不要求新增为0。
当前CLIP只输出同步结果，不输出整帧或整帧CFO/SFO补偿数据；下游需在外部保存同一epoch的原始IQ。
用户后续负责LabVIEW配置、完整Target编译、真实接口时序和板测；本次没有新native运行。
旧release rev01及未完成rev02自动包、失败回填日志保留历史；均不作为本次最终入口。不要运行旧自动XML打包脚本。
文件来源/哈希及实际XPR选源见STATIC_HANDOFF_VALIDATION.json、PROJECT_FILES.csv与SHA256SUMS.csv。
""")
readme=root/"README_ZH.md"
readme.write_text("""# Sync_Frontend 自主同步前端
"""+latest+"""

唯一最终交接入口：[handoff/Sync_Frontend_20260915_manual/README_ZH.md](handoff/Sync_Frontend_20260915_manual/README_ZH.md)。
- 完整工程：vivado/Sync_Frontend/Sync_Frontend.xpr；top=sync_frontend_top；xcvu11p-flgb2104-2-e；Vivado2021.1。
- 独立VHDL：handoff/Sync_Frontend_20260915_manual/sync_frontend_clip.vhd。
- 输入/预期：同交接目录input/及expected/；逐端口：PORT_SETTINGS_ZH.md。
- 架构/RTL层级及Host/Target接线：docs/LABVIEW_TARGET_INTEGRATION_ZH.md；GUI：docs/PROJECT_GUI_ZH.md。
- 已完成：SF001基座迁移、SF002四帧自主捕获限定短测试、SF003核心综合；原独立实现仅覆盖已约束路径。NI整体编译/接口时序/板测/持续吞吐尚未验收。
- MATLAB入口：matlab/waveform/load_frontend_waveform.m、matlab/golden/frontend_reference_catalog.m、matlab/comparison/compare_frontend_readback.m；新增包装未原生执行。
- Python读回比较：tools/compare_readback.py。
旧release rev01和未完成rev02保留历史；自动XML打包及wrapper回填已停止，旧包不是最终使用入口。历史失败不能改为通过，也不能据此认定NI不支持核心DCP。
本地Git无remote；旧工程/T10/T11只读；本轮不启动、打断或重跑冻结实验。
""",encoding="utf-8")
write("LATEST_SCOPE.json",json.dumps({"scope":"CORE_XPR_INDEPENDENT_VHDL_REPRODUCIBLE_IO_MANUAL_GUIDE","source_project":"D:/008_MA_Dev/Sync_Frontend","xpr":"vivado/Sync_Frontend/Sync_Frontend.xpr","top":"sync_frontend_top","agent_creates_clip_xml":False,"user_creates_clip_configuration":True,"native_runs_started":0,"previous_automatic_packages":"PRESERVED_SUPERSEDED"},indent=2)+"\n")
print(json.dumps({"handoff":str(out),"generated_input_u32_count":len(words),"expected_result_u32_count":len(result_words),"new_xml_files":0,"native_runs_started":0},ensure_ascii=False))
