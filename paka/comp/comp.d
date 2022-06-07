module paka.comp.comp;

import std.stdio;
import std.file;
import std.algorithm;
import std.conv;
import std.bigint;
import paka.parse.ast;

struct Output
{
    enum Type
    {
        none,
        imut,
    }

    size_t reg;
    Type type;

    bool isNone()
    {
        return type == Type.none;
    }

    static Output none()
    {
        return Output(0, Type.none);
    }

    static Output imut(size_t reg)
    {
        return Output(reg, Type.imut);
    }

    string toString() const @safe pure nothrow
    {
        return "r" ~ reg.to!string;
    }
}

class Compiler
{
    size_t nsyms = 0;
    string buf;

    size_t[string][] nonlocalsbuf;
    size_t[] nregsbuf;
    size_t[string][] localsbuf;
    string[] asmbufs;

    ref size_t[string] nonlocals()
    {
        return nonlocalsbuf[$ - 1];
    }

    ref size_t nregs()
    {
        return nregsbuf[$ - 1];
    }

    ref size_t[string] locals()
    {
        return localsbuf[$ - 1];
    }

    size_t allocReg()
    {
        return nregs++;
    }

    string gensym()
    {
        return "." ~ to!string(nsyms++);
    }

    void pushBuf()
    {
        nregsbuf ~= 2;
        nonlocalsbuf.length += 1;
        localsbuf.length += 1;
        asmbufs.length += 1;
    }

    void popBuf()
    {
        buf ~= asmbufs[$ - 1];
        nonlocalsbuf.length -= 1;
        localsbuf.length -= 1;
        asmbufs.length -= 1;
        nregsbuf.length -= 1;
    }

    void putStrNoIndent(Args...)(Args args)
    {
        static foreach (arg; args)
        {
            asmbufs[$ - 1] ~= arg.to!string;
        }
        asmbufs[$ - 1] ~= '\n';
    }

    void putStr(Args...)(Args args)
    {
        putStrNoIndent("    ", args);
    }

    void putStrSep(Args...)(Args args)
    {
        asmbufs[$ - 1] ~= "    ";
        static foreach (index, arg; args)
        {
            static if (index != 0)
            {
                asmbufs[$ - 1] ~= ' ';
            }
            asmbufs[$ - 1] ~= arg.to!string;
        }
        asmbufs[$ - 1] ~= '\n';
    }

    void emitTopLevel(Node node)
    {
        pushBuf;
        putStrNoIndent("func toplevel");
        putStrSep("ret", emitNode(node));
        putStrNoIndent("end");
        popBuf;
    }

    Output emitReg(Output from, Output to)
    {
        if (!from.isNone && from != to)
        {
            putStrSep(to, "<- reg", from);
        }
        return to;
    }

    Output emitNode(Node node)
    {
        if (Form form = cast(Form) node)
        {
            return emitForm(form, Output.none);
        }
        if (Ident ident = cast(Ident) node)
        {
            return emitIdent(ident, Output.none);
        }
        if (Value!bool value = cast(Value!bool) node)
        {
            return emitValue(value, Output.none);
        }
        if (Value!BigInt value = cast(Value!BigInt) node)
        {
            return emitValue(value, Output.none);
        }
        if (Value!string value = cast(Value!string) node)
        {
            return emitValue(value, Output.none);
        }
        assert(false, "end of: Compiler.emitNode");
    }

    void emitNode(Node node, Output target)
    {
        if (Form form = cast(Form) node)
        {
            emitReg(emitForm(form, target), target);
        }
        else if (Ident ident = cast(Ident) node)
        {
            emitReg(emitIdent(ident, target), target);
        }
        else if (Value!bool value = cast(Value!bool) node)
        {
            emitReg(emitValue(value, target), target);
        }
        else if (Value!BigInt value = cast(Value!BigInt) node)
        {
            emitReg(emitValue(value, target), target);
        }
        else if (Value!string value = cast(Value!string) node)
        {
            emitReg(emitValue(value, target), target);
        }
        else
        {
            assert(false, "end of: Compiler.emitNode");
        }
    }

    Output emitIdent(Ident ident, Output output)
    {
        if (ident.repr in locals)
        {
            return Output.imut(locals[ident.repr]);
        }
        if (ident.repr !in nonlocals)
        {
            size_t count = nonlocals.length;
            nonlocals[ident.repr] = count + 1;
        }
        putStrSep(output, "<- int", nonlocals[ident.repr]);
        putStrSep(output, "<- get", Output.imut(1), output);
        return output;
    }

