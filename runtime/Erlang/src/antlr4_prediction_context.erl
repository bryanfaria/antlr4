%% ANTLR4 Prediction Context
%% Represents parser call stack for prediction

-module(antlr4_prediction_context).

-include("antlr4_runtime.hrl").

-export([
    new_cache/0,
    empty/0,
    from_rule_context/2,
    is_empty/1,
    has_empty_path/1,
    get_return_state/2,
    get_parent/2,
    size/1,
    merge/3,
    get_cached_context/3,
    put_cached_context/4
]).

-type prediction_context() :: #prediction_context{}.
-type cache() :: #{term() => term()}.
-export_type([prediction_context/0, cache/0]).

%% @doc Create a new prediction context cache
-spec new_cache() -> cache().
new_cache() ->
    #{}.

%% @doc Create an empty prediction context
-spec empty() -> prediction_context().
empty() ->
    #prediction_context{
        context_type = ?PREDICTION_CONTEXT_EMPTY,
        id = 0,
        parents = [],
        return_states = [],
        cached_hash_code = 1
    }.

%% @doc Create a prediction context from a rule context
-spec from_rule_context(antlr4_atn:atn(), term()) -> prediction_context().
from_rule_context(_ATN, undefined) ->
    empty();
from_rule_context(ATN, RuleContext) ->
    Parent = antlr4_parser_rule_context:get_parent(RuleContext),
    case Parent of
        undefined ->
            empty();
        _ ->
            InvokingState = antlr4_parser_rule_context:get_invoking_state(RuleContext),
            ParentCtx = from_rule_context(ATN, Parent),
            #prediction_context{
                context_type = ?PREDICTION_CONTEXT_SINGLETON,
                id = erlang:unique_integer(),
                parents = [ParentCtx],
                return_states = [InvokingState],
                cached_hash_code = undefined
            }
    end.

