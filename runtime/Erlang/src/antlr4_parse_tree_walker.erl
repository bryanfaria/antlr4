%% ANTLR4 Parse Tree Walker
%% Walks a parse tree and triggers listener events

-module(antlr4_parse_tree_walker).

-include("antlr4_runtime.hrl").

-export([
    walk/2,
    enter_rule/2,
    exit_rule/2
]).

%% @doc Walk a parse tree with a listener
-spec walk(module(), term()) -> ok.
walk(Listener, Tree) ->
    case Tree of
        #terminal_node{} ->
            visit_terminal(Listener, Tree);
        #error_node{} ->
            visit_error_node(Listener, Tree);
        _ when is_tuple(Tree) ->
            enter_rule(Listener, Tree),
            Children = antlr4_parser_rule_context:get_children(Tree),
            lists:foreach(fun(Child) -> walk(Listener, Child) end, Children),
            exit_rule(Listener, Tree);
        _ ->
            ok
    end.

%% @doc Enter a rule context
-spec enter_rule(module(), term()) -> ok.
enter_rule(Listener, Ctx) ->
    %% Call enterEveryRule first
    safe_call(Listener, enter_every_rule, [Ctx]),
    %% Then call the specific enter method
    RuleName = get_rule_name(Ctx),
    EnterFunc = list_to_atom("enter_" ++ binary_to_list(RuleName)),
    safe_call(Listener, EnterFunc, [Ctx]),
    ok.

%% @doc Exit a rule context
-spec exit_rule(module(), term()) -> ok.
exit_rule(Listener, Ctx) ->
    %% Call the specific exit method first
    RuleName = get_rule_name(Ctx),
    ExitFunc = list_to_atom("exit_" ++ binary_to_list(RuleName)),
    safe_call(Listener, ExitFunc, [Ctx]),
    %% Then call exitEveryRule
    safe_call(Listener, exit_every_rule, [Ctx]),
    ok.

%% Internal: visit a terminal node
visit_terminal(Listener, Node) ->
    safe_call(Listener, visit_terminal, [Node]),
    ok.

%% Internal: visit an error node
visit_error_node(Listener, Node) ->
    safe_call(Listener, visit_error_node, [Node]),
    ok.

%% Internal: get rule name from context
get_rule_name(Ctx) ->
    %% Try to get rule name from the record type
    %% Convention: record name is rulename_context
    case erlang:is_record(Ctx, parser_rule_context) of
        true ->
            <<"rule">>;
        false ->
            %% Get the record name and extract rule name
            RecordName = element(1, Ctx),
            RecordNameStr = atom_to_binary(RecordName, utf8),
            case binary:split(RecordNameStr, <<"_context">>) of
                [RuleName, <<>>] -> RuleName;
                _ -> RecordNameStr
            end
    end.

%% Internal: safely call a listener function
safe_call(Listener, Func, Args) ->
    case erlang:function_exported(Listener, Func, length(Args)) of
        true ->
            apply(Listener, Func, Args);
        false ->
            ok
    end.
