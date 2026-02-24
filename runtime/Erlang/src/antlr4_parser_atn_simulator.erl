%% ANTLR4 Parser ATN Simulator
%% Simulates the ATN for parser prediction
%% Uses a StateMap to resolve stale state references (same pattern as lexer simulator)

-module(antlr4_parser_atn_simulator).

-include("antlr4_runtime.hrl").

-export([
    new/3,
    adaptive_predict/4,
    reset/1,
    clear_dfa/1,
    get_dfa/2
]).

-record(parser_simulator, {
    atn :: antlr4_atn:atn(),
    decision_to_dfa :: [antlr4_dfa:dfa()],
    shared_context_cache :: term()
}).

-type parser_simulator() :: #parser_simulator{}.
-export_type([parser_simulator/0]).

%% @doc Create a new parser ATN simulator
-spec new(antlr4_atn:atn(), [antlr4_dfa:dfa()], term()) -> parser_simulator().
new(ATN, DecisionToDFA, SharedContextCache) ->
    #parser_simulator{
        atn = ATN,
        decision_to_dfa = DecisionToDFA,
        shared_context_cache = SharedContextCache
    }.

%% @doc Adaptive prediction - use DFA if possible, fall back to ATN
-spec adaptive_predict(parser_simulator(), antlr4_token_stream:token_stream(), integer(), term()) -> integer().
adaptive_predict(Simulator, TokenStream, Decision, OuterContext) ->
    #parser_simulator{atn = ATN, decision_to_dfa = DFAs} = Simulator,

    %% Build state lookup map for resolving stale state references
    StateMap = build_state_map(ATN),

    %% Get DFA for this decision
    DFA = lists:nth(Decision + 1, DFAs),

    %% Get start state for this decision
    DecisionState0 = antlr4_atn:get_decision_state(ATN, Decision),
    DecisionState = resolve_state(DecisionState0, StateMap),

    %% Try DFA first
    S0 = antlr4_dfa:get_s0(DFA),
    case S0 of
        undefined ->
            %% Need to build DFA from ATN
            atn_predict(Simulator, TokenStream, Decision, DecisionState, OuterContext, DFA, StateMap);
        _ ->
            %% Use existing DFA
            dfa_predict(Simulator, TokenStream, S0, DFA, OuterContext, StateMap)
    end.

%% @doc Reset the simulator
-spec reset(parser_simulator()) -> parser_simulator().
reset(Simulator) ->
    Simulator.