%% @doc Check if context is empty
-spec is_empty(prediction_context()) -> boolean().
is_empty(#prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY}) ->
    true;
is_empty(#prediction_context{return_states = []}) ->
    true;
is_empty(_) ->
    false.

%% @doc Check if context has an empty path
-spec has_empty_path(prediction_context()) -> boolean().
has_empty_path(#prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY}) ->
    true;
has_empty_path(#prediction_context{return_states = ReturnStates}) ->
    lists:member(-1, ReturnStates).

%% @doc Get return state at index
-spec get_return_state(prediction_context(), non_neg_integer()) -> integer().
get_return_state(#prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY}, _Index) ->
    -1;
get_return_state(#prediction_context{return_states = ReturnStates}, Index) when Index < length(ReturnStates) ->
    lists:nth(Index + 1, ReturnStates);
get_return_state(_, _) ->
    -1.

%% @doc Get parent at index
-spec get_parent(prediction_context(), non_neg_integer()) -> prediction_context() | undefined.
get_parent(#prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY}, _Index) ->
    undefined;
get_parent(#prediction_context{parents = Parents}, Index) when Index < length(Parents) ->
    lists:nth(Index + 1, Parents);
get_parent(_, _) ->
    undefined.

%% @doc Get the size (number of elements)
-spec size(prediction_context()) -> non_neg_integer().
size(#prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY}) ->
    1;
size(#prediction_context{return_states = ReturnStates}) ->
    length(ReturnStates).

%% @doc Merge two prediction contexts
-spec merge(prediction_context(), prediction_context(), cache()) -> {prediction_context(), cache()}.
merge(A, B, Cache) when A =:= B ->
    {A, Cache};
merge(#prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY} = A, B, Cache) ->
    merge_empty(A, B, Cache);
merge(A, #prediction_context{context_type = ?PREDICTION_CONTEXT_EMPTY} = B, Cache) ->
    merge_empty(B, A, Cache);
merge(#prediction_context{context_type = ?PREDICTION_CONTEXT_SINGLETON} = A,
      #prediction_context{context_type = ?PREDICTION_CONTEXT_SINGLETON} = B, Cache) ->
    merge_singletons(A, B, Cache);
merge(A, B, Cache) ->
    merge_arrays(A, B, Cache).

%% Internal: merge empty context
merge_empty(_Empty, Other, Cache) ->
    %% If other has empty path, return other
    %% Otherwise, create array with both
    case has_empty_path(Other) of
        true ->
            {Other, Cache};
        false ->
            %% Create new context with empty path added
            #prediction_context{
                parents = OtherParents,
                return_states = OtherStates
            } = Other,
            NewCtx = #prediction_context{
                context_type = ?PREDICTION_CONTEXT_ARRAY,
                id = erlang:unique_integer(),
                parents = [undefined | OtherParents],
                return_states = [-1 | OtherStates],
                cached_hash_code = undefined
            },
            {NewCtx, Cache}
    end.

%% Internal: merge singleton contexts
merge_singletons(A, B, Cache) ->
    #prediction_context{parents = [ParentA], return_states = [StateA]} = A,
    #prediction_context{parents = [ParentB], return_states = [StateB]} = B,

    case StateA =:= StateB of
        true ->
            %% Same return state, merge parents
            {MergedParent, Cache1} = merge(ParentA, ParentB, Cache),
            NewCtx = #prediction_context{
                context_type = ?PREDICTION_CONTEXT_SINGLETON,
                id = erlang:unique_integer(),
                parents = [MergedParent],
                return_states = [StateA],
                cached_hash_code = undefined
            },
            {NewCtx, Cache1};
        false ->
            %% Different return states, create array
            {Parents, States} = case StateA < StateB of
                true -> {[ParentA, ParentB], [StateA, StateB]};
                false -> {[ParentB, ParentA], [StateB, StateA]}
            end,
            NewCtx = #prediction_context{
                context_type = ?PREDICTION_CONTEXT_ARRAY,
                id = erlang:unique_integer(),
                parents = Parents,
                return_states = States,
                cached_hash_code = undefined
            },
            {NewCtx, Cache}
    end.

%% Internal: merge array contexts
merge_arrays(A, B, Cache) ->
    %% Combine and sort by return state, merge parents with same state
    #prediction_context{parents = ParentsA, return_states = StatesA} = A,
    #prediction_context{parents = ParentsB, return_states = StatesB} = B,

    Combined = lists:zip(StatesA, ParentsA) ++ lists:zip(StatesB, ParentsB),
    Sorted = lists:sort(fun({S1, _}, {S2, _}) -> S1 =< S2 end, Combined),

    {MergedPairs, Cache1} = merge_sorted_pairs(Sorted, Cache),

    {States, Parents} = lists:unzip(MergedPairs),
    NewCtx = #prediction_context{
        context_type = ?PREDICTION_CONTEXT_ARRAY,
        id = erlang:unique_integer(),
        parents = Parents,
        return_states = States,
        cached_hash_code = undefined
    },
    {NewCtx, Cache1}.

merge_sorted_pairs([], Cache) ->
    {[], Cache};
merge_sorted_pairs([{State, Parent}], Cache) ->
    {[{State, Parent}], Cache};
merge_sorted_pairs([{State, Parent1}, {State, Parent2} | Rest], Cache) ->
    %% Same state, merge parents
    {MergedParent, Cache1} = merge(Parent1, Parent2, Cache),
    merge_sorted_pairs([{State, MergedParent} | Rest], Cache1);
merge_sorted_pairs([Pair | Rest], Cache) ->
    {RestPairs, Cache1} = merge_sorted_pairs(Rest, Cache),
    {[Pair | RestPairs], Cache1}.

%% @doc Get a cached context
-spec get_cached_context(cache(), prediction_context(), prediction_context()) -> prediction_context() | undefined.
get_cached_context(Cache, A, B) ->
    Key = {A, B},
    maps:get(Key, Cache, undefined).

%% @doc Put a context in the cache
-spec put_cached_context(cache(), prediction_context(), prediction_context(), prediction_context()) -> cache().
put_cached_context(Cache, A, B, Result) ->
    Key = {A, B},
    maps:put(Key, Result, Cache).
