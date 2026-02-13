%% ANTLR4 DFA Module
%% Deterministic Finite Automaton for prediction

-module(antlr4_dfa).

-include("antlr4_runtime.hrl").

-export([
    new/2,
    get_decision/1,
    get_atn_start_state/1,
    get_s0/1,
    set_s0/2,
    get_states/1,
    add_state/2,
    get_state/2,
    is_precedence_dfa/1,
    set_precedence_dfa/2,
    to_string/1,
    to_string/2
]).

-type dfa() :: #dfa{}.
-export_type([dfa/0]).

%% @doc Create a new DFA
-spec new(#atn_state{}, integer()) -> dfa().
new(ATNStartState, Decision) ->
    #dfa{
        atn_start_state = ATNStartState,
        decision = Decision,
        states = #{},
        s0 = undefined,
        precedence_dfa = false
    }.

%% @doc Get the decision number
-spec get_decision(dfa()) -> integer().
get_decision(#dfa{decision = Decision}) ->
    Decision.

%% @doc Get the ATN start state
-spec get_atn_start_state(dfa()) -> #atn_state{}.
get_atn_start_state(#dfa{atn_start_state = State}) ->
    State.

%% @doc Get the start state (s0)
-spec get_s0(dfa()) -> #dfa_state{} | undefined.
get_s0(#dfa{s0 = S0}) ->
    S0.

%% @doc Set the start state (s0)
-spec set_s0(dfa(), #dfa_state{}) -> dfa().
set_s0(DFA, S0) ->
    DFA#dfa{s0 = S0}.

%% @doc Get all states
-spec get_states(dfa()) -> #{term() => #dfa_state{}}.
get_states(#dfa{states = States}) ->
    States.

%% @doc Add a state to the DFA
-spec add_state(dfa(), #dfa_state{}) -> {#dfa_state{}, dfa()}.
add_state(#dfa{states = States} = DFA, State) ->
    Key = get_state_key(State),
    case maps:find(Key, States) of
        {ok, ExistingState} ->
            {ExistingState, DFA};
        error ->
            StateNum = maps:size(States),
            State1 = State#dfa_state{state_number = StateNum},
            States1 = maps:put(Key, State1, States),
            {State1, DFA#dfa{states = States1}}
    end.

%% @doc Get a state by its key
-spec get_state(dfa(), term()) -> #dfa_state{} | undefined.
get_state(#dfa{states = States}, Key) ->
    maps:get(Key, States, undefined).

%% @doc Check if this is a precedence DFA
-spec is_precedence_dfa(dfa()) -> boolean().
is_precedence_dfa(#dfa{precedence_dfa = PrecDFA}) ->
    PrecDFA.

%% @doc Set whether this is a precedence DFA
-spec set_precedence_dfa(dfa(), boolean()) -> dfa().
set_precedence_dfa(DFA, PrecDFA) ->
    DFA#dfa{precedence_dfa = PrecDFA}.

%% @doc Convert to string
-spec to_string(dfa()) -> binary().
to_string(DFA) ->
    to_string(DFA, []).

-spec to_string(dfa(), [binary()]) -> binary().
to_string(#dfa{states = States, s0 = S0}, TokenNames) ->
    case S0 of
        undefined ->
            <<>>;
        _ ->
            StatesList = maps:values(States),
            SortedStates = lists:sort(fun(A, B) ->
                A#dfa_state.state_number =< B#dfa_state.state_number
            end, StatesList),
            Lines = [state_to_string(S, TokenNames) || S <- SortedStates],
            iolist_to_binary(lists:join(<<"\n">>, Lines))
    end.

state_to_string(#dfa_state{state_number = StateNum, is_accept_state = IsAccept, prediction = Pred, edges = Edges}, TokenNames) ->
    Header = case IsAccept of
        true ->
            <<"s", (integer_to_binary(StateNum))/binary, "=>", (integer_to_binary(Pred))/binary>>;
        false ->
            <<"s", (integer_to_binary(StateNum))/binary>>
    end,
    EdgeStrs = maps:fold(
        fun(TokenType, TargetState, Acc) ->
            TokenName = get_token_name(TokenType, TokenNames),
            TargetNum = TargetState#dfa_state.state_number,
            [<<TokenName/binary, "->s", (integer_to_binary(TargetNum))/binary>> | Acc]
        end,
        [],
        Edges
    ),
    case EdgeStrs of
        [] ->
            Header;
        _ ->
            EdgeStr = iolist_to_binary(lists:join(<<", ">>, lists:reverse(EdgeStrs))),
            <<Header/binary, ":", EdgeStr/binary>>
    end.

get_token_name(TokenType, []) ->
    integer_to_binary(TokenType);
get_token_name(TokenType, TokenNames) when TokenType >= 0, TokenType < length(TokenNames) ->
    lists:nth(TokenType + 1, TokenNames);
get_token_name(TokenType, _) ->
    integer_to_binary(TokenType).

%% Internal: get a key for a DFA state (based on its configs)
get_state_key(#dfa_state{configs = Configs}) ->
    Configs.
