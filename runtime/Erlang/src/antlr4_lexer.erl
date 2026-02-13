%% ANTLR4 Lexer Module
%% Base lexer functionality

-module(antlr4_lexer).

-include("antlr4_runtime.hrl").

-export([
    next_token/1,
    skip/1,
    more/1,
    set_mode/2,
    push_mode/2,
    pop_mode/1,
    set_type/2,
    set_channel/2,
    get_char_index/1,
    get_text/1,
    set_text/2,
    get_line/1,
    get_char_position_in_line/1,
    get_input_stream/1,
    emit/1,
    emit/2,
    emit_eof/1,
    get_all_tokens/1,
    reset/1
]).

-record(lexer_state, {
    input :: antlr4_input_stream:input_stream(),
    token :: antlr4_token:token() | undefined,
    token_factory_source_pair :: term(),
    token_start_char_index :: integer(),
    token_start_line :: integer(),
    token_start_char_position_in_line :: integer(),
    hit_eof = false :: boolean(),
    channel = ?ANTLR4_TOKEN_DEFAULT_CHANNEL :: integer(),
    type = ?ANTLR4_TOKEN_INVALID_TYPE :: integer(),
    mode_stack = [] :: [integer()],
    mode = 0 :: integer(),
    text :: binary() | undefined,
    atn :: term(),
    interpreter :: term(),
    decision_to_dfa :: term(),
    shared_context_cache :: term()
}).

-type lexer_state() :: #lexer_state{}.
-export_type([lexer_state/0]).

