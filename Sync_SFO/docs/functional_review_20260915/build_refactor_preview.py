from pathlib import Path
import json,re,subprocess,collections,concurrent.futures,hashlib
M=Path('D:/008_MA_Dev/Sync_SFO');A=M/'docs/functional_review_20260915';B=A/'baseline_files';V=M/'work/functional_review_tools_20260915/package/verible-v0.0-4214-gce503962-win64';P=M/'work/functional_refactor_preview_20260915';P.mkdir(exist_ok=False)
plan=json.loads((A/'rename_plan.json').read_text());ids=plan['identifiers'];scoped=plan['instance_scopes'];instrows=plan['instances'];types={}
for r in instrows:
 types.setdefault(r['module'],{})[r['instance']]=r['type']

def parse(raw,key,tree=True):
 p=P/'parser_input'/key;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
 args=[str(V/'verible-verilog-syntax.exe'),'--export_json','--printtokens']
 if tree:args+=['--printtree']
 r=subprocess.run([*args,str(p)],capture_output=True)
 if r.returncode:raise RuntimeError(key+': '+r.stderr.decode(errors='replace')+' '+r.stdout.decode(errors='replace')[:1000])
 return next(iter(json.loads(r.stdout).values()))
def nodes(n):
 if isinstance(n,dict):
  yield n
  for c in n.get('children',[]):yield from nodes(c)
def leaves(n):return [x for x in nodes(n) if 'start'in x]
def texttok(t,raw):return raw[t['start']:t['end']].decode('utf-8')
def modules(d):
 out=[]
 for m in nodes(d['tree']):
  if m.get('tag')!='kModuleDeclaration':continue
  head=next(n for n in nodes(m) if n.get('tag')=='kModuleHeader');ll=leaves(m);out.append((head['children'][2]['text'],min(t['start'] for t in ll),max(t['end'] for t in ll),head))
 return out
cached={r['path']:next(iter(json.loads(Path(r['json']).read_text()).values())) for r in json.loads((A/'baseline_parser_results.json').read_text())}
all_words=set()
for d in cached.values():all_words.update(t.get('text','').lstrip('`') for t in d['tokens'])
# Global inverse maps must not reinterpret an unrelated old identifier.
for old,new in list(ids.items()):
 if new in all_words and new not in ids:ids[old]='sfo_named_'+new
for mod,mp in scoped.items():
 for old,new in list(mp.items()):
  if new in all_words or new in ids.values():mp[old]='u_sfo_'+new
flat_inst={new:old for mp in scoped.values() for old,new in mp.items()}
assert len(flat_inst)==sum(len(mp) for mp in scoped.values())
reverse={v:k for k,v in ids.items()};assert len(reverse)==len(ids);reverse.update(flat_inst)
file_literals={Path(k).name:Path(v).name for k,v in plan['paths'].items()};reverse_literals={v:k for k,v in file_literals.items()}
def rename_word(word):
 if word.startswith('`') and word[1:] in ids:return '`'+ids[word[1:]]
 return ids.get(word,word)
def restore_word(word):
 if word.startswith('`') and word[1:] in reverse:return '`'+reverse[word[1:]]
 word=reverse.get(word,word)
 if word.startswith('"'):
  for a,b in reverse_literals.items():word=word.replace(a,b)
 return word

def port_info(d,raw):
 result={};insertions={};records=[]
 for mod,start,end,head in modules(d):
  lists=[n for n in nodes(head) if n.get('tag')=='kPortDeclarationList'];ports=[];previous=None
  if not lists:result[mod]=ports;continue
  for n in lists[0].get('children',[]):
   if not isinstance(n,dict) or n.get('tag') not in ('kPortDeclaration','kPort'):continue
   if n['tag']=='kPortDeclaration':
    ident=next(x for x in leaves(n['children'][3]) if x.get('tag')=='SymbolIdentifier')
    beginning=min(x['start'] for x in leaves(n));prefix=raw[beginning:ident['start']]
    if b'(*' in prefix:raise RuntimeError('Port attribute requires manual review')
    pt=[texttok(t,raw) for t in d['tokens'] if beginning<=t['start'] and t['end']<=ident['start']];previous=(prefix,pt)
   else:
    ident=next(x for x in leaves(n) if x.get('tag')=='SymbolIdentifier');assert previous is not None
    prefix,pt=previous;insertions[ident['start']]=prefix;records.append({'module':mod,'port':ident['text'],'prefix':prefix.decode()})
   tail=[texttok(t,raw) for t in d['tokens'] if ident['end']<=t['start'] and t['end']<=max(x['end'] for x in leaves(n))]
   ports.append([ident['text'],pt,tail])
  result[mod]=ports
 return result,insertions,records

