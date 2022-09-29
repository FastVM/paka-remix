module paka.srcloc;

import std.conv;

struct SrcLoc {
    string file;
    string src;
    size_t line = 1;
    size_t column = 1;

    string pretty() {
        return line.to!string ~ ":" ~ column.to!string;
    }

    SrcLoc dup() {
        SrcLoc loc;
        loc.line = line;
        loc.column = column;
        loc.file = file;
        loc.src = src;
        return loc;
    }

    bool isAt(SrcLoc other) {
        return line == other.line && column == other.column;
    }
}

struct Span {
    SrcLoc first;
    SrcLoc last;

    string pretty() {
        return "from " ~ first.pretty ~ " to " ~ last.pretty;
    }

    Span dup() {
        Span ret;
        ret.first = first.dup;
        ret.last = last.dup;
        return ret;
    }
}
