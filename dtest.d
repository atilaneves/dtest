#!/usr/bin/rdmd

/**
 * Implements a program to search a list of directories
 * for all .d files, then writes and executes a D program
 * to run all tests contained in those files
 */

import std.stdio;
import std.file;
import std.exception;
import std.array;
import std.algorithm;
import std.path;
import std.conv;
import std.process;
import std.getopt;

/**
 * args is a filename and a list of directories to search in
 * the filename is the 1st element, the others are directories.
 */
int main(string[] args) {
    const options = getOptions(args);
    if(options.help || options.showVersion) return 0;

    writeFile(options, findModuleNames(options.dirs));
    if(options.fileNameSpecified) {
        auto rdmdArgs = getRdmdArgs(options);
        writeRdmdArgsOutString(options.fileName, rdmdArgs);
        return 0;
    }

    immutable rdmd = executeRdmd(options);
    writeln(rdmd.output);

    return rdmd.status;
}

private struct Options {
    //dtest options
    bool verbose;
    bool fileNameSpecified;
    string fileName;
    string[] dirs;
    string[] includes;
    string unit_threaded;
    bool help;

    //unit_threaded.runner options
    string[] args;
    bool debugOutput;
    bool single;
    bool list;
    bool nodub;
    string compiler;
    bool showVersion;
    string[] getRunnerArgs() const {
        auto args = ["--esccodes"];
        if(single) args ~= "--single";
        if(debugOutput) args ~= "--debug";
        if(list) args ~= "--list";
        return args;
    }
}

private Options getOptions(string[] args) {
    Options options;
    getopt(args,
           //dtest options
           "verbose|v", &options.verbose,
           "file|f", &options.fileName,
           "unit_threaded|u", &options.unit_threaded,
           "help|h", &options.help,
           "test|t", &options.dirs,
           "I", &options.includes,
           //these are unit_threaded options
           "single|s", &options.single, //single-threaded
           "debug|d", &options.debugOutput, //print debug output
           "list|l", &options.list,
           "nodub|n", &options.nodub,
           "compiler|c", &options.compiler,
           "version", &options.showVersion,
        );

    if(options.help) {
        printHelp();
        return options;
    }

    if(options.showVersion) {
        writeln("dtest version v0.2.5");
        return options;
    }

    if(!options.unit_threaded && !options.fileName && options.nodub) {
        writeln("Path to unit_threaded library not specified with -u, might fail");
    }

    if(!options.nodub) execute(["dub", "fetch", "unit-threaded", "--version=~master"]);
    if(!options.unit_threaded) options.unit_threaded = getDubUnitThreadedDir();

    if(options.fileName) {
        options.fileNameSpecified = true;
        if(exists(options.fileName)) remove(options.fileName);
    } else {
        options.fileName = createFileName(); //random filename
    }

    if(!options.dirs) options.dirs = ["tests"];
    options.args = args[1..$];
    if(options.verbose) writeln(__FILE__, ": finding all test cases in ", options.dirs);

    if(!options.compiler) options.compiler = "dmd";

    return options;
}

private string getDubUnitThreadedDir() {
    import std.c.stdlib;
    enum suffix = "packages/unit-threaded-master/source";
    version(Windows) {
        return getenv("APPDATA").to!string ~ "/dub/" ~ suffix;
    } else {
        return "~/.dub/" ~ suffix;
    }
}

