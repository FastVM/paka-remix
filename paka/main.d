module paka.main;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.math;
import std.parallelism: taskPool, task;
import std.range;
import std.stdio;
import std.string;
import std.traits;

import paka.srcloc;
import paka.parse.parse;
import paka.comp.comp;
import paka.vm;

static import raylib;

Value toValue(Type)(Type arg) if (is(Type == bool)) {
    return Value(arg ? 1 : 0);
}

Value toValue(Type)(Type arg) if (isIntegral!Type || isFloatingPoint!Type) {
    return Value(cast(ptrdiff_t) arg);
}

Value toValue(Type)(Type arg) if (isArray!Type) {
    Value ret = vm_gc_arr(arg.length);
    foreach (index, value; arg) {
        ret[index] = toValue(value);
    }
    return ret;
}

Value toValue(Type)(Type arg) if (is(Type == const(char)*)) {
    return toValue(arg.fromStringz);
}

Value toValue(Type)(Type arg) if (isSomeChar!Type) {
    return toValue(cast(ptrdiff_t) arg);
}

Type fromValue(Type)(Value arg) if (isSomeChar!Type) {
    return cast(Type) fromValue!ptrdiff_t(arg);
}

Type fromValue(Type)(Value arg) if (isFloatingPoint!Type) {
    return cast(Type) arg.val;
}

Type fromValue(Type)(Value arg) if (isIntegral!Type) {
    return cast(Type) arg.val;
}

Type fromValue(Type)(Value arg) if (isArray!Type) {
    Type ret;
    foreach (i; 0..arg.length) {
        ret ~= fromValue!(ElementType!Type)(arg[i]);
    }
    return ret;
}

Type fromValue(Type)(Value arg) if (is(Type == const(char)*)){
    return fromValue!string(arg).toStringz;
}

Value toFunc(alias val)(size_t len, Value * values) if (__traits(isStaticFunction, val)) {
    Value[] args = values[0..len];
    Parameters!(typeof(val)) params;
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

Value toValue(Type)(Type arg) if (is(Type == void*)) {
    return Value(arg);
}

Value toValue(Type)(Type arg) if (is(Type == raylib.Vector2)) {
    Value ret = vm_gc_arr(2);
    ret[0] = toValue(arg.x);
    ret[1] = toValue(arg.y);
    return ret;
}

Type fromValue(Type)(Value arg) if (is(Type == raylib.Vector2)) {
    return raylib.Vector2(fromValue!float(arg[0]), fromValue!float(arg[1]));
}

Type fromValue(Type)(Value arg) if (is(Type == raylib.Color)) {
    return raylib.Color(
        fromValue!ubyte(arg[0]),
        fromValue!ubyte(arg[1]),
        fromValue!ubyte(arg[2]),
        fromValue!ubyte(arg[3])
    );
}

Value toValue(Type)(Type arg) if (is(Type == raylib.Color)) {
    Value ret = GC.alloc(2);
    ret[0] = toValue(arg.r);
    ret[1] = toValue(arg.g);
    ret[2] = toValue(arg.b);
    ret[3] = toValue(arg.a);
    return ret;
}

/// main

string name(string name) {
    string ret = "raylib:";
    bool last = false;
    foreach (index, chr; name) {
        if ('A' <= chr && chr <= 'Z') {
            if (index != 0 && !last) {
                ret ~= '_';
                last = true;
            }
            ret ~= chr - 'A' + 'a';
        } else {
            ret ~= chr;
            if (chr != '_') {
                last = false;
            }
        }
    }
    return ret;
}

Value dynamicFold(size_t chunk=256)(Value func, Value[] range) {
    if (range.length == 1) {
        return range[0];
    } else if (range.length < chunk) {
        size_t half = range.length / 2;
        Value left = dynamicFold!chunk(func, range[0..half]);
        Value right = dynamicFold!chunk(func, range[half..$]);
        return func(left, right);
    } else {
        size_t half = range.length / 2;
        auto left = task!(dynamicFold!chunk)(func, range[0..half]);
        auto right = task!(dynamicFold!chunk)(func, range[half..$]);
        taskPool.put(left);
        taskPool.put(right);
        return func(left.yieldForce(), right.yieldForce());
    }
}

Value staticFold(alias func, size_t chunk=256)(Value[] range) {
    if (range.length == 1) {
        return range[0];
    } else {
        size_t half = range.length / 2;
        Value left = staticFold!(func, chunk)(range[0..half]);
        Value right = staticFold!(func, chunk)(range[half..$]);
        return func(left, right);
    // } else {
    //     size_t half = range.length / 2;
    //     auto left = task!(staticFold!(func, chunk))(range[0..half]);
    //     auto right = task!(staticFold!(func, chunk))(range[half..$]);
    //     taskPool.put(left);
    //     taskPool.put(right);
    //     return func(left.yieldForce(), right.yieldForce());
    }
}

void main(string[] args) {
    string src = args[1].readText;
    Function[string] funcs;
    funcs["print"] = (size_t len, Value* values) {
        Value[] args = values[0..len];
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
                funcs[name(m)] = (size_t len, Value* values) {
                    string name = fromValue!string(values[0]);
                    if (name in map) {
                        return toValue(map[name]);
                    } else {
                        throw new Exception("enum key error: " ~ name);
                    }
                };
            }
        }
        static if (__traits(isStaticFunction, __traits(getMember, raylib, m))) {
            static if (__traits(compiles, &toFunc!(__traits(getMember, raylib, m)))) {
                static if (
                    m != "SetWindowOpacity"
                    && m != "EnableEventWaiting"
                    && m != "DisableEventWaiting"
                    && m != "ExportDataAsCode"
                    && m != "GetFileLength"
                    && m != "IsPathFile"
                    && m != "GetMouseWheelMoveV"
                    && m != "GetApplicationDirectory"
                ) {
                    funcs[name(m)] = (size_t len, Value* values) {
                        return toFunc!(__traits(getMember, raylib, m))(len, values);
                    };
                }
            }
        }
    }
    funcs["str:from"] = (size_t len, Value* values) {
        string str = values[0].toString;
        Value ret = vm_gc_arr(str.length);
        foreach (index, chr; str) {
            ret[index] = Value(cast(double) chr);
        }
        return ret;
    };
    Result res = SrcLoc(args[1], src).parseUncached.compileProgram(funcs);
    run(res.src, res.funcs);
}
