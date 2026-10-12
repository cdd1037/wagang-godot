"""Is any mod code in wagan.wa's .text2 outside the audited entry points? (docs/mod_patches.md, "Coverage of the mod code")
Recursive descent over .text2 from the audit's entry points: the rel32 hooks from .text (minus the audit's FALSE sites),
the script-op table 0x410a3e, the mod code in gaps of .text, push/mov immediates in .text, and the jump tables the
original code indexes with a .text2 base. It follows jmp/jcc/call, `jmp/call [reg*4 + T]` tables, and push/mov of a
.text2 function or code-pointer table. GHIDRA_LIST (from tools/ghidra/modcov.sh) adds Ghidra's reached instructions.
Prints every range of non-padding .text2 bytes that neither reaches, with each reference into it (or up to 0x40 below
it, for base + index tables) from a live instruction, from .text or from data.
usage: modcov.py [GHIDRA_LIST]     modcov.py --seeds   (comma list of entry points, for the Ghidra script)"""
import os as _os
import sys, struct, re
sys.path.append(_os.path.dirname(_os.path.abspath(__file__)))
from pe import PE
p = PE()
T2, T2E = 0x4d0000, 0x554e00
TX, TXE = 0x401000, 0x486000
GAPS = [(0x401118, 0x401400), (0x406b4f, 0x406b80), (0x407600, 0x407700), (0x407bc8, 0x407c10), (0x40913d, 0x409160),
        (0x427025, 0x427070), (0x42beae, 0x42bf00), (0x433359, 0x433420), (0x4364b6, 0x436510), (0x43d108, 0x43d140)]
FALSE = {0x40910e, 0x409ead, 0x409ed5, 0x419ddd, 0x419eb9, 0x41b020, 0x41f553, 0x44c257, 0x44da82, 0x474b24, 0x474b80}
PAD = (0, 0x90, 0xcc)
def ok(va): return T2 <= va < T2E or any(a <= va < b for a, b in GAPS)
def looks_func(a): return p.read(a, 3) == b'\x55\x8b\xec'
t = p.read(TX, TXE - TX)

seeds, hooks = set(), set()
for i in range(len(t) - 5):
    if t[i] in (0xe8, 0xe9) and TX + i not in FALSE:
        d = TX + i + 5 + struct.unpack_from('<i', t, i + 1)[0]
        if T2 <= d < T2E: seeds.add(d); hooks.add(TX + i)
for i in range(0x7c):                                       # script-op handlers
    v = p.u32(0x410a3e + 4 * i)
    if T2 <= v < T2E: seeds.add(v)
seeds |= {a for a, b in GAPS} | {p.u32(0x45bcc8)}           # gap code, the 绝招 jump-table entry
for i in range(1, len(t) - 4):                              # push imm32 / mov reg, imm32 of a .text2 function
    d = struct.unpack_from('<I', t, i)[0]                   # (all 8 in the shipped exe are data addresses)
    if T2 <= d < T2E and (t[i - 1] == 0x68 or 0xb8 <= t[i - 1] <= 0xbf) and looks_func(d): seeds.add(d)
for i in range(len(t) - 7):                                 # jmp/call [reg*4 + T] with T in .text2
    if t[i] == 0xff and t[i + 1] in (0x24, 0x14) and t[i + 2] & 0xc7 == 0x85:
        tb = struct.unpack_from('<I', t, i + 3)[0]; k = 0
        while T2 <= tb < T2E and (T2 <= p.u32(tb + 4 * k) < T2E or TX <= p.u32(tb + 4 * k) < TXE):
            if T2 <= p.u32(tb + 4 * k) < T2E: seeds.add(p.u32(tb + 4 * k))
            k += 1
if sys.argv[1:] == ['--seeds']:
    print(','.join('%x' % a for a in sorted(seeds | hooks))); sys.exit()

