%% ANTLR4 Runtime Header File
%% Common records, types, and macros for ANTLR4 Erlang runtime

-ifndef(ANTLR4_RUNTIME_HRL).
-define(ANTLR4_RUNTIME_HRL, true).

%% Token constants
-define(ANTLR4_TOKEN_INVALID_TYPE, 0).
-define(ANTLR4_TOKEN_EPSILON, -2).
-define(ANTLR4_TOKEN_MIN_USER_TOKEN_TYPE, 1).
-define(ANTLR4_TOKEN_EOF, -1).
-define(ANTLR4_TOKEN_DEFAULT_CHANNEL, 0).
-define(ANTLR4_TOKEN_HIDDEN_CHANNEL, 1).
-define(ANTLR4_TOKEN_MIN_USER_CHANNEL_VALUE, 2).

%% ATN constants
-define(ANTLR4_ATN_INVALID_ALT_NUMBER, 0).

%% Token record
-record(token, {
    type = ?ANTLR4_TOKEN_INVALID_TYPE :: integer(),
    channel = ?ANTLR4_TOKEN_DEFAULT_CHANNEL :: integer(),
    text :: binary() | undefined,
    token_index = -1 :: integer(),
    start_index = -1 :: integer(),
    stop_index = -1 :: integer(),
    line = -1 :: integer(),
    char_position_in_line = -1 :: integer(),
    source :: {term(), term()} | undefined
}).

%% Common token record (with source reference)
-record(common_token, {
    type = ?ANTLR4_TOKEN_INVALID_TYPE :: integer(),
    channel = ?ANTLR4_TOKEN_DEFAULT_CHANNEL :: integer(),
    text :: binary() | undefined,
    token_index = -1 :: integer(),
    start_index = -1 :: integer(),
    stop_index = -1 :: integer(),
    line = -1 :: integer(),
    char_position_in_line = -1 :: integer(),
    input_stream :: term()
}).

%% Input stream position
-record(input_stream, {
    data :: binary(),
    size :: non_neg_integer(),
    index = 0 :: non_neg_integer(),
    line = 1 :: pos_integer(),
    char_position_in_line = 0 :: non_neg_integer(),
    name :: binary()
}).

