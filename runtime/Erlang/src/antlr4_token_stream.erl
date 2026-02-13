%% ANTLR4 Token Stream
%% Provides token-based input for the parser

-module(antlr4_token_stream).

-include("antlr4_runtime.hrl").

-export([
    new/1,
    new/2,
    consume/1,
    la/2,
    lt/2,
    get/2,
    get_token_source/1,
    get_text/1,
    get_text/3,
    get_text_from_interval/2,
    get_text_from_context/2,
    get_text_from_tokens/3,
    get_all_tokens/1,
    get_tokens/3,
    get_tokens_on_channel/3,
    get_hidden_tokens_to_left/2,
    get_hidden_tokens_to_left/3,
    get_hidden_tokens_to_right/2,
    get_hidden_tokens_to_right/3,
    mark/1,
    release/2,
    seek/2,
    get_index/1,
    get_size/1,
    fill/1,
    sync/2,
    reset/1
]).

-type token_stream() :: #token_stream{}.
-export_type([token_stream/0]).

%% @doc Create a new token stream from a lexer
-spec new(term()) -> token_stream().
new(TokenSource) ->
    new(TokenSource, ?ANTLR4_TOKEN_DEFAULT_CHANNEL).

%% @doc Create a new token stream from a lexer with a specific channel
-spec new(term(), integer()) -> token_stream().
new(TokenSource, Channel) ->
    #token_stream{
        token_source = TokenSource,
        tokens = [],
        index = -1,
        fetched_eof = false,
        channel = Channel
    }.