def rewrite(rel,raw,d):
 original_ports,inserts,expanded=port_info(d,raw);replacements={}
 for t in d['tokens']:
  old=texttok(t,raw);new=rename_word(old)
  if old.startswith('"'):
   for a,b in file_literals.items():new=new.replace(a,b)
  if new!=old:replacements[t['start']]=(t['end'],new.encode())
 for r in instrows:
  if r['file']==rel and r['instance'] in scoped.get(r['module'],{}):
   replacements[r['start']]=(r['end'],scoped[r['module']][r['instance']].encode())
 # Resolve actual dotted references through the unchanged instance/type graph.
 for mod,start,end,head in modules(d):
  ts=[t for t in d['tokens'] if start<=t['start']<end];words=[texttok(t,raw) for t in ts]
  for i,t in enumerate(ts):
   word=words[i]
   if not re.fullmatch(r'[A-Za-z_][\w$]*',word) or (i and words[i-1]=='.'):continue
   context=mod;j=i
   if word in types.get(context,{}):
    if word in scoped.get(context,{}):replacements[t['start']]=(t['end'],scoped[context][word].encode())
    context=types[context][word]
   elif word in types:context=word
   else:continue
   while j+1<len(ts):
    j+=1
    if words[j]=='[':
     depth=1
     while depth and j+1<len(ts):
      j+=1;depth+=int(words[j]=='[')-int(words[j]==']')
     if j+1>=len(ts):break
     j+=1
    if words[j]!='.' or j+1>=len(ts):break
    j+=1;part=words[j]
    if part in types.get(context,{}):
     if part in scoped.get(context,{}):replacements[ts[j]['start']]=(ts[j]['end'],scoped[context][part].encode())
     context=types[context][part]
 # Pure expansion baseline is the canonical token oracle; inserted qualifiers duplicate inherited types.
 expanded_raw=raw
 for pos,prefix in sorted(inserts.items(),reverse=True):expanded_raw=expanded_raw[:pos]+prefix+expanded_raw[pos:]
 out=bytearray();cursor=0
 for pos in sorted(set(inserts)|set(replacements)):
  assert pos>=cursor,(rel,pos,cursor);out+=raw[cursor:pos]
  if pos in inserts:
   prefix=inserts[pos].decode();prefix=re.sub(r'\b[A-Za-z_][A-Za-z_0-9$]*\b',lambda m:ids.get(m[0],m[0]),prefix);out+=prefix.encode()
  if pos in replacements:end,new=replacements[pos];out+=new;cursor=end
  else:cursor=pos
 out+=raw[cursor:]
 return bytes(out),expanded_raw,original_ports,expanded

def normalized_tokens(d,raw,restore=False):
 return [restore_word(texttok(t,raw)) if restore else texttok(t,raw) for t in d['tokens'] if t.get('tag')!='TK_EOF']
def canonical_tree(n,raw,restore=False):
 if n is None:return None
 if 'start'in n:return (n['tag'],restore_word(texttok(n,raw)) if restore else texttok(n,raw))
 return (n.get('tag'),tuple(canonical_tree(c,raw,restore) for c in n.get('children',[])))
def process(rel):
 raw=(B/rel).read_bytes();d=cached.get(rel) or parse(raw,'baseline/'+rel);renamed,expanded,ports,exp_records=rewrite(rel,raw,d)
 new=plan['paths'][rel];draft=P/'unformatted'/new;draft.parent.mkdir(parents=True,exist_ok=True);draft.write_bytes(renamed)
 fmt=subprocess.run([str(V/'verible-verilog-format.exe'),'--column_limit=100','--indentation_spaces=2','--port_declarations_alignment=align','--named_port_alignment=align','--try_wrap_long_lines=true','--failsafe_success=false',str(draft)],capture_output=True)
 if fmt.returncode:raise RuntimeError('Formatter '+rel+': '+fmt.stderr.decode(errors='replace'))
 formatted=fmt.stdout;target=P/'ready'/new;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(formatted)
 nd=parse(formatted,'formatted/'+new);ed=parse(expanded,'expanded/'+rel)
 assert normalized_tokens(ed,expanded)==normalized_tokens(nd,formatted,True),'Inverse token mismatch '+rel
 assert canonical_tree(ed['tree'],expanded)==canonical_tree(nd['tree'],formatted,True),'Inverse structure mismatch '+rel
 np,_,_=port_info(nd,formatted);canonical={reverse.get(mod,mod):[[reverse.get(name,name),[restore_word(x) for x in pt],[restore_word(x) for x in tail]] for name,pt,tail in ps] for mod,ps in np.items()}
 assert ports==canonical,'Port descriptor mismatch '+rel
 return {'old':rel,'new':new,'before_sha256':hashlib.sha256(raw).hexdigest(),'after_sha256':hashlib.sha256(formatted).hexdigest(),'inverse_tokens_equal':True,'inverse_tree_equal':True,'ports_equal':True,'expanded_ports':exp_records,'lines_before':len(raw.splitlines()),'lines_after':len(formatted.splitlines()),'max_line_after':max(map(len,formatted.splitlines()),default=0),'formatter_stderr':fmt.stderr.decode(errors='replace')}
sv=[k for k in plan['paths'] if Path(k).suffix in ('.sv','.svh')];results=[];failures=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
 fs={pool.submit(process,p):p for p in sv}
 for f in concurrent.futures.as_completed(fs):
  try:results.append(f.result())
  except Exception as e:failures.append({'file':fs[f],'error':str(e)})
plan['identifiers']=ids;plan['instance_scopes']=scoped
for row in plan['instances']:row['new_instance']=scoped.get(row['module'],{}).get(row['instance'],row['instance']);row['new_type']=ids.get(row['type'],row['type'])
(A/'rename_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
summary={'status':'PASS' if not failures else 'FAIL','source_count':len(sv),'passed':len(results),'failures':failures,'files':sorted(results,key=lambda r:r['old']),'expanded_inherited_ports':sum(len(r['expanded_ports']) for r in results),'preview_root':str(P),'baseline_mutated':False}
(A/'preview_equivalence.json').write_text(json.dumps(summary,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in summary.items() if k!='files'}));assert not failures
