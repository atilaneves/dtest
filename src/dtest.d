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
import std.string: strip;
import unit_threaded.runtime;

alias GenOptions = unit_threaded.runtime.Options;


/**
 * args is a filename and a list of directories to search in
 * the filename is the 1st element, the others are directories.
 */
int main(string[] args) {
    try {
        return run(args);
    } catch(Exception ex) {
        stderr.writeln(ex.msg);
        return 1;
    }
}

int run(string[] args) {
    auto options = getOptions(args);
    if(options.earlyExit) return 0;

    options.genOptions.fileName = writeUtMainFile(options.genOptions);

    immutable rdmd = executeRdmd(options);
    writeln(rdmd.output);

    return rdmd.status;
}

private struct DtestOptions {
    GenOptions genOptions;

    //dtest options
    bool verbose;
    string[] includes;
    string unit_threaded;
    bool onlyGenerate;
    bool earlyExit;

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

private DtestOptions getOptions(string[] args) {
    DtestOptions options;
    auto getOptRes = getopt(
        args,

        //dtest options
        "verbose|v", "Verbose output", &options.verbose,
        "file|f", "The file to write to containing the main function", &options.genOptions.fileName,
        "unit_threaded|u", "Path to the unit-threaded library", &options.unit_threaded,
        "test|t", "Test directory(ies)", &options.genOptions.dirs,
        "I", "Import paths", &options.includes,
        "generate", "Only generate the output file, don't run tests", &options.onlyGenerate,
        "nodub|n", "Don't call dub fetch to get unit-threaded", &options.nodub,
        "version", "print version", &options.showVersion,

        //these are unit_threaded options
        "single|s", "Run in single-threaded mode", &options.single, //single-threaded
        "debug|d", "Run in debug mode (print output)", &options.debugOutput, //print debug output
        "list|l", "List tests", &options.list,
        "compiler|c", "Compiler to use when running tests with rdmd", &options.compiler,
        );

    if(getOptRes.helpWanted) {
        defaultGetoptPrinter("usage: dtests [options] [tests]", getOptRes.options);
        options.earlyExit = true;
        return options;
    }

    if(options.showVersion) {
        writeln("dtest version v0.2.5");
        options.earlyExit = true;
        return options;
    }

    if(!options.unit_threaded && !options.genOptions.fileName && options.nodub) {
        writeln("Path to unit_threaded library not specified with -u, might fail");
    }

    if(!options.unit_threaded) {
        options.unit_threaded = getDubUnitThreadedDir();
        dubFetch(options.unit_threaded);
    }

    if(!options.genOptions.dirs) options.genOptions.dirs = ["tests"];
    options.args = args[1..$];
    if(options.verbose) writeln(__FILE__, ": finding all test cases in ", options.genOptions.dirs);

    if(!options.compiler) options.compiler = "dmd";

    return options;
}

private string unitThreadedVersion() @safe pure nothrow {
    return "~master";
}

private string unitThreadedSuffix() @safe pure nothrow {
    immutable middleDirName = "unit-threaded-" ~
        (unitThreadedVersion[0] == '~'
        ? unitThreadedVersion[1..$]
         : unitThreadedVersion);
        return buildPath("packages", middleDirName, "source");
}

private void dubFetch(in string dirName) {
    if(!dirName.exists)
        execute(["dub", "fetch", "unit-threaded", "--version=" ~ unitThreadedVersion]);
}

private string getDubUnitThreadedDir() {
    version(Windows) {
        import std.process: environment;
        return buildPath(environment["APPDATA"], "dub", unitThreadedSuffix);
    } else {
        return "~/.dub/" ~ unitThreadedSuffix;
    }
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

private void writeFile(in DtestOptions options, in string[] modules) {
    if(!haveToUpdate(options, modules))
        return;

    writeln("Writing to unit test main file ", options.genOptions.fileName);

    auto wfile = File(options.genOptions.fileName, "w");
    wfile.writeln(modulesDbList(modules));
    wfile.writeln("//Automatically generated by dtest, do not edit by hand");
    wfile.writeln("import unit_threaded.runner;");
    wfile.writeln("import std.stdio;");
    wfile.writeln("");
    wfile.writeln("int main(string[] args) {");
    wfile.writeln(`    writeln("\nAutomatically generated file ` ~ options.genOptions.fileName.replace("\\", "\\\\") ~ `");`);
    wfile.writeln("    writeln(`Running unit tests from dirs " ~ options.genOptions.dirs.to!string ~ "`);");

    immutable indent = "                          ";
    wfile.writeln("    return args.runTests!(\n" ~
                  modules.map!(a => indent ~ `"` ~ a ~ `"`).join(",\n") ~
                  "\n" ~ indent ~ ");");
    wfile.writeln("}");
    wfile.close();

    auto rfile = File(options.genOptions.fileName, "r");
    printFile(options, rfile);
}

private void printFile(in DtestOptions options, File file) {
    if(!options.verbose) return;
    writeln("Executing this code:\n");
    foreach(line; file.byLine()) {
        writeln(line);
    }
    writeln();
    file.rewind();
}

private auto getRdmdArgs(in DtestOptions options) {
    const testIncludeDirs = options.genOptions.dirs ~ options.unit_threaded ? [options.unit_threaded] : [];
    const testIncludes = testIncludeDirs.map!(a => "-I" ~ a).array;
    const moreIncludes = options.includes.map!(a => "-I" ~ a).array;
    const includes = testIncludes ~ moreIncludes;
    return [ "rdmd", "-unittest", "--compiler=" ~ options.compiler ] ~
        includes ~ options.genOptions.fileName ~ options.getRunnerArgs() ~ options.args;
}

private auto writeRdmdArgsOutString(in string fileName, string[] args) {
    return writeln("Execute unit test file ", fileName, " with: ", join(args, " "));
}

private auto executeRdmd(in DtestOptions options) {
    auto rdmdArgs = getRdmdArgs(options);
    if(options.verbose) writeRdmdArgsOutString(options.genOptions.fileName, rdmdArgs);
    return execute(rdmdArgs);
}


private bool haveToUpdate(in DtestOptions options, in string[] modules) {
    if (!options.genOptions.fileName.exists)
        return true;

    auto file = File(options.genOptions.fileName);
    return file.readln.strip != modulesDbList(modules);
}


//used to not update the file if the file list hasn't changed
private string modulesDbList(in string[] modules) @safe pure nothrow {
    return "//" ~ modules.join(",");
}
