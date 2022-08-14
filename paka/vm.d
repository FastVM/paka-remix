module paka.vm;
import core.memory;
import std.string;
import std.stdio;
import core.runtime;

extern (C) {
    alias Opcode = uint;

    struct Buffer {
        Opcode* ops;
        size_t nops;
    }

    struct Block;

    int vm_run_arch_int(size_t nops, const(Opcode)* ops);
    Buffer vm_asm(const(char)* src);

    Block* vm_ir_parse(size_t nops, const(Opcode)* ops);
    void vm_ir_opt_const(size_t* ptr_nops, Block** ptr_blocks);
    void vm_ir_opt_dead(size_t* ptr_nops, Block** ptr_blocks);
    void vm_ir_opt_reg(size_t nblocks, Block* blocks);
    void vm_ir_blocks_free(size_t nblocks, Block* blocks);
}

void optimize(ref size_t nops, ref Block* blocks) {
    vm_ir_opt_const(&nops, &blocks);
    vm_ir_opt_dead(&nops, &blocks);
    vm_ir_opt_reg(nops, blocks);
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
