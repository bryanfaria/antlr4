%% Code generated from Hello.g4 by ANTLR 4.13.2. DO NOT EDIT.

-module(hello_parser).

-export([
    new/1,
]).

-include_lib("antlr4/include/antlr4_runtime.hrl").

%% Parser state record
-record(parser_state, {
    input :: antlr4_token_stream:token_stream(),
    error_handler :: module(),
    build_parse_trees = true :: boolean(),
    ctx :: term(),
    atn :: antlr4_atn:atn(),
    decision_to_dfa :: [antlr4_dfa:dfa()],
    shared_context_cache :: antlr4_prediction_context:cache()
}).

%% Token type constants
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
    4, 1, 3, 6, 2, 0, 7, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 4, 
    0, 2, 1, 0, 0, 0, 2, 3, 5, 1, 0, 0, 3, 4, 5, 2, 0, 0, 4, 1, 1, 0, 0, 
    0, 0
]).

%% Create a new parser
new(Input) ->
    ATN = antlr4_atn_deserializer:deserialize(?SERIALIZED_ATN),
    DecisionToDFA = antlr4_atn:create_decision_to_dfa(ATN),
    SharedContextCache = antlr4_prediction_context:new_cache(),
    #parser_state{
        input = Input,
        error_handler = antlr4_default_error_strategy,
        atn = ATN,
        decision_to_dfa = DecisionToDFA,
        shared_context_cache = SharedContextCache
    }.


%% Rule: r
'r'(State0) ->
    Ctx0 = antlr4_parser_rule_context:new(
        antlr4_parser:get_ctx(State0),
        antlr4_parser:get_state_number(State0),
        ?HELLOPARSER_RULE_r
    ),
    State1 = antlr4_parser:enter_rule(State0, Ctx0, ?HELLOPARSER_RULE_r),
    try
        State2 = antlr4_parser:enter_outer_alt(State1, Ctx1, 1),
        State_2 = antlr4_parser:set_state(State1, 2),
        antlr4_parser:match(State_2, ?HELLOPARSER_T__0)
        ,
        State_3 = antlr4_parser:set_state(State1, 3),
        antlr4_parser:match(State_3, ?HELLOPARSER_ID)


    catch
        _:Exception ->
            State99 = antlr4_parser:set_exception(State1, Exception),
            antlr4_error_handler:report_error(State99, Exception),
            antlr4_error_handler:recover(State99, Exception)
    end,
    antlr4_parser:exit_rule(State1).


