#!/usr/bin/rdmd

/**
 * Implements a program to search a list of directories
 * for all .d files, then writes and executes a D program
 * to run all tests contained in those files
 */

import options;
import std.stdio;
import std.file;
import std.exception;
import std.array;
import std.algorithm;
import std.path;
import std.conv;
import std.process;
import std.string: strip;
import unit_threaded.runtime;


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

    if(options.genOptions.verbose)
        writeln("Writing main UT file");

    options.genOptions.fileName = writeUtMainFile(options.genOptions);
    if(options.onlyGenerate) return 0;

    if(options.genOptions.verbose)
        writeln("Executing rdmd on main UT file");

    immutable rdmd = executeRdmd(options);
    writeln(rdmd.output);

    return rdmd.status;
}


private string[] getRdmdArgs(in DtestOptions options) {
    const testIncludeDirs = options.genOptions.dirs ~ options.unit_threaded ? [options.unit_threaded] : [];
    const testIncludes = testIncludeDirs.map!(a => "-I" ~ a).array;
    const moreIncludes = options.genOptions.includes.map!(a => "-I" ~ a).array;
    const includes = testIncludes ~ moreIncludes;
    return [ "rdmd", "-unittest", "--compiler=" ~ options.compiler ] ~
        includes ~ options.genOptions.fileName ~ options.getRunnerArgs() ~ options.args;
}


private auto executeRdmd(in DtestOptions options) {
    auto rdmdArgs = getRdmdArgs(options);
    auto res = execute(rdmdArgs);
    if(options.genOptions.verbose)
        writeln("Execute unit test file ", options.genOptions.fileName, " with: ", join(rdmdArgs, " "));
    return res;
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
