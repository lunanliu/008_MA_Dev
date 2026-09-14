from pathlib import Path
R=Path('D:/008_MA_Dev/T11_CFO')
p=R/'sim/tb/cfo_estimator_link_tb.sv';s=p.read_text();s=s.replace('integer completed=0','integer output_fires=0;\n integer completed=0')
s=s.replace('sc=sc+1;#0.010;','''if(!rb && !reset_async && !abort_async)begin
   if(output_held && (!m_valid || result_word!==held_result))$fatal(1,"Held result changed at retirement edge");
   if(m_valid && m_ready)begin
    if(!active || result_word!==expected_result() || output_fires!=0)$fatal(1,"Invalid or duplicate output retirement");
    output_fires=output_fires+1;$fdisplay(fd,"H %0d %0d %0133h",rid,ci,result_word);
   end
  end
  sc=sc+1;#0.010;''')
s=s.replace('nw=0;nr=0;source_stalls=0;','nw=0;nr=0;output_fires=0;source_stalls=0;')
s=s.replace('completed=completed+1;if(t>max_tail)','if(t>max_tail)').replace('errors=errors+1;','')
s=s.replace('m_ready=1;@(negedge clk_slow);m_ready=0;active=0;output_held=0;','m_ready=1;@(negedge clk_slow);m_ready=0;\n   if(output_fires!=1)$fatal(1,"Result was not retired");\n   if(kind==0)completed=completed+1;else errors=errors+1;\n   active=0;output_held=0;')
p.write_text(s)
p=R/'tools/verify_link010.py';s=p.read_text().replace("['W','R','F','E','D']","['W','R','F','E','D','H']").replace("{'W':0,'R':0,'ended':False}","{'W':0,'R':0,'ended':False,'terminal':False}")
s=s.replace("if tag in ['W','R']:\n    n=", "if tag in ['W','R']:\n    assert not r['terminal'],line\n    n=")
s=s.replace("full_runs+=full;r['ended']=True","full_runs+=full;r['terminal']=True").replace("int(it[7])==5+rid%4,line;r['ended']=True","int(it[7])==5+rid%4,line;r['terminal']=True")
s=s.replace("   else:\n    assert end==tag", "   elif tag=='H':\n    assert end in ['E','F'] and r['terminal'] and len(it)==4 and int(it[3],16)==source['result_word'],line;r['ended']=True\n   else:\n    assert end==tag")
s=s.replace("counts['F']==22 and counts['E']==10", "counts['H']==32 and counts['F']==22 and counts['E']==10")
p.write_text(s)