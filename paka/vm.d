module paka.vm;

import core.memory;
import core.stdc.stdlib;
import std.conv;
import std.stdio;
import std.string;
import std.traits;

alias Opcode = uint;
struct Buffer {
    Opcode* ops;
    size_t nops;
}

extern (C) ubyte *vm_alloc0(size_t size) {
    // ubyte *ret = new ubyte[size + size_t.sizeof].ptr;
    ubyte *ret = cast(ubyte*) new void*[size / 8 + 2].ptr;
    
    *cast(size_t*)ret = size;
    ret += size_t.sizeof;
    foreach (i; 0..size) {
        ret[i] = 0;
    }
    // writeln(ret[size_t.sizeof..size_t.sizeof + size]);
    return ret;
}

extern (C) ubyte *vm_malloc(size_t size) {
    return vm_alloc0(size);
}

extern (C) ubyte *vm_realloc(ubyte *ptr, size_t size) {
    ubyte *ret = vm_alloc0(size);
    if (ptr is null) {
        return ret;
    }
    size_t oldsize = *cast(size_t *) &ptr[-size_t.sizeof];
    if (size < oldsize) {
        oldsize = size;
    }
    foreach (i; 0..oldsize) {
        ret[i] = ptr[i];
    }
    return ret;
}

extern (C) void vm_free(void *ptr) {}

extern (C) void vm_gc_init(Mem *mem, size_t nstack, Value *stack);
extern (C) void vm_gc_deinit(Mem *mem);


extern (C) Value vm_gc_arr(Mem* mem, ptrdiff_t size);
extern (C) Value vm_gc_get(Value obj, Value index);
extern (C) void vm_gc_set(Value obj, Value index, Value value);

extern (C) Value vm_gc_tab(Mem* mem);
extern (C) ptrdiff_t vm_gc_len(Value obj);
extern (C) Value vm_int_run(State* state, void* block);
extern (C) Value vm_gc_table_get(Table *obj, Value ind);
extern (C) void vm_gc_table_set(Table *obj, Value ind, Value val);
extern (C) size_t vm_gc_table_size(Table *obj);

struct Array {
    ubyte tag;
    ubyte mark;
    Value *data;
    uint len;
    uint alloc;
}

struct Table {
    ubyte tag;
    ubyte mark;
    ubyte hash_alloc;
    Value *hash_keys;
    Value *hash_values;
}

union Value {
    enum Type : ubyte {
        unknown,
        nil,
        bool_,
        float_,
        func,
        array,
        table,
        userdata,
    }
    
    struct Bits {
        uint payload;
        uint tag;
    }
    ulong as_int64;
    
    Type* pointer;
    
    double as_double;
    Bits as_bits;

    static Value empty() {
        Value val;
        val.as_int64 = 0x0;
        return val;
    }

    static Value deleted() {
        Value val;
        val.as_int64 = 0x5;
        return val;
    }

    static Value none() {
        Value val;
        val.as_int64 = 0x02;
        return val;
    }

    static Value bfalse() {
        Value val;
        val.as_int64 = 0x06;
        return val;
    }

    static Value btrue() {
        Value val;
        val.as_int64 = 0x07;
        return val;
    }

    static Value undefined() {
        Value val;
        val.as_int64 = 0x0A;
        return val;
    }

    bool isNil() {
        return as_int64 == 0x0;
    }

    bool deleted() {
        return as_int64 == 0x5;
    }
    
    bool isFalse() {
        return as_int64 == 0x06;
    }
    
    bool isTrue() {
        return as_int64 == 0x07;
    }
    
    bool isUndefined() {
        return as_int64 == 0x0A;
    }

    bool isNone() {
        return as_int64 == 0x02;
    }
    
    bool isBool() {
        return (as_int64 & ~1) == 0x06;
    }

    bool isUndefinedOrNone() {
        return (as_int64 & ~8) == 0x02;
    }

    bool toBool() {
        assert(isBool);
        return (as_int64 & 1);
    }

    this(bool b) {
        as_int64 = b ? btrue.as_int64 : bfalse.as_int64;
    }

    bool isNumber() {
        return as_int64 >= 0x0006000000000000;
    }

    this(T)(T d) if(isIntegral!T || isFloatingPoint!T) {
        as_double = cast(double) d;
        as_int64 += 0x0007000000000000;
    }    

    bool isPtr() {
        return !(as_int64 & ~0x0000fffffffffffc) && as_int64 >= 0x1000;
    }

    Type* toPtr() {
        assert(isPtr);
        return pointer;
    }

    Array* toArray() {
        assert(isPtr && ptrType == Type.array);
        return cast(Array*) pointer;
    }

    Table* toTable() {
        assert(isPtr && ptrType == Type.table);
        return cast(Table*) pointer;
    }

    this(Value other) {
        as_bits = other.as_bits;
    }

    this(void *pointer) {
        pointer = pointer;
        assert(isPtr);
    }