private void printHelp() {
        writeln(q"EOS

Usage: dtest [options] [test1] [test2]...

    Options:
        -h/--help: help
        -t/--test: add a test directory to the list. If no test directories
        are specified, then the default list is ["tests"]
        -u/--unit_threaded: directory location of the unit_threaded library
        -I: extra include directories to specify to rdmd
        -d/--debug: print debug information
        -f/--file: file name to write to
        -s/--single: run the tests in one thread
        -d/--debug: print debugging information from the tests
        -l/--list: list all tests but do not run them
        -n/--nodub: do not run dub fetch to get unit-threaded
        -c/--compiler: Set the compiler (default is dmd)

    This will run all unit tests encountered in the given directories
    (see -t option). It does this by scanning them and writing a D source
    file that imports all of them then running that source file with rdmd.
    By default the source file is a randomly named temporary file but that
    can be changed with the -f option. If the unit_threaded library is not
    in the default search paths then it can be specified with the -u option.
    If the --nodub option is not used, `dtest` defaults to using dub
    to fetch unit-threaded so that the library need not be downloaded nor
    have its location specified manually.
    If any command-line arguments exist they will be forwarded to the
    unit_threaded library and used as the names of the tests to run. If
    none are specified, all of them are run.

    To run all tests located in a directory called "tests":

    dtest

    To run all tests in dir1, dir2, etc.:

    dtest -t dir1 -t dir2...

    To run tests foo and bar in directory mydir:

    dtest -t mydir mydir.foo mydir.bar

    To run tests foo and bar in directory mydir in a single thread:

    dtest -t mydir -s mydir.foo mydir.bar

EOS");
}

private string createFileName() {
    import std.random;
    import std.ascii : letters, digits;
    immutable nameLength = uniform(10, 20);
    immutable alphanums = letters ~ digits;

    string fileName = "" ~ letters[uniform(0, letters.length)];
    foreach(i; 0 .. nameLength) {
        fileName ~= alphanums[uniform(0, alphanums.length)];
    }

    return buildPath(tempDir(),  fileName ~ ".d");
}

auto findModuleEntries(in string[] dirs) {
    DirEntry[] modules;
    foreach(dir; dirs) {
        enforce(isDir(dir), dir ~ " is not a directory name");
        auto entries = dirEntries(dir, "*.d", SpanMode.depth);
        auto normalised = entries.map!(a => DirEntry(buildNormalizedPath(a)));
        modules ~= array(normalised);
    }
    return modules;
}

auto findModuleNames(in string[] dirs) {
    //cut off extension
    return findModuleEntries(dirs).map!(a => replace(a.name[0 .. $-2], dirSeparator, ".")).array;
}

private auto writeFile(in Options options, in string[] modules) {
    auto wfile = File(options.fileName, "w");
    wfile.writeln("//Automatically generated by dtest, do not edit by hand");
    wfile.writeln("import unit_threaded.runner;");
    wfile.writeln("import std.stdio;");
    wfile.writeln("");
    wfile.writeln("int main(string[] args) {");
    wfile.writeln(`    writeln("\nAutomatically generated file ` ~ options.fileName.replace("\\", "\\\\") ~ `");`);
    wfile.writeln("    writeln(`Running unit tests from dirs " ~ options.dirs.to!string ~ "\n`);");
    wfile.writeln("    return runTests!(" ~ modules.map!(a => `"` ~ a ~ `"`).join(", ") ~ ")(args);");
    wfile.writeln("}");
    wfile.close();

    auto rfile = File(options.fileName, "r");
    printFile(options, rfile);
    return rfile;
}

private void printFile(in Options options, File file) {
    if(!options.verbose) return;
    writeln("Executing this code:\n");
    foreach(line; file.byLine()) {
        writeln(line);
    }
    writeln();
    file.rewind();
}

private auto getRdmdArgs(in Options options) {
    const testIncludeDirs = options.dirs ~ options.unit_threaded ? [options.unit_threaded] : [];
    const testIncludes = testIncludeDirs.map!(a => "-I" ~ a).array;
    const moreIncludes = options.includes.map!(a => "-I" ~ a).array;
    const includes = testIncludes ~ moreIncludes;
    return [ "rdmd", "-unittest", "--compiler=" ~ options.compiler ] ~
        includes ~ options.fileName ~ options.getRunnerArgs() ~ options.args;
}

private auto writeRdmdArgsOutString(in string fileName, string[] args) {
    return writeln("Execute unit test file ", fileName, " with: ", join(args, " "));
}

private auto executeRdmd(in Options options) {
    auto rdmdArgs = getRdmdArgs(options);
    if(options.verbose) writeRdmdArgsOutString(options.fileName, rdmdArgs);
    return execute(rdmdArgs);
}
