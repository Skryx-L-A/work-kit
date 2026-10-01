#!/usr/bin/env python3
"""Stdlib-only, restartable downloader for kit/offline/SOURCES.lock."""
from __future__ import annotations
import concurrent.futures as cf, hashlib, html.parser, os, re, shutil, signal, ssl, sys, time
from pathlib import Path
from urllib.request import Request, build_opener, ProxyHandler, HTTPSHandler
from urllib.error import URLError, HTTPError

HERE=Path(__file__).resolve().parent
# Public tree: setup/ sits next to kit/. Source repository: stick/setup/ is one level deeper.
ROOT=Path(os.environ.get("KIT_ROOT") or next((p for p in (HERE.parent, HERE.parent.parent) if (p/"kit").is_dir()), HERE.parent))
LOCK=Path(os.environ.get("SOURCES_LOCK", ROOT/"kit/offline/SOURCES.lock"))
OUT=Path(os.environ.get("KIT_OFFLINE", ROOT/"kit/offline"))
CHUNK=int(os.getenv('WORK_KIT_PART_BYTES', str(1900*1024*1024)))
STOP=False
def stop(*_):
 global STOP; STOP=True
signal.signal(signal.SIGINT,stop); signal.signal(signal.SIGTERM,stop)

def parse():
 tag="offline-2026-10-01"; rows=[]
 for line in LOCK.read_text().splitlines():
  if line.startswith("#"):
   m=re.search(r"release-tag:\s*(\S+)",line); tag=m.group(1) if m else tag; continue
  a=line.split("\t",5)
  if len(a)==6: rows.append(dict(sha=a[0],size=int(a[1]),path=a[2],mode=int(a[3],8),license=a[4],source=a[5]))
 return tag,rows
def hashok(p,row):
 if not p.is_file() or p.stat().st_size != row['size']: return False
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
 return h.hexdigest()==row['sha']
def opener():
 ctx=ssl.create_default_context(cafile=os.getenv("SSL_CERT_FILE") or None)
 ca=ROOT/"kit/modules/35-company-network/ca-bundle.pem"
 if not os.getenv("SSL_CERT_FILE") and ca.exists(): ctx.load_verify_locations(cafile=ca)
 proxies={k[:-6].lower():v for k,v in os.environ.items() if k.lower() in ('http_proxy','https_proxy')}
 return build_opener(ProxyHandler(proxies),HTTPSHandler(context=ctx))
OPENER=opener()
class Links(html.parser.HTMLParser):
 def __init__(self): super().__init__(); self.links=[]
 def handle_starttag(self,t,a):
  if t=='a': self.links += [v for k,v in a if k=='href']
def pypi_url(url,name):
 if '/simple/' not in url: return url
 with OPENER.open(Request(url,headers={'User-Agent':'work-kit-fetch'}),timeout=30) as r: data=r.read().decode('utf8','replace')
 x=Links(); x.feed(data)
 for u in x.links:
  if u.split('#',1)[0].rsplit('/',1)[-1]==name: return u
 raise RuntimeError('publisher index has no '+name)
def get(url,dest,expected, total):
 dest.parent.mkdir(parents=True,exist_ok=True); part=Path(str(dest)+'.part')
 for attempt in range(4):
  if STOP: raise KeyboardInterrupt
  try:
   url=pypi_url(url,dest.name); start=part.stat().st_size if part.exists() else 0
   req=Request(url,headers={'Range':f'bytes={start}-','User-Agent':'work-kit-fetch'}) if start else Request(url,headers={'User-Agent':'work-kit-fetch'})
   with OPENER.open(req,timeout=60) as src:
    # A server ignoring Range must not append its complete response.
    if start and src.status != 206: part.unlink(missing_ok=True); return get(url,dest,expected,total)
    with part.open('ab' if start else 'wb') as f:
     while True:
      if STOP: raise KeyboardInterrupt
      b=src.read(1024*1024)
      if not b: break
      f.write(b)
   valid = part.stat().st_size == total and (not expected or hashok(part, {'size':total,'sha':expected}))
   if valid: part.replace(dest); return
   part.unlink(missing_ok=True); raise RuntimeError('sha256 mismatch')
  except KeyboardInterrupt: raise
  except Exception:
   if attempt==3: raise
   time.sleep(2**attempt)
