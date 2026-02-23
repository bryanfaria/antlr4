# Erlang ANTLR4 Target — Status & Roadmap

## Goal

Generate a working Erlang lexer and parser from the Athena SQL grammar:
- `/grammars-v4/sql/athena/AthenaLexer.g4` (~171 tokens, 3 fragments, `caseInsensitive = true`, `-> channel(HIDDEN)`)
- `/grammars-v4/sql/athena/AthenaParser.g4` (~125 rules, 2 left-recursive rules, element labels, `tokenVocab = AthenaLexer`)

No semantic predicates, no embedded actions, no lexer modes, no alt labels, no returns/locals.

---

## What Exists Today

### Code Generation (Tool Side)

| Component | Location | Lines | Status |
|-----------|----------|-------|--------|
| ErlangTarget.java | `tool/src/.../codegen/target/ErlangTarget.java` | 146 | Minimal — file naming, reserved words, snake_case conversion |
| Erlang.stg | `tool/resources/.../codegen/Erlang/Erlang.stg` | 845 | Substantial — parser/lexer/listener/visitor templates all present |

The code generator produces valid `.erl` modules. Token constants are emitted as `-define` macros. The serialized ATN is embedded as an integer list. Rule functions, loop constructs, and decision blocks all generate syntactically correct Erlang.

### Runtime Library (`runtime/Erlang/`)

| Module | Lines | Status |
|--------|-------|--------|
| `antlr4_input_stream.erl` | 165 | **Complete** — lookahead, seeking, position tracking |
| `antlr4_token.erl` | 158 | **Complete** — token representation, all accessors |
| `antlr4_token_stream.erl` | 316 | **Complete** — buffered stream, channel filtering, lookahead |
| `antlr4_lexer.erl` | 274 | **Mostly complete** — token emission, mode stack, `skip/1` and `set_channel/2` exist but are never called |
| `antlr4_lexer_atn_simulator.erl` | 309 | **Gap** — ATN simulation works, but lexer actions are never executed |
| `antlr4_parser.erl` | 441 | **Gap** — core parsing works, but `precpred/2` is stubbed (always returns `true`) |
| `antlr4_parser_atn_simulator.erl` | 270 | **Mostly complete** — adaptive prediction, DFA caching, closure computation |
| `antlr4_atn.erl` | 194 | **Complete** — ATN structure and state management |
| `antlr4_atn_deserializer.erl` | 240 | **Complete** — full deserialization including lexer actions |
| `antlr4_dfa.erl` | 143 | **Complete** — DFA state collection |
| `antlr4_dfa_state.erl` | 142 | **Complete** — individual DFA states with edges |
| `antlr4_parse_tree.erl` | 108 | **Complete** — terminal/error nodes, accept/visitor |
| `antlr4_parse_tree_walker.erl` | 87 | **Complete** — tree walking |
| `antlr4_parser_rule_context.erl` | 291 | **Complete** — parent/child relationships, start/stop tokens |
| `antlr4_prediction_context.erl` | 217 | **Complete** — prediction context caching |
| `antlr4_interval_set.erl` | 206 | **Complete** — set operations for token ranges |
| `antlr4_default_error_strategy.erl` | 237 | **Mostly complete** — single-token insertion/deletion recovery |
| `antlr4_error_listener.erl` | 54 | **Complete** — simple listener interface |
| `antlr4_runtime.hrl` | 281 | **Complete** — all record definitions, constants, type macros |

**Build system**: `rebar.config` with proper profiles, `antlr4.app.src` with OTP metadata. No external dependencies.

**Total runtime**: ~3,850 lines of Erlang.

### Test Infrastructure

| Component | Location | Status |
|-----------|----------|--------|
| `ErlangRunner.java` | `runtime-testsuite/.../erlang/` | 217 lines — compiles runtime + generated code, runs via `erl` |
| `ErlangRuntimeTests.java` | `runtime-testsuite/.../erlang/` | 17 lines — test entry point |
| Erlang test template (`.test.stg`) | — | **Missing** — cannot run ANTLR's standard runtime test suite |
| `test_erlang/Hello.g4` | `test_erlang/` | Simple example grammar with generated output |

### What Works End-to-End

A simple grammar like `Hello.g4` (`r: 'hello' ID EOF;`) can be:
1. Fed to ANTLR tool to generate `hello_parser.erl` and `hello_lexer.erl`
2. Compiled alongside the runtime
3. Used to lex and parse simple input (no channels, no left recursion, no actions)

---

## What Must Be Fixed for Athena SQL

### Bug 1: Lexer Actions Not Executed (CRITICAL)

**Problem**: The Athena lexer uses `-> channel(HIDDEN)` on `WS` and `LINE_COMMENT` rules. The ATN deserializer correctly reads lexer action records, but `antlr4_lexer_atn_simulator.erl` never executes them. Whitespace tokens are emitted on the default channel, which causes every parser rule to fail.

**Where the fix goes**:
- `antlr4_lexer_atn_simulator.erl` — after accepting a token, check if the matched rule has associated lexer actions. If so, execute them (channel, skip, type, mode, pushMode, popMode).
- The lexer action records are already deserialized into `#lexer_action{}` records by `antlr4_atn_deserializer.erl`.
- `antlr4_lexer.erl` already has `set_channel/2`, `skip/1`, `set_type/2`, `push_mode/2`, `pop_mode/1` — they just need to be called.