%% @doc Consume one token and advance
-spec consume(token_stream()) -> token_stream().
consume(#token_stream{index = Index} = Stream) ->
    Stream1 = sync(Stream, Index + 1),
    NewIndex = adjust_seek_index(Stream1, Index + 1),
    ActualSize = get_actual_size(Stream1),
    case NewIndex < ActualSize of
        true ->
            Stream1#token_stream{index = NewIndex};
        false ->
            Stream1
    end.

%% @doc Look ahead in the token stream
-spec la(token_stream(), integer()) -> integer().
la(Stream, Offset) ->
    Token = lt(Stream, Offset),
    antlr4_token:get_type(Token).

%% @doc Get token at offset from current position
-spec lt(token_stream(), integer()) -> antlr4_token:token().
lt(_Stream, 0) ->
    undefined;
lt(#token_stream{index = Index} = Stream, Offset) when Offset < 0 ->
    case Index + Offset of
        I when I >= 0 ->
            get(Stream, I);
        _ ->
            undefined
    end;
lt(#token_stream{index = Index} = Stream, Offset) when Offset > 0 ->
    Stream1 = sync(Stream, Index + Offset),
    TargetIndex = adjust_seek_index(Stream1, Index + Offset),
    case TargetIndex < get_actual_size(Stream1) of
        true -> get(Stream1, TargetIndex);
        false -> antlr4_token:eof_token()
    end.

%% @doc Get token at absolute index
-spec get(token_stream(), non_neg_integer()) -> antlr4_token:token().
get(#token_stream{tokens = Tokens}, Index) ->
    case Index < length(Tokens) of
        true -> lists:nth(Index + 1, Tokens);
        false -> antlr4_token:eof_token()
    end.

%% @doc Get the token source (lexer)
-spec get_token_source(token_stream()) -> term().
get_token_source(#token_stream{token_source = Source}) ->
    Source.

%% @doc Get all text from the stream
-spec get_text(token_stream()) -> binary().
get_text(Stream) ->
    Stream1 = fill(Stream),
    get_text(Stream1, 0, get_actual_size(Stream1) - 1).

%% @doc Get text between two indices
-spec get_text(token_stream(), non_neg_integer(), non_neg_integer()) -> binary().
get_text(#token_stream{tokens = Tokens}, Start, Stop) ->
    ActualStop = min(Stop, length(Tokens) - 1),
    case ActualStop < Start of
        true -> <<>>;
        false ->
            TokensInRange = lists:sublist(Tokens, Start + 1, ActualStop - Start + 1),
            iolist_to_binary([antlr4_token:get_text(T) || T <- TokensInRange, T =/= undefined])
    end.

%% @doc Get text from an interval
-spec get_text_from_interval(token_stream(), #interval{}) -> binary().
get_text_from_interval(Stream, #interval{start_index = Start, stop_index = Stop}) ->
    get_text(Stream, Start, Stop).

%% @doc Get text from a parser rule context
-spec get_text_from_context(token_stream(), term()) -> binary().
get_text_from_context(Stream, Ctx) ->
    Start = antlr4_parser_rule_context:get_start(Ctx),
    Stop = antlr4_parser_rule_context:get_stop(Ctx),
    case {Start, Stop} of
        {undefined, _} -> <<>>;
        {_, undefined} -> <<>>;
        _ ->
            StartIndex = antlr4_token:get_token_index(Start),
            StopIndex = antlr4_token:get_token_index(Stop),
            get_text(Stream, StartIndex, StopIndex)
    end.

%% @doc Get text between two tokens
-spec get_text_from_tokens(token_stream(), antlr4_token:token(), antlr4_token:token()) -> binary().
get_text_from_tokens(Stream, StartToken, StopToken) ->
    case {StartToken, StopToken} of
        {undefined, _} -> <<>>;
        {_, undefined} -> <<>>;
        _ ->
            StartIndex = antlr4_token:get_token_index(StartToken),
            StopIndex = antlr4_token:get_token_index(StopToken),
            get_text(Stream, StartIndex, StopIndex)
    end.

%% @doc Get all tokens
-spec get_all_tokens(token_stream()) -> [antlr4_token:token()].
get_all_tokens(Stream) ->
    Stream1 = fill(Stream),
    Stream1#token_stream.tokens.

%% @doc Get tokens of a specific type in a range
-spec get_tokens(token_stream(), non_neg_integer(), non_neg_integer()) -> [antlr4_token:token()].
get_tokens(#token_stream{tokens = Tokens}, Start, Stop) ->
    ActualStop = min(Stop, length(Tokens) - 1),
    case ActualStop < Start of
        true -> [];
        false -> lists:sublist(Tokens, Start + 1, ActualStop - Start + 1)
    end.

%% @doc Get tokens on a specific channel
-spec get_tokens_on_channel(token_stream(), non_neg_integer(), integer()) -> [antlr4_token:token()].
get_tokens_on_channel(Stream, Start, Channel) ->
    Stream1 = sync(Stream, Start),
    Tokens = Stream1#token_stream.tokens,
    filter_by_channel(lists:nthtail(Start, Tokens), Channel, []).

filter_by_channel([], _Channel, Acc) ->
    lists:reverse(Acc);
filter_by_channel([Token | Rest], Channel, Acc) ->
    case antlr4_token:get_channel(Token) of
        Channel -> filter_by_channel(Rest, Channel, [Token | Acc]);
        _ -> filter_by_channel(Rest, Channel, Acc)
    end.

%% @doc Get hidden tokens to the left of a position
-spec get_hidden_tokens_to_left(token_stream(), non_neg_integer()) -> [antlr4_token:token()].
get_hidden_tokens_to_left(Stream, TokenIndex) ->
    get_hidden_tokens_to_left(Stream, TokenIndex, ?ANTLR4_TOKEN_HIDDEN_CHANNEL).

-spec get_hidden_tokens_to_left(token_stream(), non_neg_integer(), integer()) -> [antlr4_token:token()].
get_hidden_tokens_to_left(#token_stream{tokens = Tokens}, TokenIndex, Channel) ->
    filter_hidden_left(lists:sublist(Tokens, TokenIndex), Channel, []).

filter_hidden_left([], _Channel, Acc) ->
    Acc;
filter_hidden_left(Tokens, Channel, Acc) ->
    [Last | Rest] = lists:reverse(Tokens),
    case antlr4_token:get_channel(Last) of
        Channel -> filter_hidden_left(lists:reverse(Rest), Channel, [Last | Acc]);
        _ -> Acc
    end.

%% @doc Get hidden tokens to the right of a position
-spec get_hidden_tokens_to_right(token_stream(), non_neg_integer()) -> [antlr4_token:token()].
get_hidden_tokens_to_right(Stream, TokenIndex) ->
    get_hidden_tokens_to_right(Stream, TokenIndex, ?ANTLR4_TOKEN_HIDDEN_CHANNEL).

-spec get_hidden_tokens_to_right(token_stream(), non_neg_integer(), integer()) -> [antlr4_token:token()].
get_hidden_tokens_to_right(Stream, TokenIndex, Channel) ->
    Stream1 = sync(Stream, TokenIndex + 1),
    Tokens = lists:nthtail(TokenIndex + 1, Stream1#token_stream.tokens),
    filter_hidden_right(Tokens, Channel, []).

filter_hidden_right([], _Channel, Acc) ->
    lists:reverse(Acc);
filter_hidden_right([Token | Rest], Channel, Acc) ->
    case antlr4_token:get_channel(Token) of
        Channel -> filter_hidden_right(Rest, Channel, [Token | Acc]);
        _ -> lists:reverse(Acc)
    end.

%% @doc Mark current position
-spec mark(token_stream()) -> {integer(), token_stream()}.
mark(Stream) ->
    {0, Stream}.

%% @doc Release a mark
-spec release(token_stream(), integer()) -> token_stream().
release(Stream, _Marker) ->
    Stream.

%% @doc Seek to a specific position
-spec seek(token_stream(), non_neg_integer()) -> token_stream().
seek(Stream, Index) ->
    Stream1 = sync(Stream, Index),
    AdjustedIndex = adjust_seek_index(Stream1, Index),
    Stream1#token_stream{index = AdjustedIndex}.

%% @doc Get current index
-spec get_index(token_stream()) -> integer().
get_index(#token_stream{index = Index}) ->
    Index.

%% @doc Get the number of tokens
-spec get_size(token_stream()) -> non_neg_integer().
get_size(Stream) ->
    Stream1 = fill(Stream),
    length(Stream1#token_stream.tokens).

%% @doc Fill the token buffer (fetch all tokens)
-spec fill(token_stream()) -> token_stream().
fill(#token_stream{fetched_eof = true} = Stream) ->
    Stream;
fill(Stream) ->
    fill_loop(Stream).

fill_loop(#token_stream{fetched_eof = true} = Stream) ->
    Stream;
fill_loop(Stream) ->
    Stream1 = fetch_token(Stream),
    fill_loop(Stream1).

%% @doc Synchronize to ensure we have tokens up to index
-spec sync(token_stream(), non_neg_integer()) -> token_stream().
sync(#token_stream{fetched_eof = true} = Stream, _Index) ->
    Stream;
sync(#token_stream{tokens = Tokens} = Stream, Index) when Index < length(Tokens) ->
    Stream;
sync(Stream, Index) ->
    sync_loop(Stream, Index).

sync_loop(#token_stream{fetched_eof = true} = Stream, _Index) ->
    Stream;
sync_loop(#token_stream{tokens = Tokens} = Stream, Index) when Index < length(Tokens) ->
    Stream;
sync_loop(Stream, Index) ->
    Stream1 = fetch_token(Stream),
    sync_loop(Stream1, Index).

%% @doc Reset the stream to the beginning
-spec reset(token_stream()) -> token_stream().
reset(Stream) ->
    seek(Stream, 0).

%% Internal: fetch a single token from the source
fetch_token(#token_stream{token_source = Source, tokens = Tokens} = Stream) ->
    {Token, NewSource} = antlr4_lexer:next_token(Source),
    IndexedToken = antlr4_token:set_token_index(Token, length(Tokens)),
    NewTokens = Tokens ++ [IndexedToken],
    FetchedEof = antlr4_token:get_type(Token) =:= ?ANTLR4_TOKEN_EOF,
    Stream#token_stream{
        token_source = NewSource,
        tokens = NewTokens,
        fetched_eof = FetchedEof
    }.

%% Internal: get actual size of token list
get_actual_size(#token_stream{tokens = Tokens}) ->
    length(Tokens).

%% Internal: adjust seek index based on channel
adjust_seek_index(#token_stream{channel = Channel} = Stream, Index) ->
    adjust_seek_index_loop(Stream, Index, Channel).

adjust_seek_index_loop(Stream, Index, Channel) ->
    case Index < get_actual_size(Stream) of
        true ->
            Token = get(Stream, Index),
            case antlr4_token:get_channel(Token) of
                Channel -> Index;
                _ -> adjust_seek_index_loop(Stream, Index + 1, Channel)
            end;
        false ->
            Index
    end.
