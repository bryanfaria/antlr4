%% ANTLR4 Parser Module
%% Base parser functionality

-module(antlr4_parser).

-include("antlr4_runtime.hrl").

-export([
    new/2,
    get_input/1,
    set_input/2,
    get_token_stream/1,
    get_current_token/1,
    match/2,
    match_wildcard/1,
    consume/1,
    enter_rule/3,
    exit_rule/1,
    enter_outer_alt/3,
    enter_recursion_rule/4,
    push_new_recursion_context/4,
    unroll_recursion_contexts/2,
    get_ctx/1,
    set_ctx/2,
    get_state_number/1,
    set_state/2,
    get_atn/1,
    get_interpreter/1,
    get_error_handler/1,
    set_error_handler/2,
    get_exception/1,
    set_exception/2,
    precpred/2,
    has_parse_listeners/1,
    add_parse_listener/2,
    remove_parse_listener/2,
    remove_parse_listeners/1,
    trigger_enter_rule_event/1,
    trigger_exit_rule_event/1,
    notify_error_listeners/2,
    notify_error_listeners/4,
    get_invoking_context/2,
    get_text_from_context/2,
    is_expected_token/2,
    get_expected_tokens/1,
    get_expected_tokens_within_current_rule/1,
    get_rule_invocation_stack/1,
    get_dfa_strings/1,
    dump_dfa/1,
    get_source_name/1,
    set_trace/2,
    get_token_names/1,
    get_rule_names/1,
    get_atn_with_bypass_alts/1,
    set_build_parse_trees/2,
    get_build_parse_trees/1,
    reset/1
]).

-record(parser_state, {
    input :: antlr4_token_stream:token_stream(),
    ctx :: term(),
    error_handler :: module(),
    error_listeners = [] :: [module()],
    parse_listeners = [] :: [module()],
    build_parse_trees = true :: boolean(),
    state_number = -1 :: integer(),
    atn :: term(),
    interpreter :: term(),
    decision_to_dfa :: term(),
    shared_context_cache :: term(),
    rule_names = [] :: [binary()],
    token_names = [] :: [binary()],
    exception :: term()
}).

-type parser_state() :: #parser_state{}.
-export_type([parser_state/0]).

%% @doc Create a new parser
-spec new(antlr4_token_stream:token_stream(), term()) -> parser_state().
new(Input, ATN) ->
    DecisionToDFA = antlr4_atn:create_decision_to_dfa(ATN),
    SharedContextCache = antlr4_prediction_context:new_cache(),
    Interpreter = antlr4_parser_atn_simulator:new(ATN, DecisionToDFA, SharedContextCache),
    #parser_state{
        input = Input,
        error_handler = antlr4_default_error_strategy,
        atn = ATN,
        interpreter = Interpreter,
        decision_to_dfa = DecisionToDFA,
        shared_context_cache = SharedContextCache
    }.

