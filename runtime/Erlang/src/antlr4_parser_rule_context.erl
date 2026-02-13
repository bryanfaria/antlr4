%% ANTLR4 Parser Rule Context
%% Represents a node in the parse tree

-module(antlr4_parser_rule_context).

-include("antlr4_runtime.hrl").

-export([
    new/0,
    new/2,
    new/3,
    get_parent/1,
    set_parent/2,
    get_invoking_state/1,
    set_invoking_state/2,
    get_rule_index/1,
    set_rule_index/2,
    get_start/1,
    set_start/2,
    get_stop/1,
    set_stop/2,
    get_exception/1,
    set_exception/2,
    get_children/1,
    add_child/2,
    remove_last_child/1,
    get_child/2,
    get_child_count/1,
    get_token/3,
    get_tokens/2,
    get_rule_context/3,
    get_rule_contexts/2,
    get_text/1,
    get_alt_number/1,
    set_alt_number/2,
    get_source_interval/1,
    to_string/1,
    to_string/2,
    to_string_tree/1,
    to_string_tree/2,
    copy_from/2,
    accept/2,
    enter_rule/2,
    exit_rule/2
]).

-type parser_rule_context() :: #parser_rule_context{}.
-export_type([parser_rule_context/0]).

%% @doc Create an empty context
-spec new() -> parser_rule_context().
new() ->
    #parser_rule_context{}.

%% @doc Create a context with parent and invoking state
-spec new(term(), integer()) -> parser_rule_context().
new(Parent, InvokingState) ->
    #parser_rule_context{
        parent = Parent,
        invoking_state = InvokingState
    }.

%% @doc Create a context with parent, invoking state, and rule index
-spec new(term(), integer(), integer()) -> parser_rule_context().
new(Parent, InvokingState, RuleIndex) ->
    #parser_rule_context{
        parent = Parent,
        invoking_state = InvokingState,
        rule_index = RuleIndex
    }.

