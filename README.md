dtest
=============

Utility using the
[unit-threaded](https://github.com/atilaneves/unit-threaded) library
to run all unit tests in a list of directories. This was written
because, although
[unit-threaded](https://github.com/atilaneves/unit-threaded) can scan
and run all unit tests in a given set of modules, those modules need
to be manually specified, which can be tedious. The reason for that is
that D packages are just directories and the compiler can't read the
filesystem at compile-time, so this executable does that to write a D
source file which it runs using `rdmd`.

This means `rdmd` must be installed for this program to work.

    Usage: dtest [options] [test1] [test2]...

    Run dtest -h for help on the options.

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

    To run all tests located in the current directory

    dtest

    To run all tests in dir1, dir2, etc.:

    dtest -t dir1 -t dir2...

    To run tests foo and bar in directory mydir:

    dtest -t mydir mydir.foo mydir.bar

    To run tests foo and bar in directory mydir in a single thread:

    dtest -t mydir -s mydir.foo mydir.bar
