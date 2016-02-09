import unit_threaded.runtime;
import std.stdio;
import std.getopt;
import std.path;
import std.process;
import std.algorithm;
import std.conv;
import std.exception;

alias GenOptions = unit_threaded.runtime.Options;

struct DtestOptions {
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

DtestOptions getOptions(string[] args) {

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

    if(options.genOptions.verbose)
        writeln("Options parsed");

    if(!options.unit_threaded) {
        if(options.genOptions.verbose)
            writeln("Checking/fetching unit-threaded");

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

    auto dubInfo = getDubInfo(options.genOptions.verbose);
    if(options.genOptions.verbose)
        writeln("Setting includes from dub");

    options.genOptions.includes = dubInfo.packages.
        map!(a => a.importPaths.map!(b => buildPath(a.path, b)).array).
        reduce!((a, b) => a ~ b).array;
    return options;
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
