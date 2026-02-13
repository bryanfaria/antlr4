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
    prev_accept :: {integer(), antlr4_dfa_state:dfa_state(), integer()} | undefined
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

%% @doc Match input starting at the current position
-spec match(lexer_simulator(), antlr4_input_stream:input_stream(), integer()) -> integer().
match(Simulator, Input, Mode) ->
    ATN = Simulator#lexer_simulator.atn,
    DecisionToDFA = Simulator#lexer_simulator.decision_to_dfa,

    %% Get the start state for this mode
    ModeStartStates = antlr4_atn:get_mode_to_start_state(ATN),
    StartState = case Mode < length(ModeStartStates) of
        true -> lists:nth(Mode + 1, ModeStartStates);
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
            match_atn(Simulator, SimState, StartState, DFA);
        S0 ->
            %% Use DFA-based matching
            exec_dfa(Simulator, SimState, S0, DFA)
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

%% Internal: match using ATN simulation
match_atn(Simulator, SimState, StartState, _DFA) ->
    ATN = Simulator#lexer_simulator.atn,

    %% Initialize with start state configurations
    Reach = compute_start_state(StartState),

    %% Simulate the ATN
    {TokenType, _NewSimState} = atn_loop(Simulator, SimState, Reach, ATN),

    case TokenType of
        ?ANTLR4_TOKEN_INVALID_TYPE ->
            throw({lexer_no_viable_alt, SimState});
        _ ->
            TokenType
    end.

%% Internal: execute DFA-based matching
exec_dfa(Simulator, SimState, S0, DFA) ->
    %% Simulate the DFA
    {TokenType, _NewSimState} = dfa_loop(Simulator, SimState, S0, DFA),

    case TokenType of
        ?ANTLR4_TOKEN_INVALID_TYPE ->
            %% DFA couldn't match, try ATN
            StartState = antlr4_dfa:get_atn_start_state(DFA),
            match_atn(Simulator, SimState, StartState, DFA);
        _ ->
            TokenType
    end.

%% Internal: compute start state configurations
compute_start_state(StartState) ->
    %% Create initial configs from start state
    Transitions = StartState#atn_state.transitions,
    Configs = lists:map(
        fun(#atn_transition{target = Target}) ->
            #atn_config{
                state = Target,
                alt = 0,
                context = #prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY},
                semantic_context = undefined
            }
        end,
        Transitions
    ),
    #atn_config_set{configs = Configs}.

%% Internal: ATN simulation loop
atn_loop(Simulator, SimState, ConfigSet, ATN) ->
    #sim_state{input = Input, prev_accept = PrevAccept} = SimState,

    %% Get the current input symbol
    CurrentChar = antlr4_input_stream:la(Input, 1),

    case CurrentChar of
        ?ANTLR4_TOKEN_EOF ->
            %% End of input
            finalize_match(SimState, PrevAccept);
        _ ->
            %% Compute next state
            case get_existing_target_state(ConfigSet, CurrentChar, ATN) of
                undefined ->
                    %% Need to compute target
                    case compute_target_state(ConfigSet, CurrentChar, ATN) of
                        #atn_config_set{configs = []} ->
                            %% No valid transitions
                            finalize_match(SimState, PrevAccept);
                        NewConfigSet ->
                            %% Check if this is an accept state
                            NewPrevAccept = check_accept(NewConfigSet, SimState),
                            Input1 = antlr4_input_stream:consume(Input),
                            SimState1 = SimState#sim_state{
                                input = Input1,
                                prev_accept = NewPrevAccept
                            },
                            atn_loop(Simulator, SimState1, NewConfigSet, ATN)
                    end;
                NewConfigSet ->
                    %% Have existing target
                    NewPrevAccept = check_accept(NewConfigSet, SimState),
                    Input1 = antlr4_input_stream:consume(Input),
                    SimState1 = SimState#sim_state{
                        input = Input1,
                        prev_accept = NewPrevAccept
                    },
                    atn_loop(Simulator, SimState1, NewConfigSet, ATN)
            end
    end.

