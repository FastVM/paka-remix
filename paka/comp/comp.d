module paka.comp.comp;

import std.stdio;
import std.file;
import std.algorithm;
import std.conv;
import std.bigint;
import paka.parse.ast;

struct Output {
    enum Type {
        none,
        imut,
        mut,
    }

    size_t reg;
    Type type;

    bool isMut() {
        return type == Type.mut;
    }

    bool isNone() {
        return type == Type.none;
    }

    static Output none() {
        return Output(0, Type.none);
    }

    static Output imut(size_t reg) {
        return Output(reg, Type.imut);
    }

    static Output mut(size_t reg) {
        return Output(reg, type.mut);
    }

    string toString() const @safe pure nothrow {
        return "r" ~ reg.to!string;
    }
}

class Compiler {
    size_t nsyms = 0;
    string buf;

    size_t[] nregsbufs;
    size_t[string][] localbufs;
    string[] asmbufs;

    ref size_t nregs() {
        return nregsbufs[$-1];
    }

    ref size_t[string] locals() {
        return localbufs[$-1];
    }

    size_t allocReg() {
        return nregs++;
    }

    string gensym() {
        return "." ~ to!string(nsyms++);
    }

    void pushBuf() {
        nregsbufs.length += 1;
        localbufs.length += 1;
        asmbufs.length += 1;
    }

    void popBuf() {
        buf ~= asmbufs[$ - 1];
        asmbufs.length -= 1;
    }

    void putStrNoIndent(Args...)(Args args) {
        static foreach (arg; args) {
            asmbufs[$ - 1] ~= arg.to!string;
        }
        asmbufs[$ - 1] ~= '\n';
    }

    void putStr(Args...)(Args args) {
        putStrNoIndent("    ", args);
    }

    void putStrSep(Args...)(Args args) {
        asmbufs[$-1] ~= "    ";
        static foreach (index, arg; args) {
            static if (index != 0) {
                asmbufs[$-1] ~= ' ';
            }
            asmbufs[$ - 1] ~= arg.to!string;
        }
        asmbufs[$ - 1] ~= '\n';
    }

    void emitTopLevel(Node node) {
        pushBuf;
        putStrNoIndent("func toplevel");
        putStrSep("ret", emitNode(node));
        putStrNoIndent("end");
        popBuf;
    }

    Output emitNode(Node node) {
        if (Form form = cast(Form) node) {
            return emitForm(form);
        }
        if (Ident ident = cast(Ident) node) {
            return emitIdent(ident);
        }
        if (Value!bool value = cast(Value!bool) node) {
            return emitValue(value);
        }
        if (Value!BigInt value = cast(Value!BigInt) node) {
            return emitValue(value);
        }
        if (Value!string value = cast(Value!string) node) {
            return emitValue(value);
        }
        assert(false, "end of: Compiler.emitTopLevel");
    }

    Output emitIdent(Ident ident) {
        if (ident.repr !in locals) {
            assert(false, "no such local: "~ ident.repr);
        }
        return Output.imut(locals[ident.repr]);
    }

    void emitBranch(Node cond, string iffalse, string iftrue) {
        if (Form form = cast(Form) cond) {
            switch (form.form) {
            case "==":
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                putStrSep("beq", lhs, rhs, iffalse, iftrue);
                return;
            case "!=":
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                putStrSep("beq", lhs, rhs, iftrue, iffalse);
                return;
            case "<":
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                putStrSep("blt", lhs, rhs, iffalse, iftrue);
                return;
            case ">":
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                putStrSep("blt", rhs, lhs, iffalse, iftrue);
                return;
            case ">=":
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                putStrSep("blt", lhs, rhs, iftrue, iffalse);
                return;
            case "<=":
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                putStrSep("blt", rhs, lhs, iftrue, iffalse);
                return;
            default:
                break;
            }
        }
        Output val = emitNode(cond);
        putStrSep("bb", val, iffalse, iftrue);
    }

