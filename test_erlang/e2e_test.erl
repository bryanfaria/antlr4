-module(e2e_test).
-export([run/0]).
-include_lib("antlr4/include/antlr4_runtime.hrl").

run() ->
    io:format("=== ANTLR4 Erlang Runtime Tests ===~n~n"),
    test_lexer(),
    test_skip_action(),
    test_parser(),
    io:format("~n=== ALL TESTS PASSED ===~n").

%% Test 1: Basic lexing
test_lexer() ->
    io:format("Test 1: Basic lexing... "),
    Input = antlr4_input_stream:new(<<"hello world">>),
    LexerState = hello_lexer:new(Input),
    {Tokens, _} = hello_lexer:get_all_tokens(LexerState),

    %% Should produce 3 tokens: hello(T__0=1), world(ID=2), EOF(-1)
    3 = length(Tokens),
    [T1, T2, T3] = Tokens,
    1 = antlr4_token:get_type(T1),
    <<"hello">> = antlr4_token:get_text(T1),
    2 = antlr4_token:get_type(T2),
    <<"world">> = antlr4_token:get_text(T2),
    -1 = antlr4_token:get_type(T3),
    io:format("PASSED~n").

%% Test 2: Skip action works (whitespace is skipped)
test_skip_action() ->
    io:format("Test 2: Skip action (WS)... "),
    Input = antlr4_input_stream:new(<<"hello   world">>),
    LexerState = hello_lexer:new(Input),
    {Tokens, _} = hello_lexer:get_all_tokens(LexerState),

    %% Multiple spaces should all be skipped, producing same 3 tokens
    3 = length(Tokens),
    [T1, T2, _T3] = Tokens,
    <<"hello">> = antlr4_token:get_text(T1),
    <<"world">> = antlr4_token:get_text(T2),
    io:format("PASSED~n").

%% Test 3: Parser end-to-end
test_parser() ->
    io:format("Test 3: Parser e2e... "),
    Input = antlr4_input_stream:new(<<"hello world">>),
    LexerState = hello_lexer:new(Input),
    TokenStream = antlr4_token_stream:new(LexerState),

    %% Initialize parser
    hello_parser:new(TokenStream),

    %% Call the rule
    _Result = hello_parser:'r'(antlr4_parser:get_state()),

    %% If we got here without exception, parse succeeded
    io:format("PASSED~n").
