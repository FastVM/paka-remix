module paka.main;

static import std.math;
import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.math;
import std.parallelism: taskPool, task;
import std.range;
import std.stdio;
import std.string;
import std.file;
import std.traits;

import core.memory: GC;

import paka.srcloc;
import paka.parse.parse;
import paka.comp.comp;
import paka.vm;

static import raylib;
static import rlgl;

Value toValue(Type)(Type arg) if (is(Type == bool)) {
    return Value(arg);
}

Value toValue(Type)(Type arg) if (isIntegral!Type || isFloatingPoint!Type) {
    return Value(cast(double) arg);
}

Value toValue(Type)(Type arg) if (isArray!Type) {
    Value ret = vm_gc_arr(&state.gc, arg.length);
    foreach (index, value; arg) {
        ret[index] = toValue(value);
    }
    return ret;
}

Value toValue(Type)(Type arg) if (isPointer!Type && isSomeChar!(PointerTarget!Type)) {
    import core.stdc.string: strlen;
    return toValue(arg[0..strlen(arg)]);
}

Value toValue(Type)(Type arg) if (isSomeChar!Type) {
    return toValue(cast(ptrdiff_t) arg);
}

Value toValue(Type)(Type arg) if (isPointer!Type && !isSomeChar!(PointerTarget!Type)) {
    struct Intern {
        Value.Type tag;
        Type data;
    }
    Intern *it = new Intern(Value.Type.userdata, arg);
    return Value(it);
}

Type fromValue(Type)(Value arg) if (isPointer!Type && !isSomeChar!(PointerTarget!Type)) {
    struct Intern {
        Value.Type tag;
        Type data;
    }
    return (* cast(Intern*) arg.pointer).data;
}

Type fromValue(Type)(Value arg) if (isSomeChar!Type) {
    return cast(Type) fromValue!ptrdiff_t(arg);
}

Type fromValue(Type)(Value arg) if (isFloatingPoint!Type) {
    return cast(Type) arg.toNumber;
}

Type fromValue(Type)(Value arg) if (isIntegral!Type) {
    return cast(Type) arg.toNumber;
}

Type fromValue(Type)(Value arg) if (isDynamicArray!Type) {
    Type ret;
    foreach (k; 0..arg.length) {
        ret ~= fromValue!(ElementType!Type)(arg[k]);
    }
    return ret;
}

Type fromValue(Type)(Value arg) if (isStaticArray!Type) {
    Type ret;
    foreach (k; 0..arg.length) {
        ret[k] = fromValue!(ElementType!Type)(arg[k]);
    }
    return ret;
}

Type fromValue(Type)(Value arg) if (isPointer!Type && isSomeChar!(PointerTarget!Type)) {
    PointerTarget!Type[] ret;
    foreach (k; 0..arg.length) {
        ret ~= fromValue!(PointerTarget!Type)(arg[k]);
    }
    ret ~= 0;
    return ret.ptr;
}

Type fromValue(Type)(Value arg) if (is(Type == bool)){
    return arg.toBool;
}

Value toFunc(alias val)(Value[] args) if (__traits(isStaticFunction, val)) {
    staticMap!(Unqual, Parameters!(typeof(val))) params;
    static foreach (index; 0 .. params.length) {
        params[index] = fromValue!(typeof(params[index]))(args[index]);
    }
    static if (is(ReturnType!(typeof(val)) == void)) {
        val(params);
        return Value(0);
    } else {
        return toValue(val(params));
    }
}

/// raylib conv

template ok(alias Type) {
    enum ok = !is(Type) && !is(typeof(Type) == void) && !is(typeof(Type) == function);
}

Value toValue(Type)(Type arg) if (is(Type == struct)) {
    Value ret = vm_gc_tab(&state.gc);
    static foreach (name; __traits(allMembers, Type)) {
        static if (!is(__traits(getMember, arg, name)) && ok!(__traits(getMember, Type, name))) {
            ret[toValue(name)] = toValue(__traits(getMember, arg, name));
        }
    }
    return ret;
}

Type fromValue(Type)(Value arg) if (is(Type == struct)) {
    Type ret;
    static foreach (name; __traits(allMembers, Type)) {
        static if (!is(__traits(getMember, ret, name)) && ok!(__traits(getMember, Type, name))) {
            __traits(getMember, ret, name) = fromValue!(typeof(__traits(getMember, ret, name)))(arg[toValue(name)]);
        }
    }
    return ret; 
}

/// main

version (GNU) {
    extern(C) const char *raylibVersion = "4.0.1";
}

void main(string[] args) {
    string src = args[1].readText;
    Function[string] funcs;
    funcs["print"] = (Value[] args) {
        foreach (index, arg; args) {
            if (index != 0) {
                write(" ");
            }
            write(arg);
        }
        write('\n');
        return Value(0);
    };
    static foreach (m; __traits(allMembers, raylib)) {
        static if (is(__traits(getMember, raylib, m) == enum)) {
            {
                ptrdiff_t[string] map = null;
                static foreach (n; EnumMembers!(__traits(getMember, raylib, m))) {
                    map[n.to!string] = cast(ptrdiff_t) n;
                }
                funcs[m] = (Value[] values) {
                    string name = fromValue!string(values[0]);
                    if (auto v = name in map) {
                        return toValue(*v);
                    } else {
                        throw new Exception("enum key error: " ~ name);
                    }
                };
            }
        }
        static if (__traits(isStaticFunction, __traits(getMember, raylib, m))) {
            funcs[m] = (Value[] values) {
                return toFunc!(__traits(getMember, raylib, m))(values);
            };
        }
    }
    static foreach (m; __traits(allMembers, rlgl)) {
        static if (is(__traits(getMember, rlgl, m) == enum)) {
            {
                ptrdiff_t[string] map = null;
                static foreach (n; EnumMembers!(__traits(getMember, rlgl, m))) {
                    map[n.to!string] = cast(ptrdiff_t) n;
                }
                funcs[m] = (Value[] values) {
                    string name = fromValue!string(values[0]);
                    if (auto v = name in map) {
                        return toValue(*v);
                    } else {
                        throw new Exception("enum key error: " ~ name);
                    }
                };
            }
        }
        static if (__traits(isStaticFunction, __traits(getMember, rlgl, m))) {
            funcs[m] = (Value[] values) {
                return toFunc!(__traits(getMember, rlgl, m))(values);
            };
        }
    }
    Value table = vm_gc_tab(&state.gc); 
    static foreach (k; ["algebraic", "constants", "exponential", "operations", "remainder", "rounding", "traits", "trigonometry"])
    {
        {
            alias math = __traits(getMember, std.math, k);
            static foreach (m; __traits(allMembers, math)) {
                static if (m != "approxEqual") {
                    static if (is(typeof(__traits(getMember, math, m)) == function)) {
                        funcs["math:" ~ m] = (Value[] values) {
                            return toFunc!(__traits(getMember, math, m))(values);
                        };
                    }
                }
            }
        }
    }
    funcs["str:from"] = (Value[] values) {
        string str = values[0].toString;
        Value ret = vm_gc_arr(&state.gc, str.length);
        foreach (index, chr; str) {
            ret[index] = Value(cast(double) chr);
        }
        return ret;
    };
    Result res = SrcLoc(args[1], src).parseUncached.compileProgram(funcs);
    File("out.vasm", "w").writeln(res.src);
    run(res.src, res.funcs);
}
