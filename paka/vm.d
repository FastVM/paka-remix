module paka.vm;

import std.conv;
import std.string;

alias Opcode = uint;
struct Buffer {
    Opcode* ops;
    size_t nops;
}

struct GCHeader {
    ushort mark;
    ushort type;
    uint len;
}

union GCData {
    Value value;
    GCHeader header;
}

struct GC {
    GCData* buf;
    ptrdiff_t buf_used;
    ptrdiff_t buf_alloc;

    ptrdiff_t* move_buf;
    ptrdiff_t move_alloc;

    ptrdiff_t nregs;
    Value* regs;

    ptrdiff_t count;
    ptrdiff_t max;

    bool running;

    ref uint len(ptrdiff_t ptr) {
        return buf[ptr - 1].header.len;
    }

    ref Value get(ptrdiff_t ptr, size_t index) {
        return buf[ptr + index].value;
    }

    ref Value set(ptrdiff_t ptr, size_t index, Value data) {
        return get(ptr, index) = data;
    }
}

union Value {
    void* ptr;
    ptrdiff_t ival;

    this(ptrdiff_t i) {
        ival = i * 2;
    }

    ptrdiff_t toInt() {
        assert(isInt);
        return ival >> 1;
    }

    ptrdiff_t toArray() {
        assert(isArray);
        return ival >> 1;
    }


    bool isInt() {
        return (ival & 1) == 0;
    }

    bool isArray() {
        return (ival & 1) == 1;
    }
}

struct Data {
    GC* gc;
    Value val;

    ptrdiff_t toInt() {
        return val.toInt();
    }

    Data opIndex(size_t index) {
        return Data(gc, gc.get(val.toArray, index));
    }

    ptrdiff_t opCast(T)() const if (is(T == ptrdiff_t)) {
        return val.toInt();
    }
    
    uint length() {
        return gc.len(val.toArray);
    }

    string str(Value[] done = null) {
        if (val.isInt) {
            return val.toInt.to!string;
        } else {
            foreach (index, ent; done) {
                if (ent.ival == val.ival) {
                    return "$" ~ index.to!string;
                }
            }
            done ~= val;
            scope(exit) done = done[0..$-1];
            string ret;
            ret ~= "[";
            foreach (index; 0..length) {
                if (index != 0) {
                    ret ~= ", ";
                }
                ret ~= this[index].str(done);
            }
            ret ~= "]";
            return ret;
        }
    }

    string toString() {
        return this.str(null);    
    }
}

alias Function = Value delegate(GC* gc, size_t nargs, Value *args);

struct Delegate {
    void *data;
    Value function(GC* gc, size_t nvalues, Value* values) func;
}

extern (C) void vm_run_arch_int(size_t nops, Opcode* opcodes, Delegate* funcs);
extern (C) Buffer vm_asm(const char* src);

void run(string src, Function[] funcs) {
    Delegate[] deles;
    foreach (func; funcs) {
        deles ~= Delegate(func.ptr, func.funcptr);
    }
    Buffer buf = vm_asm(src.toStringz);
    vm_run_arch_int(buf.nops, buf.ops, deles.ptr);
}
