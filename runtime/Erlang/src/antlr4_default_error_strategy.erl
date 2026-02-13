%% ANTLR4 Default Error Strategy
%% Default error recovery strategy for parsers

-module(antlr4_default_error_strategy).

-include("antlr4_runtime.hrl").

-export([
    reset/1,
    recover_inline/1,
    recover/2,
    sync/1,
    report_error/2,
    report_no_viable_alternative/2,
    report_input_mismatch/2,
    report_failed_predicate/2,
    report_unwanted_token/1,
    report_missing_token/1,
    report_match/1
]).

%% @doc Reset the error handler state
-spec reset(term()) -> ok.
reset(_Recognizer) ->
    ok.

%% @doc Attempt single-token insertion or deletion for inline recovery
-spec recover_inline(term()) -> antlr4_token:token().
recover_inline(Recognizer) ->
    %% Try single token deletion
    case single_token_deletion(Recognizer) of
        undefined ->
            %% Try single token insertion
            case single_token_insertion(Recognizer) of
                true ->
                    get_missing_symbol(Recognizer);
                false ->
                    throw({input_mismatch, Recognizer})
            end;
        MatchedSymbol ->
            MatchedSymbol
    end.

%% @doc Recover from a recognition error
-spec recover(term(), term()) -> ok.
recover(Recognizer, _Exception) ->
    %% Consume tokens until we find something in the resync set
    consume_until_resync(Recognizer),
    ok.

%% @doc Synchronize the parser at the current position
-spec sync(term()) -> ok.
sync(_Recognizer) ->
    %% Default implementation does nothing
    ok.

%% @doc Report a recognition error
-spec report_error(term(), term()) -> ok.
report_error(Recognizer, Exception) ->
    case Exception of
        #no_viable_alt_exception{} ->
            report_no_viable_alternative(Recognizer, Exception);
        #input_mismatch_exception{} ->
            report_input_mismatch(Recognizer, Exception);
        #failed_predicate_exception{} ->
            report_failed_predicate(Recognizer, Exception);
        _ ->
            %% Generic error
            Token = antlr4_parser:get_current_token(Recognizer),
            Message = <<"Recognition error">>,
            antlr4_parser:notify_error_listeners(Recognizer, Message, Token, Exception),
            ok
    end.

