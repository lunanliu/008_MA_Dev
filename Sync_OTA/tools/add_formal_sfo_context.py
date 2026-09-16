from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[1]
changes=[]
for rel in ['rtl/sfo/first_resampling/sfo_first_resampler.sv','rtl/sfo/second_resampling/sfo_second_resampler.sv']:
 p=root/rel;before=p.read_text(encoding='utf-8-sig')
 # New production callers enable ACK; default retains the source baseline's timing.
 marker='    parameter integer NOMINAL_SAMPLES'
 if marker not in before:raise RuntimeError('parameter anchor missing')
 s=before.replace(marker,'    parameter integer REQUIRE_CONTEXT_ACK = 0,\n'+marker,1)
 marker='    output logic signed [ 63:0]       diagnostic_phase,'
 # Formatting differs slightly in the two accepted files; require exact discovered line.
 lines=s.splitlines()
 anchors=[x for x in lines if 'output logic signed' in x and 'diagnostic_phase' in x]
 if len(anchors)!=1:raise RuntimeError('port anchor ambiguous')
 anchor=anchors[0]
 ports='''    // Formal descriptor transfer is coupled to the actual engine configuration.
    output wire context_valid,
    input wire context_ready,
    output wire [31:0] context_frame, context_generation, context_step_q28,
    output wire signed [63:0] context_phase,
    output wire signed [31:0] context_raw_first, context_nominal_first,
'''
 s=s.replace(anchor,ports+anchor,1)
 marker='  wire abort_engine = abort_request && state == ACTIVE;'
 extra='''
  wire context_ack = !REQUIRE_CONTEXT_ACK || context_ready;
  assign context_valid = !rst && !abort_request && state == LAUNCH && engine_cfg_ready;
  assign context_frame = d_frame;
  assign context_generation = d_gen;
  assign context_step_q28 = d_step;
  assign context_phase = d_phase;
  assign context_raw_first = d_raw;
  assign context_nominal_first = d_origin;
'''
 s=s.replace(marker,marker+extra,1)
 old='.m_ready              (state == LAUNCH && engine_cfg_ready)'
 old2='.m_ready          (state == LAUNCH && engine_cfg_ready)'
 if old in s:s=s.replace(old,'.m_ready              (state == LAUNCH && engine_cfg_ready && context_ack && !abort_request)',1)
 elif old2 in s:s=s.replace(old2,'.m_ready          (state == LAUNCH && engine_cfg_ready && context_ack && !abort_request)',1)
 else:raise RuntimeError('descriptor ready anchor missing')
 old='.cfg_valid            (state == LAUNCH && !abort_request)'
 if old not in s:raise RuntimeError('engine valid anchor missing')
 s=s.replace(old,'.cfg_valid            (state == LAUNCH && !abort_request && context_ack)',1)
 old='LAUNCH: if (engine_cfg_ready) state <= ACTIVE;'
 if old not in s:raise RuntimeError('launch anchor missing')
 s=s.replace(old,'LAUNCH: if (engine_cfg_ready && context_ack) state <= ACTIVE;',1)
 p.write_text(s,encoding='utf-8')
 changes.append(dict(path=rel,baseline_sha256=hashlib.sha256(before.encode()).hexdigest(),new_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),status='formal ports implemented; production transport binding and native validation pending'))
(root/'docs/architecture/SFO_CONTEXT_PORT_CHANGE.json').write_text(json.dumps(changes,indent=2),encoding='utf-8')
print('FORMAL_SFO_PORTS_ADDED',len(changes))
