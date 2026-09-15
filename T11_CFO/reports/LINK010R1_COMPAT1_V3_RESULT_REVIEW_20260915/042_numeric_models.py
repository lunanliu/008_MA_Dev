"""Read-only exact two-edit proof for private simulation XPM; no native startup."""
from pathlib import Path
import hashlib,json,re
R=Path(__file__).resolve().parents[1]
EXPECTED={'xpm_cdc':'D08434ED5A310C44C13936D6EDA5381D64FF0F627A335368C85826A30E8ADAA7','xpm_fifo':'D3C1E861CDDF00EBC82552C464A46FB5228E68B4D458001D064B99E04134B9D4','xpm_memory':'E72758E6794B1F7AD00428FEEEACC4F90A38B0500583B2CA93CA2EBA12BA01BD'}
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def run():
 rows=[]
 for name,h in EXPECTED.items():
  src=Path(f'C:/NIFPGA/programs/Vivado2021_1/data/ip/xpm/{name}/hdl/{name}.sv');dst=R/f'sim/vendor/link010r1/{name}.sv'
  a=src.read_bytes();b=dst.read_bytes();assert sha(a)==h,(name,'official changed')
  expected=a
  if name=='xpm_fifo':
   edits=[(b"($rose(rd_rst_busy) || (empty && $rose(rd_rst_busy))) |-> ##1 $rose(empty))",b"($rose(rd_rst_busy) || (empty && $rose(rd_rst_busy))) |-> ##1 (empty === 1'b1))"),(b'if (SIM_ASSERT_CHK == 1) begin : sleep_chk',b'if (SIM_ASSERT_CHK == 1 && WAKEUP_TIME > 0) begin : sleep_chk')]
   for old,new in edits:
    assert expected.count(old)==1
    pos=expected.index(old)
    assert expected.rfind(b'// synthesis translate_off',0,pos)>expected.rfind(b'// synthesis translate_on',0,pos)
    expected=expected.replace(old,new)
  assert b==expected,(name,'unexpected private edit')
  strip=lambda x:re.sub(rb'// synthesis translate_off.*?// synthesis translate_on',b'',x,flags=re.S)
  assert strip(a)==strip(b),(name,'synthesized behavior changed')
  rows.append({'name':name,'official_sha256':h,'private_sha256':sha(b),'exact_byte_copy':a==b,'outside_translate_off_identical':True})
 return {'status':'PRIVATE_XPM_EXACT_PATCH_PASS','native_started':False,'files':rows,'global_installation_modified':False,'global_assertion_disable_used':False}
if __name__=='__main__':print(json.dumps(run()))
