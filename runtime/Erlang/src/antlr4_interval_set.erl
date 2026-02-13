%% ANTLR4 Interval Set
%% Represents a set of integers as intervals

-module(antlr4_interval_set).

-include("antlr4_runtime.hrl").

-export([
    new/0,
    add/2,
    add_interval/3,
    add_all/2,
    remove/2,
    complement/3,
    contains/2,
    is_empty/1,
    get_min/1,
    get_max/1,
    get_intervals/1,
    size/1,
    to_list/1,
    to_string/1
]).

-type interval_set() :: #interval_set{}.
-export_type([interval_set/0]).

%% @doc Create a new empty interval set
-spec new() -> interval_set().
new() ->
    #interval_set{intervals = [], read_only = false}.

%% @doc Add a single value to the set
-spec add(interval_set(), integer()) -> interval_set().
add(Set, Value) ->
    add_interval(Set, Value, Value).

%% @doc Add an interval [a, b] to the set
-spec add_interval(interval_set(), integer(), integer()) -> interval_set().
add_interval(#interval_set{read_only = true}, _A, _B) ->
    throw({illegal_state, <<"Cannot modify read-only interval set">>});
add_interval(#interval_set{intervals = Intervals} = Set, A, B) when A =< B ->
    NewInterval = #interval{start_index = A, stop_index = B},
    MergedIntervals = merge_interval(Intervals, NewInterval),
    Set#interval_set{intervals = MergedIntervals};
add_interval(Set, _A, _B) ->
    Set.

%% @doc Add all intervals from another set
-spec add_all(interval_set(), interval_set()) -> interval_set().
add_all(Set, #interval_set{intervals = Intervals}) ->
    lists:foldl(
        fun(#interval{start_index = A, stop_index = B}, AccSet) ->
            add_interval(AccSet, A, B)
        end,
        Set,
        Intervals
    ).

%% @doc Remove a single value from the set
-spec remove(interval_set(), integer()) -> interval_set().
remove(#interval_set{read_only = true}, _Value) ->
    throw({illegal_state, <<"Cannot modify read-only interval set">>});
remove(#interval_set{intervals = Intervals} = Set, Value) ->
    NewIntervals = remove_value(Intervals, Value, []),
    Set#interval_set{intervals = NewIntervals}.

remove_value([], _Value, Acc) ->
    lists:reverse(Acc);
remove_value([#interval{start_index = A, stop_index = B} = I | Rest], Value, Acc) ->
    case Value >= A andalso Value =< B of
        false ->
            remove_value(Rest, Value, [I | Acc]);
        true when Value =:= A, Value =:= B ->
            %% Interval is just this value, remove it entirely
            remove_value(Rest, Value, Acc);
        true when Value =:= A ->
            %% Remove from start
            remove_value(Rest, Value, [#interval{start_index = A + 1, stop_index = B} | Acc]);
        true when Value =:= B ->
            %% Remove from end
            remove_value(Rest, Value, [#interval{start_index = A, stop_index = B - 1} | Acc]);
        true ->
            %% Split interval
            I1 = #interval{start_index = A, stop_index = Value - 1},
            I2 = #interval{start_index = Value + 1, stop_index = B},
            remove_value(Rest, Value, [I2, I1 | Acc])
    end.

%% @doc Get the complement of this set within [minElement, maxElement]
-spec complement(interval_set(), integer(), integer()) -> interval_set().
complement(#interval_set{intervals = []}, MinElement, MaxElement) ->
    #interval_set{intervals = [#interval{start_index = MinElement, stop_index = MaxElement}]};
complement(#interval_set{intervals = Intervals}, MinElement, MaxElement) ->
    ComplementIntervals = compute_complement(Intervals, MinElement, MaxElement, []),
    #interval_set{intervals = ComplementIntervals}.

compute_complement([], Current, MaxElement, Acc) when Current =< MaxElement ->
    lists:reverse([#interval{start_index = Current, stop_index = MaxElement} | Acc]);
compute_complement([], _Current, _MaxElement, Acc) ->
    lists:reverse(Acc);
compute_complement([#interval{start_index = A, stop_index = B} | Rest], Current, MaxElement, Acc) ->
    case Current < A of
        true ->
            NewInterval = #interval{start_index = Current, stop_index = A - 1},
            compute_complement(Rest, B + 1, MaxElement, [NewInterval | Acc]);
        false ->
            compute_complement(Rest, max(Current, B + 1), MaxElement, Acc)
    end.

%% @doc Check if the set contains a value
-spec contains(interval_set(), integer()) -> boolean().
contains(#interval_set{intervals = Intervals}, Value) ->
    lists:any(
        fun(#interval{start_index = A, stop_index = B}) ->
            Value >= A andalso Value =< B
        end,
        Intervals
    ).

%% @doc Check if the set is empty
-spec is_empty(interval_set()) -> boolean().
is_empty(#interval_set{intervals = []}) ->
    true;
is_empty(_) ->
    false.

%% @doc Get the minimum value in the set
-spec get_min(interval_set()) -> integer() | undefined.
get_min(#interval_set{intervals = []}) ->
    undefined;
get_min(#interval_set{intervals = [#interval{start_index = Min} | _]}) ->
    Min.

%% @doc Get the maximum value in the set
-spec get_max(interval_set()) -> integer() | undefined.
get_max(#interval_set{intervals = []}) ->
    undefined;
get_max(#interval_set{intervals = Intervals}) ->
    #interval{stop_index = Max} = lists:last(Intervals),
    Max.

%% @doc Get the intervals
-spec get_intervals(interval_set()) -> [#interval{}].
get_intervals(#interval_set{intervals = Intervals}) ->
    Intervals.

%% @doc Get the size (number of elements) in the set
-spec size(interval_set()) -> non_neg_integer().
size(#interval_set{intervals = Intervals}) ->
    lists:foldl(
        fun(#interval{start_index = A, stop_index = B}, Acc) ->
            Acc + (B - A + 1)
        end,
        0,
        Intervals
    ).

%% @doc Convert to a list of integers
-spec to_list(interval_set()) -> [integer()].
to_list(#interval_set{intervals = Intervals}) ->
    lists:flatten([lists:seq(A, B) || #interval{start_index = A, stop_index = B} <- Intervals]).

%% @doc Convert to a string representation
-spec to_string(interval_set()) -> binary().
to_string(#interval_set{intervals = []}) ->
    <<"{}">>;
to_string(#interval_set{intervals = Intervals}) ->
    IntervalStrs = [interval_to_string(I) || I <- Intervals],
    Joined = iolist_to_binary(lists:join(<<", ">>, IntervalStrs)),
    <<"{", Joined/binary, "}">>.

interval_to_string(#interval{start_index = A, stop_index = A}) ->
    integer_to_binary(A);
interval_to_string(#interval{start_index = A, stop_index = B}) ->
    <<(integer_to_binary(A))/binary, "..", (integer_to_binary(B))/binary>>.

%% Internal: merge a new interval into the list
merge_interval([], NewInterval) ->
    [NewInterval];
merge_interval(Intervals, NewInterval) ->
    merge_interval_loop(Intervals, NewInterval, []).

merge_interval_loop([], NewInterval, Acc) ->
    lists:reverse([NewInterval | Acc]);
merge_interval_loop([#interval{start_index = A, stop_index = B} = I | Rest],
                    #interval{start_index = NewA, stop_index = NewB} = NewInterval, Acc) ->
    case NewB < A - 1 of
        true ->
            %% New interval comes before this one, insert it
            lists:reverse(Acc) ++ [NewInterval, I | Rest];
        false ->
            case NewA > B + 1 of
                true ->
                    %% New interval comes after this one, continue
                    merge_interval_loop(Rest, NewInterval, [I | Acc]);
                false ->
                    %% Intervals overlap or are adjacent, merge them
                    MergedInterval = #interval{
                        start_index = min(A, NewA),
                        stop_index = max(B, NewB)
                    },
                    %% Continue merging with the rest
                    merge_interval_loop(Rest, MergedInterval, Acc)
            end
    end.