%% Token stream
-record(token_stream, {
    token_source :: term(),
    tokens = [] :: [#common_token{}],
    index = -1 :: integer(),
    fetched_eof = false :: boolean(),
    channel = ?ANTLR4_TOKEN_DEFAULT_CHANNEL :: integer()
}).

%% Parser rule context
-record(parser_rule_context, {
    parent :: term(),
    invoking_state = -1 :: integer(),
    rule_index = -1 :: integer(),
    start_token :: #common_token{} | undefined,
    stop_token :: #common_token{} | undefined,
    exception :: term(),
    children = [] :: [term()],
    alt_number = 0 :: integer()
}).

%% Terminal node
-record(terminal_node, {
    symbol :: #common_token{},
    parent :: term()
}).

%% Error node
-record(error_node, {
    symbol :: #common_token{},
    parent :: term()
}).

%% ATN State types
-define(ATN_STATE_INVALID, 0).
-define(ATN_STATE_BASIC, 1).
-define(ATN_STATE_RULE_START, 2).
-define(ATN_STATE_BLOCK_START, 3).
-define(ATN_STATE_PLUS_BLOCK_START, 4).
-define(ATN_STATE_STAR_BLOCK_START, 5).
-define(ATN_STATE_TOKEN_START, 6).
-define(ATN_STATE_RULE_STOP, 7).
-define(ATN_STATE_BLOCK_END, 8).
-define(ATN_STATE_STAR_LOOP_BACK, 9).
-define(ATN_STATE_STAR_LOOP_ENTRY, 10).
-define(ATN_STATE_PLUS_LOOP_BACK, 11).
-define(ATN_STATE_LOOP_END, 12).

%% ATN Transition types
-define(ATN_TRANSITION_EPSILON, 1).
-define(ATN_TRANSITION_RANGE, 2).
-define(ATN_TRANSITION_RULE, 3).
-define(ATN_TRANSITION_PREDICATE, 4).
-define(ATN_TRANSITION_ATOM, 5).
-define(ATN_TRANSITION_ACTION, 6).
-define(ATN_TRANSITION_SET, 7).
-define(ATN_TRANSITION_NOT_SET, 8).
-define(ATN_TRANSITION_WILDCARD, 9).
-define(ATN_TRANSITION_PRECEDENCE, 10).

%% ATN record
-record(atn, {
    grammar_type :: lexer | parser,
    max_token_type :: integer(),
    states = [] :: [term()],
    rule_to_start_state = [] :: [term()],
    rule_to_stop_state = [] :: [term()],
    mode_name_to_start_state = #{} :: #{binary() => term()},
    mode_to_start_state = [] :: [term()],
    rule_to_token_type = [] :: [integer()],
    lexer_actions = [] :: [term()],
    decision_to_state = [] :: [term()]
}).

%% ATN State record
-record(atn_state, {
    state_number = -1 :: integer(),
    state_type = ?ATN_STATE_INVALID :: integer(),
    rule_index = -1 :: integer(),
    epsilon_only_transitions = false :: boolean(),
    transitions = [] :: [term()],
    next_token_within_rule :: term()
}).

%% ATN Transition record
-record(atn_transition, {
    transition_type :: integer(),
    target :: #atn_state{},
    label :: term(),
    is_epsilon = false :: boolean()
}).

%% DFA record
-record(dfa, {
    atn_start_state :: #atn_state{},
    decision :: integer(),
    states = #{} :: #{term() => term()},
    s0 :: term(),
    precedence_dfa = false :: boolean()
}).

%% DFA State record
-record(dfa_state, {
    state_number = -1 :: integer(),
    configs :: term(),
    edges = #{} :: #{integer() => term()},
    is_accept_state = false :: boolean(),
    prediction :: integer(),
    requires_full_context = false :: boolean(),
    predicates :: [term()]
}).

%% Interval record
-record(interval, {
    start_index :: integer(),
    stop_index :: integer()
}).

%% Interval set record
-record(interval_set, {
    intervals = [] :: [#interval{}],
    read_only = false :: boolean()
}).

%% Prediction context types
-define(PREDICTION_CONTEXT_EMPTY, empty).
-define(PREDICTION_CONTEXT_SINGLETON, singleton).
-define(PREDICTION_CONTEXT_ARRAY, array).

%% Prediction context record
-record(prediction_context, {
    context_type :: atom(),
    id :: integer(),
    parents :: [term()],
    return_states :: [integer()],
    cached_hash_code :: integer()
}).

%% Semantic context types
-define(SEMANTIC_CONTEXT_PREDICATE, predicate).
-define(SEMANTIC_CONTEXT_PRECEDENCE, precedence).
-define(SEMANTIC_CONTEXT_AND, 'and').
-define(SEMANTIC_CONTEXT_OR, 'or').

%% Semantic context record
-record(semantic_context, {
    context_type :: atom(),
    rule_index :: integer(),
    pred_index :: integer(),
    is_ctx_dependent :: boolean(),
    operands :: [term()],
    precedence :: integer()
}).

%% ATN Config record
-record(atn_config, {
    state :: #atn_state{},
    alt :: integer(),
    context :: #prediction_context{},
    semantic_context :: #semantic_context{} | undefined,
    reaches_into_outer_context = 0 :: integer(),
    precedence_filter_suppressed = false :: boolean()
}).

%% ATN Config Set record
-record(atn_config_set, {
    configs = [] :: [#atn_config{}],
    unique_alt :: integer(),
    conflicting_alts :: term(),
    has_semantic_context = false :: boolean(),
    dips_into_outer_context = false :: boolean(),
    full_ctx = false :: boolean(),
    read_only = false :: boolean(),
    cached_hash_code :: integer()
}).

%% Lexer action types
-define(LEXER_ACTION_CHANNEL, channel).
-define(LEXER_ACTION_CUSTOM, custom).
-define(LEXER_ACTION_MODE, mode).
-define(LEXER_ACTION_MORE, more).
-define(LEXER_ACTION_POP_MODE, pop_mode).
-define(LEXER_ACTION_PUSH_MODE, push_mode).
-define(LEXER_ACTION_SKIP, skip).
-define(LEXER_ACTION_TYPE, type).

%% Lexer action record
-record(lexer_action, {
    action_type :: atom(),
    data :: term()
}).

%% Recognition exception types
-record(recognition_exception, {
    message :: binary(),
    recognizer :: term(),
    input :: term(),
    ctx :: term(),
    offending_token :: #common_token{},
    offending_state :: integer()
}).

-record(no_viable_alt_exception, {
    base :: #recognition_exception{},
    dead_end_configs :: #atn_config_set{},
    start_token :: #common_token{}
}).

-record(input_mismatch_exception, {
    base :: #recognition_exception{}
}).

-record(failed_predicate_exception, {
    base :: #recognition_exception{},
    rule_index :: integer(),
    pred_index :: integer(),
    predicate :: binary()
}).

-record(lexer_no_viable_alt_exception, {
    base :: #recognition_exception{},
    start_index :: integer(),
    dead_end_configs :: #atn_config_set{}
}).

-endif.  % ANTLR4_RUNTIME_HRL
