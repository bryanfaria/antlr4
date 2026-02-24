%% ANTLR4 ATN Deserializer
%% Deserializes ATN from integer array (ANTLR4 serialized ATN format v4)

-module(antlr4_atn_deserializer).

-include("antlr4_runtime.hrl").

-export([
    deserialize/1
]).

%% ATN serialization constants
-define(SERIALIZED_VERSION, 4).

%% @doc Deserialize an ATN from a list of integers
-spec deserialize([integer()]) -> antlr4_atn:atn().
deserialize(Data) when is_list(Data) ->
    %% Convert to array for random access
    DataArray = array:from_list(Data),
    Pos = 0,

    %% Read header (no UUID in format v4)
    {_Version, Pos1} = read_int(DataArray, Pos),

    %% Read grammar type
    {GrammarTypeInt, Pos2} = read_int(DataArray, Pos1),
    GrammarType = case GrammarTypeInt of
        0 -> lexer;
        1 -> parser
    end,

    %% Read max token type
    {MaxTokenType, Pos3} = read_int(DataArray, Pos2),

    %% Create empty ATN
    ATN0 = antlr4_atn:new(GrammarType, MaxTokenType),

    %% Read states (handles extra ints for LOOP_END and BlockStartState)
    {ATN1, Pos4} = read_states(DataArray, Pos3, ATN0),

    %% Read non-greedy states (skip over them)
    {_ATN2, Pos5} = read_non_greedy_states(DataArray, Pos4, ATN1),

    %% Read precedence states (skip over them)
    {ATN3, Pos6} = read_precedence_states(DataArray, Pos5, ATN1),
    _ = ATN3,

    %% Read rules (format differs for lexer vs parser)
    {ATN4, Pos7} = read_rules(DataArray, Pos6, ATN1, GrammarType),

    %% Read modes (lexer only)
    {ATN5, Pos8} = read_modes(DataArray, Pos7, ATN4, GrammarType),

    %% Read sets
    {Sets, Pos9} = read_sets(DataArray, Pos8),

    %% Read edges (transitions)
    {ATN6, Pos10} = read_edges(DataArray, Pos9, ATN5, Sets),

    %% Read decisions
    {ATN7, Pos11} = read_decisions(DataArray, Pos10, ATN6),

    %% Read lexer actions (lexer only)
    {ATN8, _Pos12} = read_lexer_actions(DataArray, Pos11, ATN7, GrammarType),

    %% Refresh all state references (rule_to_start_state, rule_to_stop_state,
    %% mode_to_start_state, decision_to_state) since edges may have been added
    %% to the states list after these references were created.
    refresh_state_references(ATN8).

%% Read a single integer from the data
read_int(DataArray, Pos) ->
    Value = array:get(Pos, DataArray),
    {Value, Pos + 1}.

%% Read all states - handles extra ints for LOOP_END and BlockStartState subtypes
read_states(DataArray, Pos, ATN) ->
    {NumStates, Pos1} = read_int(DataArray, Pos),
    read_states_loop(DataArray, Pos1, ATN, NumStates).

read_states_loop(_DataArray, Pos, ATN, 0) ->
    {ATN, Pos};
read_states_loop(DataArray, Pos, ATN, Remaining) ->
    {StateType, Pos1} = read_int(DataArray, Pos),
    case StateType of
        ?ATN_STATE_INVALID ->
            %% Invalid/null state: only type is read, no ruleIndex
            ATN1 = antlr4_atn:add_state(ATN, #atn_state{
                state_type = ?ATN_STATE_INVALID,
                rule_index = -1,
                transitions = []
            }),
            read_states_loop(DataArray, Pos1, ATN1, Remaining - 1);
        _ ->
            {RuleIndex, Pos2} = read_int(DataArray, Pos1),
            State = create_state(StateType, RuleIndex),
            ATN1 = antlr4_atn:add_state(ATN, State),
            %% Handle extra int for LOOP_END (loopBackStateNumber)
            Pos3 = case StateType of
                ?ATN_STATE_LOOP_END ->
                    {_LoopBackStateNumber, P} = read_int(DataArray, Pos2),
                    P;
                _ ->
                    Pos2
            end,
            %% Handle extra int for BlockStartState subtypes (endStateNumber)
            %% BlockStartState types: BLOCK_START(3), PLUS_BLOCK_START(4), STAR_BLOCK_START(5)
            Pos4 = case StateType of
                ?ATN_STATE_BLOCK_START ->
                    {_EndStateNum, P2} = read_int(DataArray, Pos3),
                    P2;
                ?ATN_STATE_PLUS_BLOCK_START ->
                    {_EndStateNum2, P2} = read_int(DataArray, Pos3),
                    P2;
                ?ATN_STATE_STAR_BLOCK_START ->
                    {_EndStateNum3, P2} = read_int(DataArray, Pos3),
                    P2;
                _ ->
                    Pos3
            end,
            read_states_loop(DataArray, Pos4, ATN1, Remaining - 1)
    end.

