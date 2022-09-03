module paka.main;

import std.file;
import std.stdio;
import paka.srcloc;
import paka.parse.parse;
import paka.comp.comp;
import paka.vm;

void main(string[] args) {
    string src = args[1].readText;
    Function[string] funcs = [
        "$inspect$": (GC* gc, size_t len, Value* values) {
            Data[] args;
            foreach (i; 0..len) {
                args ~= Data(gc, values[i]);
            }
            writeln(args);
            return Value(0);
        }
    ];
    Result res = SrcLoc(args[1], src).parseUncached.compileProgram(funcs);
    run(res.src, res.funcs);
}