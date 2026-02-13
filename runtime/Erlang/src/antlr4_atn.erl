%% ANTLR4 ATN Module
%% Augmented Transition Network representation

-module(antlr4_atn).

-include("antlr4_runtime.hrl").

-export([
    new/2,
    get_grammar_type/1,
    get_max_token_type/1,
    get_states/1,
    add_state/2,
    get_state/2,
    get_number_of_decisions/1,
    get_decision_state/2,
    get_rule_to_start_state/1,
    get_rule_to_stop_state/1,
    get_rule_to_token_type/1,
    get_mode_to_start_state/1,
    get_expected_tokens/3,
    create_decision_to_dfa/1
]).

-type atn() :: #atn{}.
-export_type([atn/0]).

%% @doc Create a new ATN
-spec new(lexer | parser, integer()) -> atn().
new(GrammarType, MaxTokenType) ->
    #atn{
        grammar_type = GrammarType,
        max_token_type = MaxTokenType,
        states = [],
        rule_to_start_state = [],
        rule_to_stop_state = [],
        mode_to_start_state = [],
        decision_to_state = []
    }.

%% @doc Get the grammar type
-spec get_grammar_type(atn()) -> lexer | parser.
get_grammar_type(#atn{grammar_type = Type}) ->
    Type.

%% @doc Get the maximum token type
-spec get_max_token_type(atn()) -> integer().
get_max_token_type(#atn{max_token_type = MaxType}) ->
    MaxType.

%% @doc Get all states
-spec get_states(atn()) -> [#atn_state{}].
get_states(#atn{states = States}) ->
    States.

%% @doc Add a state to the ATN
-spec add_state(atn(), #atn_state{}) -> atn().
add_state(#atn{states = States} = ATN, State) ->
    StateNum = length(States),
    State1 = State#atn_state{state_number = StateNum},
    ATN#atn{states = States ++ [State1]}.

%% @doc Get a state by number
-spec get_state(atn(), integer()) -> #atn_state{} | undefined.
get_state(#atn{states = States}, StateNum) when StateNum >= 0, StateNum < length(States) ->
    lists:nth(StateNum + 1, States);
get_state(_, _) ->
    undefined.

%% @doc Get the number of decisions
-spec get_number_of_decisions(atn()) -> integer().
get_number_of_decisions(#atn{decision_to_state = DecisionToState}) ->
    length(DecisionToState).

%% @doc Get a decision state by decision number
-spec get_decision_state(atn(), integer()) -> #atn_state{} | undefined.
get_decision_state(#atn{decision_to_state = DecisionToState}, Decision)
  when Decision >= 0, Decision < length(DecisionToState) ->
    lists:nth(Decision + 1, DecisionToState);
get_decision_state(_, _) ->
    undefined.

%% @doc Get rule to start state mapping
-spec get_rule_to_start_state(atn()) -> [#atn_state{}].
get_rule_to_start_state(#atn{rule_to_start_state = RuleToStart}) ->
    RuleToStart.

%% @doc Get rule to stop state mapping
-spec get_rule_to_stop_state(atn()) -> [#atn_state{}].
get_rule_to_stop_state(#atn{rule_to_stop_state = RuleToStop}) ->
    RuleToStop.

%% @doc Get rule to token type mapping (for lexer)
-spec get_rule_to_token_type(atn()) -> [integer()].
get_rule_to_token_type(#atn{rule_to_token_type = RuleToToken}) ->
    RuleToToken.

%% @doc Get mode to start state mapping (for lexer)
-spec get_mode_to_start_state(atn()) -> [#atn_state{}].
get_mode_to_start_state(#atn{mode_to_start_state = ModeToStart}) ->
    ModeToStart.

%% @doc Get expected tokens from a state within a context
-spec get_expected_tokens(atn(), integer(), term()) -> antlr4_interval_set:interval_set().
get_expected_tokens(ATN, StateNumber, Ctx) ->
    State = get_state(ATN, StateNumber),
    Following = next_tokens(ATN, State),
    case antlr4_interval_set:contains(Following, ?ANTLR4_TOKEN_EPSILON) of
        false ->
            Following;
        true ->
            Expected = antlr4_interval_set:new(),
            Expected1 = antlr4_interval_set:add_all(Expected, Following),
            Expected2 = antlr4_interval_set:remove(Expected1, ?ANTLR4_TOKEN_EPSILON),
            add_following_tokens(ATN, Expected2, Ctx)
    end.

%% @doc Create DFA array for all decision states
-spec create_decision_to_dfa(atn()) -> [antlr4_dfa:dfa()].
create_decision_to_dfa(#atn{decision_to_state = DecisionToState}) ->
    [antlr4_dfa:new(State, I) || {State, I} <- lists:zip(DecisionToState, lists:seq(0, length(DecisionToState) - 1))].

%% Internal: get next tokens from a state
next_tokens(_ATN, undefined) ->
    antlr4_interval_set:new();
next_tokens(_ATN, #atn_state{next_token_within_rule = NextTokens}) when NextTokens =/= undefined ->
    NextTokens;
next_tokens(ATN, State) ->
    compute_next_tokens(ATN, State, antlr4_interval_set:new(), #{}).

compute_next_tokens(ATN, #atn_state{transitions = Transitions} = State, Set, Visited) ->
    Key = State#atn_state.state_number,
    case maps:is_key(Key, Visited) of
        true ->
            Set;
        false ->
            Visited1 = maps:put(Key, true, Visited),
            lists:foldl(
                fun(Transition, AccSet) ->
                    process_transition(ATN, Transition, AccSet, Visited1)
                end,
                Set,
                Transitions
            )
    end.

process_transition(_ATN, #atn_transition{transition_type = ?ATN_TRANSITION_RULE}, Set, _Visited) ->
    %% For rule transitions, add epsilon and follow
    antlr4_interval_set:add(Set, ?ANTLR4_TOKEN_EPSILON);
process_transition(_ATN, #atn_transition{transition_type = ?ATN_TRANSITION_WILDCARD}, Set, _Visited) ->
    %% Wildcard matches everything except EOF
    Set1 = antlr4_interval_set:add_interval(Set, ?ANTLR4_TOKEN_MIN_USER_TOKEN_TYPE, 16#FFFF),
    Set1;
process_transition(_ATN, #atn_transition{transition_type = Type, label = Label}, Set, _Visited)
  when Type =:= ?ATN_TRANSITION_ATOM; Type =:= ?ATN_TRANSITION_RANGE; Type =:= ?ATN_TRANSITION_SET ->
    %% Add the label to the set
    case Label of
        #interval_set{} ->
            antlr4_interval_set:add_all(Set, Label);
        _ when is_integer(Label) ->
            antlr4_interval_set:add(Set, Label);
        _ ->
            Set
    end;
process_transition(_ATN, #atn_transition{transition_type = ?ATN_TRANSITION_NOT_SET, label = Label}, Set, _Visited) ->
    %% Add complement of set
    Complement = antlr4_interval_set:complement(Label, ?ANTLR4_TOKEN_MIN_USER_TOKEN_TYPE, 16#FFFF),
    antlr4_interval_set:add_all(Set, Complement);
process_transition(ATN, #atn_transition{is_epsilon = true, target = Target}, Set, Visited) ->
    %% Follow epsilon transitions
    compute_next_tokens(ATN, Target, Set, Visited);
process_transition(_ATN, _Transition, Set, _Visited) ->
    Set.

%% Internal: add following tokens from context
add_following_tokens(_ATN, Expected, undefined) ->
    Expected;
add_following_tokens(ATN, Expected, Ctx) ->
    case antlr4_parser_rule_context:get_invoking_state(Ctx) of
        -1 ->
            Expected;
        InvokingState ->
            State = get_state(ATN, InvokingState),
            Following = next_tokens(ATN, State),
            Expected1 = antlr4_interval_set:add_all(Expected, Following),
            case antlr4_interval_set:contains(Following, ?ANTLR4_TOKEN_EPSILON) of
                false ->
                    Expected1;
                true ->
                    Expected2 = antlr4_interval_set:remove(Expected1, ?ANTLR4_TOKEN_EPSILON),
                    Parent = antlr4_parser_rule_context:get_parent(Ctx),
                    add_following_tokens(ATN, Expected2, Parent)
            end
    end.