%% Internal: DFA simulation loop
dfa_loop(Simulator, SimState, DFAState, DFA) ->
    #sim_state{input = Input, prev_accept = PrevAccept} = SimState,

    %% Check if this is an accept state
    NewPrevAccept = case antlr4_dfa_state:is_accept_state(DFAState) of
        true ->
            Prediction = antlr4_dfa_state:get_prediction(DFAState),
            StopIndex = antlr4_input_stream:get_index(Input),
            {Prediction, DFAState, StopIndex};
        false ->
            PrevAccept
    end,

    %% Get the current input symbol
    CurrentChar = antlr4_input_stream:la(Input, 1),

    case CurrentChar of
        ?ANTLR4_TOKEN_EOF ->
            finalize_match(SimState#sim_state{prev_accept = NewPrevAccept}, NewPrevAccept);
        _ ->
            %% Look up the edge
            case antlr4_dfa_state:get_edge(DFAState, CurrentChar) of
                undefined ->
                    %% No edge, return what we have
                    finalize_match(SimState#sim_state{prev_accept = NewPrevAccept}, NewPrevAccept);
                TargetState ->
                    Input1 = antlr4_input_stream:consume(Input),
                    SimState1 = SimState#sim_state{
                        input = Input1,
                        prev_accept = NewPrevAccept
                    },
                    dfa_loop(Simulator, SimState1, TargetState, DFA)
            end
    end.

%% Internal: finalize the match
finalize_match(_SimState, undefined) ->
    {?ANTLR4_TOKEN_INVALID_TYPE, undefined};
finalize_match(SimState, {TokenType, _DFAState, _StopIndex}) ->
    {TokenType, SimState}.

%% Internal: check if config set represents an accept state
check_accept(#atn_config_set{configs = Configs}, SimState) ->
    #sim_state{input = Input, prev_accept = PrevAccept} = SimState,
    StopIndex = antlr4_input_stream:get_index(Input),

    %% Find accepting configs (those in rule stop states)
    AcceptConfigs = [C || #atn_config{state = S} = C <- Configs,
                         S#atn_state.state_type =:= ?ATN_STATE_RULE_STOP],

    case AcceptConfigs of
        [] ->
            PrevAccept;
        [#atn_config{alt = Alt} | _] ->
            {Alt, undefined, StopIndex}
    end.

%% Internal: get existing target state (placeholder)
get_existing_target_state(_ConfigSet, _Char, _ATN) ->
    undefined.

%% Internal: compute target state
compute_target_state(#atn_config_set{configs = Configs}, Char, ATN) ->
    NewConfigs = lists:flatmap(
        fun(Config) ->
            get_reachable_configs(Config, Char, ATN)
        end,
        Configs
    ),
    #atn_config_set{configs = NewConfigs}.

%% Internal: get reachable configurations from a config on input char
get_reachable_configs(#atn_config{state = State} = Config, Char, _ATN) ->
    Transitions = State#atn_state.transitions,
    lists:filtermap(
        fun(Transition) ->
            case matches_transition(Transition, Char) of
                true ->
                    #atn_transition{target = Target} = Transition,
                    {true, Config#atn_config{state = Target}};
                false ->
                    false
            end
        end,
        Transitions
    ).

%% Internal: check if a transition matches the current character
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_ATOM, label = Label}, Char) ->
    Label =:= Char;
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_RANGE, label = #interval{start_index = A, stop_index = B}}, Char) ->
    Char >= A andalso Char =< B;
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_SET, label = Set}, Char) ->
    antlr4_interval_set:contains(Set, Char);
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_NOT_SET, label = Set}, Char) ->
    not antlr4_interval_set:contains(Set, Char);
matches_transition(#atn_transition{transition_type = ?ATN_TRANSITION_WILDCARD}, Char) ->
    Char =/= ?ANTLR4_TOKEN_EOF;
matches_transition(#atn_transition{is_epsilon = true}, _Char) ->
    true;
matches_transition(_, _) ->
    false.
