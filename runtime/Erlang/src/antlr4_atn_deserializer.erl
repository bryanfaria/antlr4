%% ANTLR4 ATN Deserializer
%% Deserializes ATN from integer array

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

    %% Read header
    {_Version, Pos1} = read_int(DataArray, Pos),
    {_UUID1, Pos2} = read_uuid(DataArray, Pos1),

    %% Read grammar type
    {GrammarTypeInt, Pos3} = read_int(DataArray, Pos2),
    GrammarType = case GrammarTypeInt of
        0 -> lexer;
        1 -> parser
    end,

    %% Read max token type
    {MaxTokenType, Pos4} = read_int(DataArray, Pos3),

    %% Create empty ATN
    ATN0 = antlr4_atn:new(GrammarType, MaxTokenType),

    %% Read states
    {ATN1, Pos5} = read_states(DataArray, Pos4, ATN0),

    %% Read rules
    {ATN2, Pos6} = read_rules(DataArray, Pos5, ATN1),

    %% Read modes (lexer only)
    {ATN3, Pos7} = read_modes(DataArray, Pos6, ATN2, GrammarType),

    %% Read sets
    {Sets, Pos8} = read_sets(DataArray, Pos7),

    %% Read edges (transitions)
    {ATN4, Pos9} = read_edges(DataArray, Pos8, ATN3, Sets),

    %% Read decisions
    {ATN5, Pos10} = read_decisions(DataArray, Pos9, ATN4),

    %% Read lexer actions (lexer only)
    {ATN6, _Pos11} = read_lexer_actions(DataArray, Pos10, ATN5, GrammarType),

    ATN6.

%% Read a single integer from the data
read_int(DataArray, Pos) ->
    Value = array:get(Pos, DataArray),
    {Value, Pos + 1}.

%% Read a UUID (5 integers)
read_uuid(DataArray, Pos) ->
    %% UUID is stored as 5 16-bit values
    {_, Pos1} = read_int(DataArray, Pos),
    {_, Pos2} = read_int(DataArray, Pos1),
    {_, Pos3} = read_int(DataArray, Pos2),
    {_, Pos4} = read_int(DataArray, Pos3),
    {_, Pos5} = read_int(DataArray, Pos4),
    {ok, Pos5}.

%% Read all states
read_states(DataArray, Pos, ATN) ->
    {NumStates, Pos1} = read_int(DataArray, Pos),
    read_states_loop(DataArray, Pos1, ATN, NumStates).

read_states_loop(_DataArray, Pos, ATN, 0) ->
    {ATN, Pos};
read_states_loop(DataArray, Pos, ATN, Remaining) ->
    {StateType, Pos1} = read_int(DataArray, Pos),
    {RuleIndex, Pos2} = read_int(DataArray, Pos1),
    State = create_state(StateType, RuleIndex),
    ATN1 = antlr4_atn:add_state(ATN, State),
    read_states_loop(DataArray, Pos2, ATN1, Remaining - 1).

create_state(StateType, RuleIndex) ->
    #atn_state{
        state_type = StateType,
        rule_index = RuleIndex,
        transitions = []
    }.

%% Read rules
read_rules(DataArray, Pos, ATN) ->
    {NumRules, Pos1} = read_int(DataArray, Pos),
    read_rules_loop(DataArray, Pos1, ATN, NumRules, [], []).

read_rules_loop(_DataArray, Pos, ATN, 0, StartStates, StopStates) ->
    States = antlr4_atn:get_states(ATN),
    RuleToStart = [lists:nth(S + 1, States) || S <- lists:reverse(StartStates)],
    RuleToStop = [lists:nth(S + 1, States) || S <- lists:reverse(StopStates)],
    ATN1 = ATN#atn{
        rule_to_start_state = RuleToStart,
        rule_to_stop_state = RuleToStop
    },
    {ATN1, Pos};
read_rules_loop(DataArray, Pos, ATN, Remaining, StartStates, StopStates) ->
    {StartState, Pos1} = read_int(DataArray, Pos),
    {StopState, Pos2} = read_int(DataArray, Pos1),
    read_rules_loop(DataArray, Pos2, ATN, Remaining - 1, [StartState | StartStates], [StopState | StopStates]).

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

create_transition(Type, Target, Arg1, Arg2, _Arg3, Sets) ->
    IsEpsilon = Type =:= ?ATN_TRANSITION_EPSILON,
    Label = case Type of
        ?ATN_TRANSITION_EPSILON -> undefined;
        ?ATN_TRANSITION_ATOM -> Arg1;
        ?ATN_TRANSITION_RANGE -> #interval{start_index = Arg1, stop_index = Arg2};
        ?ATN_TRANSITION_SET -> lists:nth(Arg1 + 1, Sets);
        ?ATN_TRANSITION_NOT_SET -> lists:nth(Arg1 + 1, Sets);
        _ -> undefined
    end,
    #atn_transition{
        transition_type = Type,
        target = Target,
        label = Label,
        is_epsilon = IsEpsilon
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
