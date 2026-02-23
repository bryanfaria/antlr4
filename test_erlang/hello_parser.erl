%% Code generated from Hello.g4 by ANTLR 4.13.2. DO NOT EDIT.

-module(hello_parser).

-export([
    new/1,
    'r'/0,
    'r'/1]).

-include_lib("antlr4/include/antlr4_runtime.hrl").

%% Token type constants
-define(HELLOPARSER_EOF, -1).
-define(HELLOPARSER_T__0, 1).
-define(HELLOPARSER_ID, 2).
-define(HELLOPARSER_WS, 3).

%% Rule index constants
-define(HELLOPARSER_RULE_r, 0).

%% Rule names
-define(RULE_NAMES, ["r"]).

%% Literal names
-define(LITERAL_NAMES, [undefined, "'hello'"]).

%% Symbolic names
-define(SYMBOLIC_NAMES, [undefined, undefined, "ID", "WS"]).

%% Serialized ATN
-define(SERIALIZED_ATN, [
    4, 1, 3, 7, 2, 0, 7, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 
    0, 5, 0, 2, 1, 0, 0, 0, 2, 3, 5, 1, 0, 0, 3, 4, 5, 2, 0, 0, 4, 5, 5, 
    0, 0, 1, 5, 1, 1, 0, 0, 0, 0
]).

%% Create a new parser state (stored in process dictionary)
new(Input) ->
    ATN = antlr4_atn_deserializer:deserialize(?SERIALIZED_ATN),
    DecisionToDFA = antlr4_atn:create_decision_to_dfa(ATN),
    SharedContextCache = antlr4_prediction_context:new_cache(),
    antlr4_parser:init(#{
        input => Input,
        error_handler => antlr4_default_error_strategy,
        atn => ATN,
        decision_to_dfa => DecisionToDFA,
        shared_context_cache => SharedContextCache,
        build_parse_trees => true,
        ctx => undefined,
        state_number => -1,
        error_listeners => [antlr4_error_listener],
        parse_listeners => [],
        exception => undefined,
        rule_names => ?RULE_NAMES
    }),
    ok.


%% Rule: r
'r'(State0) ->
    antlr4_parser:init(State0),
    'r'().

'r'() ->
    LocalCtx = antlr4_parser:enter_rule(?HELLOPARSER_RULE_r),
    try
        antlr4_parser:enter_outer_alt(1),
        antlr4_parser:set_state(2),
        antlr4_parser:match(?HELLOPARSER_T__0)
        ,
        antlr4_parser:set_state(3),
        antlr4_parser:match(?HELLOPARSER_ID)
        ,
        antlr4_parser:set_state(4),
        antlr4_parser:match(?HELLOPARSER_EOF)


    catch
        throw:Reason ->
            antlr4_parser:handle_rule_exception(Reason);
        error:Reason:Stacktrace ->
            antlr4_parser:handle_rule_exception({error, Reason, Stacktrace})
    end,
    antlr4_parser:exit_rule(),
    antlr4_parser:get_state().


