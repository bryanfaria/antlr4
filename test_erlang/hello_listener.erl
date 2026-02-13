%% Code generated from Hello.g4 by ANTLR 4.13.2. DO NOT EDIT.

-module(hello_listener).

%% Listener behavior for Hello

-export([behaviour_info/1]).

behaviour_info(callbacks) ->
    [
        {enter_every_rule, 1},
        {exit_every_rule, 1},
        {visit_terminal, 1},
        {visit_error_node, 1},
        {enter_r, 1},
                {exit_r, 1}];
behaviour_info(_Other) ->
    undefined.