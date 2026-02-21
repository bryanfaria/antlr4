%% Code generated from Hello.g4 by ANTLR 4.13.2. DO NOT EDIT.

-module(hello_lexer).

-export([
    new/1,
    next_token/1,
    get_all_tokens/1
]).

-include_lib("antlr4/include/antlr4_runtime.hrl").
%% Token type constants
-define(HELLOLEXER_EOF, -1).
-define(HELLOLEXER_T__0, 1).
-define(HELLOLEXER_ID, 2).
-define(HELLOLEXER_WS, 3).

%% Channel constants
-define(HELLOLEXER_DEFAULT_TOKEN_CHANNEL, 0).
-define(HELLOLEXER_HIDDEN, 1).
%% Mode constants
-define(HELLOLEXER_DEFAULT_MODE, 0).
%% Rule names
-define(RULE_NAMES, ["T__0", "ID", "WS"]).

%% Channel names
-define(CHANNEL_NAMES, ["DEFAULT_TOKEN_CHANNEL", "HIDDEN"]).

%% Mode names
-define(MODE_NAMES, ["DEFAULT_MODE"]).

%% Literal names
-define(LITERAL_NAMES, [undefined, "'hello'"]).

%% Symbolic names
-define(SYMBOLIC_NAMES, [undefined, undefined, "ID", "WS"]).

%% Serialized ATN
-define(SERIALIZED_ATN, [
    4, 0, 3, 25, 6, -1, 2, 0, 7, 0, 2, 1, 7, 1, 2, 2, 7, 2, 1, 0, 1, 0, 
    1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 4, 1, 15, 8, 1, 11, 1, 12, 1, 16, 1, 2, 
    4, 2, 20, 8, 2, 11, 2, 12, 2, 21, 1, 2, 1, 2, 0, 0, 3, 1, 1, 3, 2, 5, 
    3, 1, 0, 2, 1, 0, 97, 122, 3, 0, 9, 10, 13, 13, 32, 32, 26, 0, 1, 1, 
    0, 0, 0, 0, 3, 1, 0, 0, 0, 0, 5, 1, 0, 0, 0, 1, 7, 1, 0, 0, 0, 3, 14, 
    1, 0, 0, 0, 5, 19, 1, 0, 0, 0, 7, 8, 5, 104, 0, 0, 8, 9, 5, 101, 0, 
    0, 9, 10, 5, 108, 0, 0, 10, 11, 5, 108, 0, 0, 11, 12, 5, 111, 0, 0, 
    12, 2, 1, 0, 0, 0, 13, 15, 7, 0, 0, 0, 14, 13, 1, 0, 0, 0, 15, 16, 1, 
    0, 0, 0, 16, 14, 1, 0, 0, 0, 16, 17, 1, 0, 0, 0, 17, 4, 1, 0, 0, 0, 
    18, 20, 7, 1, 0, 0, 19, 18, 1, 0, 0, 0, 20, 21, 1, 0, 0, 0, 21, 19, 
    1, 0, 0, 0, 21, 22, 1, 0, 0, 0, 22, 23, 1, 0, 0, 0, 23, 24, 6, 2, 0, 
    0, 24, 6, 1, 0, 0, 0, 3, 0, 16, 21, 1, 6, 0, 0
]).

%% Create a new lexer
new(Input) ->
    ATN = antlr4_atn_deserializer:deserialize(?SERIALIZED_ATN),
    DecisionToDFA = antlr4_atn:create_decision_to_dfa(ATN),
    SharedContextCache = antlr4_prediction_context:new_cache(),
    Interpreter = antlr4_lexer_atn_simulator:new(ATN, DecisionToDFA, SharedContextCache),
    #{
        input => Input,
        atn => ATN,
        interpreter => Interpreter,
        decision_to_dfa => DecisionToDFA,
        shared_context_cache => SharedContextCache,
        channel => ?HELLOLEXER_DEFAULT_TOKEN_CHANNEL,
        type => 0,
        mode => ?HELLOLEXER_DEFAULT_MODE,
        mode_stack => [],
        token_start_char_index => -1,
        token_start_line => 1,
        token_start_char_position_in_line => 0,
        text => undefined
    }.

%% Get next token
next_token(State) ->
    antlr4_lexer:next_token(State).

%% Get all tokens
get_all_tokens(State) ->
    get_all_tokens(State, []).

get_all_tokens(State, Acc) ->
    {Token, State1} = next_token(State),
    case antlr4_token:get_type(Token) of
        ?HELLOLEXER_EOF ->
            {lists:reverse([Token | Acc]), State1};
        _ ->
            get_all_tokens(State1, [Token | Acc])
    end.