def asset_name(path):
 # GitHub release assets are flat and drop some characters: build/release-upload.sh uses the same mapping.
 return path.replace('/','__').replace('+','-plus-')
def source_url(tag,row,part=None):
 if row['source']=='release':
  name=asset_name(row['path']) if part is None else f"{asset_name(row['path'])}.part-{part:02d}"
  base=os.getenv('WORK_KIT_RELEASE_BASE','https://github.com/Skryx-L-A/work-kit/releases/download')
  return f'{base.rstrip("/")}/{tag}/{name}'
 return re.search(r'<([^>]+)>',row['source']).group(1)
def fetch(tag,row):
 dest=OUT/row['path']
 if hashok(dest,row): os.chmod(dest,row['mode']); return 'skip'
 if row['source']=='release' and row['size']>CHUNK:
  parts=[]; left=row['size']; n=1
  while left:
   sz=min(CHUNK,left); p=Path(str(dest)+f'.part-{n:02d}'); get(source_url(tag,row,n),p,'',sz) if not p.exists() or p.stat().st_size!=sz else None; parts.append(p); left-=sz; n+=1
  with Path(str(dest)+'.part').open('wb') as w:
   for p in parts:
    with p.open('rb') as r: shutil.copyfileobj(r,w,1024*1024)
  for p in parts:p.unlink()
  if hashok(Path(str(dest)+'.part'),row): Path(str(dest)+'.part').replace(dest); os.chmod(dest,row['mode']); return 'done'
  Path(str(dest)+'.part').unlink(missing_ok=True); raise RuntimeError('sha256 mismatch after part reassembly')
 get(source_url(tag,row),dest,row['sha'],row['size']); os.chmod(dest,row['mode']); return 'done'
def main():
 tag,rows=parse(); need=sum(r['size'] for r in rows if not hashok(OUT/r['path'],r)); free=shutil.disk_usage(OUT.parent if OUT.parent.exists() else ROOT).free
 margin=2*1024**3
 if free < need+margin: raise SystemExit(f'Not enough disk space: need {(need+margin)//1048576} MB including margin; free {free//1048576} MB.')
 total=sum(r['size'] for r in rows); done=sum(r['size'] for r in rows if hashok(OUT/r['path'],r)); errors=[]
 print(f'Fetching {len(rows)} files ({total//1048576} MB) into {OUT} ...')
 with cf.ThreadPoolExecutor(max_workers=4) as ex:
  fs={ex.submit(fetch,tag,r):r for r in rows}
  for f in cf.as_completed(fs):
   r=fs[f]
   try:
    if f.result()=='skip': continue  # already counted in done
    done+=r['size']; print(f'{done//1048576} / {total//1048576} MB ({done*100//max(total,1)}%) {r["path"][:42]}')
   except KeyboardInterrupt: raise
   except Exception as e: errors.append((r,str(e)))
 if STOP: raise KeyboardInterrupt
 if errors:
  print('Failed files:',file=sys.stderr)
  for r,e in errors: print(f'  {r["path"]}: {e}; {source_url(tag,r)}',file=sys.stderr)
  raise SystemExit(1)
 sums=OUT/'SHA256SUMS'
 if not sums.exists(): raise SystemExit('SHA256SUMS is missing after fetch')
 bad=[]
 for line in sums.read_text().splitlines():
  a=line.split(maxsplit=1)
  if len(a)==2 and not hashok(OUT/a[1].lstrip('*'),{'size':(OUT/a[1].lstrip('*')).stat().st_size if (OUT/a[1].lstrip('*')).exists() else -1,'sha':a[0]}): bad.append(a[1])
 if bad: raise SystemExit('SHA256SUMS verification failed: '+', '.join(bad))
 print('Offline set verified. Next: bash setup/install-kit.sh')
if __name__=='__main__':
 try: main()
 except KeyboardInterrupt: print('\nStopped. Run again to continue.',file=sys.stderr); raise SystemExit(130)