    double toNumber() {
        assert(isNumber);
        Value val = this;
        val.as_int64 -= 0x0007000000000000;
        return val.as_double;
    }

    size_t length() {
        assert(isPtr);
        if (ptrType == Type.array) {
            return vm_gc_len(this);
        } else {
            return 0;
        }
    }

    Type ptrType() {
        assert(isPtr);
        return *toPtr;
    }

    Value opIndex(I)(I index) {
        assert(isPtr);
        if (ptrType == Type.array) {
            return vm_gc_get(this, Value(index));
        } else if (ptrType == Type.table) {
            return vm_gc_table_get(this.toTable, Value(index));
        } else {
            assert(false);
        }
    }

    void opIndexAssign(I)(Value value, I index) {
        assert(isPtr);
        if (ptrType == Type.array) {
            vm_gc_set(this, Value(index), value);
        } else if (ptrType == Type.table) {
            vm_gc_table_set(this.toTable, Value(index), value);
        } else {
            assert(false);
        }
    }

    Value rawCall(Value[] args) {
        foreach (key, value; args) {
            state.locals[key + 1] = value;
        }
        Value ret = vm_int_run(&state, cast(void*) toPtr);
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
        foreach (i; 0 .. this.length) {
            ret ~= cast(char) this[i].toNumber;
        }
        return ret;
    }

    string toString() {
        if (isPtr) {
            if (ptrType == Value.Type.array) {
                size_t len = this.length;
                string ret;
                ret ~= "[";
                foreach (i; 0 .. len) {
                    if (i != 0) {
                        ret ~= ", ";
                    }
                    ret ~= this[i].toString;
                }
                ret ~= "]";
                return ret;
            } else if (ptrType == Value.Type.table) {
                Table* tab = cast(Table*) pointer;
                string ret;
                ret ~= "{";
                bool first = true;
                foreach (i; 0..vm_gc_table_size(tab)) {
                    if (!tab.hash_keys[i].isNil) {
                        // writeln(tab.hash_keys[i]);
                        if (first)
                        {
                            first = false;
                        }
                        else
                        {
                            ret ~= ", ";
                        }
                        ret ~= "\n  ";
                        ret ~= "@";
                        ret ~= tab.hash_keys[i].to!string.replace("\n", "\n  ");
                        ret ~= " = ";
                        ret ~= tab.hash_values[i].to!string.replace("\n", "\n  ");
                    }
                }
                ret ~= "\n}";
                return ret;
            } else {
                return "pointer 0x" ~ to!string(cast(size_t) toPtr, 16);
            }
        } else if (isNumber) {
            return toNumber.to!string;
        } else if (isBool) {
            return isTrue ? "true" : "false";
        } else if (isNil) {
            return "nil";
        } else {
            return "(value: " ~ to!string(as_int64) ~ ")";
        }
    }
}

State state;

static this() {
    state.heads = new void*[256].ptr;
    state.framesize = 256;
    state.funcs = null;
    state.locals = new Value[256 * 256].ptr;
    vm_gc_init(&state.gc, 256 * 256, state.locals);
}

static ~this() {
    vm_gc_deinit(&state.gc);
}

struct Mem {
    Value *vals;
    size_t len;
    size_t alloc;
    size_t max;
    Value *stack;
    size_t nstack;
}

struct State {
    void** heads;
    size_t framesize;
    Delegate* funcs;
    Value* locals;
    Mem gc;
}

alias Function = Value delegate(Value[] args);

struct Delegate {
    void* data;
    extern(C) Value function(void *data, State *state, size_t nvalues, Value* values) func;
}

struct Arg {
    union Value {
        size_t reg;
        double num;
        const char *str;
        Block *func;
        Instr *instr;
        bool logic;
    }
    Value value;
    ubyte type;
}

struct Branch {
    Block*[2] targets;
    Arg[2] args;
    ubyte op;
}

struct Instr {
    Arg[9] args;
    Arg out_;
    ubyte op;
}

struct Block {
    ubyte tag;
    
    ptrdiff_t id;

    Instr **instrs;
    size_t len;
    size_t alloc;

    Branch *branch;

    size_t *args;
    size_t nargs;

    size_t nregs;

    void *data;

    bool isfunc;
}

extern (C) Block *vm_ir_parse(size_t nops, const Opcode *ops);

extern (C) void vm_run_arch_int(size_t nops, Opcode* opcodes, Delegate* funcs);
extern (C) Buffer vm_asm(const char* src);

extern (C) Value vm_call(void* data, State *vstate, size_t nvalues, Value* values) {
    state = *vstate;
    return (* cast(Function*) data)(values[0..nvalues]);
}

void run(string src, Function[] funcs) {
    Delegate[] deles = null;
    foreach (func; funcs) {
        deles ~= Delegate(cast(void*) [func].ptr, &vm_call);
    }
    state.funcs = deles.ptr;
    Buffer buf = vm_asm(src.toStringz);
    Block *blocks = vm_ir_parse(buf.nops, buf.ops);
    cast(void) vm_int_run(&state, &blocks[0]);
}