**Reference**: See how the Java runtime does it in `LexerATNSimulator.java` → `execATN()` → calls `lexerAction.execute(lexer)` after accepting.

### Bug 2: Precedence Predicate Stubbed (CRITICAL)

**Problem**: The Athena parser has two left-recursive rules:
```
boolean_expression
    : boolean_expression AND boolean_expression
    | boolean_expression OR boolean_expression
    | NOT* ('(' boolean_expression ')' | pred)
    ;

expression
    : primitive_expression
    | '(' expression ')'
    | expression op = (STAR | DIVIDE | MODULE) expression
    | expression op = (PLUS | MINUS) expression
    | expression DOT expression
    | ...
    ;
```

ANTLR rewrites these into precedence-climbing loops. The generated code calls `antlr4_parser:precpred(Precedence)`, but the current implementation always returns `true`:

```erlang
precpred(_State, _Precedence) ->
    true.
```

This means operator precedence is ignored — `1 + 2 * 3` would parse incorrectly.

**Where the fix goes**:
- `antlr4_parser.erl` — `precpred/2` must compare the given precedence against the current precedence level stored when `enter_recursion_rule` was called.
- `enter_recursion_rule` must store the precedence level in the parser state (it currently ignores the `_Precedence` parameter).
- `push_new_recursion_context` and `unroll_recursion_contexts` are present but may need review to ensure the precedence stack is maintained correctly.

**Reference**: See `Parser.java` → `precpred(RuleContext, int)` which calls `_ctx.precedence >= precedence`.

### Bug 3: Case-Insensitive Lexing Not Supported (CRITICAL)

**Problem**: The Athena lexer declares `options { caseInsensitive = true; }`. This means keywords like `SELECT`, `select`, and `Select` must all match. This option affects how the ATN is built — character transitions should match both cases.

**Where the fix goes**: This is handled at the **tool level**, not the runtime. ANTLR's `LexerATNFactory` generates case-insensitive transitions when this option is set. Need to verify:
1. Does `ErlangTarget.java` need to opt into this? Check if other targets do anything special.
2. Does the ATN serialization preserve case-insensitive ranges correctly?
3. Test: generate code from `AthenaLexer.g4` and inspect whether the serialized ATN contains both-case character ranges.

**Likely outcome**: This may already work if the ATN factory handles it language-independently. Needs verification.

---

## What Is NOT Required for Athena SQL

These features are absent from the Athena grammar and can be deferred:

- Semantic predicates (`{...}?`) — not used
- Embedded actions (`{...}`) — not used
- Lexer modes (`mode`, `pushMode`, `popMode`) — not used
- Alt labels (`# labelName`) — not used
- Rule `returns` / `locals` — not used
- Visitor tree traversal — not needed for parsing
- `-> skip` — not used (Athena uses `channel(HIDDEN)` instead)
- `-> type(...)` — not used

---

## Verification Plan

### Step 1: Generate Erlang code from Athena grammars
```bash
java -jar antlr4.jar -Dlanguage=Erlang -o gen \
  /path/to/grammars-v4/sql/athena/AthenaLexer.g4 \
  /path/to/grammars-v4/sql/athena/AthenaParser.g4
```
Verify: generated `.erl` files compile without errors.

### Step 2: Compile and link
```bash
cd runtime/Erlang && rebar3 compile
erlc -I runtime/Erlang/include -pa runtime/Erlang/_build/default/lib/antlr4/ebin gen/*.erl
```

### Step 3: Test lexing
```erlang
Input = antlr4_input_stream:new(<<"SELECT 1 FROM foo">>),
LexerState = athena_lexer:new(Input),
{Tokens, _} = athena_lexer:get_all_tokens(LexerState),
%% Verify: WS tokens on HIDDEN channel, keywords recognized case-insensitively
```

### Step 4: Test parsing
```erlang
TokenStream = antlr4_token_stream:new(Tokens),
ParserState = athena_parser:new(TokenStream),
Tree = athena_parser:query(ParserState),
%% Verify: parse tree correctly represents SELECT 1 FROM foo
```

### Step 5: Test precedence
```erlang
%% Parse: SELECT 1 + 2 * 3 FROM foo
%% Verify: * binds tighter than + in the parse tree
```

---

## File Inventory

```
tool/
  src/org/antlr/v4/codegen/target/ErlangTarget.java    # Code gen target
  resources/.../codegen/Erlang/Erlang.stg               # Output templates

runtime/Erlang/
  rebar.config                                          # Build config
  src/antlr4.app.src                                    # OTP app
  src/antlr4_*.erl                                      # Runtime modules (~17 files)
  include/antlr4_runtime.hrl                            # Records & constants

runtime-testsuite/
  test/.../erlang/ErlangRunner.java                     # Test runner
  test/.../erlang/ErlangRuntimeTests.java               # Test entry

test_erlang/
  Hello.g4                                              # Example grammar
  hello_parser.erl, hello_lexer.erl, ...                # Generated output
```
