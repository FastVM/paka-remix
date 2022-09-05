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

extern(C) ptrdiff_t vm_gc_arr(GC* gc, ptrdiff_t size);
extern(C) Value vm_gc_get(GC* gc, Value obj, Value index);
extern(C) void vm_gc_set(GC* gc, Value obj, Value index, Value value);
extern(C) ptrdiff_t vm_gc_len(GC* gc, Value obj);
extern(C) Value vm_int_run(State* state, void* block);

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

    State* state;

    bool running;

    static ptrdiff_t len(GC* gc, Value ptr) {
        return vm_gc_len(gc, ptr);
    }

    static Value get(GC* gc, Value ptr, Value index) {
        return vm_gc_get(gc, ptr, index);
    }

    static void set(GC* gc, Value ptr, Value index, Value data) {
        vm_gc_set(gc, ptr, index, data);
    }

    static Value alloc(GC* gc, size_t len) {
        return Value(vm_gc_arr(gc, cast(ptrdiff_t) len));
    }
}

union Value {
    void* ptr;
    ptrdiff_t ival;

    this(void *v) {
        assert(cast(size_t) v % 2 == 0);
        ptr = v;
    }

    this(ptrdiff_t v) {
        ival = v;
    }

    static Value fromPtr(void* i) {
        return Value(i);
    }

    static Value fromInt(ptrdiff_t i) {
        return Value(i * 2);
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

    this(GC* gc_, Value val_) {
        gc = gc_;
        val = val_;
    }

    ptrdiff_t toInt() {
        return val.toInt();
    }

    Data opIndex(size_t index) {
        return Data(gc, GC.get(gc, val, Value.fromInt(index)));
    }

    Data opIndex(Value index) {
        return Data(gc, GC.get(gc, val, index));
    }

    ptrdiff_t opCast(T)() const if (is(T == ptrdiff_t)) {
        return val.toInt();
    }
    
    ptrdiff_t length() {
        return GC.len(gc, val);
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

    Data opCall(Data[] args) {
        foreach (index, arg; args) {
            gc.state.locals[index + 1] = arg.val;
        }
        return Data(gc, vm_int_run(gc.state, val.ptr));
    }

    string toString() {
        return this.str(null);    
    }
}

struct State
{
    size_t nblocks;
    void *blocks;
    void **heads;
    GC gc;
    size_t framesize;
    Delegate *funcs;
    void **ptrs;
    Value *locals;
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