%% @doc Report a no viable alternative error
-spec report_no_viable_alternative(term(), term()) -> ok.
report_no_viable_alternative(Recognizer, #no_viable_alt_exception{start_token = StartToken} = Exception) ->
    Input = antlr4_parser:get_input(Recognizer),
    Token = antlr4_parser:get_current_token(Recognizer),

    TokenText = case StartToken of
        undefined ->
            <<"<unknown input>">>;
        _ ->
            case antlr4_token:get_type(Token) of
                ?ANTLR4_TOKEN_EOF ->
                    <<"<EOF>">>;
                _ ->
                    antlr4_token_stream:get_text_from_tokens(Input, StartToken, Token)
            end
    end,

    Message = <<"no viable alternative at input ", TokenText/binary>>,
    antlr4_parser:notify_error_listeners(Recognizer, Message, Token, Exception),
    ok.

%% @doc Report an input mismatch error
-spec report_input_mismatch(term(), term()) -> ok.
report_input_mismatch(Recognizer, Exception) ->
    Token = antlr4_parser:get_current_token(Recognizer),
    TokenText = get_token_error_display(Token),
    Expected = get_expected_tokens_text(Recognizer),
    Message = <<"mismatched input ", TokenText/binary, " expecting ", Expected/binary>>,
    antlr4_parser:notify_error_listeners(Recognizer, Message, Token, Exception),
    ok.

%% @doc Report a failed predicate error
-spec report_failed_predicate(term(), term()) -> ok.
report_failed_predicate(Recognizer, #failed_predicate_exception{predicate = Predicate} = Exception) ->
    Token = antlr4_parser:get_current_token(Recognizer),
    RuleName = get_rule_name(Recognizer),
    Message = <<"rule ", RuleName/binary, " failed predicate: {", Predicate/binary, "}?">>,
    antlr4_parser:notify_error_listeners(Recognizer, Message, Token, Exception),
    ok.

%% @doc Report an unwanted token error
-spec report_unwanted_token(term()) -> ok.
report_unwanted_token(Recognizer) ->
    Token = antlr4_parser:get_current_token(Recognizer),
    TokenText = get_token_error_display(Token),
    Expected = get_expected_tokens_text(Recognizer),
    Message = <<"extraneous input ", TokenText/binary, " expecting ", Expected/binary>>,
    antlr4_parser:notify_error_listeners(Recognizer, Message, Token, undefined),
    ok.

%% @doc Report a missing token error
-spec report_missing_token(term()) -> ok.
report_missing_token(Recognizer) ->
    Token = antlr4_parser:get_current_token(Recognizer),
    Expected = get_expected_tokens_text(Recognizer),
    Message = <<"missing ", Expected/binary, " at ", (get_token_error_display(Token))/binary>>,
    antlr4_parser:notify_error_listeners(Recognizer, Message, Token, undefined),
    ok.

%% @doc Called when the error handler successfully matches a token
-spec report_match(term()) -> ok.
report_match(_Recognizer) ->
    ok.

%% Internal: try single token deletion
single_token_deletion(Recognizer) ->
    NextToken = antlr4_token_stream:lt(antlr4_parser:get_input(Recognizer), 2),
    NextTokenType = antlr4_token:get_type(NextToken),
    Expected = antlr4_parser:get_expected_tokens(Recognizer),
    case antlr4_interval_set:contains(Expected, NextTokenType) of
        true ->
            report_unwanted_token(Recognizer),
            %% Consume the unwanted token
            antlr4_parser:consume(Recognizer),
            %% Return the matched next token
            antlr4_parser:get_current_token(Recognizer);
        false ->
            undefined
    end.

%% Internal: try single token insertion
single_token_insertion(Recognizer) ->
    Expected = antlr4_parser:get_expected_tokens(Recognizer),
    %% Check if current token could follow missing token
    %% Simplified: just check if we have expected tokens
    case antlr4_interval_set:is_empty(Expected) of
        true -> false;
        false ->
            report_missing_token(Recognizer),
            true
    end.

%% Internal: get a missing symbol for insertion
get_missing_symbol(Recognizer) ->
    Expected = antlr4_parser:get_expected_tokens(Recognizer),
    ExpectedType = antlr4_interval_set:get_min(Expected),
    CurrentToken = antlr4_parser:get_current_token(Recognizer),

    Text = case ExpectedType of
        ?ANTLR4_TOKEN_EOF -> <<"<missing EOF>">>;
        _ -> <<"<missing token>">>
    end,

    #common_token{
        type = ExpectedType,
        text = Text,
        line = antlr4_token:get_line(CurrentToken),
        char_position_in_line = antlr4_token:get_char_position_in_line(CurrentToken)
    }.

%% Internal: consume tokens until we find a resync token
consume_until_resync(Recognizer) ->
    consume_until_resync_loop(Recognizer).

consume_until_resync_loop(Recognizer) ->
    Token = antlr4_parser:get_current_token(Recognizer),
    case antlr4_token:get_type(Token) of
        ?ANTLR4_TOKEN_EOF ->
            ok;
        TokenType ->
            Expected = antlr4_parser:get_expected_tokens_within_current_rule(Recognizer),
            case antlr4_interval_set:contains(Expected, TokenType) of
                true ->
                    ok;
                false ->
                    antlr4_parser:consume(Recognizer),
                    consume_until_resync_loop(Recognizer)
            end
    end.

%% Internal: get token display text for error messages
get_token_error_display(Token) ->
    case antlr4_token:get_type(Token) of
        ?ANTLR4_TOKEN_EOF ->
            <<"<EOF>">>;
        _ ->
            Text = antlr4_token:get_text(Token),
            case Text of
                undefined -> <<"<no text>">>;
                _ -> <<"'", Text/binary, "'">>
            end
    end.

%% Internal: get expected tokens text
get_expected_tokens_text(Recognizer) ->
    Expected = antlr4_parser:get_expected_tokens(Recognizer),
    antlr4_interval_set:to_string(Expected).

%% Internal: get current rule name
get_rule_name(Recognizer) ->
    RuleNames = antlr4_parser:get_rule_names(Recognizer),
    Ctx = antlr4_parser:get_ctx(Recognizer),
    case Ctx of
        undefined ->
            <<"<unknown>">>;
        _ ->
            RuleIndex = antlr4_parser_rule_context:get_rule_index(Ctx),
            case RuleIndex >= 0 andalso RuleIndex < length(RuleNames) of
                true -> lists:nth(RuleIndex + 1, RuleNames);
                false -> integer_to_binary(RuleIndex)
            end
    end.
