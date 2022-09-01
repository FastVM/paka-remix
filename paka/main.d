module paka.main;

import std.file;
import std.stdio;
import paka.srcloc;
import paka.parse.parse;
import paka.comp.comp;

void main(string[] args) {
    string src = args[1].readText;
    string asm_ = SrcLoc(args[1], src).parseUncached.compileProgram;
    writeln(asm_);
}