%% @doc Clear the DFA cache
-spec clear_dfa(parser_simulator()) -> parser_simulator().
clear_dfa(#parser_simulator{atn = ATN} = Simulator) ->
    DecisionToDFA = antlr4_atn:create_decision_to_dfa(ATN),
    Simulator#parser_simulator{decision_to_dfa = DecisionToDFA}.

%% @doc Get the DFA for a specific decision
-spec get_dfa(parser_simulator(), integer()) -> antlr4_dfa:dfa() | undefined.
get_dfa(#parser_simulator{decision_to_dfa = DFAs}, Decision) when Decision < length(DFAs) ->
    lists:nth(Decision + 1, DFAs);
get_dfa(_, _) ->
    undefined.

%% Build a map from state_number -> state for resolving stale references
build_state_map(ATN) ->
    maps:from_list(
        [{S#atn_state.state_number, S} || S <- ATN#atn.states]
    ).

%% Resolve a potentially stale state reference through the state map
resolve_state(#atn_state{state_number = Num}, StateMap) ->
    maps:get(Num, StateMap);
resolve_state(undefined, _StateMap) ->
    undefined.

%% Internal: DFA-based prediction
dfa_predict(Simulator, TokenStream, S0, DFA, OuterContext, StateMap) ->
    TokenIndex = antlr4_token_stream:get_index(TokenStream),
    dfa_predict_loop(Simulator, TokenStream, S0, DFA, OuterContext, TokenIndex, StateMap).

dfa_predict_loop(Simulator, TokenStream, DFAState, DFA, OuterContext, StartIndex, StateMap) ->
    case antlr4_dfa_state:is_accept_state(DFAState) of
        true ->
            antlr4_dfa_state:get_prediction(DFAState);
        false ->
            Token = antlr4_token_stream:lt(TokenStream, 1),
            TokenType = antlr4_token:get_type(Token),

            case TokenType of
                ?ANTLR4_TOKEN_EOF ->
                    ?ANTLR4_ATN_INVALID_ALT_NUMBER;
                _ ->
                    case antlr4_dfa_state:get_edge(DFAState, TokenType) of
                        undefined ->
                            DecisionState0 = antlr4_dfa:get_atn_start_state(DFA),
                            DecisionState = resolve_state(DecisionState0, StateMap),
                            atn_predict(Simulator, TokenStream, antlr4_dfa:get_decision(DFA),
                                       DecisionState, OuterContext, DFA, StateMap);
                        TargetState ->
                            TokenStream1 = antlr4_token_stream:consume(TokenStream),
                            dfa_predict_loop(Simulator, TokenStream1, TargetState, DFA, OuterContext, StartIndex, StateMap)
                    end
            end
    end.

%% Internal: ATN-based prediction
atn_predict(Simulator, TokenStream, _Decision, DecisionState, OuterContext, DFA, StateMap) ->
    ATN = Simulator#parser_simulator.atn,

    %% Compute start state with closure
    StartState = compute_start_state(ATN, DecisionState, OuterContext, StateMap),

    %% Save initial token index
    StartIndex = antlr4_token_stream:get_index(TokenStream),

    %% Simulate ATN
    atn_predict_loop(Simulator, TokenStream, StartState, ATN, DFA, OuterContext, StartIndex, StateMap).

atn_predict_loop(Simulator, TokenStream, ConfigSet, ATN, DFA, OuterContext, StartIndex, StateMap) ->
    case get_unique_alt(ConfigSet) of
        Alt when Alt =/= ?ANTLR4_ATN_INVALID_ALT_NUMBER ->
            Alt;
        _ ->
            Token = antlr4_token_stream:lt(TokenStream, 1),
            TokenType = antlr4_token:get_type(Token),

            case TokenType of
                ?ANTLR4_TOKEN_EOF ->
                    resolve_to_min_alt(ConfigSet);
                _ ->
                    NewConfigSet = compute_reach_set(ConfigSet, TokenType, ATN, StateMap),
                    case NewConfigSet of
                        #atn_config_set{configs = []} ->
                            ?ANTLR4_ATN_INVALID_ALT_NUMBER;
                        _ ->
                            TokenStream1 = antlr4_token_stream:consume(TokenStream),
                            atn_predict_loop(Simulator, TokenStream1, NewConfigSet, ATN, DFA, OuterContext, StartIndex, StateMap)
                    end
            end
    end.

%% Internal: compute start state configuration set
compute_start_state(ATN, DecisionState, _OuterContext, StateMap) ->
    Transitions = DecisionState#atn_state.transitions,

    Configs = lists:map(
        fun({#atn_transition{target = Target}, AltIndex}) ->
            ResolvedTarget = resolve_state(Target, StateMap),
            #atn_config{
                state = ResolvedTarget,
                alt = AltIndex,
                context = #prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY},
                semantic_context = undefined
            }
        end,
        lists:zip(Transitions, lists:seq(1, length(Transitions)))
    ),

    %% Closure over epsilon transitions
    closure(#atn_config_set{configs = Configs}, ATN, StateMap).

%% Internal: compute reach set on a symbol
compute_reach_set(#atn_config_set{configs = Configs}, Symbol, ATN, StateMap) ->
    NewConfigs = lists:flatmap(
        fun(Config) ->
            get_reachable_target(Config, Symbol, StateMap)
        end,
        Configs
    ),

    closure(#atn_config_set{configs = NewConfigs}, ATN, StateMap).

%% Internal: get reachable targets from a config on a symbol
get_reachable_target(#atn_config{state = State, alt = Alt, context = Ctx}, Symbol, StateMap) ->
    Transitions = State#atn_state.transitions,
    lists:filtermap(
        fun(#atn_transition{is_epsilon = true}) ->
                %% Skip epsilon transitions - handled by closure
                false;
           (Transition) ->
                case matches_transition(Transition, Symbol) of
                    true ->
                        #atn_transition{target = Target} = Transition,
                        ResolvedTarget = resolve_state(Target, StateMap),
                        {true, #atn_config{state = ResolvedTarget, alt = Alt, context = Ctx}};
                    false ->
                        false
                end
        end,
        Transitions
    ).

%% Internal: check if a transition matches a symbol
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_ATOM, label = Label}, Symbol) ->
    Label =:= Symbol;
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_RANGE, label = #interval{start_index = A, stop_index = B}}, Symbol) ->
    Symbol >= A andalso Symbol =< B;
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_SET, label = Set}, Symbol) ->
    antlr4_interval_set:contains(Set, Symbol);
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_NOT_SET, label = Set}, Symbol) ->
    not antlr4_interval_set:contains(Set, Symbol);
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_WILDCARD}, Symbol) ->
    Symbol =/= ?ANTLR4_TOKEN_EOF;
matches_transition(_, _) ->
    false.

%% Internal: compute closure over epsilon transitions
%% Uses StateMap to resolve stale state references
closure(ConfigSet, ATN, StateMap) ->
    closure(ConfigSet, ConfigSet, ATN, StateMap, #{}).

closure(#atn_config_set{configs = []} = Result, _WorkList, _ATN, _StateMap, _Visited) ->
    Result;
closure(Result, #atn_config_set{configs = []}, _ATN, _StateMap, _Visited) ->
    Result;
closure(Result, #atn_config_set{configs = [Config | Rest]}, ATN, StateMap, Visited) ->
    Key = {Config#atn_config.state#atn_state.state_number, Config#atn_config.alt},
    case maps:is_key(Key, Visited) of
        true ->
            closure(Result, #atn_config_set{configs = Rest}, ATN, StateMap, Visited);
        false ->
            Visited1 = maps:put(Key, true, Visited),
            EpsilonConfigs = get_epsilon_targets(Config, ATN, StateMap),

            #atn_config_set{configs = ResultConfigs} = Result,
            NewResult = Result#atn_config_set{configs = ResultConfigs ++ EpsilonConfigs},
            NewWorkList = #atn_config_set{configs = Rest ++ EpsilonConfigs},

            closure(NewResult, NewWorkList, ATN, StateMap, Visited1)
    end.

%% Internal: get epsilon targets from a config
%% Handles PRECEDENCE transitions by checking against the parser's precedence stack
get_epsilon_targets(#atn_config{state = State, alt = Alt, context = Ctx}, _ATN, StateMap) ->
    Transitions = State#atn_state.transitions,
    lists:filtermap(
        fun(Transition) ->
            case Transition#atn_transition.is_epsilon of
                true ->
                    #atn_transition{target = Target, transition_type = Type, label = Label} = Transition,
                    ResolvedTarget = resolve_state(Target, StateMap),
                    case Type of
                        ?ATN_TRANSITION_PRECEDENCE ->
                            %% For precedence transitions, check if the current
                            %% precedence allows this transition. Label holds the
                            %% required precedence value. We check against the
                            %% parser's precedence stack via process dictionary.
                            case check_precedence(Label) of
                                true ->
                                    {true, #atn_config{state = ResolvedTarget, alt = Alt, context = Ctx}};
                                false ->
                                    false
                            end;
                        _ ->
                            {true, #atn_config{state = ResolvedTarget, alt = Alt, context = Ctx}}
                    end;
                false ->
                    false
            end
        end,
        Transitions
    ).

%% Check if a precedence value is allowed by the parser's current precedence stack.
%% The parser stores its state in the process dictionary under 'antlr4_parser_state'.
check_precedence(Precedence) ->
    case get(antlr4_parser_state) of
        undefined ->
            %% No parser state — allow all (happens during lexer-only use)
            true;
        _State ->
            %% Use the process-dict API to get current precedence
            Top = antlr4_parser:get_precedence(),
            Precedence >= Top
    end.

%% Internal: get unique alternative if only one exists
get_unique_alt(#atn_config_set{configs = Configs}) ->
    Alts = lists:usort([Alt || #atn_config{alt = Alt} <- Configs]),
    case Alts of
        [SingleAlt] -> SingleAlt;
        _ -> ?ANTLR4_ATN_INVALID_ALT_NUMBER
    end.

%% Internal: resolve conflict by choosing minimum alternative
resolve_to_min_alt(#atn_config_set{configs = []}) ->
    ?ANTLR4_ATN_INVALID_ALT_NUMBER;
resolve_to_min_alt(#atn_config_set{configs = Configs}) ->
    Alts = [Alt || #atn_config{alt = Alt} <- Configs],
    lists:min(Alts).
