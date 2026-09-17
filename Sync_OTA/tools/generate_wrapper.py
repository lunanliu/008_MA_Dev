"""Generate a transparent VHDL shell and exact port map from the production SV top."""
from pathlib import Path
import re,json,csv
root=Path(__file__).resolve().parents[1]
text=(root/'rtl/control/sync_ota_top.sv').read_text()
header=text[text.index('module sync_ota_top (')+len('module sync_ota_top ('):text.index('\n);')]
header=re.sub(r'//[^\n]*','',header)
ports=[];direction=None;width=1
for item in header.split(','):
 item=item.strip()
 match=re.fullmatch(r'(input|output)\s+wire\s*(?:\[(\d+):0\])?\s*(\w+)',item)
 if match:
  direction=match[1];width=int(match[2])+1 if match[2] else 1;name=match[3]
 else:
  assert re.fullmatch(r'\w+',item),item
  name=item
 assert direction
 domain='clk150' if name.startswith('m_') or name.endswith('150') else 'clk125'
 if name in ['clk125','clk150','clk500']:domain='clock'
 if name=='reset_request':domain='platform async assertion; local synchronous release'
 ports.append(dict(name=name,direction=direction,width=width,domain=domain))
assert len({p['name'] for p in ports})==len(ports)
def typ(n):return 'std_logic' if n==1 else f'std_logic_vector({n-1} downto 0)'
wrapper=[];assign=[]
for p in ports:
 n=p['width'];name=p['name'];p['wrapper']=[]
 for index in range((n+63)//64):
  lo=index*64;bits=min(64,n-lo)
  pad=1 if bits==1 and n==1 else next(v for v in [8,16,32,64] if v>=bits)
  wname=name if n<=64 else f'{name}_w{index}'
  wrapper.append(dict(name=wname,direction=p['direction'],width=pad,core=name,hi=lo+bits-1,lo=lo))
  p['wrapper'].append(dict(name=wname,width=pad,core_bits=f'{lo+bits-1}:{lo}',upper_padding=pad-bits))
  core='core_'+name+(f'({lo+bits-1} downto {lo})' if n>1 else '')
  if p['direction']=='input':
   rhs=wname if pad==bits else f'{wname}({bits-1} downto 0)'
   if n>1 and bits==1:rhs=f'{wname}(0 downto 0)'
   assign.append(f'  {core} <= {rhs};')
  else:
   rhs=core if pad==bits else f'({pad-1} downto {bits} => \'0\') & {core}'
   assign.append(f'  {wname} <= {rhs};')
head=['library ieee;','use ieee.std_logic_1164.all;','','-- Transparent wiring only. The separately delivered sync_ota_top is the algorithm core.','-- Multiword vectors use w0 = least-significant 64 bits; unused output bits are zero.','entity sync_ota_wrapper is','  port (']
head += ['    '+p['name']+' : '+('in' if p['direction']=='input' else 'out')+' '+typ(p['width'])+(';' if i<len(wrapper)-1 else '') for i,p in enumerate(wrapper)]
head += ['  );','end entity;','','architecture rtl of sync_ota_wrapper is','  component sync_ota_top is','    port (']
head += ['      '+p['name']+' : '+('in' if p['direction']=='input' else 'out')+' '+typ(p['width'])+(';' if i<len(ports)-1 else '') for i,p in enumerate(ports)]
head += ['    );','  end component;']
head += ['  signal core_'+p['name']+' : '+typ(p['width'])+';' for p in ports]
head += ['begin']+assign+['  algorithm : sync_ota_top','    port map (']
head += ['      '+p['name']+' => core_'+p['name']+(',' if i<len(ports)-1 else '') for i,p in enumerate(ports)]
head += ['    );','end architecture;','']
(root/'wrapper/sync_ota_wrapper.vhd').write_text('\n'.join(head),encoding='utf-8')
(root/'docs/CORE_WRAPPER_PORT_MAP.json').write_text(json.dumps(dict(core='sync_ota_top',wrapper='sync_ota_wrapper',ports=ports),indent=2),encoding='utf-8')
with (root/'docs/WRAPPER_PORTS.csv').open('w',newline='',encoding='utf-8-sig') as f:
 w=csv.DictWriter(f,fieldnames=['name','direction','width','core','hi','lo']);w.writeheader();w.writerows(wrapper)
print('WRAPPER_GENERATED',len(ports),'core ports',len(wrapper),'wrapper ports')
