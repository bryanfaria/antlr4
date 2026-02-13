%% Code generated from Hello.g4 by ANTLR 4.13.2. DO NOT EDIT.

-module(hello_base_listener).

-behaviour(hello_listener).

-export([
    enter_every_rule/1,
    exit_every_rule/1,
    visit_terminal/1,
    visit_error_node/1,
    enter_r/1,
        exit_r/1]).

enter_every_rule(_Ctx) -> ok.
exit_every_rule(_Ctx) -> ok.
visit_terminal(_Node) -> ok.
visit_error_node(_Node) -> ok.

enter_r(_Ctx) -> ok.
exit_r(_Ctx) -> ok.
