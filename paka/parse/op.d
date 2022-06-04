module paka.parse.op;

import std.stdio;
import std.conv;
import paka.parse.ast;
import paka.parse.util;

UnaryOp parseUnaryOp(string[] ops) {
    string opName = ops[0];
    if (opName == "#") {
        return (Node rhs) { return new Form("length", [rhs]); };
    } else if (opName == "not") {
        return (Node rhs) { return new Form("!=", rhs, new Value!bool(true)); };
    } else if (opName == "-") {
        throw new Exception("parse error: not a unary operator: " ~ opName
                ~ " (consider 0- instead)");
    } else {
        throw new Exception("parse error: not a unary operator: " ~ opName);
    }
}

BinaryOp parseBinaryOp(string[] ops) {
    string opName = ops[0];
    switch (opName) {
    case "=":
        return (Node lhs, Node rhs) { return new Form("set", lhs, rhs); };
    case "+=":
    case "~=":
    case "-=":
    case "*=":
    case "/=":
    case "%=":
        throw new Exception("no operator assignment");
    default:
        if (opName == "|>") {
            return (Node lhs, Node rhs) { return new Form("rall", rhs, lhs); };
        } else if (opName == "<|") {
            return (Node lhs, Node rhs) { return new Form("call", lhs, rhs); };
        } else {
            if (opName == "or") {
                opName = "||";
            } else if (opName == "and") {
                opName = "&&";
            }
            return (Node lhs, Node rhs) { return new Form(opName, [lhs, rhs]); };
        }
    }
}
