module paka.main;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.range;
import std.stdio;
import std.string;
import std.traits;

import paka.srcloc;
import paka.parse.parse;
import paka.comp.comp;
import paka.vm;

static import raylib;

Value toValue(Type)(GC* gc, Type arg) if (is(Type == bool)) {
    return Value.fromInt(arg ? 1 : 0);
}

Value toValue(Type)(GC* gc, Type arg) if (isIntegral!Type || isFloatingPoint!Type) {
    return Value.fromInt(cast(ptrdiff_t) arg);
}

Value toValue(Type)(GC* gc, Type arg) if (isArray!Type) {
    Value ret = GC.alloc(gc, arg.length);
    foreach (index, value; arg) {
        gc.set(ret.toArray, index, Value.fromInt(value));
    }
    return ret;
}

Value toValue(Type)(GC* gc, Type arg) if (is(Type == const(char)*)) {
    return toValue(gc, arg.fromStringz);
}

Value toValue(Type)(GC* gc, Type arg) if (isSomeChar!Type) {
    return toValue(gc, cast(ptrdiff_t) arg);
}

Type fromValue(Type)(GC* gc, Data arg) if (isSomeChar!Type) {
    return cast(Type) fromValue!ptrdiff_t(gc, arg);
}

Type fromValue(Type)(GC* gc, Data arg) if (isFloatingPoint!Type) {
    if (arg.val.isInt) {
        return cast(Type) arg.val.toInt;
    } else {
        return cast(Type) arg[0].toInt / cast(Type) arg[1].toInt;
    }
}

Type fromValue(Type)(GC* gc, Data arg) if (isIntegral!Type) {
    if (arg.val.isInt) {
        return cast(Type) arg.val.toInt;
    } else {
        return cast(Type) arg[0].toInt / cast(Type) arg[1].toInt;
    }
}

Type fromValue(Type)(GC* gc, Data arg) if (isArray!Type) {
    Type ret;
    foreach (i; 0..arg.length) {
        ret ~= fromValue!(ElementType!Type)(gc, arg[i]);
    }
    return ret;
}

Type fromValue(Type)(GC* gc, Data arg) if (is(Type == const(char)*)){
    return fromValue!string(gc, arg).toStringz;
}

Value toFunc(alias val)(GC * gc, size_t len, Value * values) if (__traits(isStaticFunction, val)) {
    Data[] args;
    foreach (i; 0 .. len) {
        args ~= Data(gc, values[i]);
    }
    Parameters!(typeof(val)) params;
    static foreach (index; 0 .. params.length) {
        params[index] = fromValue!(typeof(params[index]))(gc, args[index]);
    }
    static if (is(ReturnType!(typeof(val)) == void)) {
        val(params);
        return Value.fromInt(0);
    } else {
        return toValue(gc, val(params));
    }
}

/// raylib conv

Value toValue(Type)(GC* gc, Type arg) if (is(Type == raylib.Image)) {
    return Value.fromPtr(new raylib.Image(arg));
}

Type fromValue(Type)(GC* gc, Data arg) if (is(Type == raylib.Image)) {
    return * cast(raylib.Image*) arg.val.ptr;
}

Value toValue(Type)(GC* gc, Type arg) if (is(Type == void*)) {
    return Value.fromPtr(arg);
}

Type fromValue(Type)(GC* gc, Data arg) if (is(Type == void*)) {
    return arg.val.ptr;
}

Value toValue(Type)(GC* gc, Type arg) if (is(Type == raylib.Vector2)) {
    Value ret = GC.alloc(gc, 2);
    gc.set(ret.toArray, 0, toValue(gc, arg.x));
    gc.set(ret.toArray, 1, toValue(gc, arg.y));
    return ret;
}

Type fromValue(Type)(GC* gc, Data arg) if (is(Type == raylib.Vector2)) {
    return raylib.Vector2(fromValue!float(gc, arg[0]), fromValue!float(gc, arg[1]));
}

Type fromValue(Type)(GC* gc, Data arg) if (is(Type == raylib.Color)) {
    return raylib.Color(
        fromValue!ubyte(gc, arg[0]),
        fromValue!ubyte(gc, arg[1]),
        fromValue!ubyte(gc, arg[2]),
        fromValue!ubyte(gc, arg[3])
    );
}

Value toValue(Type)(GC* gc, Type arg) if (is(Type == raylib.Color)) {
    Value ret = GC.alloc(gc, 2);
    gc.set(ret.toArray, 0, toValue(gc, arg.r));
    gc.set(ret.toArray, 1, toValue(gc, arg.g));
    gc.set(ret.toArray, 2, toValue(gc, arg.b));
    gc.set(ret.toArray, 3, toValue(gc, arg.a));
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

Data[] toData(GC* gc, Value[] values) {
    return values.map!((x) => Data(gc, x)).array;
}

void main(string[] args) {
    string src = args[1].readText;
    Function[string] funcs;
    funcs["inspect"] = (GC* gc, size_t len, Value* values) {
        Data[] args = gc.toData(values[0..len]);
        foreach (index, arg; args) {
            if (index != 0) {
                write(" ");
            }
            write(arg);
        }
        write('\n');
        return Value.fromInt(0);
    };
    static foreach (m; __traits(allMembers, raylib)) {
        static if (is(__traits(getMember, raylib, m) == enum)) {
            {
                ptrdiff_t[string] map = null;
                static foreach (n; EnumMembers!(__traits(getMember, raylib, m))) {
                    map[n.to!string] = cast(ptrdiff_t) n;
                }
                funcs[name(m)] = (GC* gc, size_t len, Value* values) {
                    string name = fromValue!string(gc, Data(gc, values[0]));
                    if (name in map) {
                        return toValue(gc, map[name]);
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
                ) {
                    funcs[name(m)] = (GC* gc, size_t len, Value* values) {
                        return toFunc!(__traits(getMember, raylib, m))(gc, len, values);
                    };
                }
            }
        }
    }
    funcs["env:new"] = (GC* gc, size_t len, Value* values) {
        Data[] args = gc.toData(values[0..len]);
        return Value.fromInt(0);
    };
    Result res = SrcLoc(args[1], src).parseUncached.compileProgram(funcs);
    run(res.src, res.funcs);
}
