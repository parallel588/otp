%% -*- erlang-indent-level: 2 -*-
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(dialyzer_cl_parse).

-export([start/0, get_lib_dir/1]).
-export([collect_args/1]).	% used also by typer

-include("dialyzer.hrl").

%%-----------------------------------------------------------------------

-type dial_cl_parse_ret() :: {'check_init', #options{}}
                           | {'plt_info', #options{}}
                           | {'cl', #options{}}
                           | {'gui', #options{}}
                           | {'error', string()}.

-type deep_string() :: string() | [deep_string()].

%%-----------------------------------------------------------------------

-spec start() -> dial_cl_parse_ret().

start() ->
  init(),
  Args = init:get_plain_arguments(),
  try
    Ret = cl(Args),
    Ret
  catch
    throw:{dialyzer_cl_parse_error, Msg} -> {error, Msg};
    _:R:S ->
      Msg = io_lib:format("~tp\n~tp\n", [R, S]),
      {error, lists:flatten(Msg)}
  end.

cl(["--add_to_plt"|T]) ->
  put(dialyzer_options_analysis_type, plt_add),
  cl(T);
cl(["--apps"|T]) ->
  T1 = get_lib_dir(T),
  {Args, T2} = collect_args(T1),
  append_var(dialyzer_options_files_rec, Args),
  cl(T2);
cl(["--warning_apps"|T]) ->
  T1 = get_lib_dir(T),
  {Args, T2} = collect_args(T1),
  append_var(dialyzer_options_warning_files_rec, Args),
  cl(T2);
cl(["--build_plt"|T]) ->
  put(dialyzer_options_analysis_type, plt_build),
  cl(T);
cl(["--check_plt"|T]) ->
  put(dialyzer_options_analysis_type, plt_check),
  cl(T);
cl(["-n"|T]) ->
  cl(["--no_check_plt"|T]);
cl(["--no_check_plt"|T]) ->
  put(dialyzer_options_check_plt, false),
  cl(T);
cl(["-nn"|T]) ->
  %% Ignored since Erlang/OTP 24.0.
  cl(T);
cl(["--no_native"|T]) ->
  %% Ignored since Erlang/OTP 24.0.
  cl(T);
cl(["--no_native_cache"|T]) ->
  %% Ignored since Erlang/OTP 24.0.
  cl(T);
cl(["--plt_info"|T]) ->
  put(dialyzer_options_analysis_type, plt_info),
  cl(T);
cl(["--get_warnings"|T]) ->
  put(dialyzer_options_get_warnings, true),
  cl(T);
cl(["-D"|_]) ->
  cl_error("No defines specified after -D");
cl(["-D"++Define|T]) ->
  Def = re:split(Define, "=", [{return, list}, unicode]),
  append_defines(Def),
  cl(T);
cl(["-h"|_]) ->
  help_message();
cl(["--help"|_]) ->
  help_message();
cl(["-I"]) ->
  cl_error("no include directory specified after -I");
cl(["-I", Dir|T]) ->
  append_include(Dir),
  cl(T);
cl(["-I"++Dir|T]) ->
  append_include(Dir),
  cl(T);
cl(["--input_list_file"]) ->
  cl_error("No input list file specified");
cl(["--input_list_file",File|L]) ->
  read_input_list_file(File),
  cl(L);
cl(["-c"++_|T]) ->
  NewTail = command_line(T),
  cl(NewTail);
cl(["-r"++_|T0]) ->
  {Args, T} = collect_args(T0),
  append_var(dialyzer_options_files_rec, Args),
  cl(T);
cl(["--remove_from_plt"|T]) ->
  put(dialyzer_options_analysis_type, plt_remove),
  cl(T);
cl(["--incremental"|T]) ->
  put(dialyzer_options_analysis_type, incremental),
  cl(T);
cl(["--com"++_|T]) ->
  NewTail = command_line(T),
  cl(NewTail);
cl(["--output"]) ->
  cl_error("No outfile specified");
cl(["-o"]) ->
  cl_error("No outfile specified");
cl(["--output",Output|T]) ->
  put(dialyzer_output, Output),
  cl(T);
cl(["--metrics_file",MetricsFile|T]) ->
  put(dialyzer_metrics, MetricsFile),
  cl(T);
cl(["--module_lookup_file",ModuleLookupFile|T]) ->
  put(dialyzer_module_lookup, ModuleLookupFile),
  cl(T);
cl(["--output_plt"]) ->
  cl_error("No outfile specified for --output_plt");
cl(["--output_plt",Output|T]) ->
  put(dialyzer_output_plt, Output),
  cl(T);
cl(["-o", Output|T]) ->
  put(dialyzer_output, Output),
  cl(T);
cl(["-o"++Output|T]) ->
  put(dialyzer_output, Output),
  cl(T);
cl(["--raw"|T]) ->
  put(dialyzer_output_format, raw),
  cl(T);
cl(["--fullpath"|T]) ->
  put(dialyzer_filename_opt, fullpath),
  cl(T);
cl(["--no_indentation"|T]) ->
  put(dialyzer_indent_opt, false),
  cl(T);
cl(["-pa", Path|T]) ->
  case code:add_patha(Path) of
    true -> cl(T);
    {error, _} -> cl_error("Bad directory for -pa: " ++ Path)
  end;
cl(["--plt"]) ->
  error("No plt specified for --plt");
cl(["--plt", PLT|T]) ->
  put(dialyzer_init_plts, [PLT]),
  cl(T);
cl(["--plts"]) ->
  error("No plts specified for --plts");
cl(["--plts"|T]) ->
  {PLTs, NewT} = get_plts(T, []),
  put(dialyzer_init_plts, PLTs),
  cl(NewT);
cl(["-q"|T]) ->
  put(dialyzer_options_report_mode, quiet),
  cl(T);
cl(["--quiet"|T]) ->
  put(dialyzer_options_report_mode, quiet),
  cl(T);
cl(["--src"|T]) ->
  put(dialyzer_options_from, src_code),
  cl(T);
cl(["--no_spec"|T]) ->
  put(dialyzer_options_use_contracts, false),
  cl(T);
cl(["--statistics"|T]) ->
  put(dialyzer_timing, true),
  cl(T);
cl(["--resources"|T]) ->
  put(dialyzer_options_report_mode, quiet),
  put(dialyzer_timing, debug),
  cl(T);
cl(["-v"|_]) ->
  io:format("Dialyzer version "++?VSN++"\n"),
  erlang:halt(?RET_NOTHING_SUSPICIOUS);
cl(["--version"|_]) ->
  io:format("Dialyzer version "++?VSN++"\n"),
  erlang:halt(?RET_NOTHING_SUSPICIOUS);
cl(["--verbose"|T]) ->
  put(dialyzer_options_report_mode, verbose),
  cl(T);
cl(["-W"|_]) ->
  cl_error("-W given without warning");
cl(["-Whelp"|_]) ->
  help_warnings();
cl(["-W"++Warn|T]) ->
  append_var(dialyzer_warnings, [list_to_atom(Warn)]),
  cl(T);
cl(["--dump_callgraph"]) ->
  cl_error("No outfile specified for --dump_callgraph");
cl(["--dump_callgraph", File|T]) ->
  put(dialyzer_callgraph_file, File),
  cl(T);
cl(["--dump_full_dependencies_graph"]) ->
  cl_error("No outfile specified for --dump_full_dependencies_graph");
cl(["--dump_full_dependencies_graph", File|T]) ->
  put(dialyzer_mod_deps_file, File),
  cl(T);
cl(["--gui"|T]) ->
  put(dialyzer_options_mode, gui),
  cl(T);
cl(["--error_location", LineOrColumn|T]) ->
  put(dialyzer_error_location_opt, list_to_atom(LineOrColumn)),
  cl(T);
cl(["--solver", Solver|T]) -> % not documented
  append_var(dialyzer_solvers, [list_to_atom(Solver)]),
  cl(T);
cl([H|_] = L) ->
  case filelib:is_file(H) orelse filelib:is_dir(H) of
    true ->
      NewTail = command_line(L),
      cl(NewTail);
    false ->
      cl_error("Unknown option: " ++ H)
  end;
cl([]) ->
  {RetTag, Opts} =
    case get(dialyzer_options_analysis_type) =:= plt_info of
      true ->
	put(dialyzer_options_analysis_type, plt_check),
	{plt_info, cl_options()};
      false ->
	case get(dialyzer_options_mode) of
	  gui -> {gui, common_options()};
	  cl ->
	    case get(dialyzer_options_analysis_type) =:= plt_check of
	      true  -> {check_init, cl_options()};
	      false -> {cl, cl_options()}
	    end
	end
    end,
  case dialyzer_options:build(Opts) of
    {error, Msg} -> cl_error(Msg);
    OptsRecord -> {RetTag, OptsRecord}
  end.

%%-----------------------------------------------------------------------

command_line(T0) ->
  {Args, T} = collect_args(T0),
  append_var(dialyzer_options_files, Args),
  %% if all files specified are ".erl" files, set the 'src' flag automatically
  case lists:all(fun(F) -> filename:extension(F) =:= ".erl" end, Args) of
    true -> put(dialyzer_options_from, src_code);
    false -> ok
  end,
  T.

read_input_list_file(File) ->
  case file:read_file(File) of
    {ok,Bin} ->
      Files = binary:split(Bin, <<"\n">>, [trim_all,global]),
      NewFiles = [binary_to_list(string:trim(F)) || F <- Files],
      append_var(dialyzer_options_files, NewFiles);
    {error,Reason} ->
      cl_error(io_lib:format("Reading of ~s failed: ~s", [File,file:format_error(Reason)]))
  end.

-spec cl_error(deep_string()) -> no_return().

cl_error(Str) ->
  Msg = lists:flatten(Str),
  throw({dialyzer_cl_parse_error, Msg}).

init() ->
  %% By not initializing every option, the modified options can be
  %% found. If every option were to be returned by cl_options() and
  %% common_options(), then the environment variables (currently only
  %% ERL_COMPILER_OPTIONS) would be overwritten by default values.
  put(dialyzer_options_mode, cl),
  put(dialyzer_options_files_rec, []),
  put(dialyzer_options_warning_files_rec, []),
  put(dialyzer_options_report_mode, normal),
  put(dialyzer_warnings, []),
  ok.

append_defines([Def, Val]) ->
  {ok, Tokens, _} = erl_scan:string(Val++"."),
  {ok, ErlVal} = erl_parse:parse_term(Tokens),
  append_var(dialyzer_options_defines, [{list_to_atom(Def), ErlVal}]);
append_defines([Def]) ->
  append_var(dialyzer_options_defines, [{list_to_atom(Def), true}]).

append_include(Dir) ->
  append_var(dialyzer_include, [Dir]).

append_var(Var, List) when is_list(List) ->
  case get(Var) of
    undefined ->
      put(Var, List);
    L ->
      put(Var, L ++ List)
  end,
  ok.

%%-----------------------------------------------------------------------

-spec collect_args([string()]) -> {[string()], [string()]}.

collect_args(List) ->
  collect_args_1(List, []).

collect_args_1(["-"++_|_] = L, Acc) ->
  {lists:reverse(Acc), L};
collect_args_1([Arg|T], Acc) ->
  collect_args_1(T, [Arg|Acc]);
collect_args_1([], Acc) ->
  {lists:reverse(Acc), []}.

%%-----------------------------------------------------------------------

cl_options() ->
  OptsList = [{files, dialyzer_options_files},
   {files_rec, dialyzer_options_files_rec},
   {warning_files_rec, dialyzer_options_warning_files_rec},
   {output_file, dialyzer_output},
   {metrics_file, dialyzer_metrics},
   {module_lookup_file, dialyzer_module_lookup},
   {output_format, dialyzer_output_format},
   {filename_opt, dialyzer_filename_opt},
   {indent_opt, dialyzer_indent_opt},
   {analysis_type, dialyzer_options_analysis_type},
   {get_warnings, dialyzer_options_get_warnings},
   {timing, dialyzer_timing},
   {callgraph_file, dialyzer_callgraph_file},
   {mod_deps_file, dialyzer_mod_deps_file}],
   get_options(OptsList) ++ common_options().

common_options() ->
  OptsList = [{defines, dialyzer_options_defines},
              {from, dialyzer_options_from},
              {include_dirs, dialyzer_include},
              {plts, dialyzer_init_plts},
              {output_plt, dialyzer_output_plt},
              {report_mode, dialyzer_options_report_mode},
              {use_spec, dialyzer_options_use_contracts},
              {warnings, dialyzer_warnings},
              {check_plt, dialyzer_options_check_plt},
              {solvers, dialyzer_solvers}],
  get_options(OptsList).

get_options(TagOptionList) ->
  lists:append([get_opt(Tag, Opt) || {Tag, Opt} <- TagOptionList]).

get_opt(Tag, Opt) ->
  case get(Opt) of
    undefined ->
      [];
    V ->
      [{Tag, V}]
  end.

%%-----------------------------------------------------------------------

-spec get_lib_dir([string()]) -> [string()].

get_lib_dir(Apps) ->
  get_lib_dir(Apps, []).

get_lib_dir([H|T], Acc) ->
  NewElem =
    case code:lib_dir(list_to_atom(H)) of
      {error, bad_name} -> H;
      LibDir when H =:= "erts" -> % hack for including erts in an un-installed system
        EbinDir = filename:join([LibDir,"ebin"]),
        case file:read_file_info(EbinDir) of
          {error,enoent} ->
            filename:join([LibDir,"preloaded","ebin"]);
          _ ->
            EbinDir
        end;
      LibDir -> filename:join(LibDir,"ebin")
    end,
  get_lib_dir(T, [NewElem|Acc]);
get_lib_dir([], Acc) ->
  lists:reverse(Acc).

%%-----------------------------------------------------------------------

get_plts(["--"|T], Acc) -> {lists:reverse(Acc), T};
get_plts(["-"++_Opt = H|T], Acc) -> {lists:reverse(Acc), [H|T]};
get_plts([H|T], Acc) -> get_plts(T, [H|Acc]);
get_plts([], Acc) -> {lists:reverse(Acc), []}.

%%-----------------------------------------------------------------------

-spec help_warnings() -> no_return().

help_warnings() ->
  S = warning_options_msg(),
  io:put_chars(S),
  erlang:halt(?RET_NOTHING_SUSPICIOUS).

-spec help_message() -> no_return().

help_message() ->
  S = "Usage: dialyzer [--add_to_plt] [--apps applications] [--build_plt]
                [--check_plt] [-Ddefine]* [-Dname]* [--dump_callgraph file]
                [--error_location flag] [files_or_dirs] [--fullpath]
                [--get_warnings] [--gui] [--help] [-I include_dir]*
                [--incremental] [--no_check_plt] [--no_indentation] [-o outfile]
                [--output_plt file] [-pa dir]* [--plt plt] [--plt_info]
                [--plts plt*] [--quiet] [-r dirs] [--raw] [--remove_from_plt]
                [--shell] [--src] [--statistics] [--verbose] [--version]
                [-Wwarn]*

Options:
  files_or_dirs (for backwards compatibility also as: -c files_or_dirs)
      Use Dialyzer from the command line to detect defects in the
      specified files or directories containing .erl or .beam files,
      depending on the type of the analysis.
  -r dirs
      Same as the previous but the specified directories are searched
      recursively for subdirectories containing .erl or .beam files in
      them, depending on the type of analysis.
  --input_list_file file
      Specify the name of a file that contains the names of the files
      to be analyzed (one file name per line).
  --apps applications
      Option typically used when building or modifying a plt as in:
        dialyzer --build_plt --apps erts kernel stdlib mnesia ...
      to conveniently refer to library applications corresponding to the
      Erlang/OTP installation. However, the option is general and can also
      be used during analysis in order to refer to Erlang/OTP applications.
      In addition, file or directory names can also be included, as in:
        dialyzer --apps inets ssl ./ebin ../other_lib/ebin/my_module.beam
  -o outfile (or --output outfile)
      When using Dialyzer from the command line, send the analysis
      results to the specified outfile rather than to stdout.
  --raw
      When using Dialyzer from the command line, output the raw analysis
      results (Erlang terms) instead of the formatted result.
      The raw format is easier to post-process (for instance, to filter
      warnings or to output HTML pages).
  --src
      Override the default, which is to analyze BEAM files, and
      analyze starting from Erlang source code instead.
  -Dname (or -Dname=value)
      When analyzing from source, pass the define to Dialyzer. (**)
  -I include_dir
      When analyzing from source, pass the include_dir to Dialyzer. (**)
  -pa dir
      Include dir in the path for Erlang (useful when analyzing files
      that have '-include_lib()' directives).
  --output_plt file
      Store the plt at the specified file after building it.
  --plt plt
      Use the specified plt as the initial plt (if the plt was built
      during setup the files will be checked for consistency).
  --plts plt*
      Merge the specified plts to create the initial plt -- requires
      that the plts are disjoint (i.e., do not have any module
      appearing in more than one plt).
      The plts are created in the usual way:
        dialyzer --build_plt --output_plt plt_1 files_to_include
        ...
        dialyzer --build_plt --output_plt plt_n files_to_include
      and then can be used in either of the following ways:
        dialyzer files_to_analyze --plts plt_1 ... plt_n
      or:
        dialyzer --plts plt_1 ... plt_n -- files_to_analyze
      (Note the -- delimiter in the second case)
  -Wwarn
      A family of options which selectively turn on/off warnings
      (for help on the names of warnings use dialyzer -Whelp).
  --shell
      Do not disable the Erlang shell while running the GUI.
  --version (or -v)
      Print the Dialyzer version and some more information and exit.
  --help (or -h)
      Print this message and exit.
  --quiet (or -q)
      Make Dialyzer a bit more quiet.
  --verbose
      Make Dialyzer a bit more verbose.
  --statistics
      Prints information about the progress of execution (analysis phases,
      time spent in each and size of the relative input).
  --build_plt
      The analysis starts from an empty plt and creates a new one from the
      files specified with -c and -r. Only works for beam files.
      Use --plt(s) or --output_plt to override the default plt location.
  --add_to_plt
      The plt is extended to also include the files specified with -c and -r.
      Use --plt(s) to specify which plt to start from, and --output_plt to
      specify where to put the plt. Note that the analysis might include
      files from the plt if they depend on the new files.
      This option only works with beam files.
  --remove_from_plt
      The information from the files specified with -c and -r is removed
      from the plt. Note that this may cause a re-analysis of the remaining
      dependent files.
  --check_plt
      Check the plt for consistency and rebuild it if it is not up-to-date.
      Actually, this option is of rare use as it is on by default.
  --no_check_plt (or -n)
      Skip the plt check when running Dialyzer. Useful when working with
      installed plts that never change.
  --incremental
      The analysis starts from an existing incremental PLT, or builds one from
      scratch if one doesn't exist, and runs the minimal amount of additional
      analysis to report all issues in the given set of apps. Notably, incremental
      PLT files are not compatible with \"classic\" PLT files, and vice versa.
      The initial incremental PLT will be updated unless an alternative output
      incremental PLT is given.
  --plt_info
      Make Dialyzer print information about the plt and then quit. The plt
      can be specified with --plt(s).
  --get_warnings
      Make Dialyzer emit warnings even when manipulating the plt. Warnings
      are only emitted for files that are actually analyzed.
  --dump_callgraph file
      Dump the call graph into the specified file whose format is determined
      by the file name extension. Supported extensions are: raw, dot, and ps.
      If something else is used as file name extension, default format '.raw'
      will be used.
  --dump_full_dependencies_graph file
      Dump the full dependency graph (i.e. dependencies induced by function
      calls, usages of types in specs, behaviour implementations, etc.) into
      the specified file whose format is determined by the file name
      extension. Supported extensions are: dot and ps.
  --error_location column | line
      Use a pair {Line, Column} or an integer Line to pinpoint the location
      of warnings. The default is to use a pair {Line, Column}. When
      formatted, the line and the column are separated by a colon.
  --fullpath
      Display the full path names of files for which warnings are emitted.
  --no_indentation
      Do not indent contracts and success typings. Note that this option has
      no effect when combined with the --raw option.
  --gui
      Use the GUI.

Note:
  * denotes that multiple occurrences of these options are possible.
 ** options -D and -I work both from command-line and in the Dialyzer GUI;
    the syntax of defines and includes is the same as that used by \"erlc\".

" ++ warning_options_msg() ++ "
The exit status of the command line version is:
  0 - No problems were encountered during the analysis and no
      warnings were emitted.
  1 - Problems were encountered during the analysis.
  2 - No problems were encountered, but warnings were emitted.
",
  io:put_chars(S),
  erlang:halt(?RET_NOTHING_SUSPICIOUS).

warning_options_msg() ->
  "Warning options:
  -Wno_return
     Suppress warnings for functions that will never return a value.
  -Wno_unused
     Suppress warnings for unused functions.
  -Wno_improper_lists
     Suppress warnings for construction of improper lists.
  -Wno_fun_app
     Suppress warnings for fun applications that will fail.
  -Wno_match
     Suppress warnings for patterns that are unused or cannot match.
  -Wno_opaque
     Suppress warnings for violations of opacity of data types.
  -Wno_fail_call
     Suppress warnings for failing calls.
  -Wno_contracts
     Suppress warnings about invalid contracts.
  -Wno_behaviours
     Suppress warnings about behaviour callbacks which drift from the published
     recommended interfaces.
  -Wno_missing_calls
     Suppress warnings about calls to missing functions.
  -Wno_undefined_callbacks
     Suppress warnings about behaviours that have no -callback attributes for
     their callbacks.
  -Wunmatched_returns ***
     Include warnings for function calls which ignore a structured return
     value or do not match against one of many possible return value(s).
  -Werror_handling ***
     Include warnings for functions that only return by means of an exception.
  -Wunderspecs ***
     Warn about underspecified functions
     (those whose -spec is strictly more allowing than the success typing).
  -Wextra_return ***
     Warn about functions whose specification includes types that the
     function cannot return.
  -Wmissing_return ***
     Warn about functions that return values that are not part
     of the specification.
  -Wunknown ***
     Let warnings about unknown functions and types affect the
     exit status of the command line version. The default is to ignore
     warnings about unknown functions and types when setting the exit
     status. When using the Dialyzer from Erlang, warnings about unknown
     functions and types are returned; the default is not to return
     such warnings.

The following options are also available but their use is not recommended:
(they are mostly for Dialyzer developers and internal debugging)
  -Woverspecs ***
     Warn about overspecified functions
     (those whose -spec is strictly less allowing than the success typing).
  -Wspecdiffs ***
     Warn when the -spec is different than the success typing.

*** Identifies options that turn on warnings rather than turning them off.

The following options are not strictly needed as they specify the default.
They are primarily intended to be used with the -dialyzer attribute:
  -Wno_underspecs
     Suppress warnings about underspecified functions (those whose -spec
     is strictly more allowing than the success typing).
  -Wno_extra_return
     Suppress warnings about functions whose specification includes types that the function cannot return.
  -Wno_missing_return
     Suppress warnings about functions that return values that are not part of the specification.
".