create_state(StateType, RuleIndex) ->
    #atn_state{
        state_type = StateType,
        rule_index = RuleIndex,
        transitions = []
    }.

%% Read non-greedy states (mark decision states as non-greedy)
read_non_greedy_states(DataArray, Pos, ATN) ->
    {NumNonGreedy, Pos1} = read_int(DataArray, Pos),
    skip_ints(DataArray, Pos1, NumNonGreedy, ATN).

%% Read precedence states (mark rule start states as left-recursive)
read_precedence_states(DataArray, Pos, ATN) ->
    {NumPrecedence, Pos1} = read_int(DataArray, Pos),
    skip_ints(DataArray, Pos1, NumPrecedence, ATN).

%% Skip N integers (for sections we don't fully process)
skip_ints(_DataArray, Pos, 0, ATN) ->
    {ATN, Pos};
skip_ints(DataArray, Pos, N, ATN) ->
    {_, Pos1} = read_int(DataArray, Pos),
    skip_ints(DataArray, Pos1, N - 1, ATN).

%% Read rules - format differs for lexer vs parser
read_rules(DataArray, Pos, ATN, GrammarType) ->
    {NumRules, Pos1} = read_int(DataArray, Pos),
    read_rules_loop(DataArray, Pos1, ATN, GrammarType, NumRules, [], []).

read_rules_loop(_DataArray, Pos, ATN, _GrammarType, 0, StartStates, TokenTypes) ->
    States = antlr4_atn:get_states(ATN),
    RuleToStart = [lists:nth(S + 1, States) || S <- lists:reverse(StartStates)],
    %% Derive stop states from state data (find RULE_STOP states by rule_index)
    RuleToStop = derive_stop_states(States, length(StartStates)),
    ATN1 = ATN#atn{
        rule_to_start_state = RuleToStart,
        rule_to_stop_state = RuleToStop,
        rule_to_token_type = lists:reverse(TokenTypes)
    },
    {ATN1, Pos};
read_rules_loop(DataArray, Pos, ATN, lexer, Remaining, StartStates, TokenTypes) ->
    %% Lexer: each rule has startState + tokenType
    {StartState, Pos1} = read_int(DataArray, Pos),
    {TokenType, Pos2} = read_int(DataArray, Pos1),
    read_rules_loop(DataArray, Pos2, ATN, lexer, Remaining - 1,
                    [StartState | StartStates], [TokenType | TokenTypes]);
read_rules_loop(DataArray, Pos, ATN, parser, Remaining, StartStates, TokenTypes) ->
    %% Parser: each rule has only startState
    {StartState, Pos1} = read_int(DataArray, Pos),
    read_rules_loop(DataArray, Pos1, ATN, parser, Remaining - 1,
                    [StartState | StartStates], TokenTypes).

