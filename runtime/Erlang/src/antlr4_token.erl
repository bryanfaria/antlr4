%% ANTLR4 Token Module
%% Represents a token in the input stream

-module(antlr4_token).

-include("antlr4_runtime.hrl").

-export([
    new/0,
    new/1,
    new/5,
    get_type/1,
    set_type/2,
    get_channel/1,
    set_channel/2,
    get_text/1,
    set_text/2,
    get_line/1,
    set_line/2,
    get_char_position_in_line/1,
    set_char_position_in_line/2,
    get_token_index/1,
    set_token_index/2,
    get_start_index/1,
    set_start_index/2,
    get_stop_index/1,
    set_stop_index/2,
    get_source/1,
    set_source/2,
    eof_token/0
]).

-type token() :: #common_token{}.
-export_type([token/0]).

%% @doc Create a new empty token
-spec new() -> token().
new() ->
    #common_token{}.

%% @doc Create a new token with a type
-spec new(integer()) -> token().
new(Type) ->
    #common_token{type = Type}.

%% @doc Create a new token with all basic fields
-spec new(integer(), binary(), integer(), integer(), integer()) -> token().
new(Type, Text, Channel, Start, Stop) ->
    #common_token{
        type = Type,
        text = Text,
        channel = Channel,
        start_index = Start,
        stop_index = Stop
    }.

%% @doc Get the token type
-spec get_type(token()) -> integer().
get_type(#common_token{type = Type}) ->
    Type.

%% @doc Set the token type
-spec set_type(token(), integer()) -> token().
set_type(Token, Type) ->
    Token#common_token{type = Type}.

%% @doc Get the token channel
-spec get_channel(token()) -> integer().
get_channel(#common_token{channel = Channel}) ->
    Channel.

%% @doc Set the token channel
-spec set_channel(token(), integer()) -> token().
set_channel(Token, Channel) ->
    Token#common_token{channel = Channel}.

%% @doc Get the token text
-spec get_text(token()) -> binary() | undefined.
get_text(#common_token{text = Text, input_stream = undefined}) ->
    Text;
get_text(#common_token{text = undefined, input_stream = Input, start_index = Start, stop_index = Stop})
  when Input =/= undefined, Start >= 0, Stop >= Start ->
    antlr4_input_stream:get_text(Input, Start, Stop);
get_text(#common_token{text = Text}) ->
    Text.

%% @doc Set the token text
-spec set_text(token(), binary()) -> token().
set_text(Token, Text) ->
    Token#common_token{text = Text}.

%% @doc Get the line number
-spec get_line(token()) -> integer().
get_line(#common_token{line = Line}) ->
    Line.

%% @doc Set the line number
-spec set_line(token(), integer()) -> token().
set_line(Token, Line) ->
    Token#common_token{line = Line}.

%% @doc Get the character position in line
-spec get_char_position_in_line(token()) -> integer().
get_char_position_in_line(#common_token{char_position_in_line = Pos}) ->
    Pos.

%% @doc Set the character position in line
-spec set_char_position_in_line(token(), integer()) -> token().
set_char_position_in_line(Token, Pos) ->
    Token#common_token{char_position_in_line = Pos}.

%% @doc Get the token index
-spec get_token_index(token()) -> integer().
get_token_index(#common_token{token_index = Index}) ->
    Index.

%% @doc Set the token index
-spec set_token_index(token(), integer()) -> token().
set_token_index(Token, Index) ->
    Token#common_token{token_index = Index}.

%% @doc Get the start index
-spec get_start_index(token()) -> integer().
get_start_index(#common_token{start_index = Index}) ->
    Index.

%% @doc Set the start index
-spec set_start_index(token(), integer()) -> token().
set_start_index(Token, Index) ->
    Token#common_token{start_index = Index}.

%% @doc Get the stop index
-spec get_stop_index(token()) -> integer().
get_stop_index(#common_token{stop_index = Index}) ->
    Index.

%% @doc Set the stop index
-spec set_stop_index(token(), integer()) -> token().
set_stop_index(Token, Index) ->
    Token#common_token{stop_index = Index}.

%% @doc Get the source
-spec get_source(token()) -> term().
get_source(#common_token{input_stream = Input}) ->
    Input.

%% @doc Set the source
-spec set_source(token(), term()) -> token().
set_source(Token, Source) ->
    Token#common_token{input_stream = Source}.

%% @doc Create an EOF token
-spec eof_token() -> token().
eof_token() ->
    #common_token{
        type = ?ANTLR4_TOKEN_EOF,
        text = <<"<EOF>">>
    }.