    void emitBranch(Node cond, string iffalse, string iftrue)
    {
        if (Value!BigInt val = cast(Value!BigInt) cond)
        {
            if (val.value == 0) {
                putStrSep("jump", iffalse);
            } else {
                putStrSep("jump", iftrue);
            }
            return;
        }
        if (Form form = cast(Form) cond)
        {
            switch (form.form)
            {
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
            case "<=":
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                putStrSep("blt", rhs, lhs, iftrue, iffalse);
                return;
            case ">=":
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                putStrSep("blt", lhs, rhs, iftrue, iffalse);
                return;
            default:
                break;
            }
        }
        Output val = emitNode(cond);
        putStrSep("bb", val, iffalse, iftrue);
    }

    Output emitForm(Form form, Output output)
    {
        switch (form.form)
        {
        case "+":
            {
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                putStrSep(output, "<- add", lhs, rhs);
                return output;
            }
        case "-":
            {
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                putStrSep(output, "<- sub", lhs, rhs);
                return output;
            }
        case "*":
            {
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                putStrSep(output, "<- mul", lhs, rhs);
                return output;
            }
        case "/":
            {
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                putStrSep(output, "<- div", lhs, rhs);
                return output;
            }
        case "%":
            {
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                putStrSep(output, "<- mod", lhs, rhs);
                return output;
            }
        case "index":
            {
                Output lhs = emitNode(form.args[0]);
                Output rhs = emitNode(form.args[1]);
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                putStrSep(output, "<- get", lhs, rhs);
                return output;
            }
        case "do":
            {
                if (output.isNone)
                {
                    foreach (arg; form.args)
                    {
                        output = emitNode(arg);
                    }
                    return output;
                }
                else
                {
                    foreach (arg; form.args[0 .. $ - 1])
                    {
                        emitNode(arg);
                    }
                    emitNode(form.args[$ - 1], output);
                    return output;
                }
            }
        case "length":
            {
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                Output arg = emitNode(form.args[0]);
                putStrSep(output, "<- len", arg);
                return output;
            }
        case "array":
            {
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                Output tmp = Output.imut(allocReg);
                putStrSep(output, "<- int", form.args.length);
                putStrSep(output, "<- arr", output);
                foreach (index, argvalue; form.args)
                {
                    putStrSep(tmp, "<- int", index);
                    Output value = emitNode(argvalue);
                    putStrSep("set", output, tmp, value);
                }
                return output;
            }
        case "call":
            {
                Output[] args;
                if (Ident id = cast(Ident) form.args[0])
                {
                    if (id.repr == "putchar")
                    {
                        foreach (arg; form.args[1 .. $])
                        {
                            Output val = emitNode(arg);
                            args ~= val;
                        }
                        putStrSep("putchar", args.map!(to!string).joiner(" "));
                        return Output.none;
                    }
                }
                args ~= emitNode(form.args[0]);
                foreach (arg; form.args[1 .. $])
                {
                    args ~= emitNode(arg);
                }
                Output tmpreg = Output.imut(allocReg);
                putStrSep(tmpreg, "<- int", 0);
                putStrSep(tmpreg, "<- get", args[0], tmpreg);
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                putStrSep(output, "<- dcall", tmpreg, args.map!(to!string).joiner(" "));
                return output;
            }
        case "if":
            {
                if (output.isNone)
                {
                    output = Output.imut(allocReg);
                }
                string lfalse = gensym;
                string ltrue = gensym;
                string lend = gensym;
                emitBranch(form.args[0], lfalse, ltrue);
                putStrNoIndent("@", ltrue);
                Output treg = emitNode(form.args[1]);
                if (!treg.isNone)
                {
                    putStrSep(output, "<- reg", treg);
                }
                else
                {
                    putStrSep(output, "<- int", 0);
                }
                putStrSep("jump", lend);
                putStrNoIndent("@", lfalse);
                Output freg = emitNode(form.args[2]);
                if (!freg.isNone)
                {
                    putStrSep(output, "<- reg", freg);
                }
                else
                {
                    putStrSep(output, "<- int", 0);
                }
                putStrNoIndent("@", lend);
                return output;
            }
        case "while":
            {
                string linit = gensym;
                string lcond = gensym;
                string lend = gensym;
                emitBranch(form.args[0], lend, linit);
                putStrNoIndent("@", linit);
                Output endreg = emitNode(form.args[1]);
                putStrNoIndent("@", lcond);
                emitBranch(form.args[0], lend, linit);
                putStrNoIndent("@", lend);
                return Output.none;
            }
        case "return":
            {
                Output reg = emitNode(form.args[0]);
                putStrSep("ret", reg);
                return Output.none;
            }
        case "set":
            {
                if (Ident ident = cast(Ident) form.args[0])
                {
                    if (ident.repr !in locals)
                    {
                        locals[ident.repr] = allocReg;
                    }
                    Output outreg = Output.imut(locals[ident.repr]);
                    emitNode(form.args[1], outreg);
                    return outreg;
                }
                else if (Form args = cast(Form) form.args[0])
                {
                    switch (args.form)
                    {
                    case "args":
                    case "call":
                        if (Ident varname = cast(Ident) args.args[0])
                        {
                            pushBuf;
                            foreach (arg; args.args[1 .. $])
                            {
                                if (Ident argname = cast(Ident) arg)
                                {
                                    locals[argname.repr] = allocReg;
                                }
                            }
                            string name = gensym;
                            putStrNoIndent("func ", name);
                            Output rhs = emitNode(form.args[1]);
                            putStrSep("ret", rhs);
                            putStrNoIndent("end");
                            size_t[string] caps = nonlocals;
                            popBuf;
                            if (varname.repr !in locals)
                            {
                                locals[varname.repr] = allocReg;
                            }
                            Output cloreg = Output.imut(locals[varname.repr]);
                            Output indexreg = Output.imut(allocReg);
                            Output valuereg = Output.imut(allocReg);
                            putStrSep(cloreg, "<- int", caps.length + 1);
                            putStrSep(cloreg, "<- arr", cloreg);
                            putStrSep(indexreg, "<- int", 0);
                            putStrSep(valuereg, "<- addr", name);
                            putStrSep("set", cloreg, indexreg, valuereg);
                            foreach (index, value; caps)
                            {
                                Output capreg = emitNode(cast(Node) new Ident(index));
                                putStrSep(indexreg, "<- int", value);
                                putStrSep("set", cloreg, indexreg, capreg);
                            }
                            return cloreg;
                        }
                        else
                        {
                            assert(false, "bad assign to function");
                        }
                    default:
                        assert(false, "bad set to form: form.form = " ~ args.form.to!string);
                    }
                }
                else
                {
                    assert(false, "set to node: " ~ form.args[0].to!string);
                }
            }
        default:
            {
                assert(false, "form.form = " ~ form.form);
            }
        }
    }

