module paka.parse.ast;

import std.algorithm;
import std.conv;
import std.meta;
import paka.srcloc;

/// any node, not valid in the ast
class Node {
    Span span;
}

/// call of function or operator call
final class Form : Node {
    string form;
    Node[] args;

    this(Args...)(string f, Args as) {
        static foreach (a; as) {
            args ~= a;
        }
        form = f;
    }

    override string toString() {
        char[] ret;
        ret ~= "(";
        ret ~= form;
        foreach (i, v; args) {
            ret ~= " ";
            ret ~= v.to!string;
        }
        ret ~= ")";
        return cast(string) ret;
    }
}

size_t usedSyms;

Ident genSym() {
    usedSyms++;
    return new Ident(".purr." ~ to!string(usedSyms - 1));
}

template ident(string name) {
    Ident value;

    shared static this() {
        value = new Ident(name);
    }

    Ident ident() {
        return value;
    }
}

/// ident or number, detects at runtime
final class Ident : Node {
    string repr;

    this(string s) {
        repr = s;
    }

    override string toString() {
        return repr;
    }
}

/// dynamic value literal
final class Value(Type) : Node {
    Type value;

    this(Type value_) {
        value = value_;
    }

    override string toString() {
        return "<" ~ value.to!string ~ ">";
    }
}