starts, live, pending = set(), set(), list(seeds)
while pending:
    va = pending.pop()
    while ok(va) and va not in starts:
        b = p.read(va, 16)
        ins = next(p.md.disasm(b, va), None)
        if ins is None or b[:2] == b'\0\0': break
        starts.add(va); live.update(range(va, va + ins.size))
        m, o = ins.mnemonic.replace('notrack ', ''), ins.op_str
        mt = re.search(r'dword ptr (?:ds:)?\[e\w\w\*4 \+ 0x([0-9a-f]+)\]', o)
        if m in ('jmp', 'call') and mt:
            tb = int(mt[1], 16); k = 0
            while T2 <= p.u32(tb + 4 * k) < T2E or TX <= p.u32(tb + 4 * k) < TXE:
                if ok(p.u32(tb + 4 * k)): pending.append(p.u32(tb + 4 * k))
                k += 1
        elif m in ('push', 'mov') and re.search(r'(?:^|, )0x[0-9a-f]{6}$', o):
            a = int(o[-8:], 16)
            if T2 <= a < T2E:
                if looks_func(a): pending.append(a)
                elif T2 <= p.u32(a) < T2E and T2 <= p.u32(a + 4) < T2E:      # a table of code pointers
                    k = 0
                    while T2 <= p.u32(a + 4 * k) < T2E: pending.append(p.u32(a + 4 * k)); k += 1
        elif (m == 'call' or m.startswith('j')) and re.fullmatch(r'0x[0-9a-f]+', o):
            if ok(int(o, 16)): pending.append(int(o, 16))
        if m in ('ret', 'jmp', 'int3', 'hlt', 'retf'): break
        va += ins.size
cap = sum(1 for a in live if T2 <= a < T2E and p.read(a, 1)[0] not in PAD)
if len(sys.argv) > 1:
    for l in open(sys.argv[1]):
        a, n = l.split(); a = int(a, 16); starts.add(a); live.update(range(a, a + int(n)))

raw = p.read(T2, T2E - T2)
total = sum(1 for c in raw if c not in PAD)
got = sum(1 for a in live if T2 <= a < T2E and raw[a - T2] not in PAD)
print('.text2: %d non-padding bytes; reached as instructions: %d by this descent%s'
      % (total, cap, ', %d with Ghidra' % got if len(sys.argv) > 1 else ' (no Ghidra list given)'))
regs = []; s = e = None
for i, c in enumerate(raw):
    if c not in PAD and T2 + i not in live:
        if s is not None and T2 + i - e <= 8: e = T2 + i
        else:
            if s is not None: regs.append((s, e))
            s = e = T2 + i
if s is not None: regs.append((s, e))
secs = [(v, p.data[ro:ro + rs], n) for v, vs, ro, rs, n in p.secs]
def refs(lo, hi):
    out = []
    for v, seg, n in secs:
        intext = 'text' in n
        for i in range(len(seg) - 4):
            a = v + i
            if lo <= a <= hi: continue
            d = struct.unpack_from('<I', seg, i)[0]
            if lo - 0x40 <= d <= hi:
                where = '.text' if TX <= a < TXE else '.text2' if T2 <= a < T2E else n.split('\0')[0]
                op = next((b for b in range(a - 1, a - 8, -1) if b in starts), None) if T2 <= a < T2E else None
                out.append('dword %x in %s%s%s' % (a, where, ' (operand of live insn %x)' % op if op else '',
                                                   '' if d >= lo else ' [base %x]' % d))
            if intext:
                b = seg[i]; tg = None
                if b in (0xe8, 0xe9) and i + 5 <= len(seg): tg = a + 5 + struct.unpack_from('<i', seg, i + 1)[0]
                elif b == 0x0f and i + 6 <= len(seg) and 0x80 <= seg[i + 1] <= 0x8f: tg = a + 6 + struct.unpack_from('<i', seg, i + 2)[0]
                elif 0x70 <= b <= 0x7f or b == 0xeb: tg = a + 2 + struct.unpack_from('<b', seg, i + 1)[0]
                if tg is not None and lo <= tg <= hi:
                    if TX <= a < TXE: out.append('branch %x from .text%s' % (a, ' (FALSE site)' if a in FALSE else ''))
                    elif a in starts: out.append('branch %x LIVE' % a)
    return out
left = 0
for lo, hi in regs:
    nz = sum(1 for a in range(lo, hi + 1) if raw[a - T2] not in PAD); left += nz
    print('%x..%x %4d | %s' % (lo, hi, nz, '; '.join(refs(lo, hi)) or '-'))
print('%d ranges, %d bytes not reached' % (len(regs), left))
