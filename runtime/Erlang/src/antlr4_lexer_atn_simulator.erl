%% ANTLR4 Lexer ATN Simulator
%% Simulates the ATN for lexer prediction

-module(antlr4_lexer_atn_simulator).

-include("antlr4_runtime.hrl").

-export([
    new/3,
    match/3,
    reset/1,
    clear_dfa/1,
    get_dfa/2
]).

-record(lexer_simulator, {
    atn :: antlr4_atn:atn(),
    decision_to_dfa :: [antlr4_dfa:dfa()],
    shared_context_cache :: term(),
    recog :: term(),
    start_index :: integer(),
    line :: integer(),
    char_position_in_line :: integer(),
    mode :: integer(),
    prev_accept :: term()
}).

-type lexer_simulator() :: #lexer_simulator{}.
-export_type([lexer_simulator/0]).

-record(sim_state, {
    input :: antlr4_input_stream:input_stream(),
    start_index :: integer(),
    line :: integer(),
    char_position_in_line :: integer(),
    dfa_state :: antlr4_dfa_state:dfa_state() | undefined,
    %% {TokenType, LexerActions, DFAState, StopIndex}
    prev_accept :: {integer(), [#lexer_action{}], term(), integer()} | undefined
}).

%% @doc Create a new lexer ATN simulator
-spec new(antlr4_atn:atn(), [antlr4_dfa:dfa()], term()) -> lexer_simulator().
new(ATN, DecisionToDFA, SharedContextCache) ->
    #lexer_simulator{
        atn = ATN,
        decision_to_dfa = DecisionToDFA,
        shared_context_cache = SharedContextCache,
        recog = undefined,
        start_index = 0,
        line = 1,
        char_position_in_line = 0,
        mode = 0,
        prev_accept = undefined
    }.

%% @doc Match input starting at the current position.
%% Returns {TokenType, LexerActions, NewInput} where LexerActions is a list of
%% #lexer_action{} records accumulated during the match, and NewInput is the
%% input stream positioned after the matched token.
-spec match(lexer_simulator(), antlr4_input_stream:input_stream(), integer()) ->
    {integer(), [#lexer_action{}], antlr4_input_stream:input_stream()}.
match(Simulator, Input, Mode) ->
    ATN = Simulator#lexer_simulator.atn,
    DecisionToDFA = Simulator#lexer_simulator.decision_to_dfa,

    %% Build state lookup map for resolving stale state references.
    %% Erlang records are immutable, so transition targets may be stale copies
    %% from before transitions were added to those states. This map always
    %% provides the current, fully-populated version of each state.
    StateMap = build_state_map(ATN),

    %% Get the start state for this mode
    ModeStartStates = antlr4_atn:get_mode_to_start_state(ATN),
    StartState = case Mode < length(ModeStartStates) of
        true ->
            S = lists:nth(Mode + 1, ModeStartStates),
            resolve_state(S, StateMap);
        false -> throw({illegal_argument, <<"Invalid mode">>})
    end,

    %% Get or create the DFA for this mode
    DFA = case Mode < length(DecisionToDFA) of
        true -> lists:nth(Mode + 1, DecisionToDFA);
        false -> antlr4_dfa:new(StartState, Mode)
    end,

    %% Try DFA-based matching first
    SimState = #sim_state{
        input = Input,
        start_index = antlr4_input_stream:get_index(Input),
        line = antlr4_input_stream:get_line(Input),
        char_position_in_line = antlr4_input_stream:get_char_position_in_line(Input),
        dfa_state = antlr4_dfa:get_s0(DFA),
        prev_accept = undefined
    },

    case SimState#sim_state.dfa_state of
        undefined ->
            %% No DFA yet, use ATN simulation
            match_atn(Simulator, SimState, StartState, DFA, StateMap);
        S0 ->
            %% Use DFA-based matching
            exec_dfa(Simulator, SimState, S0, DFA, StateMap)
    end.

%% @doc Reset the simulator
-spec reset(lexer_simulator()) -> lexer_simulator().
reset(Simulator) ->
    Simulator#lexer_simulator{
        start_index = 0,
        line = 1,
        char_position_in_line = 0,
        mode = 0,
        prev_accept = undefined
    }.

%% @doc Clear the DFA cache
-spec clear_dfa(lexer_simulator()) -> lexer_simulator().
clear_dfa(#lexer_simulator{atn = ATN} = Simulator) ->
    DecisionToDFA = antlr4_atn:create_decision_to_dfa(ATN),
    Simulator#lexer_simulator{decision_to_dfa = DecisionToDFA}.

%% @doc Get the DFA for a specific mode
-spec get_dfa(lexer_simulator(), integer()) -> antlr4_dfa:dfa() | undefined.
get_dfa(#lexer_simulator{decision_to_dfa = DFAs}, Mode) when Mode < length(DFAs) ->
    lists:nth(Mode + 1, DFAs);
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

%% Internal: match using ATN simulation
match_atn(Simulator, SimState, StartState, _DFA, StateMap) ->
    ATN = Simulator#lexer_simulator.atn,

    %% Initialize with start state configurations (with epsilon closure)
    Reach = compute_start_state(StartState, ATN, StateMap),

    %% Check for immediate accept at start
    SimState1 = SimState#sim_state{
        prev_accept = check_accept(Reach, SimState, ATN)
    },

    %% Simulate the ATN
    Result = atn_loop(Simulator, SimState1, Reach, ATN, StateMap),

    case Result of
        {?ANTLR4_TOKEN_INVALID_TYPE, _Actions, _Input} ->
            throw({lexer_no_viable_alt, SimState});
        {TokenType, Actions, NewInput} ->
            {TokenType, Actions, NewInput}
    end.

%% Internal: execute DFA-based matching
exec_dfa(Simulator, SimState, S0, DFA, StateMap) ->
    %% Simulate the DFA
    Result = dfa_loop(Simulator, SimState, S0, DFA),

    case Result of
        {?ANTLR4_TOKEN_INVALID_TYPE, _Actions, _Input} ->
            %% DFA couldn't match, try ATN
            StartState = antlr4_dfa:get_atn_start_state(DFA),
            match_atn(Simulator, SimState, StartState, DFA, StateMap);
        {TokenType, Actions, NewInput} ->
            {TokenType, Actions, NewInput}
    end.

%% Internal: compute start state configurations with epsilon closure
compute_start_state(StartState, ATN, StateMap) ->
    %% Create initial configs from start state transitions
    Transitions = StartState#atn_state.transitions,
    InitialConfigs = lists:map(
        fun({Index, #atn_transition{target = Target}}) ->
            %% Resolve target through state map to get current version
            ResolvedTarget = resolve_state(Target, StateMap),
            #atn_config{
                state = ResolvedTarget,
                alt = Index + 1,
                context = #prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY},
                semantic_context = undefined,
                lexer_actions = []
            }
        end,
        lists:zip(lists:seq(0, length(Transitions) - 1), Transitions)
    ),
    %% Apply epsilon closure to all initial configs
    ClosedConfigs = epsilon_closure(InitialConfigs, ATN, StateMap),
    #atn_config_set{configs = ClosedConfigs}.

%% Internal: epsilon closure - follow all epsilon transitions without consuming input
%% Accumulates lexer actions when traversing ACTION transitions
%% Uses StateMap to resolve stale state references
epsilon_closure(Configs, ATN, StateMap) ->
    epsilon_closure_loop(Configs, ATN, StateMap, #{}, []).

epsilon_closure_loop([], _ATN, _StateMap, _Visited, Acc) ->
    lists:reverse(Acc);
epsilon_closure_loop([#atn_config{state = State} = Config | Rest], ATN, StateMap, Visited, Acc) ->
    Key = {State#atn_state.state_number, Config#atn_config.alt},
    case maps:is_key(Key, Visited) of
        true ->
            epsilon_closure_loop(Rest, ATN, StateMap, Visited, Acc);
        false ->
            Visited1 = maps:put(Key, true, Visited),
            %% Find epsilon transitions from this state
            EpsilonTargets = lists:filtermap(
                fun(#atn_transition{is_epsilon = true, transition_type = Type,
                                    target = Target, action_index = AI}) ->
                    %% Resolve target through state map
                    ResolvedTarget = resolve_state(Target, StateMap),
                    NewConfig = case Type of
                        ?ATN_TRANSITION_ACTION when AI =/= undefined ->
                            LexerActions = ATN#atn.lexer_actions,
                            Action = case AI < length(LexerActions) of
                                true -> lists:nth(AI + 1, LexerActions);
                                false -> undefined
                            end,
                            case Action of
                                undefined ->
                                    Config#atn_config{state = ResolvedTarget};
                                _ ->
                                    Config#atn_config{
                                        state = ResolvedTarget,
                                        lexer_actions = Config#atn_config.lexer_actions ++ [Action]
                                    }
                            end;
                        _ ->
                            Config#atn_config{state = ResolvedTarget}
                    end,
                    {true, NewConfig};
                   (#atn_transition{is_epsilon = false}) ->
                    false
                end,
                State#atn_state.transitions
            ),
            %% Add current config to result and continue with epsilon targets
            epsilon_closure_loop(EpsilonTargets ++ Rest, ATN, StateMap, Visited1, [Config | Acc])
    end.

%% Internal: ATN simulation loop
%% Follows Java's order: compute target, consume, THEN check accept
atn_loop(Simulator, SimState, ConfigSet, ATN, StateMap) ->
    #sim_state{input = Input, prev_accept = PrevAccept} = SimState,

    %% Get the current input symbol
    CurrentChar = antlr4_input_stream:la(Input, 1),

    case CurrentChar of
        ?ANTLR4_TOKEN_EOF ->
            %% End of input - check for accept in current config set
            NewPrevAccept = check_accept(ConfigSet, SimState, ATN),
            BestAccept = best_accept(NewPrevAccept, PrevAccept),
            finalize_match(BestAccept, Input);
        _ ->
            %% Compute next state (only character-matching transitions + epsilon closure)
            NewConfigSet = compute_target_state(ConfigSet, CurrentChar, ATN, StateMap),
            case NewConfigSet of
                #atn_config_set{configs = []} ->
                    %% No valid transitions - use last accept
                    finalize_match(PrevAccept, Input);
                _ ->
                    %% Consume the character FIRST (like Java)
                    Input1 = antlr4_input_stream:consume(Input),
                    %% THEN check if this is an accept state (after consume)
                    SimState1 = SimState#sim_state{input = Input1},
                    NewPrevAccept = check_accept(NewConfigSet, SimState1, ATN),
                    %% Use best accept found so far
                    BestAccept = best_accept(NewPrevAccept, PrevAccept),
                    SimState2 = SimState1#sim_state{
                        prev_accept = BestAccept
                    },
                    atn_loop(Simulator, SimState2, NewConfigSet, ATN, StateMap)
            end
    end.

%% Pick the better accept (prefer new if available)
best_accept(undefined, Old) -> Old;
best_accept(New, _Old) -> New.

%% Internal: DFA simulation loop
dfa_loop(Simulator, SimState, DFAState, DFA) ->
    #sim_state{input = Input, prev_accept = PrevAccept} = SimState,

    %% Check if this is an accept state
    NewPrevAccept = case antlr4_dfa_state:is_accept_state(DFAState) of
        true ->
            Prediction = antlr4_dfa_state:get_prediction(DFAState),
            StopIndex = antlr4_input_stream:get_index(Input),
            Actions = case DFAState of
                #dfa_state{lexer_action_executor = LAE} when is_list(LAE) -> LAE;
                _ -> []
            end,
            {Prediction, Actions, DFAState, StopIndex};
        false ->
            PrevAccept
    end,

    %% Get the current input symbol
    CurrentChar = antlr4_input_stream:la(Input, 1),

    case CurrentChar of
        ?ANTLR4_TOKEN_EOF ->
            finalize_match(NewPrevAccept, Input);
        _ ->
            %% Look up the edge
            case antlr4_dfa_state:get_edge(DFAState, CurrentChar) of
                undefined ->
                    %% No edge, return what we have
                    finalize_match(NewPrevAccept, Input);
                TargetState ->
                    Input1 = antlr4_input_stream:consume(Input),
                    SimState1 = SimState#sim_state{
                        input = Input1,
                        prev_accept = NewPrevAccept
                    },
                    dfa_loop(Simulator, SimState1, TargetState, DFA)
            end
    end.

%% Internal: finalize the match - return {TokenType, LexerActions, Input}
%% Seeks input to the accept position (StopIndex) so the lexer
%% knows where the matched token ends.
finalize_match(undefined, Input) ->
    {?ANTLR4_TOKEN_INVALID_TYPE, [], Input};
finalize_match({TokenType, Actions, _DFAState, StopIndex}, Input) ->
    %% Seek input to the accept position
    %% StopIndex is the input index AFTER consuming the last matched char
    %% (like Java: capture happens after consume)
    FinalInput = antlr4_input_stream:seek(Input, StopIndex),
    {TokenType, Actions, FinalInput}.

%% Internal: check if config set contains an accept state (rule stop state)
%% Returns {TokenType, LexerActions, undefined, StopIndex} or undefined
check_accept(#atn_config_set{configs = Configs}, SimState, _ATN) ->
    #sim_state{input = Input} = SimState,
    StopIndex = antlr4_input_stream:get_index(Input),

    %% Find accepting configs (those in rule stop states)
    AcceptConfigs = [C || #atn_config{state = S} = C <- Configs,
                         S#atn_state.state_type =:= ?ATN_STATE_RULE_STOP],

    case AcceptConfigs of
        [] ->
            undefined;
        [#atn_config{state = AcceptState, lexer_actions = Actions} | _] ->
            %% Token type is rule_index + 1 (rule indices are 0-based,
            %% token types start at 1 for user tokens)
            TokenType = AcceptState#atn_state.rule_index + 1,
            {TokenType, Actions, undefined, StopIndex}
    end.

%% Internal: compute target state - follow character-matching transitions
%% then apply epsilon closure
compute_target_state(#atn_config_set{configs = Configs}, Char, ATN, StateMap) ->
    %% Get configs reachable by character-matching transitions only
    ReachedConfigs = lists:flatmap(
        fun(Config) ->
            get_reachable_configs(Config, Char, StateMap)
        end,
        Configs
    ),
    %% Apply epsilon closure to reached configs
    ClosedConfigs = epsilon_closure(ReachedConfigs, ATN, StateMap),
    #atn_config_set{configs = ClosedConfigs}.

%% Internal: get reachable configurations from a config on input char
%% Only follows non-epsilon (character-matching) transitions
%% Uses StateMap to resolve stale target references
get_reachable_configs(#atn_config{state = State} = Config, Char, StateMap) ->
    Transitions = State#atn_state.transitions,
    lists:filtermap(
        fun(#atn_transition{is_epsilon = true}) ->
                %% Skip epsilon transitions - handled by epsilon_closure
                false;
           (Transition) ->
                case matches_transition(Transition, Char) of
                    true ->
                        #atn_transition{target = Target} = Transition,
                        %% Resolve target through state map
                        ResolvedTarget = resolve_state(Target, StateMap),
                        {true, Config#atn_config{state = ResolvedTarget}};
                    false ->
                        false
                end
        end,
        Transitions
    ).

%% Internal: check if a transition matches the current character
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_ATOM, label = Label}, Char) ->
    Label =:= Char;
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_RANGE,
                                    label = #interval{start_index = A, stop_index = B}}, Char) ->
    Char >= A andalso Char =< B;
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_SET, label = Set}, Char) ->
    antlr4_interval_set:contains(Set, Char);
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_NOT_SET, label = Set}, Char) ->
    not antlr4_interval_set:contains(Set, Char);
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_WILDCARD}, Char) ->
    Char =/= ?ANTLR4_TOKEN_EOF;
matches_transition(_, _) ->
    false.