%% @doc Get the parent context
-spec get_parent(parser_rule_context()) -> term().
get_parent(#parser_rule_context{parent = Parent}) ->
    Parent.

%% @doc Set the parent context
-spec set_parent(parser_rule_context(), term()) -> parser_rule_context().
set_parent(Ctx, Parent) ->
    Ctx#parser_rule_context{parent = Parent}.

%% @doc Get the invoking state
-spec get_invoking_state(parser_rule_context()) -> integer().
get_invoking_state(#parser_rule_context{invoking_state = State}) ->
    State.

%% @doc Set the invoking state
-spec set_invoking_state(parser_rule_context(), integer()) -> parser_rule_context().
set_invoking_state(Ctx, State) ->
    Ctx#parser_rule_context{invoking_state = State}.

%% @doc Get the rule index
-spec get_rule_index(parser_rule_context()) -> integer().
get_rule_index(#parser_rule_context{rule_index = Index}) ->
    Index.

%% @doc Set the rule index
-spec set_rule_index(parser_rule_context(), integer()) -> parser_rule_context().
set_rule_index(Ctx, Index) ->
    Ctx#parser_rule_context{rule_index = Index}.

%% @doc Get the start token
-spec get_start(parser_rule_context()) -> antlr4_token:token() | undefined.
get_start(#parser_rule_context{start_token = Token}) ->
    Token.

%% @doc Set the start token
-spec set_start(parser_rule_context(), antlr4_token:token()) -> parser_rule_context().
set_start(Ctx, Token) ->
    Ctx#parser_rule_context{start_token = Token}.

%% @doc Get the stop token
-spec get_stop(parser_rule_context()) -> antlr4_token:token() | undefined.
get_stop(#parser_rule_context{stop_token = Token}) ->
    Token.

%% @doc Set the stop token
-spec set_stop(parser_rule_context(), antlr4_token:token()) -> parser_rule_context().
set_stop(Ctx, Token) ->
    Ctx#parser_rule_context{stop_token = Token}.

%% @doc Get the exception
-spec get_exception(parser_rule_context()) -> term().
get_exception(#parser_rule_context{exception = Exception}) ->
    Exception.

%% @doc Set the exception
-spec set_exception(parser_rule_context(), term()) -> parser_rule_context().
set_exception(Ctx, Exception) ->
    Ctx#parser_rule_context{exception = Exception}.

%% @doc Get all children
-spec get_children(parser_rule_context()) -> [term()].
get_children(#parser_rule_context{children = Children}) ->
    Children.

%% @doc Add a child to this context
-spec add_child(parser_rule_context(), term()) -> parser_rule_context().
add_child(#parser_rule_context{children = Children} = Ctx, Child) ->
    Ctx#parser_rule_context{children = Children ++ [Child]}.

%% @doc Remove the last child
-spec remove_last_child(parser_rule_context()) -> parser_rule_context().
remove_last_child(#parser_rule_context{children = []} = Ctx) ->
    Ctx;
remove_last_child(#parser_rule_context{children = Children} = Ctx) ->
    Ctx#parser_rule_context{children = lists:droplast(Children)}.

%% @doc Get a specific child by index
-spec get_child(parser_rule_context(), non_neg_integer()) -> term() | undefined.
get_child(#parser_rule_context{children = Children}, Index) when Index < length(Children) ->
    lists:nth(Index + 1, Children);
get_child(_, _) ->
    undefined.

%% @doc Get the number of children
-spec get_child_count(parser_rule_context()) -> non_neg_integer().
get_child_count(#parser_rule_context{children = Children}) ->
    length(Children).

%% @doc Get a token child at index with a specific type
-spec get_token(parser_rule_context(), integer(), non_neg_integer()) -> term() | undefined.
get_token(#parser_rule_context{children = Children}, TokenType, Index) ->
    MatchingTokens = [C || #terminal_node{symbol = S} = C <- Children,
                          antlr4_token:get_type(S) =:= TokenType],
    case Index < length(MatchingTokens) of
        true -> lists:nth(Index + 1, MatchingTokens);
        false -> undefined
    end.

%% @doc Get all tokens of a specific type
-spec get_tokens(parser_rule_context(), integer()) -> [term()].
get_tokens(#parser_rule_context{children = Children}, TokenType) ->
    [C || #terminal_node{symbol = S} = C <- Children,
          antlr4_token:get_type(S) =:= TokenType].

%% @doc Get a rule context child at index
-spec get_rule_context(parser_rule_context(), atom(), non_neg_integer()) -> term() | undefined.
get_rule_context(#parser_rule_context{children = Children}, CtxType, Index) ->
    Matching = [C || C <- Children, is_tuple(C), element(1, C) =:= CtxType],
    case Index < length(Matching) of
        true -> lists:nth(Index + 1, Matching);
        false -> undefined
    end.

%% @doc Get all rule contexts of a specific type
-spec get_rule_contexts(parser_rule_context(), atom()) -> [term()].
get_rule_contexts(#parser_rule_context{children = Children}, CtxType) ->
    [C || C <- Children, is_tuple(C), element(1, C) =:= CtxType].

%% @doc Get the text covered by this context
-spec get_text(parser_rule_context()) -> binary().
get_text(#parser_rule_context{children = []}) ->
    <<>>;
get_text(#parser_rule_context{children = Children}) ->
    iolist_to_binary([get_child_text(C) || C <- Children]).

get_child_text(#terminal_node{symbol = Token}) ->
    antlr4_token:get_text(Token);
get_child_text(#error_node{symbol = Token}) ->
    antlr4_token:get_text(Token);
get_child_text(Ctx) when is_tuple(Ctx) ->
    get_text(Ctx);
get_child_text(_) ->
    <<>>.

%% @doc Get the alternative number
-spec get_alt_number(parser_rule_context()) -> integer().
get_alt_number(#parser_rule_context{alt_number = AltNum}) ->
    AltNum.

%% @doc Set the alternative number
-spec set_alt_number(parser_rule_context(), integer()) -> parser_rule_context().
set_alt_number(Ctx, AltNum) ->
    Ctx#parser_rule_context{alt_number = AltNum}.

%% @doc Get the source interval (token indices)
-spec get_source_interval(parser_rule_context()) -> #interval{}.
get_source_interval(#parser_rule_context{start_token = undefined}) ->
    #interval{start_index = -1, stop_index = -2};
get_source_interval(#parser_rule_context{stop_token = undefined}) ->
    #interval{start_index = -1, stop_index = -2};
get_source_interval(#parser_rule_context{start_token = Start, stop_token = Stop}) ->
    #interval{
        start_index = antlr4_token:get_token_index(Start),
        stop_index = antlr4_token:get_token_index(Stop)
    }.

%% @doc Convert to string
-spec to_string(parser_rule_context()) -> binary().
to_string(Ctx) ->
    to_string(Ctx, []).

-spec to_string(parser_rule_context(), [binary()]) -> binary().
to_string(#parser_rule_context{rule_index = RuleIndex}, RuleNames) when RuleIndex >= 0, length(RuleNames) > RuleIndex ->
    lists:nth(RuleIndex + 1, RuleNames);
to_string(#parser_rule_context{rule_index = RuleIndex}, _) ->
    integer_to_binary(RuleIndex).

%% @doc Convert to string tree representation
-spec to_string_tree(parser_rule_context()) -> binary().
to_string_tree(Ctx) ->
    to_string_tree(Ctx, []).

-spec to_string_tree(parser_rule_context(), [binary()]) -> binary().
to_string_tree(#parser_rule_context{children = []} = Ctx, RuleNames) ->
    to_string(Ctx, RuleNames);
to_string_tree(#parser_rule_context{children = Children} = Ctx, RuleNames) ->
    ChildStrings = [child_to_string_tree(C, RuleNames) || C <- Children],
    ChildStr = iolist_to_binary(lists:join(<<" ">>, ChildStrings)),
    RuleStr = to_string(Ctx, RuleNames),
    <<"(", RuleStr/binary, " ", ChildStr/binary, ")">>.

child_to_string_tree(#terminal_node{symbol = Token}, _RuleNames) ->
    antlr4_token:get_text(Token);
child_to_string_tree(#error_node{symbol = Token}, _RuleNames) ->
    <<"<error:", (antlr4_token:get_text(Token))/binary, ">">>;
child_to_string_tree(Ctx, RuleNames) when is_tuple(Ctx) ->
    to_string_tree(Ctx, RuleNames);
child_to_string_tree(_, _) ->
    <<"?">>.

%% @doc Copy fields from another context
-spec copy_from(parser_rule_context(), parser_rule_context()) -> parser_rule_context().
copy_from(Dest, #parser_rule_context{
    parent = Parent,
    invoking_state = InvokingState,
    start_token = Start,
    stop_token = Stop
}) ->
    Dest#parser_rule_context{
        parent = Parent,
        invoking_state = InvokingState,
        start_token = Start,
        stop_token = Stop
    }.

%% @doc Accept a visitor
-spec accept(parser_rule_context(), module()) -> term().
accept(Ctx, Visitor) ->
    Visitor:visit(Ctx).

%% @doc Called when entering a rule (for listener dispatch)
-spec enter_rule(parser_rule_context(), module()) -> ok.
enter_rule(Ctx, Listener) ->
    Listener:enter_every_rule(Ctx).

%% @doc Called when exiting a rule (for listener dispatch)
-spec exit_rule(parser_rule_context(), module()) -> ok.
exit_rule(Ctx, Listener) ->
    Listener:exit_every_rule(Ctx).