%% Derive rule stop states from state data
derive_stop_states(States, NumRules) ->
    %% Build a map of rule_index -> stop state
    StopMap = lists:foldl(
        fun(#atn_state{state_type = ?ATN_STATE_RULE_STOP, rule_index = RI} = S, Acc) ->
            maps:put(RI, S, Acc);
           (_, Acc) ->
            Acc
        end,
        #{},
        States
    ),
    [maps:get(I, StopMap, undefined) || I <- lists:seq(0, NumRules - 1)].

%% Read modes (for lexer)
read_modes(DataArray, Pos, ATN, lexer) ->
    {NumModes, Pos1} = read_int(DataArray, Pos),
    read_modes_loop(DataArray, Pos1, ATN, NumModes, []);
read_modes(_DataArray, Pos, ATN, parser) ->
    {ATN, Pos}.

read_modes_loop(_DataArray, Pos, ATN, 0, ModeStates) ->
    States = antlr4_atn:get_states(ATN),
    ModeToStart = [lists:nth(S + 1, States) || S <- lists:reverse(ModeStates)],
    ATN1 = ATN#atn{mode_to_start_state = ModeToStart},
    {ATN1, Pos};
read_modes_loop(DataArray, Pos, ATN, Remaining, ModeStates) ->
    {ModeState, Pos1} = read_int(DataArray, Pos),
    read_modes_loop(DataArray, Pos1, ATN, Remaining - 1, [ModeState | ModeStates]).

%% Read interval sets
read_sets(DataArray, Pos) ->
    {NumSets, Pos1} = read_int(DataArray, Pos),
    read_sets_loop(DataArray, Pos1, NumSets, []).

read_sets_loop(_DataArray, Pos, 0, Sets) ->
    {lists:reverse(Sets), Pos};
read_sets_loop(DataArray, Pos, Remaining, Sets) ->
    {Set, Pos1} = read_set(DataArray, Pos),
    read_sets_loop(DataArray, Pos1, Remaining - 1, [Set | Sets]).

read_set(DataArray, Pos) ->
    {NumIntervals, Pos1} = read_int(DataArray, Pos),
    {_ContainsEof, Pos2} = read_int(DataArray, Pos1),
    read_intervals(DataArray, Pos2, NumIntervals, antlr4_interval_set:new()).

read_intervals(_DataArray, Pos, 0, Set) ->
    {Set, Pos};
read_intervals(DataArray, Pos, Remaining, Set) ->
    {A, Pos1} = read_int(DataArray, Pos),
    {B, Pos2} = read_int(DataArray, Pos1),
    Set1 = antlr4_interval_set:add_interval(Set, A, B),
    read_intervals(DataArray, Pos2, Remaining - 1, Set1).

%% Read edges (transitions)
read_edges(DataArray, Pos, ATN, Sets) ->
    {NumEdges, Pos1} = read_int(DataArray, Pos),
    read_edges_loop(DataArray, Pos1, ATN, Sets, NumEdges).

read_edges_loop(_DataArray, Pos, ATN, _Sets, 0) ->
    {ATN, Pos};
read_edges_loop(DataArray, Pos, ATN, Sets, Remaining) ->
    {Src, Pos1} = read_int(DataArray, Pos),
    {Trg, Pos2} = read_int(DataArray, Pos1),
    {Type, Pos3} = read_int(DataArray, Pos2),
    {Arg1, Pos4} = read_int(DataArray, Pos3),
    {Arg2, Pos5} = read_int(DataArray, Pos4),
    {Arg3, Pos6} = read_int(DataArray, Pos5),

    States = antlr4_atn:get_states(ATN),
    TargetState = lists:nth(Trg + 1, States),
    Transition = create_transition(Type, TargetState, Arg1, Arg2, Arg3, Sets),

    SrcState = lists:nth(Src + 1, States),
    SrcState1 = SrcState#atn_state{
        transitions = SrcState#atn_state.transitions ++ [Transition]
    },
    States1 = lists:sublist(States, Src) ++ [SrcState1] ++ lists:nthtail(Src + 1, States),
    ATN1 = ATN#atn{states = States1},

    read_edges_loop(DataArray, Pos6, ATN1, Sets, Remaining - 1).

create_transition(Type, Target, Arg1, Arg2, Arg3, Sets) ->
    IsEpsilon = Type =:= ?ATN_TRANSITION_EPSILON orelse
                Type =:= ?ATN_TRANSITION_ACTION orelse
                Type =:= ?ATN_TRANSITION_RULE orelse
                Type =:= ?ATN_TRANSITION_PREDICATE orelse
                Type =:= ?ATN_TRANSITION_PRECEDENCE,
    Label = case Type of
        ?ATN_TRANSITION_EPSILON -> undefined;
        ?ATN_TRANSITION_ACTION -> undefined;
        ?ATN_TRANSITION_ATOM -> Arg1;
        ?ATN_TRANSITION_RANGE -> #interval{start_index = Arg1, stop_index = Arg2};
        ?ATN_TRANSITION_SET -> lists:nth(Arg1 + 1, Sets);
        ?ATN_TRANSITION_NOT_SET -> lists:nth(Arg1 + 1, Sets);
        ?ATN_TRANSITION_PRECEDENCE -> Arg1;  %% Arg1 is precedence value
        ?ATN_TRANSITION_RULE -> {Arg1, Arg2, Arg3};  %% {ruleIndex, precedence, followState}
        ?ATN_TRANSITION_PREDICATE -> {Arg1, Arg2, Arg3};  %% {ruleIndex, predIndex, isCtxDependent}
        _ -> undefined
    end,
    ActionIndex = case Type of
        ?ATN_TRANSITION_ACTION -> Arg2;  %% Arg2 is actionIndex (Arg1 is ruleIndex)
        _ -> undefined
    end,
    #atn_transition{
        transition_type = Type,
        target = Target,
        label = Label,
        is_epsilon = IsEpsilon,
        action_index = ActionIndex
    }.

%% Read decisions
read_decisions(DataArray, Pos, ATN) ->
    {NumDecisions, Pos1} = read_int(DataArray, Pos),
    read_decisions_loop(DataArray, Pos1, ATN, NumDecisions, []).

