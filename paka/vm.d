module paka.vm;
import std.string;

extern(C) {
    alias Opcode = uint;

    struct Buffer {
        Opcode* ops;
        size_t nops;
    }

    int vm_run_arch_int(size_t nops, const(Opcode)* ops);
    Buffer vm_asm(const(char)* src);
}

void run(Buffer buf) {
    int res = vm_run_arch_int(buf.nops, buf.ops);
    assert(res == 0);
}

void run(const(char)* src) {
    Buffer res = vm_asm(src);
    assert(res.nops != 0);
    run(res);
}

void run(string src) {
    run(src.toStringz);
}