# Erlang ANTLR4 Target — Status & Roadmap

## Goal

Generate a working Erlang lexer and parser from the Athena SQL grammar:
- `/grammars-v4/sql/athena/AthenaLexer.g4` (~171 tokens, 3 fragments, `caseInsensitive = true`, `-> channel(HIDDEN)`)
- `/grammars-v4/sql/athena/AthenaParser.g4` (~125 rules, 2 left-recursive rules, element labels, `tokenVocab = AthenaLexer`)

No semantic predicates, no embedded actions, no lexer modes, no alt labels, no returns/locals.

---

## Current Status

### What Works End-to-End

The `Hello.g4` grammar (`r: 'hello' ID EOF; WS: [ \t\r\n]+ -> skip;`) works fully:
1. ANTLR tool generates `hello_parser.erl` and `hello_lexer.erl`
2. Runtime compiles cleanly with `rebar3 compile`
3. Lexer correctly tokenizes input, including `-> skip` actions (whitespace is consumed but no token emitted)
4. Parser correctly matches token sequences via process-dictionary-based API
5. All three e2e tests pass (basic lexing, skip action, parser)

### Recently Fixed Bugs

#### Bug 1: Lexer Actions Not Executed — FIXED

The ATN simulator now properly accumulates lexer actions during epsilon closure and returns them alongside the token type. The lexer executes them after matching (`channel`, `skip`, `type`, `mode`, `pushMode`, `popMode`, `more`).

