from pathlib import Path
import json,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
# name, direction, bits, LabVIEW type, meaning; one source for XML and VHDL.
p=[('clk125','in',1,'Boolean','NI-provided free-running 125 MHz; use this same clock for the SCTL'),('reset_n','in',1,'Boolean','Active-low reset, hold at least 4 clocks, wait for input_ready after release'),('session_start','in',1,'Boolean','One clock pulse starts a new continuity epoch'),('session_abort','in',1,'Boolean','One clock pulse disarms input and discards in-flight state'),('stream_gap','in',1,'Boolean','One clock pulse declares real sample loss; discard old epoch; valid pause alone is not sample loss'),('input_valid','in',1,'Boolean','Hold all four IQ words until valid and ready'),('input_ready','out',1,'Boolean','Accept all four IQ samples on valid and ready')]
for k in range(4):p.append((f'input_data{k}','in',32,'U32',f'Lane {k}, packed Q16 high / I16 low, lane0 is earliest'))
p += [('result_valid','out',1,'Boolean','Entire result bundle remains stable until result_ready'),('result_ready','in',1,'Boolean','Acknowledge all result fields atomically'),('result_epoch','out',32,'U32','Continuity epoch of this result'),('rx_frame_id','out',32,'U32','Local confirmed frame sequence, starts at zero per epoch; not decoded transmitter frame id'),('candidate_id','out',32,'U32','Internal candidate sequence, including rejected proposals'),('coarse_absolute','out',64,'U64','Coarse position in accepted samples since epoch start'),('fine_absolute','out',64,'U64','Fine position in accepted samples since epoch start'),('cfo_hz','out',32,'I32','Signed coarse CFO Hz; raw payload has not been corrected'),('quality_q1_15','out',16,'U16','Fine timing quality code Q1.15'),('result_status','out',16,'U16','Kind and validity flags; 0x3800 is a valid fine result')]
for name,bits,meaning in [('accepted_samples',64,'Live accepted-sample count within current epoch'),('epoch',32,'Live continuity epoch'),('candidate_count',32,'Eligible plateau proposals'),('rejected_count',32,'Candidates rejected by local estimator'),('capture_drop_count',32,'Candidates rejected for copy/slot capacity or stale history'),('duplicate_count',32,'Queued proposals suppressed near the confirmed frame'),('confirmed_count',32,'Confirmed frames admitted to result holding register'),('snapshot_occupancy',8,'Number of occupied snapshot slots, 0..2'),('snapshot_peak',8,'Maximum snapshot occupancy, 0..2'),('max_history_age',16,'Largest oldest-needed-sample age at copy start'),('error_sticky',16,'Per-epoch hardware diagnostics; see interface guide')]:p.append((name,'out',bits,f'U{bits}',meaning))
def typ(n):return 'std_logic' if n==1 else f'std_logic_vector({n-1} downto 0)'
ports=';\n'.join(f'        {name} : {d} {typ(n)}' for name,d,n,_,_ in p)
core=[('clk','in',1),('reset_n','in',1),('session_start','in',1),('session_abort','in',1),('stream_gap','in',1),('s_valid','in',1),('s_ready','out',1),('s_data','in',128),('m_valid','out',1),('m_ready','in',1),('m_result','out',288),('accepted_samples','out',64),('epoch','out',32),('candidate_count','out',32),('rejected_count','out',32),('capture_drop_count','out',32),('duplicate_count','out',32),('confirmed_count','out',32),('snapshot_occupancy','out',2),('snapshot_peak','out',2),('max_history_age','out',16),('error_sticky','out',16)]
cp=';\n'.join(f'            {name} : {d} {typ(n)}' for name,d,n in core)
mapping={'clk':'clk125','s_valid':'input_valid','s_ready':'input_ready','s_data':'raw_iq','m_valid':'result_valid','m_ready':'result_ready','m_result':'result_bundle','snapshot_occupancy':'occupancy_bits','snapshot_peak':'peak_bits'}
cm=',\n'.join(f'            {name} => {mapping.get(name,name)}' for name,_,_ in core)
v=f'''library ieee;
use ieee.std_logic_1164.all;
-- Pure wiring wrapper around the complete EDIF core. No algorithm or clock generator.
entity sync_frontend_clip is
    port (
{ports}
    );
end entity;
architecture rtl of sync_frontend_clip is
    component sync_frontend_top is
        port (
{cp}
        );
    end component;
    signal raw_iq : std_logic_vector(127 downto 0);
    signal result_bundle : std_logic_vector(287 downto 0);
    signal occupancy_bits, peak_bits : std_logic_vector(1 downto 0);
begin
    raw_iq <= input_data3 & input_data2 & input_data1 & input_data0;
    result_epoch <= result_bundle(287 downto 256);
    rx_frame_id <= result_bundle(255 downto 224);
    candidate_id <= result_bundle(223 downto 192);
    coarse_absolute <= result_bundle(191 downto 128);
    fine_absolute <= result_bundle(127 downto 64);
    cfo_hz <= result_bundle(63 downto 32);
    quality_q1_15 <= result_bundle(31 downto 16);
    result_status <= result_bundle(15 downto 0);
    snapshot_occupancy <= "000000" & occupancy_bits;
    snapshot_peak <= "000000" & peak_bits;
    implementation : sync_frontend_top port map (
{cm}
    );
end architecture;
'''
(root/'clip/sync_frontend_clip.vhd').write_text(v,encoding='utf-8')
r=ET.Element('CLIPDeclaration',Name='Autonomous TO CFO frontend 125MHz FLGB')
ET.SubElement(r,'FormatVersion').text='4.3'
ET.SubElement(r,'Description').text='Raw-IQ autonomous capture, coarse TO/CFO and fine TO. Single clock. Finite queue; not sustained ADC or board qualified.'
s=ET.SubElement(ET.SubElement(r,'TopLevelEntityAndArchitecture'),'SynthesisModel')
ET.SubElement(s,'Entity').text='sync_frontend_clip';ET.SubElement(s,'Architecture').text='rtl'
ET.SubElement(r,'SupportedDeviceFamilies').text='Unlimited'
it=ET.SubElement(ET.SubElement(r,'InterfaceList'),'Interface',Name='LabVIEW');ET.SubElement(it,'InterfaceType').text='LabVIEW'
sl=ET.SubElement(it,'SignalList')
for name,d,n,dt,desc in p:
    s=ET.SubElement(sl,'Signal',Name=name)
    for tag,val in [('HDLName',name),('HDLType',typ(n)),('Direction','ToCLIP' if d=='in' else 'FromCLIP')]:ET.SubElement(s,tag).text=val
    ET.SubElement(ET.SubElement(s,'DataType'),dt);ET.SubElement(s,'Description').text=desc
    ET.SubElement(s,'SignalType').text='clock' if name=='clk125' else 'data'
    if name=='clk125':
        fq=ET.SubElement(s,'FreqInHertz');ET.SubElement(fq,'Min').text='125000000';ET.SubElement(fq,'Max').text='125000000'
    else:
        ET.SubElement(s,'RequiredClockDomain').text='clk125';ET.SubElement(s,'UseInLabVIEWSingleCycleTimedLoop').text='Required'
il=ET.SubElement(r,'ImplementationList')
for fn in ['sync_frontend_clip.vhd','sync_frontend_top.edf','sync_frontend_clip.xdc']:
    x=ET.SubElement(il,'Path',Name=fn)
    if fn.endswith('.vhd'):ET.SubElement(x,'TopLevel')
    ET.SubElement(ET.SubElement(x,'SimulationFileList'),'SimulationModelType').text='Exclude from simulation model'
for tag in ['NumberOfDCMsNeeded','NumberOfMMCMsNeeded','NumberOfBufGsNeeded']:ET.SubElement(r,tag).text='0'
ET.indent(r,space='  ');ET.ElementTree(r).write(root/'clip/sync_frontend_clip.xml',encoding='utf-8',xml_declaration=True)
(root/'clip/ports.json').write_text(json.dumps([dict(name=n,direction=d,bits=b,datatype=dt,description=ds) for n,d,b,dt,ds in p],indent=2)+'\n')
print('CLIP_DECLARED_PORTS',len(p),'CORE_PORTS',len(core))
