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
    if(options.onlyGenerate) return 0;

    immutable rdmd = executeRdmd(options);
    writeln(rdmd.output);

    return rdmd.status;
}

private struct DtestOptions {
    GenOptions genOptions;

    //dtest options
    string unit_threaded;
    bool onlyGenerate;
    bool earlyExit;

    //unit_threaded.runner options
    string[] args;
    bool debugOutput;
    bool single;
    bool list;
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
        "verbose|v", "Verbose output", &options.genOptions.verbose,
        "file|f", "The file to write to containing the main function", &options.genOptions.fileName,
        "unit_threaded|u", "Path to the unit-threaded library", &options.unit_threaded,
        "test|t", "Test directory(ies)", &options.genOptions.dirs,
        "generate", "Only generate the output file, don't run tests", &options.onlyGenerate,
        "version", "print version", &options.showVersion,

        //these are unit_threaded options
        "I", "Import paths as would be passed to the compiler", &options.genOptions.includes,
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
        writeln("dtest version v0.2.6");
        options.earlyExit = true;
        return options;
    }

    if(!options.unit_threaded) {
        options.unit_threaded = getDubUnitThreadedDir();
        dubFetch(options.unit_threaded);
    }

    if(!options.genOptions.dirs) options.genOptions.dirs = ["."];
    options.args = args[1..$];
    if(options.genOptions.verbose) writeln(__FILE__, ": finding all test cases in ", options.genOptions.dirs);

    if(!options.compiler) options.compiler = "dmd";

    import dub;
    return isDubProject ? getOptionsDub(options) : options;
}

private DtestOptions getOptionsDub(DtestOptions options) {
    import dub;
    import std.array;
    import std.path;

    auto dubInfo = getDubInfo;
    options.genOptions.includes = dubInfo.packages.
        map!(a => a.importPaths.map!(b => buildPath(a.path, b)).array).
        reduce!((a, b) => a ~ b).array;
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

private string getDubUnitThreadedDir() {
    version(Windows) {
        import std.process: environment;
        return buildPath(environment["APPDATA"], "dub", unitThreadedSuffix);
    } else {
        return expandTilde(buildPath("~", ".dub", unitThreadedSuffix));
    }
}

private void dubFetch(in string dirName) {
    if(dirName.exists) return;

    writeln("Couldn't find ", dirName, ", running 'dub fetch'");
    immutable cmd = ["dub", "fetch", "unit-threaded", "--version=" ~ unitThreadedVersion];
    immutable res = execute(cmd);
    enforce(res.status == 0, text("Could not execute ", cmd.join(" "), " :\n", res.output));
}


private auto getRdmdArgs(in DtestOptions options) {
    const testIncludeDirs = options.genOptions.dirs ~ options.unit_threaded ? [options.unit_threaded] : [];
    const testIncludes = testIncludeDirs.map!(a => "-I" ~ a).array;
    const moreIncludes = options.genOptions.includes.map!(a => "-I" ~ a).array;
    const includes = testIncludes ~ moreIncludes;
    return [ "rdmd", "-unittest", "--compiler=" ~ options.compiler ] ~
        includes ~ options.genOptions.fileName ~ options.getRunnerArgs() ~ options.args;
}

private auto writeRdmdArgsOutString(in string fileName, string[] args) {
    return writeln("Execute unit test file ", fileName, " with: ", join(args, " "));
}

private auto executeRdmd(in DtestOptions options) {
    auto rdmdArgs = getRdmdArgs(options);
    if(options.genOptions.verbose) writeRdmdArgsOutString(options.genOptions.fileName, rdmdArgs);
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