%% @doc Get the next token from the lexer
-spec next_token(lexer_state()) -> {antlr4_token:token(), lexer_state()}.
next_token(#lexer_state{hit_eof = true} = State) ->
    %% Return EOF token if we've already hit EOF
    EofToken = create_eof_token(State),
    {EofToken, State};
next_token(State) ->
    State1 = State#lexer_state{
        token = undefined,
        channel = ?ANTLR4_TOKEN_DEFAULT_CHANNEL,
        token_start_char_index = antlr4_input_stream:get_index(State#lexer_state.input),
        token_start_char_position_in_line = antlr4_input_stream:get_char_position_in_line(State#lexer_state.input),
        token_start_line = antlr4_input_stream:get_line(State#lexer_state.input),
        text = undefined
    },
    next_token_loop(State1).

next_token_loop(#lexer_state{input = Input} = State) ->
    case antlr4_input_stream:la(Input, 1) of
        ?ANTLR4_TOKEN_EOF ->
            EofToken = create_eof_token(State),
            {EofToken, State#lexer_state{hit_eof = true}};
        _ ->
            try
                %% Try to match a token using the ATN simulator
                State1 = match_token(State),
                case State1#lexer_state.token of
                    undefined ->
                        %% No token emitted, skip was called, try again
                        next_token_loop(State1);
                    Token ->
                        {Token, State1}
                end
            catch
                throw:{lexer_no_viable_alt, State2} ->
                    %% Recovery: skip one character and try again
                    recover(State2)
            end
    end.

%% @doc Match a token using the ATN
match_token(#lexer_state{interpreter = Interpreter, input = Input, mode = Mode} = State) ->
    TokenType = antlr4_lexer_atn_simulator:match(Interpreter, Input, Mode),
    State1 = State#lexer_state{type = TokenType},
    case State1#lexer_state.token of
        undefined when TokenType =/= ?ANTLR4_TOKEN_INVALID_TYPE ->
            emit(State1);
        _ ->
            State1
    end.

%% @doc Recover from a lexer error
recover(#lexer_state{input = Input} = State) ->
    %% Skip one character
    Input1 = antlr4_input_stream:consume(Input),
    State1 = State#lexer_state{input = Input1},
    next_token_loop(State1).

%% @doc Skip the current token (don't emit anything)
-spec skip(lexer_state()) -> lexer_state().
skip(State) ->
    State#lexer_state{type = ?ANTLR4_TOKEN_INVALID_TYPE}.

%% @doc Mark that more input is needed for the current token
-spec more(lexer_state()) -> lexer_state().
more(State) ->
    State#lexer_state{type = ?ANTLR4_TOKEN_INVALID_TYPE}.

%% @doc Set the lexer mode
-spec set_mode(lexer_state(), integer()) -> lexer_state().
set_mode(State, Mode) ->
    State#lexer_state{mode = Mode}.

%% @doc Push a new mode onto the mode stack
-spec push_mode(lexer_state(), integer()) -> lexer_state().
push_mode(#lexer_state{mode_stack = Stack, mode = CurrentMode} = State, Mode) ->
    State#lexer_state{
        mode_stack = [CurrentMode | Stack],
        mode = Mode
    }.

%% @doc Pop a mode from the mode stack
-spec pop_mode(lexer_state()) -> lexer_state().
pop_mode(#lexer_state{mode_stack = []}) ->
    throw({empty_stack, <<"Cannot pop mode from empty stack">>});
pop_mode(#lexer_state{mode_stack = [Mode | Rest]} = State) ->
    State#lexer_state{
        mode_stack = Rest,
        mode = Mode
    }.

%% @doc Set the token type
-spec set_type(lexer_state(), integer()) -> lexer_state().
set_type(State, Type) ->
    State#lexer_state{type = Type}.

%% @doc Set the token channel
-spec set_channel(lexer_state(), integer()) -> lexer_state().
set_channel(State, Channel) ->
    State#lexer_state{channel = Channel}.

%% @doc Get the current character index
-spec get_char_index(lexer_state()) -> integer().
get_char_index(#lexer_state{input = Input}) ->
    antlr4_input_stream:get_index(Input).

%% @doc Get the current token text
-spec get_text(lexer_state()) -> binary().
get_text(#lexer_state{text = Text}) when Text =/= undefined ->
    Text;
get_text(#lexer_state{input = Input, token_start_char_index = Start}) ->
    Stop = antlr4_input_stream:get_index(Input) - 1,
    antlr4_input_stream:get_text(Input, Start, Stop).

%% @doc Set the token text
-spec set_text(lexer_state(), binary()) -> lexer_state().
set_text(State, Text) ->
    State#lexer_state{text = Text}.

%% @doc Get the current line number
-spec get_line(lexer_state()) -> integer().
get_line(#lexer_state{input = Input}) ->
    antlr4_input_stream:get_line(Input).

%% @doc Get the character position in line
-spec get_char_position_in_line(lexer_state()) -> integer().
get_char_position_in_line(#lexer_state{input = Input}) ->
    antlr4_input_stream:get_char_position_in_line(Input).

%% @doc Get the input stream
-spec get_input_stream(lexer_state()) -> antlr4_input_stream:input_stream().
get_input_stream(#lexer_state{input = Input}) ->
    Input.

%% @doc Emit a token with the current state
-spec emit(lexer_state()) -> lexer_state().
emit(State) ->
    Token = create_token(State),
    emit(State, Token).

%% @doc Emit a specific token
-spec emit(lexer_state(), antlr4_token:token()) -> lexer_state().
emit(State, Token) ->
    State#lexer_state{token = Token}.

%% @doc Emit an EOF token
-spec emit_eof(lexer_state()) -> lexer_state().
emit_eof(State) ->
    EofToken = create_eof_token(State),
    emit(State, EofToken).

%% @doc Get all tokens from the input
-spec get_all_tokens(lexer_state()) -> {[antlr4_token:token()], lexer_state()}.
get_all_tokens(State) ->
    get_all_tokens(State, []).

get_all_tokens(State, Acc) ->
    {Token, State1} = next_token(State),
    case antlr4_token:get_type(Token) of
        ?ANTLR4_TOKEN_EOF ->
            {lists:reverse([Token | Acc]), State1};
        _ ->
            get_all_tokens(State1, [Token | Acc])
    end.

%% @doc Reset the lexer to the beginning
-spec reset(lexer_state()) -> lexer_state().
reset(#lexer_state{input = Input} = State) ->
    Input1 = antlr4_input_stream:seek(Input, 0),
    State#lexer_state{
        input = Input1,
        token = undefined,
        channel = ?ANTLR4_TOKEN_DEFAULT_CHANNEL,
        type = ?ANTLR4_TOKEN_INVALID_TYPE,
        token_start_char_index = 0,
        token_start_line = 1,
        token_start_char_position_in_line = 0,
        hit_eof = false,
        mode = 0,
        mode_stack = [],
        text = undefined
    }.

%% Internal: create a token from the current state
create_token(#lexer_state{
    type = Type,
    channel = Channel,
    token_start_char_index = Start,
    token_start_line = Line,
    token_start_char_position_in_line = Column,
    input = Input
} = State) ->
    Stop = antlr4_input_stream:get_index(Input) - 1,
    Text = case State#lexer_state.text of
        undefined -> antlr4_input_stream:get_text(Input, Start, Stop);
        T -> T
    end,
    #common_token{
        type = Type,
        channel = Channel,
        text = Text,
        start_index = Start,
        stop_index = Stop,
        line = Line,
        char_position_in_line = Column,
        input_stream = Input
    }.

%% Internal: create an EOF token
create_eof_token(#lexer_state{input = Input}) ->
    Index = antlr4_input_stream:get_index(Input),
    Line = antlr4_input_stream:get_line(Input),
    Column = antlr4_input_stream:get_char_position_in_line(Input),
    #common_token{
        type = ?ANTLR4_TOKEN_EOF,
        channel = ?ANTLR4_TOKEN_DEFAULT_CHANNEL,
        text = <<"<EOF>">>,
        start_index = Index,
        stop_index = Index,
        line = Line,
        char_position_in_line = Column,
        input_stream = Input
    }.