    Output emitValue(Value!bool value, Output output)
    {
        if (value.value)
        {
            return emitValue(new Value!BigInt(BigInt(1)), output);
        }
        else
        {
            return emitValue(new Value!BigInt(BigInt(0)), output);
        }
    }

    Output emitValue(Value!string value, Output output)
    {
        if (output.isNone)
        {
            output = Output.imut(allocReg);
        }
        putStrSep(output, "<- str", ':' ~ value.value);
        return output;
    }

    Output emitValue(Value!BigInt value, Output output)
    {
        BigInt n = value.value;
        if (output.isNone)
        {
            output = Output.imut(allocReg);
        }
        if (n < 0)
        {
            if (n < 2 ^^ 24)
            {
                putStrSep(output, "<- int", n);
            }
            else
            {
                n = -n;
                Output size = Output.imut(allocReg);
                Output tmp = Output.imut(allocReg);
                putStrSep(size, "<- int", 2 ^^ 24);
                putStrSep(output, "<- int 0");
                while (n != 0)
                {
                    BigInt part = n % 2 ^^ 24;
                    putStrSep(tmp, "<- int", part);
                    putStrSep(output, "<- mul", output, size);
                    putStrSep(output, "<- sub", output, tmp);
                    n /= 2 ^^ 24;
                }
            }
        }
        else
        {
            if (n < 2 ^^ 24)
            {
                putStrSep(output, "<- int", value.value);
            }
            else
            {
                Output size = Output.imut(allocReg);
                Output tmp = Output.imut(allocReg);
                putStrSep(size, "<- int", 2 ^^ 24);
                putStrSep(output, "<- int 0");
                while (n != 0)
                {
                    BigInt part = n % 2 ^^ 24;
                    putStrSep(tmp, "<- int", part);
                    putStrSep(output, "<- mul", output, size);
                    putStrSep(output, "<- add", output, tmp);
                    n /= 2 ^^ 24;
                }
            }
        }
        return output;
    }
}

string compileProgram(Node node)
{
    Compiler compiler = new Compiler();
    compiler.emitTopLevel(node);
    compiler.pushBuf;
    compiler.putStrNoIndent("@__entry");
    compiler.putStrSep("r0 <- call toplevel");
    compiler.putStrSep("exit");
    compiler.popBuf;
    std.file.write("out.vasm", compiler.buf);
    return compiler.buf;
}
