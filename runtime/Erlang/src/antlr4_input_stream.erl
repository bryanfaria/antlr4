%% ANTLR4 Input Stream
%% Provides character-based input for the lexer

-module(antlr4_input_stream).

-include("antlr4_runtime.hrl").

-export([
    new/1,
    new/2,
    consume/1,
    la/2,
    lt/2,
    mark/1,
    release/2,
    seek/2,
    get_text/3,
    get_source_name/1,
    get_index/1,
    get_size/1,
    get_line/1,
    get_char_position_in_line/1,
    set_line/2,
    set_char_position_in_line/2
]).

-type input_stream() :: #input_stream{}.
-export_type([input_stream/0]).

%% @doc Create a new input stream from binary data
-spec new(binary()) -> input_stream().
new(Data) ->
    new(Data, <<"<unknown>">>).

%% @doc Create a new input stream from binary data with a name
-spec new(binary(), binary()) -> input_stream().
new(Data, Name) when is_binary(Data) ->
    #input_stream{
        data = Data,
        size = byte_size(Data),
        index = 0,
        line = 1,
        char_position_in_line = 0,
        name = Name
    }.

%% @doc Consume one character and advance the stream position
-spec consume(input_stream()) -> input_stream().
consume(#input_stream{index = Index, size = Size}) when Index >= Size ->
    throw({illegal_state, <<"cannot consume EOF">>});
consume(#input_stream{data = Data, index = Index, line = Line, char_position_in_line = Pos} = Stream) ->
    case binary:at(Data, Index) of
        $\n ->
            Stream#input_stream{
                index = Index + 1,
                line = Line + 1,
                char_position_in_line = 0
            };
        _ ->
            Stream#input_stream{
                index = Index + 1,
                char_position_in_line = Pos + 1
            }
    end.

%% @doc Look ahead in the input stream (1-based index for positive, negative looks back)
-spec la(input_stream(), integer()) -> integer().
la(#input_stream{index = Index, size = Size}, Offset) when Index + Offset - 1 >= Size ->
    ?ANTLR4_TOKEN_EOF;
la(#input_stream{index = Index}, Offset) when Index + Offset - 1 < 0 ->
    ?ANTLR4_TOKEN_EOF;
la(_, 0) ->
    0;
la(#input_stream{data = Data, index = Index}, Offset) when Offset > 0 ->
    binary:at(Data, Index + Offset - 1);
la(#input_stream{data = Data, index = Index}, Offset) when Offset < 0 ->
    binary:at(Data, Index + Offset).

%% @doc Same as la/2 but returns the character at position
-spec lt(input_stream(), integer()) -> integer().
lt(Stream, Offset) ->
    la(Stream, Offset).

%% @doc Mark the current position for later reset (returns a marker)
-spec mark(input_stream()) -> {integer(), input_stream()}.
mark(Stream) ->
    {-1, Stream}.

%% @doc Release a marker (no-op for this implementation)
-spec release(input_stream(), integer()) -> input_stream().
release(Stream, _Marker) ->
    Stream.

%% @doc Seek to a specific position
-spec seek(input_stream(), non_neg_integer()) -> input_stream().
seek(#input_stream{size = Size} = Stream, Index) when Index >= Size ->
    Stream#input_stream{index = Size};
seek(#input_stream{data = Data} = Stream, Index) when Index >= 0 ->
    %% Recalculate line and char position
    {Line, CharPos} = calculate_position(Data, 0, Index, 1, 0),
    Stream#input_stream{
        index = Index,
        line = Line,
        char_position_in_line = CharPos
    }.

%% @doc Get text from the stream between two indices
-spec get_text(input_stream(), non_neg_integer(), non_neg_integer()) -> binary().
get_text(#input_stream{data = Data, size = Size}, Start, Stop) ->
    ActualStop = min(Stop, Size - 1),
    case ActualStop >= Start of
        true ->
            Length = ActualStop - Start + 1,
            binary:part(Data, Start, Length);
        false ->
            <<>>
    end.

%% @doc Get the source name
-spec get_source_name(input_stream()) -> binary().
get_source_name(#input_stream{name = Name}) ->
    Name.

%% @doc Get the current index
-spec get_index(input_stream()) -> non_neg_integer().
get_index(#input_stream{index = Index}) ->
    Index.

%% @doc Get the total size
-spec get_size(input_stream()) -> non_neg_integer().
get_size(#input_stream{size = Size}) ->
    Size.

%% @doc Get the current line number
-spec get_line(input_stream()) -> pos_integer().
get_line(#input_stream{line = Line}) ->
    Line.

%% @doc Get the current character position in line
-spec get_char_position_in_line(input_stream()) -> non_neg_integer().
get_char_position_in_line(#input_stream{char_position_in_line = Pos}) ->
    Pos.

%% @doc Set the current line number
-spec set_line(input_stream(), pos_integer()) -> input_stream().
set_line(Stream, Line) ->
    Stream#input_stream{line = Line}.

%% @doc Set the character position in line
-spec set_char_position_in_line(input_stream(), non_neg_integer()) -> input_stream().
set_char_position_in_line(Stream, Pos) ->
    Stream#input_stream{char_position_in_line = Pos}.

%% Internal helper to calculate line and position
-spec calculate_position(binary(), non_neg_integer(), non_neg_integer(), pos_integer(), non_neg_integer()) ->
    {pos_integer(), non_neg_integer()}.
calculate_position(_Data, CurrentIndex, TargetIndex, Line, CharPos) when CurrentIndex >= TargetIndex ->
    {Line, CharPos};
calculate_position(Data, CurrentIndex, TargetIndex, Line, _CharPos) ->
    case binary:at(Data, CurrentIndex) of
        $\n ->
            calculate_position(Data, CurrentIndex + 1, TargetIndex, Line + 1, 0);
        _ ->
            calculate_position(Data, CurrentIndex + 1, TargetIndex, Line, _CharPos + 1)
    end.
