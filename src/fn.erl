-module(fn).
-export([get_lex/2,
        print_lex/2,
        get_tree/2,
        print_tree/2,
        get_ast/2,
        print_ast/2,
        get_publics/1,
        get_publics/2,
        build_module/1,
        compile/2,
        get_erlang/2,
        print_erlang/2,
        erl_to_ast/1,
        run/0,
        run/1]).

% lexer functions

get_lex(String) ->
    case fn_lexer:string(String) of
        {ok, Tokens, _Endline} -> Tokens;
        Errors -> throw(Errors)
    end.

get_lex(string, String) ->
    Lex = get_lex(String),
    fn_lexpp:clean_whites(Lex);
get_lex(istring, String) ->
    Lex  = get_lex(String),
    Lex1 = fn_lexpp:clean_tabs(Lex),
    fn_lexpp:indent_to_blocks(Lex1);
get_lex(file, Path) ->
    Program = file_to_string(Path),

    IsFn = lists:suffix(".fn", Path),
    IsIfn = lists:suffix(".ifn", Path),

    if
        IsFn  -> get_lex(string, Program);
        IsIfn -> get_lex(istring, Program);
        true  -> exit("Invalid file extension (.fn or .ifn expected)")
    end.

print_lex(From, String) ->
    io:format("~p~n", [get_lex(From, String)]).

% tree functions
% the tree differs from the erlang absform in some small things, you should use
% ast functions for almost anything

get_tree(From, String) ->
    Tokens = get_lex(From, String),
    case fn_parser:parse(Tokens) of
        {ok, Tree}    -> Tree;
        {ok, Tree, _} -> Tree;
        {error, _Warnings, Errors} -> throw(Errors);
        Error -> throw(Error)
    end.

print_tree(From, String) ->
    io:format("~p~n", [get_tree(From, String)]).

tree_to_ast(Tree) ->
    tree_to_ast(Tree, [], []).

tree_to_ast([], Publics, Ast) ->
    {lists:reverse(Publics), lists:reverse(Ast)};
tree_to_ast([{public_function, Line, Name, Arity, Body}|Tree], Publics, Ast) ->
    tree_to_ast(Tree, [{Name, Arity}|Publics], [{function, Line, Name, Arity, Body}|Ast]);
tree_to_ast([H|Tree], Publics, Ast) ->
    tree_to_ast(Tree, Publics, [H|Ast]).

get_publics(Tree) ->
    {Publics, _Ast} = tree_to_ast(Tree),
    Publics.

get_publics(From, String) ->
    Tree = get_tree(From, String),
    get_publics(Tree).

% ast functions

get_ast(From, String) ->
    Tree = get_tree(From, String),
    {_Publics, Ast} = tree_to_ast(Tree),
    Ast.

print_ast(From, String) ->
    io:format("~p~n", [get_ast(From, String)]).

erl_to_ast(String) ->
    Scanned = case erl_scan:string(String) of
        {ok, Return, _} -> Return;
        Errors -> throw(Errors)
    end,

    case erl_parse:parse_exprs(Scanned) of
        {ok, Parsed} -> Parsed;
        Errors1 -> throw(Errors1)
    end.

% to erlang functions

get_erlang(From, String) ->
    Ast = get_ast(From, String),
    erl_prettypr:format(erl_syntax:form_list(Ast)).

print_erlang(From, String) ->
    Str = get_erlang(From, String),
    io:format("~s~n", [Str]).

% from erlang functions

from_erlang(Path) ->
    case epp:parse_file(Path, [], []) of
        {ok, Tree} -> Tree;
        Error -> throw(Error)
    end.

print_from_erlang(Path) ->
    Ast = from_erlang(Path),
    io:format("~p~n", [Ast]).

% compile functions
get_code(Ast) ->
    case compile:forms(Ast) of
        {ok, _, Code} -> Code;
        {ok, _, Code, _} -> Code;
        {error, Errors, _Warnings} -> throw(Errors);
        Error -> throw(Error)
    end.

compile(Name, Dir) ->
    Module = get_code(build_module(Name)),
    Path = filename:join([Dir, get_module_beam_name(Name)]),

    Device = case file:open(Path, [binary, write]) of
        {ok, Return} -> Return;
        {error, _Reason} = Error -> throw(Error)
    end,

    file:write(Device, Module).

build_module(Name) ->
    [{attribute, 1, module, get_module_name(Name)},
        {attribute, 1, export, get_publics(file, Name)}] ++ get_ast(file, Name).

% utils

remove_quotes(String) ->
    lists:reverse(tl(lists:reverse(tl(String)))).

file_to_string(Path) ->
    Content = case file:read_file(Path) of
        {ok, Return} -> Return;
        {error, _Reason} = Error -> throw(Error)
    end,

    binary_to_list(Content).

get_module_name(String) ->
    File = filename:basename(String),
    ModuleNameStr = filename:rootname(File),
    list_to_atom(ModuleNameStr).

get_module_beam_name(String) ->
    File = filename:basename(String),
    ModuleNameStr = filename:rootname(File),
    string:concat(ModuleNameStr, ".beam").

% eval functions

eval(Expression, Lang) ->
    Bindings = erl_eval:new_bindings(),

    try
        Ast = get_ast(string, Expression ++ "\n"),
        {value, Result, _} = erl_eval:exprs(Ast, Bindings),
        if
            Lang == efene ->
                io:format(">>> ~s~n~p~n", [Expression, Result]);

            Lang == erlang ->
                io:format("1> ~s~n~p~n",
                    [erl_prettypr:format(erl_syntax:form_list(Ast)), Result])
        end
    catch _:Error ->
        io:format("~p~n", [Error])
    end.

% command line interface

run() -> run([]).

run(["shell"]) ->
    fn_shell:start();
run(["eval", Expr]) ->
    eval(remove_quotes(Expr), efene);
run(["erleval", Expr]) ->
    eval(remove_quotes(Expr), erlang);
run(["lex", File]) ->
    fn_errors:handle(fun () -> print_lex(file, File) end);
run(["tree", File]) ->
    fn_errors:handle(fun () -> print_tree(file, File) end);
run(["ast", File]) ->
    fn_errors:handle(fun () -> print_ast(file, File) end);
run(["erl", File]) ->
    fn_errors:handle(fun () -> print_erlang(file, File) end);
run(["fn", File]) ->
   fn_errors:handle(fun () ->  fn_pp:pretty_print(get_lex(file, File), true) end);
run(["ifn", File]) ->
    fn_errors:handle(fun () -> fn_pp:pretty_print(get_lex(file, File), false) end);
run(["erl2ast", File]) ->
    fn_errors:handle(fun () -> print_from_erlang(File) end);
run(["beam", File]) ->
    fn_errors:handle(fun () -> compile(File, ".") end);
run(["beam", File, Dir]) ->
    fn_errors:handle(fun () -> compile(File, Dir) end);
run(Opts) ->
    io:format("Invalid input to fn.erl: \"~p\"~n", [Opts]).
