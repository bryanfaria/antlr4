%% ANTLR4 DFA State Module
%% Represents a state in the DFA

-module(antlr4_dfa_state).

-include("antlr4_runtime.hrl").

-export([
    new/0,
    new/1,
    get_state_number/1,
    set_state_number/2,
    get_configs/1,
    set_configs/2,
    get_edges/1,
    set_edge/3,
    get_edge/2,
    is_accept_state/1,
    set_accept_state/2,
    get_prediction/1,
    set_prediction/2,
    is_context_sensitive/1,
    set_context_sensitive/2,
    get_predicates/1,
    set_predicates/2,
    equals/2,
    hash/1
]).

-type dfa_state() :: #dfa_state{}.
-export_type([dfa_state/0]).

%% @doc Create a new empty DFA state
-spec new() -> dfa_state().
new() ->
    #dfa_state{
        state_number = -1,
        configs = undefined,
        edges = #{},
        is_accept_state = false,
        prediction = 0,
        requires_full_context = false,
        predicates = undefined
    }.

%% @doc Create a new DFA state with configs
-spec new(term()) -> dfa_state().
new(Configs) ->
    #dfa_state{
        state_number = -1,
        configs = Configs,
        edges = #{},
        is_accept_state = false,
        prediction = 0,
        requires_full_context = false,
        predicates = undefined
    }.

%% @doc Get the state number
-spec get_state_number(dfa_state()) -> integer().
get_state_number(#dfa_state{state_number = Num}) ->
    Num.

%% @doc Set the state number
-spec set_state_number(dfa_state(), integer()) -> dfa_state().
set_state_number(State, Num) ->
    State#dfa_state{state_number = Num}.

%% @doc Get the configs
-spec get_configs(dfa_state()) -> term().
get_configs(#dfa_state{configs = Configs}) ->
    Configs.

%% @doc Set the configs
-spec set_configs(dfa_state(), term()) -> dfa_state().
set_configs(State, Configs) ->
    State#dfa_state{configs = Configs}.

%% @doc Get the edges map
-spec get_edges(dfa_state()) -> #{integer() => dfa_state()}.
get_edges(#dfa_state{edges = Edges}) ->
    Edges.

%% @doc Set an edge
-spec set_edge(dfa_state(), integer(), dfa_state()) -> dfa_state().
set_edge(#dfa_state{edges = Edges} = State, Symbol, Target) ->
    State#dfa_state{edges = maps:put(Symbol, Target, Edges)}.

%% @doc Get an edge target
-spec get_edge(dfa_state(), integer()) -> dfa_state() | undefined.
get_edge(#dfa_state{edges = Edges}, Symbol) ->
    maps:get(Symbol, Edges, undefined).

%% @doc Check if this is an accept state
-spec is_accept_state(dfa_state()) -> boolean().
is_accept_state(#dfa_state{is_accept_state = IsAccept}) ->
    IsAccept.

%% @doc Set whether this is an accept state
-spec set_accept_state(dfa_state(), boolean()) -> dfa_state().
set_accept_state(State, IsAccept) ->
    State#dfa_state{is_accept_state = IsAccept}.

%% @doc Get the prediction
-spec get_prediction(dfa_state()) -> integer().
get_prediction(#dfa_state{prediction = Pred}) ->
    Pred.

%% @doc Set the prediction
-spec set_prediction(dfa_state(), integer()) -> dfa_state().
set_prediction(State, Pred) ->
    State#dfa_state{prediction = Pred}.

%% @doc Check if this state requires full context
-spec is_context_sensitive(dfa_state()) -> boolean().
is_context_sensitive(#dfa_state{requires_full_context = RequiresFullCtx}) ->
    RequiresFullCtx.

%% @doc Set whether this state requires full context
-spec set_context_sensitive(dfa_state(), boolean()) -> dfa_state().
set_context_sensitive(State, RequiresFullCtx) ->
    State#dfa_state{requires_full_context = RequiresFullCtx}.

%% @doc Get the predicates
-spec get_predicates(dfa_state()) -> [term()] | undefined.
get_predicates(#dfa_state{predicates = Preds}) ->
    Preds.

%% @doc Set the predicates
-spec set_predicates(dfa_state(), [term()]) -> dfa_state().
set_predicates(State, Preds) ->
    State#dfa_state{predicates = Preds}.

%% @doc Check if two DFA states are equal (based on configs)
-spec equals(dfa_state(), dfa_state()) -> boolean().
equals(#dfa_state{configs = Configs1}, #dfa_state{configs = Configs2}) ->
    Configs1 =:= Configs2.

%% @doc Compute a hash code for the state (based on configs)
-spec hash(dfa_state()) -> integer().
hash(#dfa_state{configs = Configs}) ->
    erlang:phash2(Configs).
