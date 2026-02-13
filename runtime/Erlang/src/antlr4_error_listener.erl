%% ANTLR4 Error Listener
%% Base error listener behavior and default implementations

-module(antlr4_error_listener).

-include("antlr4_runtime.hrl").

-export([behaviour_info/1]).

%% Default error listeners
-export([
    console_error_listener/0,
    syntax_error/6,
    report_ambiguity/6,
    report_attempting_full_context/5,
    report_context_sensitivity/5
]).

%% @doc Define the error listener behavior callbacks
behaviour_info(callbacks) ->
    [
        {syntax_error, 6},
        {report_ambiguity, 6},
        {report_attempting_full_context, 5},
        {report_context_sensitivity, 5}
    ];
behaviour_info(_Other) ->
    undefined.

%% @doc Create a console error listener
-spec console_error_listener() -> module().
console_error_listener() ->
    ?MODULE.

%% @doc Called when a syntax error occurs
-spec syntax_error(term(), antlr4_token:token(), integer(), integer(), binary(), term()) -> ok.
syntax_error(_Recognizer, _OffendingSymbol, Line, CharPositionInLine, Message, _Exception) ->
    io:format("line ~p:~p ~s~n", [Line, CharPositionInLine, Message]),
    ok.

%% @doc Called when the parser detects an ambiguity
-spec report_ambiguity(term(), antlr4_dfa:dfa(), integer(), integer(), boolean(), term()) -> ok.
report_ambiguity(_Recognizer, _DFA, _StartIndex, _StopIndex, _Exact, _AmbigAlts) ->
    ok.

%% @doc Called when the parser is attempting full context prediction
-spec report_attempting_full_context(term(), antlr4_dfa:dfa(), integer(), integer(), term()) -> ok.
report_attempting_full_context(_Recognizer, _DFA, _StartIndex, _StopIndex, _ConflictingAlts) ->
    ok.

%% @doc Called when the parser detects a context sensitivity
-spec report_context_sensitivity(term(), antlr4_dfa:dfa(), integer(), integer(), integer()) -> ok.
report_context_sensitivity(_Recognizer, _DFA, _StartIndex, _StopIndex, _Prediction) ->
    ok.
