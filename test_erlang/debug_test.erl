-module(debug_test).
-export([run/0]).
-include_lib("antlr4/include/antlr4_runtime.hrl").

run() ->
    try
        Input = antlr4_input_stream:new(<<"hello world">>),
        LexerState = hello_lexer:new(Input),
        ATN = maps:get(atn, LexerState),
        io:format("Grammar type: ~p~n", [ATN#atn.grammar_type]),
        io:format("Num states: ~p~n", [length(ATN#atn.states)]),
        io:format("Num modes: ~p~n", [length(ATN#atn.mode_to_start_state)]),
        io:format("Lexer actions: ~p~n", [ATN#atn.lexer_actions]),

        %% Print all states and their transitions
        lists:foreach(fun(S) ->
            io:format("State ~p: type=~p rule=~p transitions=~p~n",
                [S#atn_state.state_number, S#atn_state.state_type,
                 S#atn_state.rule_index, length(S#atn_state.transitions)]),
            lists:foreach(fun(T) ->
                Target = T#atn_transition.target,
                io:format("  -> trans_type=~p target=~p is_eps=~p label=~p action_idx=~p~n",
                    [T#atn_transition.transition_type,
                     Target#atn_state.state_number,
                     T#atn_transition.is_epsilon,
                     T#atn_transition.label,
                     T#atn_transition.action_index])
            end, S#atn_state.transitions)
        end, ATN#atn.states),

        %% Now try lexing
        io:format("~nAttempting to lex 'hello world'...~n"),
        {Tokens, _} = hello_lexer:get_all_tokens(LexerState),
        lists:foreach(fun(T) ->
            Type = antlr4_token:get_type(T),
            Text = antlr4_token:get_text(T),
            Channel = antlr4_token:get_channel(T),
            io:format("Token type=~p text=~p channel=~p~n", [Type, Text, Channel])
        end, Tokens),
        io:format("SUCCESS: Lexer produced ~p tokens~n", [length(Tokens)])
    catch
        Class:Reason:Stack ->
            io:format("ERROR: ~p:~p~n~p~n", [Class, Reason, Stack])
    end.
