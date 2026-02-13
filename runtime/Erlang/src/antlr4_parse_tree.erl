%% ANTLR4 Parse Tree Module
%% Parse tree utilities and visitor support

-module(antlr4_parse_tree).

-include("antlr4_runtime.hrl").

-export([
    get_text/1,
    get_child/2,
    get_child_count/1,
    get_parent/1,
    accept/2,
    visit_children/2,
    to_string_tree/1,
    to_string_tree/2
]).

%% @doc Get the text of a parse tree node
-spec get_text(term()) -> binary().
get_text(#terminal_node{symbol = Token}) ->
    antlr4_token:get_text(Token);
get_text(#error_node{symbol = Token}) ->
    antlr4_token:get_text(Token);
get_text(Ctx) when is_tuple(Ctx) ->
    antlr4_parser_rule_context:get_text(Ctx);
get_text(_) ->
    <<>>.

%% @doc Get a child at a specific index
-spec get_child(term(), non_neg_integer()) -> term() | undefined.
get_child(#terminal_node{}, _Index) ->
    undefined;
get_child(#error_node{}, _Index) ->
    undefined;
get_child(Ctx, Index) when is_tuple(Ctx) ->
    antlr4_parser_rule_context:get_child(Ctx, Index);
get_child(_, _) ->
    undefined.

%% @doc Get the number of children
-spec get_child_count(term()) -> non_neg_integer().
get_child_count(#terminal_node{}) ->
    0;
get_child_count(#error_node{}) ->
    0;
get_child_count(Ctx) when is_tuple(Ctx) ->
    antlr4_parser_rule_context:get_child_count(Ctx);
get_child_count(_) ->
    0.

%% @doc Get the parent node
-spec get_parent(term()) -> term() | undefined.
get_parent(#terminal_node{parent = Parent}) ->
    Parent;
get_parent(#error_node{parent = Parent}) ->
    Parent;
get_parent(Ctx) when is_tuple(Ctx) ->
    antlr4_parser_rule_context:get_parent(Ctx);
get_parent(_) ->
    undefined.

%% @doc Accept a visitor
-spec accept(term(), module()) -> term().
accept(Node, Visitor) ->
    case Node of
        #terminal_node{} ->
            Visitor:visit_terminal(Node);
        #error_node{} ->
            Visitor:visit_error_node(Node);
        _ when is_tuple(Node) ->
            antlr4_parser_rule_context:accept(Node, Visitor);
        _ ->
            undefined
    end.

%% @doc Visit all children of a node
-spec visit_children(term(), module()) -> term().
visit_children(Node, Visitor) ->
    ChildCount = get_child_count(Node),
    visit_children_loop(Node, Visitor, 0, ChildCount, undefined).

visit_children_loop(_Node, _Visitor, Index, ChildCount, Result) when Index >= ChildCount ->
    Result;
visit_children_loop(Node, Visitor, Index, ChildCount, _Result) ->
    Child = get_child(Node, Index),
    ChildResult = accept(Child, Visitor),
    %% Return the last non-undefined result
    NewResult = case ChildResult of
        undefined -> _Result;
        _ -> ChildResult
    end,
    visit_children_loop(Node, Visitor, Index + 1, ChildCount, NewResult).

%% @doc Convert a parse tree to a string representation
-spec to_string_tree(term()) -> binary().
to_string_tree(Node) ->
    to_string_tree(Node, []).

-spec to_string_tree(term(), [binary()]) -> binary().
to_string_tree(#terminal_node{symbol = Token}, _RuleNames) ->
    antlr4_token:get_text(Token);
to_string_tree(#error_node{symbol = Token}, _RuleNames) ->
    <<"<error:", (antlr4_token:get_text(Token))/binary, ">">>;
to_string_tree(Ctx, RuleNames) when is_tuple(Ctx) ->
    antlr4_parser_rule_context:to_string_tree(Ctx, RuleNames);
to_string_tree(_, _) ->
    <<"?">>.
