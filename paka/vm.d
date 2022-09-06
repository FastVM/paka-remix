module paka.vm;

import core.memory;
import std.conv;
import std.stdio;
import std.string;
import std.traits;

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

extern(C) void *vm_malloc(size_t size) {
    return GC.malloc(size);
}
extern(C) void *vm_alloc0(size_t size) {
    return GC.calloc(size);
}
extern(C) void *vm_realloc(void *ptr, size_t size) {
    return GC.realloc(ptr, size);
}
extern(C) void vm_free(void *ptr) {
    // GC.free(ptr);
}
extern(C) Value vm_gc_arr(ptrdiff_t size) {
    Value[string] ret;
    ret["length"] = Value(size);
    return Value(ret);
}
extern(C) Value vm_gc_get(Value obj, Value index) {
    return obj.map[index.toString];
}
extern(C) void vm_gc_set(Value obj, Value index, Value value) {
    obj.map[index.toString] = value;
}
extern(C) ptrdiff_t vm_gc_len(Value obj) {
    return cast(ptrdiff_t) obj.map["length"].val;
}
extern(C) Value vm_int_run(State* state, void* block);

union Value {
    void* ptr;
    Value[string] map;
    double val;

    this(Value[string] p) {
        map = p;
    }

    this(Value other) {
        val = other.val;
    }

    this(Type)(Type v) if (isIntegral!Type || isFloatingPoint!Type) {
        val = cast(double) v;
    }

    Value opIndex(I)(I index) {
        return vm_gc_get(this, Value(index));
    }

    void opIndexAssign(I)(Value value, I index) {
        vm_gc_set(this, Value(index), value);
    }

    ptrdiff_t length() {
        return vm_gc_len(this);
    }

    Value rawCall(Value[] args) {
        State state;
        state.framesize = 64;
        state.locals = cache;
        cache += 256;
        scope(exit) {
            cache -= 256;
        }
        foreach (key, value; args) {
            state.locals[key + 1] = value;
        }
        state.funcs = deles.ptr;
        state.heads = new void*[256].ptr;
        Value ret = vm_int_run(&state, cast(void*) ptr);
        return ret;
    }

    Value opCall(Params...)(Params params) {
        Value[] args = [this];
        static foreach (param; params) {
            args ~= param;
        }
        return this[0].rawCall(args);
    }

    bool opCast(T : bool)() const {
        return val != 0;    
    }

    string chars() {
        string ret;
        foreach (i; 0..this.length) {
            ret ~= cast(char) this[i].val;
        }
        return ret;
    }

    string toString() {
        if (Value* base = cast(Value*) GC.addrOf(ptr)) {
            size_t len = this.length;
            string ret;
            ret ~= "[";
            foreach (i; 0..len) {
                if (i != 0) {
                    ret ~= ", ";
                }
                ret ~= this[i].toString;
            }
            ret ~= "]";
            return ret;
        } else {
            return val.to!string;
        }
    }
}

Value* cache;
static this() {
    cache = new Value[2 ^^ 20].ptr;
}

struct State
{
    void **heads;
    size_t framesize;
    Delegate *funcs;
    Value *locals;
}

alias Function = Value delegate(size_t nargs, Value *args);

struct Delegate {
    void *data;
    Value function(size_t nvalues, Value* values) func;
}

extern (C) void vm_run_arch_int(size_t nops, Opcode* opcodes, Delegate* funcs);
extern (C) Buffer vm_asm(const char* src);

Delegate[] deles;

void run(string src, Function[] funcs) {
    deles = null;
    foreach (func; funcs) {
        deles ~= Delegate(func.ptr, func.funcptr);
    }
    Buffer buf = vm_asm(src.toStringz);
    vm_run_arch_int(buf.nops, buf.ops, deles.ptr);
}