read_decisions_loop(_DataArray, Pos, ATN, 0, DecisionStates) ->
    States = antlr4_atn:get_states(ATN),
    DecisionToState = [lists:nth(S + 1, States) || S <- lists:reverse(DecisionStates)],
    ATN1 = ATN#atn{decision_to_state = DecisionToState},
    {ATN1, Pos};
read_decisions_loop(DataArray, Pos, ATN, Remaining, DecisionStates) ->
    {DecisionState, Pos1} = read_int(DataArray, Pos),
    read_decisions_loop(DataArray, Pos1, ATN, Remaining - 1, [DecisionState | DecisionStates]).

%% Read lexer actions
read_lexer_actions(DataArray, Pos, ATN, lexer) ->
    {NumActions, Pos1} = read_int(DataArray, Pos),
    read_lexer_actions_loop(DataArray, Pos1, ATN, NumActions, []);
read_lexer_actions(_DataArray, Pos, ATN, parser) ->
    {ATN, Pos}.

read_lexer_actions_loop(_DataArray, Pos, ATN, 0, Actions) ->
    ATN1 = ATN#atn{lexer_actions = lists:reverse(Actions)},
    {ATN1, Pos};
read_lexer_actions_loop(DataArray, Pos, ATN, Remaining, Actions) ->
    {ActionType, Pos1} = read_int(DataArray, Pos),
    {Data1, Pos2} = read_int(DataArray, Pos1),
    {Data2, Pos3} = read_int(DataArray, Pos2),
    Action = create_lexer_action(ActionType, Data1, Data2),
    read_lexer_actions_loop(DataArray, Pos3, ATN, Remaining - 1, [Action | Actions]).

create_lexer_action(0, Data1, _Data2) -> #lexer_action{action_type = ?LEXER_ACTION_CHANNEL, data = Data1};
create_lexer_action(1, Data1, Data2) -> #lexer_action{action_type = ?LEXER_ACTION_CUSTOM, data = {Data1, Data2}};
create_lexer_action(2, Data1, _Data2) -> #lexer_action{action_type = ?LEXER_ACTION_MODE, data = Data1};
create_lexer_action(3, _Data1, _Data2) -> #lexer_action{action_type = ?LEXER_ACTION_MORE, data = undefined};
create_lexer_action(4, _Data1, _Data2) -> #lexer_action{action_type = ?LEXER_ACTION_POP_MODE, data = undefined};
create_lexer_action(5, Data1, _Data2) -> #lexer_action{action_type = ?LEXER_ACTION_PUSH_MODE, data = Data1};
create_lexer_action(6, _Data1, _Data2) -> #lexer_action{action_type = ?LEXER_ACTION_SKIP, data = undefined};
create_lexer_action(7, Data1, _Data2) -> #lexer_action{action_type = ?LEXER_ACTION_TYPE, data = Data1}.

%% Refresh all state references after edges have been added.
%% Because Erlang records are immutable, the rule_to_start_state,
%% rule_to_stop_state, mode_to_start_state, and decision_to_state
%% lists contain stale copies of states (without transitions).
%% This function replaces them with the current versions from ATN.states.
refresh_state_references(#atn{states = States} = ATN) ->
    %% Build a lookup from state_number to current state
    StateMap = maps:from_list(
        [{S#atn_state.state_number, S} || S <- States]
    ),
    %% Also refresh targets in transitions
    FinalStates = [refresh_transition_targets(S, StateMap) || S <- States],
    FinalStateMap = maps:from_list(
        [{S#atn_state.state_number, S} || S <- FinalStates]
    ),
    ATN#atn{
        states = FinalStates,
        rule_to_start_state = [maps:get(S#atn_state.state_number, FinalStateMap, S)
                               || S <- ATN#atn.rule_to_start_state],
        rule_to_stop_state = [case S of
                                  undefined -> undefined;
                                  _ -> maps:get(S#atn_state.state_number, FinalStateMap, S)
                              end || S <- ATN#atn.rule_to_stop_state],
        mode_to_start_state = [maps:get(S#atn_state.state_number, FinalStateMap, S)
                               || S <- ATN#atn.mode_to_start_state],
        decision_to_state = [maps:get(S#atn_state.state_number, FinalStateMap, S)
                             || S <- ATN#atn.decision_to_state]
    }.

%% Update transition targets to point to the current state versions
refresh_transition_targets(#atn_state{transitions = Transitions} = State, StateMap) ->
    NewTransitions = [T#atn_transition{
        target = maps:get(
            (T#atn_transition.target)#atn_state.state_number,
            StateMap,
            T#atn_transition.target
        )
    } || T <- Transitions],
    State#atn_state{transitions = NewTransitions}.
