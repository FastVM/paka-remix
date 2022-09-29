module paka.comp.std;

string readStd(string src) {
    if (src == "io") {
        return import("std/io.paka");
    } else {
        throw new Exception("no such std:" ~ src);
    }
}