    Output emitForm(Form form) {
        switch (form.form) {
        case "+": {
            Output lhs = emitNode(form.args[0]);
            Output rhs = emitNode(form.args[1]);
            if (lhs.isMut) {
                putStrSep(lhs, "<- add", lhs, rhs);
                return lhs;
            }
            if (rhs.isMut) {
                putStrSep(rhs, "<- add", lhs, rhs);
                return rhs;
            }
            Output output = Output.mut(allocReg);
            putStrSep(output, "<- add", lhs, rhs);
            return output;
        }
        case "-": {
            Output lhs = emitNode(form.args[0]);
            Output rhs = emitNode(form.args[1]);
            if (lhs.isMut) {
                putStrSep(lhs, "<- sub", lhs, rhs);
                return lhs;
            }
            if (rhs.isMut) {
                putStrSep(rhs, "<- sub", lhs, rhs);
                return rhs;
            }
            Output output = Output.mut(allocReg);
            putStrSep(output, "<- sub", lhs, rhs);
            return output;
        }
        case "*": {
            Output lhs = emitNode(form.args[0]);
            Output rhs = emitNode(form.args[1]);
            if (lhs.isMut) {
                putStrSep(lhs, "<- mul", lhs, rhs);
                return lhs;
            }
            if (rhs.isMut) {
                putStrSep(rhs, "<- mul", lhs, rhs);
                return rhs;
            }
            Output output = Output.mut(allocReg);
            putStrSep(output, "<- mul", lhs, rhs);
            return output;
        }
        case "/": {
            Output lhs = emitNode(form.args[0]);
            Output rhs = emitNode(form.args[1]);
            if (lhs.isMut) {
                putStrSep(lhs, "<- div", lhs, rhs);
                return lhs;
            }
            if (rhs.isMut) {
                putStrSep(rhs, "<- div", lhs, rhs);
                return rhs;
            }
            Output output = Output.mut(allocReg);
            putStrSep(output, "<- div", lhs, rhs);
            return output;
        }
        case "%": {
            Output lhs = emitNode(form.args[0]);
            Output rhs = emitNode(form.args[1]);
            if (lhs.isMut) {
                putStrSep(lhs, "<- mod", lhs, rhs);
                return lhs;
            }
            if (rhs.isMut) {
                putStrSep(rhs, "<- mod", lhs, rhs);
                return rhs;
            }
            Output output = Output.mut(allocReg);
            putStrSep(output, "<- mod", lhs, rhs);
            return output;
        }
        case "do": {
            Output output = Output.none;
            foreach (arg; form.args) {
                output = emitNode(arg);
            }
            return output;
        }
        case "call": {
            Output output = Output.none;
            Output[] args;
            if (Ident id = cast(Ident) form.args[0]) {
                if (id.repr == "putchar") {
                    foreach (arg; form.args[1..$]) {
                        Output val = emitNode(arg);
                        if (val.isMut && output.isNone) {
                            output = val;
                        }
                        args ~= val;
                    }
                    putStrSep("putchar", args.map!(to!string).joiner(" "));
                    return Output.none;
                }
            }
            if (output.isNone) {
                output = Output.mut(allocReg);
            }
            args ~= emitNode(form.args[0]);
            foreach (arg; form.args[1..$]) {
                args ~= emitNode(arg);
            }
            putStrSep(output, "<- dcall", args.map!(to!string).joiner(" "));
            return output;
        }
        case "while": {
            string linit = gensym;
            string lcond = gensym;
            string lend = gensym;
            putStrSep("jump", lcond);
            putStrNoIndent("@", linit);
            Output endreg = emitNode(form.args[1]);
            putStrNoIndent("@", lcond);
            emitBranch(form.args[0], lend, linit);
            putStrNoIndent("@", lend);
            return Output.none;
        }
        case "set": {
            if (Ident ident = cast(Ident) form.args[0]) {
                if (ident.repr !in locals) {
                    Output rhs = emitNode(form.args[1]);
                    locals[ident.repr] = rhs.reg;
                    return Output.imut(rhs.reg);
                } else {
                    Output outreg = Output.imut(locals[ident.repr]);
                    Output rhs = emitNode(form.args[1]);
                    putStrSep(outreg, "<- reg", rhs);
                    return outreg;
                }
            } else if (Form args = cast(Form) form.args[0]) {
                switch (args.form) {
                case "args":
                case "call":
                    if (Ident varname = cast(Ident) args.args[0]) {
                        pushBuf;
                        string name = gensym;
                        putStrNoIndent("func ", name);
                        Output rhs = emitNode(form.args[1]);
                        putStrSep("ret", rhs);
                        putStrNoIndent("end");
                        popBuf;
                        if (varname.repr !in locals) {
                            locals[varname.repr] = allocReg;
                        }
                        Output outreg = Output.imut(locals[varname.repr]);
                        putStrSep(outreg, "<- addr", name);
                        return outreg;
                    } else {
                        assert(false, "bad assign to function");
                    }
                default:
                    assert(false, "bad set to form: form.form = " ~ args.form.to!string);
                }
            } else {
                assert(false, "set to node: " ~ form.args[0].to!string);
            }
        }
        default: {
            assert(false, "form.form = " ~ form.form);
        }
        }
    }
    
    Output emitValue(Value!bool value) {
        if (value.value) {
            return emitValue(new Value!BigInt(BigInt(1)));
        } else {
            return emitValue(new Value!BigInt(BigInt(0)));
        }
    }
    Output emitValue(Value!string value) {assert(false);}

    Output emitValue(Value!BigInt value) {
        BigInt n = value.value;
        Output outreg = Output.mut(allocReg);
        if (n < 0) {
            if (n < 2^^24) {
                putStrSep(outreg, "<- int", n);
            } else {
                n = -n;
                Output size = Output.mut(allocReg);
                Output tmp = Output.mut(allocReg);
                putStrSep(size, "<- int", 2 ^^ 24);
                putStrSep(outreg, "<- int 0");
                while (n != 0) {
                    BigInt part = n % 2^^24;
                    putStrSep(tmp, "<- int", part);
                    putStrSep(outreg, "<- mul", outreg, size);
                    putStrSep(outreg, "<- sub", outreg, tmp);
                    n /= 2^^24;
                }
            }
        } else {
            if (n < 2^^24) {
                putStrSep(outreg, "<- int ", value.value);
            } else {
                Output size = Output.mut(allocReg);
                Output tmp = Output.mut(allocReg);
                putStrSep(size, "<- int", 2 ^^ 24);
                putStrSep(outreg, "<- int 0");
                while (n != 0) {
                    BigInt part = n % 2^^24;
                    putStrSep(tmp, "<- int", part);
                    putStrSep(outreg, "<- mul", outreg, size);
                    putStrSep(outreg, "<- add", outreg, tmp);
                    n /= 2^^24;
                }
            }
        }
        return outreg;
    }
}

string compileProgram(Node node) {
    Compiler compiler = new Compiler();
    compiler.emitTopLevel(node);
    compiler.buf ~= import("boot.vasm");
    std.file.write("out.vasm", compiler.buf);
    return compiler.buf;
}