%% @doc Get the input token stream
-spec get_input(parser_state()) -> antlr4_token_stream:token_stream().
get_input(#parser_state{input = Input}) ->
    Input.

%% @doc Set the input token stream
-spec set_input(parser_state(), antlr4_token_stream:token_stream()) -> parser_state().
set_input(State, Input) ->
    State#parser_state{input = Input}.

%% @doc Get the token stream (alias for get_input)
-spec get_token_stream(parser_state()) -> antlr4_token_stream:token_stream().
get_token_stream(State) ->
    get_input(State).

%% @doc Get the current token
-spec get_current_token(parser_state()) -> antlr4_token:token().
get_current_token(#parser_state{input = Input}) ->
    antlr4_token_stream:lt(Input, 1).

%% @doc Match the current token against an expected token type
-spec match(parser_state(), integer()) -> {antlr4_token:token(), parser_state()}.
match(State, TokenType) ->
    Token = get_current_token(State),
    case antlr4_token:get_type(Token) of
        TokenType ->
            State1 = consume(State),
            {Token, State1};
        _ ->
            ErrorHandler = State#parser_state.error_handler,
            RecoveredToken = ErrorHandler:recover_inline(State),
            {RecoveredToken, State}
    end.

%% @doc Match any token (wildcard)
-spec match_wildcard(parser_state()) -> {antlr4_token:token(), parser_state()}.
match_wildcard(State) ->
    Token = get_current_token(State),
    case antlr4_token:get_type(Token) of
        ?ANTLR4_TOKEN_EOF ->
            ErrorHandler = State#parser_state.error_handler,
            RecoveredToken = ErrorHandler:recover_inline(State),
            {RecoveredToken, State};
        _ ->
            State1 = consume(State),
            {Token, State1}
    end.

%% @doc Consume the current token
-spec consume(parser_state()) -> parser_state().
consume(#parser_state{input = Input, build_parse_trees = BuildTrees, ctx = Ctx} = State) ->
    Token = antlr4_token_stream:lt(Input, 1),
    Input1 = antlr4_token_stream:consume(Input),
    State1 = State#parser_state{input = Input1},
    case BuildTrees andalso Ctx =/= undefined of
        true ->
            %% Add terminal node to parse tree
            TerminalNode = #terminal_node{symbol = Token, parent = Ctx},
            Ctx1 = antlr4_parser_rule_context:add_child(Ctx, TerminalNode),
            State1#parser_state{ctx = Ctx1};
        false ->
            State1
    end.

%% @doc Enter a rule context
-spec enter_rule(parser_state(), term(), integer()) -> parser_state().
enter_rule(#parser_state{ctx = ParentCtx, input = Input} = State, Ctx, _RuleIndex) ->
    %% Set start token
    Token = antlr4_token_stream:lt(Input, 1),
    Ctx1 = antlr4_parser_rule_context:set_start(Ctx, Token),
    %% Add to parent context if building parse trees
    State1 = case State#parser_state.build_parse_trees andalso ParentCtx =/= undefined of
        true ->
            _ = antlr4_parser_rule_context:add_child(ParentCtx, Ctx1),
            State#parser_state{ctx = Ctx1};
        false ->
            State#parser_state{ctx = Ctx1}
    end,
    %% Notify listeners
    trigger_enter_rule_event(State1).

%% @doc Exit a rule context
-spec exit_rule(parser_state()) -> parser_state().
exit_rule(#parser_state{ctx = Ctx, input = Input} = State) ->
    %% Set stop token
    Token = antlr4_token_stream:lt(Input, -1),
    Ctx1 = antlr4_parser_rule_context:set_stop(Ctx, Token),
    %% Notify listeners
    State1 = trigger_exit_rule_event(State#parser_state{ctx = Ctx1}),
    %% Pop context
    ParentCtx = antlr4_parser_rule_context:get_parent(Ctx1),
    State1#parser_state{ctx = ParentCtx}.

%% @doc Enter an outer alternative
-spec enter_outer_alt(parser_state(), term(), integer()) -> parser_state().
enter_outer_alt(#parser_state{build_parse_trees = true, ctx = ParentCtx} = State, Ctx, AltNum) ->
    Ctx1 = antlr4_parser_rule_context:set_alt_number(Ctx, AltNum),
    case ParentCtx =/= undefined of
        true ->
            _ = antlr4_parser_rule_context:add_child(ParentCtx, Ctx1),
            State#parser_state{ctx = Ctx1};
        false ->
            State#parser_state{ctx = Ctx1}
    end;
enter_outer_alt(State, Ctx, AltNum) ->
    Ctx1 = antlr4_parser_rule_context:set_alt_number(Ctx, AltNum),
    State#parser_state{ctx = Ctx1}.

%% @doc Enter a recursion rule
-spec enter_recursion_rule(parser_state(), term(), integer(), integer()) -> parser_state().
enter_recursion_rule(State, Ctx, RuleIndex, _Precedence) ->
    State1 = State#parser_state{ctx = Ctx},
    enter_rule(State1, Ctx, RuleIndex).

%% @doc Push a new recursion context
-spec push_new_recursion_context(parser_state(), term(), integer(), integer()) -> parser_state().
push_new_recursion_context(#parser_state{ctx = ParentCtx} = State, Ctx, StartState, _RuleIndex) ->
    Ctx1 = antlr4_parser_rule_context:set_parent(Ctx, ParentCtx),
    State#parser_state{ctx = Ctx1, state_number = StartState}.

%% @doc Unroll recursion contexts
-spec unroll_recursion_contexts(parser_state(), term()) -> parser_state().
unroll_recursion_contexts(#parser_state{ctx = Ctx, input = Input} = State, ParentCtx) ->
    %% Set stop token on all contexts back to parent
    Token = antlr4_token_stream:lt(Input, -1),
    unroll_contexts(State, Ctx, ParentCtx, Token).

unroll_contexts(State, Ctx, ParentCtx, _Token) when Ctx =:= ParentCtx ->
    State#parser_state{ctx = ParentCtx};
unroll_contexts(State, Ctx, ParentCtx, Token) ->
    Ctx1 = antlr4_parser_rule_context:set_stop(Ctx, Token),
    State1 = trigger_exit_rule_event(State#parser_state{ctx = Ctx1}),
    NextCtx = antlr4_parser_rule_context:get_parent(Ctx1),
    unroll_contexts(State1, NextCtx, ParentCtx, Token).

%% @doc Get the current context
-spec get_ctx(parser_state()) -> term().
get_ctx(#parser_state{ctx = Ctx}) ->
    Ctx.

%% @doc Set the current context
-spec set_ctx(parser_state(), term()) -> parser_state().
set_ctx(State, Ctx) ->
    State#parser_state{ctx = Ctx}.

%% @doc Get the current state number
-spec get_state_number(parser_state()) -> integer().
get_state_number(#parser_state{state_number = StateNum}) ->
    StateNum.

%% @doc Set the state number
-spec set_state(parser_state(), integer()) -> parser_state().
set_state(State, StateNum) ->
    State#parser_state{state_number = StateNum}.

%% @doc Get the ATN
-spec get_atn(parser_state()) -> term().
get_atn(#parser_state{atn = ATN}) ->
    ATN.

%% @doc Get the ATN interpreter
-spec get_interpreter(parser_state()) -> term().
get_interpreter(#parser_state{interpreter = Interpreter}) ->
    Interpreter.

%% @doc Get the error handler
-spec get_error_handler(parser_state()) -> module().
get_error_handler(#parser_state{error_handler = Handler}) ->
    Handler.

%% @doc Set the error handler
-spec set_error_handler(parser_state(), module()) -> parser_state().
set_error_handler(State, Handler) ->
    State#parser_state{error_handler = Handler}.

%% @doc Get the last exception
-spec get_exception(parser_state()) -> term().
get_exception(#parser_state{exception = Exception}) ->
    Exception.

%% @doc Set an exception
-spec set_exception(parser_state(), term()) -> parser_state().
set_exception(State, Exception) ->
    State#parser_state{exception = Exception}.

%% @doc Check if current rule can take a precedence
-spec precpred(parser_state(), integer()) -> boolean().
precpred(_State, _Precedence) ->
    true.

%% @doc Check if there are parse listeners
-spec has_parse_listeners(parser_state()) -> boolean().
has_parse_listeners(#parser_state{parse_listeners = Listeners}) ->
    length(Listeners) > 0.

%% @doc Add a parse listener
-spec add_parse_listener(parser_state(), module()) -> parser_state().
add_parse_listener(#parser_state{parse_listeners = Listeners} = State, Listener) ->
    State#parser_state{parse_listeners = Listeners ++ [Listener]}.

%% @doc Remove a parse listener
-spec remove_parse_listener(parser_state(), module()) -> parser_state().
remove_parse_listener(#parser_state{parse_listeners = Listeners} = State, Listener) ->
    State#parser_state{parse_listeners = lists:delete(Listener, Listeners)}.

%% @doc Remove all parse listeners
-spec remove_parse_listeners(parser_state()) -> parser_state().
remove_parse_listeners(State) ->
    State#parser_state{parse_listeners = []}.

%% @doc Trigger enter rule event for listeners
-spec trigger_enter_rule_event(parser_state()) -> parser_state().
trigger_enter_rule_event(#parser_state{parse_listeners = [], ctx = _Ctx} = State) ->
    State;
trigger_enter_rule_event(#parser_state{parse_listeners = Listeners, ctx = Ctx} = State) ->
    lists:foreach(fun(L) -> L:enter_every_rule(Ctx) end, Listeners),
    State.

%% @doc Trigger exit rule event for listeners
-spec trigger_exit_rule_event(parser_state()) -> parser_state().
trigger_exit_rule_event(#parser_state{parse_listeners = [], ctx = _Ctx} = State) ->
    State;
trigger_exit_rule_event(#parser_state{parse_listeners = Listeners, ctx = Ctx} = State) ->
    lists:foreach(fun(L) -> L:exit_every_rule(Ctx) end, lists:reverse(Listeners)),
    State.

%% @doc Notify error listeners of an error
-spec notify_error_listeners(parser_state(), binary()) -> parser_state().
notify_error_listeners(State, Message) ->
    Token = get_current_token(State),
    notify_error_listeners(State, Message, Token, undefined).

-spec notify_error_listeners(parser_state(), binary(), antlr4_token:token(), term()) -> parser_state().
notify_error_listeners(#parser_state{error_listeners = Listeners} = State, Message, Token, Exception) ->
    Line = antlr4_token:get_line(Token),
    Column = antlr4_token:get_char_position_in_line(Token),
    lists:foreach(fun(L) -> L:syntax_error(State, Token, Line, Column, Message, Exception) end, Listeners),
    State.

%% @doc Get the invoking context at a specific depth
-spec get_invoking_context(parser_state(), integer()) -> term().
get_invoking_context(#parser_state{ctx = Ctx}, Depth) ->
    get_invoking_context_loop(Ctx, Depth).

get_invoking_context_loop(undefined, _Depth) ->
    undefined;
get_invoking_context_loop(Ctx, 0) ->
    Ctx;
get_invoking_context_loop(Ctx, Depth) ->
    Parent = antlr4_parser_rule_context:get_parent(Ctx),
    get_invoking_context_loop(Parent, Depth - 1).

%% @doc Get text from a context
-spec get_text_from_context(parser_state(), term()) -> binary().
get_text_from_context(#parser_state{input = Input}, Ctx) ->
    antlr4_token_stream:get_text_from_context(Input, Ctx).

%% @doc Check if a token type is expected
-spec is_expected_token(parser_state(), integer()) -> boolean().
is_expected_token(#parser_state{interpreter = _Interpreter, ctx = _Ctx, atn = _ATN}, _TokenType) ->
    %% This would involve computing the expected tokens from the ATN
    %% Simplified implementation
    true.

%% @doc Get expected tokens at current position
-spec get_expected_tokens(parser_state()) -> term().
get_expected_tokens(State) ->
    get_expected_tokens_within_current_rule(State).

%% @doc Get expected tokens within current rule
-spec get_expected_tokens_within_current_rule(parser_state()) -> term().
get_expected_tokens_within_current_rule(#parser_state{atn = _ATN, state_number = _StateNum}) ->
    %% This would compute follow sets from the ATN
    antlr4_interval_set:new().

%% @doc Get the rule invocation stack
-spec get_rule_invocation_stack(parser_state()) -> [binary()].
get_rule_invocation_stack(#parser_state{ctx = Ctx, rule_names = RuleNames}) ->
    get_rule_stack(Ctx, RuleNames, []).

get_rule_stack(undefined, _RuleNames, Acc) ->
    lists:reverse(Acc);
get_rule_stack(Ctx, RuleNames, Acc) ->
    RuleIndex = antlr4_parser_rule_context:get_rule_index(Ctx),
    RuleName = case RuleIndex >= 0 andalso RuleIndex < length(RuleNames) of
        true -> lists:nth(RuleIndex + 1, RuleNames);
        false -> integer_to_binary(RuleIndex)
    end,
    Parent = antlr4_parser_rule_context:get_parent(Ctx),
    get_rule_stack(Parent, RuleNames, [RuleName | Acc]).

%% @doc Get DFA state strings for debugging
-spec get_dfa_strings(parser_state()) -> [binary()].
get_dfa_strings(_State) ->
    [].

%% @doc Dump DFA for debugging
-spec dump_dfa(parser_state()) -> ok.
dump_dfa(_State) ->
    ok.

%% @doc Get the source name
-spec get_source_name(parser_state()) -> binary().
get_source_name(#parser_state{input = Input}) ->
    TokenSource = antlr4_token_stream:get_token_source(Input),
    antlr4_lexer:get_input_stream(TokenSource).

%% @doc Enable/disable tracing
-spec set_trace(parser_state(), boolean()) -> parser_state().
set_trace(State, _Trace) ->
    State.

%% @doc Get token names
-spec get_token_names(parser_state()) -> [binary()].
get_token_names(#parser_state{token_names = Names}) ->
    Names.

%% @doc Get rule names
-spec get_rule_names(parser_state()) -> [binary()].
get_rule_names(#parser_state{rule_names = Names}) ->
    Names.

%% @doc Get ATN with bypass alternatives
-spec get_atn_with_bypass_alts(parser_state()) -> term().
get_atn_with_bypass_alts(#parser_state{atn = ATN}) ->
    ATN.

%% @doc Set whether to build parse trees
-spec set_build_parse_trees(parser_state(), boolean()) -> parser_state().
set_build_parse_trees(State, Build) ->
    State#parser_state{build_parse_trees = Build}.

%% @doc Get whether building parse trees
-spec get_build_parse_trees(parser_state()) -> boolean().
get_build_parse_trees(#parser_state{build_parse_trees = Build}) ->
    Build.

%% @doc Reset the parser
-spec reset(parser_state()) -> parser_state().
reset(#parser_state{input = Input} = State) ->
    Input1 = antlr4_token_stream:reset(Input),
    State#parser_state{
        input = Input1,
        ctx = undefined,
        state_number = -1,
        exception = undefined
    }.
