from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
rows=[]
ports='''    // Formal successful descriptor launches, clk150. No debug-derived configuration.
    output wire first_context_valid,
    input wire first_context_ready,
    output wire [223:0] first_context_record,
    output wire second_context_valid,
    input wire second_context_ready,
    output wire [223:0] second_context_record,
'''
p=root/'rtl/sfo/control/sfo_two_pass_transport.sv'
s=p.read_text();original=p.read_bytes()
s=s.replace('    parameter integer NOMINAL_SAMPLES = 1336320,','    parameter integer REQUIRE_CONTEXT_ACK = 0,\n    parameter integer NOMINAL_SAMPLES = 1336320,',1)
s=s.replace('    input  logic         clk125,',ports+'    input  logic         clk125,',1)
for number,module in [('first','sfo_first_resampler'),('second','sfo_second_resampler')]:
 s=s.replace(f'  {module} #(\n',f'  {module} #(\n      .REQUIRE_CONTEXT_ACK(REQUIRE_CONTEXT_ACK),\n',1)
 anchor=f'  ) {number}_resampling (\n'
 body=f'''      .context_valid({number}_context_valid),
      .context_ready({number}_context_ready),
      .context_frame({number}_context_record[223:192]),
      .context_generation({number}_context_record[191:160]),
      .context_step_q28({number}_context_record[159:128]),
      .context_phase({number}_context_record[127:64]),
      .context_raw_first({number}_context_record[63:32]),
      .context_nominal_first({number}_context_record[31:0]),
'''
 assert anchor in s
 s=s.replace(anchor,anchor+body,1)
p.write_text(s);rows.append(dict(path=str(p.relative_to(root)),before_sha256=hashlib.sha256(original).hexdigest(),after_sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
p=root/'rtl/sfo/control/sync_sfo_top.sv';s=p.read_text();original=p.read_bytes()
s=s.replace('    parameter integer OUTPUT_CLOCK_MHZ = 150','    parameter integer REQUIRE_CONTEXT_ACK = 0,\n    parameter integer PROCESSING_LIMIT_CYCLES = 400896,\n    parameter integer OUTPUT_CLOCK_MHZ = 150',1)
s=s.replace('    input  logic                                               clk125,',ports+'    input  logic                                               clk125,',1)
s=s.replace('  sfo_two_pass_transport #(\n','  sfo_two_pass_transport #(\n      .REQUIRE_CONTEXT_ACK(REQUIRE_CONTEXT_ACK),\n      .PROCESSING_LIMIT_CYCLES(PROCESSING_LIMIT_CYCLES),\n',1)
s=s.replace('  ) two_pass_transport (\n','''  ) two_pass_transport (
      .first_context_valid(first_context_valid),.first_context_ready(first_context_ready),.first_context_record(first_context_record),
      .second_context_valid(second_context_valid),.second_context_ready(second_context_ready),.second_context_record(second_context_record),
''',1)
p.write_text(s);rows.append(dict(path=str(p.relative_to(root)),before_sha256=hashlib.sha256(original).hexdigest(),after_sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
(root/'docs/architecture/SFO_FORMAL_BINDING_CHANGE.json').write_text(json.dumps(rows,indent=2))
print('FORMAL_TRANSPORT_BINDING_WRITTEN')
