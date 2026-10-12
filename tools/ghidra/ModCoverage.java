// Ghidra headless post-script for tools/ghidra/modcov.sh: which mod code in .text2 (0x4d0000..0x554dff) is reachable?
// First disassembles the audit's entry points that the auto-analysis missed (seeds). Nodes are the functions in
// .text2, the runs of instructions outside any function, and the data between them (split at referenced addresses).
// A node is a root when something outside .text2 refers into it; edges are Ghidra's references plus raw dword
// pointers from .text2 data into code. Writes a summary with the unreached code nodes to <out_file> and the reached
// instructions ("addr length" per line) to <out_file>.reached, the input of tools/modcov.py.
// args: <out_file> <seeds: comma-separated hex> [addresses to describe: comma-separated hex]
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.mem.*;
import java.io.*;
import java.util.*;

public class ModCoverage extends GhidraScript {
    Address lo, hi;
    boolean inT2(Address a) { return a.compareTo(lo) >= 0 && a.compareTo(hi) <= 0; }

    @Override
    public void run() throws Exception {
        PrintWriter out = new PrintWriter(new FileWriter(getScriptArgs()[0]));
        lo = toAddr(0x4d0000L); hi = toAddr(0x554dffL);
        Listing lst = currentProgram.getListing();
        ReferenceManager rm = currentProgram.getReferenceManager();
        FunctionManager fm = currentProgram.getFunctionManager();
        Memory mem = currentProgram.getMemory();

        // the entry points the auto-analysis missed (the script-op table, hook sites, gap code): modcov.py --seeds
        for (String x : getScriptArgs()[1].split(",")) {
            Address a = toAddr(Long.parseLong(x, 16));
            if (lst.getInstructionContaining(a) == null && lst.getDefinedDataContaining(a) == null) {
                boolean ok = disassemble(a);
                if (inT2(a) && ok && fm.getFunctionContaining(a) == null) createFunction(a, null);
            }
        }
        // nodes
        List<AddressSetView> bodies = new ArrayList<>();
        List<String> names = new ArrayList<>();
        AddressSet inFunc = new AddressSet();
        for (Function f : fm.getFunctions(new AddressSet(lo, hi), true)) {
            bodies.add(f.getBody()); names.add("func " + f.getEntryPoint());
            inFunc.add(f.getBody());
        }
        // orphan instruction runs
        Address runStart = null, runEnd = null;
        InstructionIterator it = lst.getInstructions(new AddressSet(lo, hi), true);
        while (it.hasNext()) {
            Instruction ins = it.next();
            if (inFunc.contains(ins.getMinAddress())) continue;
            if (runStart != null && ins.getMinAddress().subtract(runEnd) <= 1) { runEnd = ins.getMaxAddress(); continue; }
            if (runStart != null) { bodies.add(new AddressSet(runStart, runEnd)); names.add("orphan " + runStart); }
            runStart = ins.getMinAddress(); runEnd = ins.getMaxAddress();
        }
        if (runStart != null) { bodies.add(new AddressSet(runStart, runEnd)); names.add("orphan " + runStart); }

        int nCode = bodies.size();
        AddressSet codeSet = new AddressSet();
        for (AddressSetView b : bodies) codeSet.add(b);
        // data nodes: the rest of .text2, split where something refers to an address and at code boundaries
        Address ds = null, de = null;
        for (Address a = lo; a.compareTo(hi) <= 0; a = a.add(1)) {
            boolean code = codeSet.contains(a);
            boolean split = code || rm.hasReferencesTo(a);
            if (split && ds != null) { bodies.add(new AddressSet(ds, de)); names.add("data " + ds); ds = null; }
            if (!code) { if (ds == null) ds = a; de = a; }
        }
        if (ds != null) { bodies.add(new AddressSet(ds, de)); names.add("data " + ds); }
        int n = bodies.size();
        TreeMap<Long, Integer> starts = new TreeMap<>();
        for (int i = 0; i < n; i++)
            for (AddressRange r : bodies.get(i)) starts.put(r.getMinAddress().getOffset(), i);
        java.util.function.LongFunction<Integer> nodeAt = (long off) -> {
            Map.Entry<Long, Integer> e2 = starts.floorEntry(off);
            if (e2 == null) return -1;
            int k = e2.getValue();
            return bodies.get(k).contains(toAddr(off)) ? k : -1;
        };
        boolean[] root = new boolean[n];
        List<Set<Integer>> edges = new ArrayList<>();
        for (int i = 0; i < n; i++) edges.add(new HashSet<>());
        Map<Integer, List<String>> incoming = new HashMap<>();
        for (int i = 0; i < n; i++) incoming.put(i, new ArrayList<>());
        for (int i = 0; i < n; i++) {
            for (Address a : bodies.get(i).getAddresses(true)) {
                for (Reference r : rm.getReferencesTo(a)) {
                    Address fr = r.getFromAddress();
                    if (bodies.get(i).contains(fr)) continue;
                    if (!inT2(fr)) root[i] = true;
                    else { int j = nodeAt.apply(fr.getOffset()); if (j >= 0) edges.get(j).add(i); }
                    Function ff = fm.getFunctionContaining(fr);
                    incoming.get(i).add(fr + "(" + r.getReferenceType() + (ff != null ? " in " + ff.getEntryPoint() : "") +
                            (lst.getInstructionAt(fr) == null ? " DATA" : "") + ")->" + a);
                }
            }
        }
        // raw dword pointers into .text2 code that Ghidra has no reference for: from anywhere outside .text2 → root,
        // from a .text2 data node → edge
        for (MemoryBlock blk : mem.getBlocks()) {
            if (!blk.isInitialized()) continue;
            byte[] buf = new byte[(int) blk.getSize()];
            blk.getBytes(blk.getStart(), buf);
            for (int k = 0; k + 4 <= buf.length; k++) {
                long v = (buf[k] & 0xffL) | (buf[k+1] & 0xffL) << 8 | (buf[k+2] & 0xffL) << 16 | (buf[k+3] & 0xffL) << 24;
                if (v < 0x4d0000L || v > 0x554dffL) continue;
                int t = nodeAt.apply(v);
                if (t < 0 || t >= nCode || lst.getInstructionAt(toAddr(v)) == null) continue;
                Address fr = blk.getStart().add(k);
                if (bodies.get(t).contains(fr)) continue;
                if (lst.getInstructionContaining(fr) != null && !inT2(fr)) continue;   // .text operands: Ghidra has those
                String tag = fr + "(RAWPTR)->" + toAddr(v);
                if (!inT2(fr)) { if (!root[t]) incoming.get(t).add(tag + " ROOT"); root[t] = true; }
                else { int j = nodeAt.apply(fr.getOffset()); if (j >= 0 && j >= nCode) { edges.get(j).add(t); incoming.get(t).add(tag); } }
            }
        }
        boolean[] seen = new boolean[n];
        Deque<Integer> q = new ArrayDeque<>();
        for (int i = 0; i < n; i++) if (root[i]) { seen[i] = true; q.add(i); }
        while (!q.isEmpty()) { int i = q.poll(); for (int j : edges.get(i)) if (!seen[j]) { seen[j] = true; q.add(j); } }

        long tot = 0, reached = 0;
        for (int i = 0; i < nCode; i++) { long s2 = bodies.get(i).getNumAddresses(); tot += s2; if (seen[i]) reached += s2; }
        out.println("code nodes " + nCode + ", data nodes " + (n - nCode) + "; code bytes " + tot + ", reached " + reached);
        try (PrintWriter rc = new PrintWriter(new FileWriter(getScriptArgs()[0] + ".reached"))) {
            for (int i = 0; i < nCode; i++) if (seen[i])
                for (AddressRange r : bodies.get(i)) {
                    // only bytes of real instructions, not the function's whole span
                    InstructionIterator ii = lst.getInstructions(new AddressSet(r), true);
                    while (ii.hasNext()) { Instruction x = ii.next(); rc.println(Long.toHexString(x.getMinAddress().getOffset()) + " " + x.getLength()); }
                }
        }
        out.println("== unreached code nodes");
        for (int i = 0; i < nCode; i++) if (!seen[i]) {
            AddressSetView b = bodies.get(i);
            out.println(names.get(i) + " [" + b.getMinAddress() + ".." + b.getMaxAddress() + "] " + b.getNumAddresses() + " bytes; in: " + incoming.get(i));
        }
        if (getScriptArgs().length > 2) {
            out.println("== reference sources");
            for (String x : getScriptArgs()[2].split(",")) {
                Address a = toAddr(Long.parseLong(x, 16));
                Instruction ins = lst.getInstructionAt(a);
                Instruction cont = lst.getInstructionContaining(a);
                int k = nodeAt.apply(a.getOffset());
                String st = !inT2(a) ? "outside .text2" : k < 0 ? "no node" : (names.get(k) + (seen[k] ? " REACHED" : " unreached"));
                out.println(x + ": " + (ins != null ? "insn " + ins : cont != null ? "inside insn " + cont.getMinAddress() + " " + cont : lst.getDefinedDataContaining(a) != null ? "data " + lst.getDefinedDataContaining(a) : "undefined") + " | " + st);
            }
        }
        out.println("== root list (refs from outside .text2 that Ghidra lacks)");
        for (int i = 0; i < n; i++) for (String x : incoming.get(i)) if (x.endsWith("ROOT")) out.println(names.get(i) + " " + x);
        out.close();
    }
}