**Root causes found and fixed:**
- ATN deserializer was completely wrong for format v4 (reading non-existent UUID, missing LOOP_END/BlockStartState extra ints, wrong rules format)
- ACTION transitions stored `Arg1` (ruleIndex) as action_index instead of `Arg2` (actionIndex)
- Epsilon transitions (ACTION, RULE, PREDICATE, PRECEDENCE) were not marked as epsilon
- Epsilon closure was missing entirely — epsilon transitions were being treated as character-matching transitions
- Erlang immutability caused stale state references: transition targets were copies from before transitions were added. Fixed with a `StateMap` lookup that resolves every target through the canonical state list
- The ATN simulator consumed input during matching but never returned the updated input stream (lost due to Erlang immutability). Fixed by returning `{TokenType, LexerActions, NewInput}`
- Accept state capture happened before consume (should be after, matching Java's order)

#### Bug 2: Precedence Predicate Stubbed — FIXED

`precpred/2` now compares `Precedence >= Top` using a precedence stack. `enter_recursion_rule` pushes, `unroll_recursion_contexts` pops. **Not yet tested with a left-recursive grammar** — needs verification with Athena SQL or a simpler expression grammar.

#### Bug 3: Case-Insensitive Lexing — No Runtime Changes Needed

Confirmed: case-insensitive support is handled entirely at the ATN construction level by `LexerATNFactory`. The serialized ATN already contains both-case ranges. No target-specific or runtime code needed.

#### Additional Fix: API Mismatch Between Generated Code and Runtime

The generated code uses **maps + process dictionary** while the runtime used **records + functional state passing**. Fixed by adding:
- `antlr4_lexer:next_token/1` — accepts maps, converts to records internally, converts back on return
- `antlr4_parser:init/1` — accepts maps or records, stores parser state in process dictionary
- Process-dictionary-based 0/1-arg wrapper functions in parser (`enter_rule/1`, `match/1`, `set_state/1`, etc.)

---

## Code Generation (Tool Side)

| Component | Location | Lines | Status |
|-----------|----------|-------|--------|
| ErlangTarget.java | `tool/src/.../codegen/target/ErlangTarget.java` | 146 | Minimal — file naming, reserved words, snake_case conversion |
| Erlang.stg | `tool/resources/.../codegen/Erlang/Erlang.stg` | 845 | Substantial — parser/lexer/listener/visitor templates all present |

The code generator produces valid `.erl` modules. Token constants are emitted as `-define` macros. The serialized ATN is embedded as an integer list. Rule functions, loop constructs, and decision blocks all generate syntactically correct Erlang.

**Known issue**: Generated parser does not export rule functions (e.g. `'r'/0`, `'r'/1`). These must be added manually to `-export([...])` for the parser to be callable from other modules.

---

## Runtime Library (`runtime/Erlang/`)

| Module | Lines | Status |
|--------|-------|--------|
| `antlr4_input_stream.erl` | 165 | **Complete** — lookahead, seeking, position tracking |
| `antlr4_token.erl` | 158 | **Complete** — token representation, all accessors |
| `antlr4_token_stream.erl` | 316 | **Complete** — buffered stream, channel filtering, lookahead |
| `antlr4_lexer.erl` | 351 | **Complete** — map/record bridge, token emission, mode stack, lexer action execution |
| `antlr4_lexer_atn_simulator.erl` | 412 | **Complete** — epsilon closure, action accumulation, state map resolution, input threading |
| `antlr4_parser.erl` | 650 | **Complete** — dual API (explicit + process-dict), precedence stack, recursion rule support |
| `antlr4_parser_atn_simulator.erl` | 270 | **Mostly complete** — adaptive prediction, DFA caching, closure computation |
| `antlr4_atn.erl` | 194 | **Complete** — ATN structure and state management |
| `antlr4_atn_deserializer.erl` | 363 | **Complete** — format v4 deserialization, state refresh for Erlang immutability |
| `antlr4_dfa.erl` | 143 | **Complete** — DFA state collection |
| `antlr4_dfa_state.erl` | 142 | **Complete** — individual DFA states with edges |
| `antlr4_parse_tree.erl` | 108 | **Complete** — terminal/error nodes, accept/visitor |
| `antlr4_parse_tree_walker.erl` | 87 | **Complete** — tree walking |
| `antlr4_parser_rule_context.erl` | 291 | **Complete** — parent/child relationships, start/stop tokens |
| `antlr4_prediction_context.erl` | 217 | **Complete** — prediction context caching |
| `antlr4_interval_set.erl` | 206 | **Complete** — set operations for token ranges |
| `antlr4_default_error_strategy.erl` | 237 | **Mostly complete** — single-token insertion/deletion recovery |
| `antlr4_error_listener.erl` | 54 | **Complete** — simple listener interface |
| `antlr4_runtime.hrl` | 283 | **Complete** — all record definitions, constants, type macros |

**Build system**: `rebar.config` with proper profiles, `antlr4.app.src` with OTP metadata. No external dependencies.

**Total runtime**: ~4,650 lines of Erlang.

---

## Test Infrastructure

| Component | Location | Status |
|-----------|----------|--------|
| `ErlangRunner.java` | `runtime-testsuite/.../erlang/` | 217 lines — compiles runtime + generated code, runs via `erl` |
| `ErlangRuntimeTests.java` | `runtime-testsuite/.../erlang/` | 17 lines — test entry point |
| Erlang test template (`.test.stg`) | — | **Missing** — cannot run ANTLR's standard runtime test suite |
| `test_erlang/Hello.g4` | `test_erlang/` | Simple example grammar with generated output |
| `test_erlang/e2e_test.erl` | `test_erlang/` | 3 passing tests: basic lexing, skip action, parser e2e |

---

## What Remains for Athena SQL

### Must Verify

1. **`-> channel(HIDDEN)` action**: The `skip` action is tested and works. The `channel` action uses the same code path (accumulated during epsilon closure, executed after match). Should work but needs testing with a grammar that uses `-> channel(HIDDEN)`.

2. **Precedence predicates with left-recursive rules**: The precedence stack is implemented (`enter_recursion_rule` pushes, `unroll_recursion_contexts` pops, `precpred` compares). Needs testing with an expression grammar like `expr: expr '*' expr | expr '+' expr | INT;`.

3. **Case-insensitive lexing**: Confirmed no runtime changes needed. Should verify by generating from `AthenaLexer.g4` and checking that keywords match case-insensitively.

4. **Generated parser exports**: The code generator template (`Erlang.stg`) needs to export rule functions. Currently only `new/1` is exported.

### Likely Issues with Larger Grammars

- **Parser ATN simulator**: The adaptive prediction (`antlr4_parser_atn_simulator.erl`) has not been tested with complex grammars. It may have similar stale-state-reference issues as the lexer ATN simulator had.
- **Error recovery**: `antlr4_default_error_strategy.erl` has basic single-token insertion/deletion but may not handle all error scenarios in complex grammars.
- **Performance**: Lists are used throughout (e.g., `lists:nth/2` for state lookup). For large ATNs this could be slow. Consider converting to maps or arrays if performance is an issue.

---

## What Is NOT Required for Athena SQL

These features are absent from the Athena grammar and can be deferred:

- Semantic predicates (`{...}?`) — not used
- Embedded actions (`{...}`) — not used
- Lexer modes (`mode`, `pushMode`, `popMode`) — not used (but runtime support exists)
- Alt labels (`# labelName`) — not used
- Rule `returns` / `locals` — not used
- Visitor tree traversal — not needed for parsing
- `-> type(...)` — not used (but runtime support exists)

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
TokenStream = antlr4_token_stream:new(LexerState),
athena_parser:new(TokenStream),
Tree = athena_parser:query(),
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
  e2e_test.erl                                          # Runtime integration tests
```
