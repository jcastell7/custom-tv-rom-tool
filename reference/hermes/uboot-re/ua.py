"""Small helpers for reading firmware/boot-package/u-boot.bin with capstone (Thumb-2, linked at 0x4a000000)."""
import os,re,struct,capstone as C
U=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','firmware','boot-package','u-boot.bin')
BASE=0x4a000000
d=open(U,'rb').read()
md=C.Cs(C.CS_ARCH_ARM,C.CS_MODE_THUMB); md.skipdata=True
def cstr(a):
    o=a-BASE
    if not(0<=o<len(d)): return None
    e=d.find(b'\0',o,o+160)
    if e<=o: return None
    s=d[o:e]
    return s.decode() if all(32<=c<127 or c in(9,10,13) for c in s) and len(s)>=3 else None
def xrefs(t): return [BASE+o for o in range(0,len(d)-3,4) if struct.unpack_from('<I',d,o)[0]==t]
def strs(sub):
    o=-1;r=[];b=sub.encode()
    while True:
        o=d.find(b,o+1)
        if o<0:return r
        r.append(BASE+o)
def dis(a,n=120):
    o=a-BASE
    yield from md.disasm(d[o:o+n*4],a,n)
def ann(i):
    t=i.op_str;x=''
    m=re.search(r'\[pc, #(-?0x[0-9a-f]+|-?\d+)\]',t)
    if i.mnemonic.startswith('ldr') and m:
        la=((i.address+4)&~3)+int(m.group(1),0);o=la-BASE
        if 0<=o<len(d)-3:
            v=struct.unpack_from('<I',d,o)[0];s=cstr(v);x=f' ; ={v:#x}'+(f' "{s}"' if s else '')
    return f'{i.address:08x}  {i.mnemonic:8s} {t}{x}'
def rng(a,n):
    for i in dis(a,n): print(ann(i))
def fnstart(a):
    o=(a-BASE)&~1
    while o>0:
        o-=2;h=struct.unpack_from('<H',d,o)[0]
        if (h&0xff00)==0xb500 and h&0xff: return BASE+o
        if h==0xe92d and (struct.unpack_from('<H',d,o+2)[0]&0x4000): return BASE+o
    return BASE
def bl_callers(t):
    r=[]
    for o in range(0,len(d)-4,2):
        a,b=struct.unpack_from('<HH',d,o)
        if (a&0xF800)==0xF000 and (b&0xD000)==0xD000:
            S=(a>>10)&1;J1=(b>>13)&1;J2=(b>>11)&1
            off=(S<<24)|((1-(J1^S))<<23)|((1-(J2^S))<<22)|((a&0x3ff)<<12)|((b&0x7ff)<<1)
            if S:off-=1<<25
            if BASE+o+4+off==t:r.append(BASE+o)
    return r
