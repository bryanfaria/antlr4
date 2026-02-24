# Erlang ANTLR4 Target — Status & Roadmap

## Goal

Generate a working Erlang lexer and parser from the Athena SQL grammar:
- `/grammars-v4/sql/athena/AthenaLexer.g4` (~171 tokens, 3 fragments, `caseInsensitive = true`, `-> channel(HIDDEN)`)
- `/grammars-v4/sql/athena/AthenaParser.g4` (~125 rules, 2 left-recursive rules, element labels, `tokenVocab = AthenaLexer`)

No semantic predicates, no embedded actions, no lexer modes, no alt labels, no returns/locals.

---

## Current Status

### What Works End-to-End

**Three grammars tested and passing:**

1. **Hello.g4** — Simple grammar (`r: 'hello' ID EOF; WS: [ \t\r\n]+ -> skip;`)
   - Lexer tokenizes correctly, `-> skip` action works
   - Parser matches token sequences
   - 3 e2e tests pass

2. **Expr.g4** — Expression grammar with `-> channel(HIDDEN)` (lexer-only test)
   - WS tokens emitted on HIDDEN channel (channel=1), not skipped
   - Token stream correctly filters hidden tokens for parser lookahead
   - 2 channel tests pass

3. **Calc.g4** — Left-recursive expression grammar with operator precedence
   - `expr: expr ('*'|'/') expr | expr ('+'|'-') expr | INT | '(' expr ')'`
   - Precedence predicates work: `1+2*3` parses with `*` binding tighter than `+`
   - Parentheses work: `(1+2)*3` overrides natural precedence
   - 4 precedence tests pass

**Total: 9 passing tests across 3 grammars.**

### All Critical Bugs Fixed

#### Bug 1: Lexer Actions Not Executed — FIXED

The ATN simulator now properly accumulates lexer actions during epsilon closure and returns them alongside the token type. The lexer executes them after matching (`channel`, `skip`, `type`, `mode`, `pushMode`, `popMode`, `more`).

**Root causes found and fixed:**
- ATN deserializer was wrong for format v4 (reading non-existent UUID, missing LOOP_END/BlockStartState extra ints, wrong rules format)
- ACTION transitions stored `Arg1` (ruleIndex) as action_index instead of `Arg2` (actionIndex)
- Epsilon transitions (ACTION, RULE, PREDICATE, PRECEDENCE) were not marked as epsilon
- Epsilon closure was missing — epsilon transitions were treated as character-matching transitions
- Erlang immutability caused stale state references: transition targets were copies from before transitions were added. Fixed with `StateMap` lookup in both lexer and parser ATN simulators
- The ATN simulator consumed input but never returned the updated input stream. Fixed by returning `{TokenType, LexerActions, NewInput}`
- Accept state capture happened before consume (should be after, matching Java's order)

#### Bug 2: Precedence Predicates — FIXED & TESTED

`precpred/1` compares `Precedence >= Top` using a precedence stack. `enter_recursion_rule` pushes, `unroll_recursion_contexts` pops. **Verified working** with a left-recursive expression grammar (Calc.g4).

#### Bug 3: Case-Insensitive Lexing — No Runtime Changes Needed

Confirmed: case-insensitive support is handled entirely at the ATN construction level by `LexerATNFactory`. The serialized ATN already contains both-case ranges. No target-specific or runtime code needed.

#### Bug 4: API Mismatch Between Generated Code and Runtime — FIXED

The generated code uses **maps + process dictionary** while the runtime uses **records + functional state passing**. Fixed by adding:
- `antlr4_lexer:next_token/1` — accepts maps, converts to records internally, converts back on return
- `antlr4_parser:init/1` — accepts maps or records, stores parser state in process dictionary
- Complete set of process-dictionary-based wrapper functions in parser (`enter_rule/1`, `match/1`, `set_state/1`, `la/1`, `lt/1`, `adaptive_predict/1`, `sync/0`, `push_new_recursion_context/1`, etc.)

#### Bug 5: Parser ATN Simulator Stale State References — FIXED

Same pattern as the lexer: transition targets were stale copies. Fixed by adding `build_state_map`/`resolve_state` to `antlr4_parser_atn_simulator.erl`. Also added proper PRECEDENCE transition handling in the parser's epsilon closure.

#### Bug 6: Code Generator Template Issues — FIXED

- **Export placement**: Rule function exports are now emitted in the module header before function definitions
- **Left-recursive function clash**: `LeftRecursiveRuleFunction` now uses guard-based clauses (`when is_map(State0); is_tuple(State0)`) to distinguish entry point from recursive call
- **Loop constructs**: `StarBlock`, `PlusBlock`, `LL1StarBlockSingleAlt`, `LL1PlusBlockSingleAlt` templates now use Erlang named funs instead of defining separate named functions (which can't appear inside try-catch blocks)
- **Sempred arity mismatch**: `RuleSempredFunction` now generates 2-arg functions matching the parser's call convention

---

## Code Generation (Tool Side)

| Component | Location | Lines | Status |
|-----------|----------|-------|--------|
| ErlangTarget.java | `tool/src/.../codegen/target/ErlangTarget.java` | 146 | Minimal — file naming, reserved words, snake_case conversion |
| Erlang.stg | `tool/resources/.../codegen/Erlang/Erlang.stg` | ~850 | Substantial — parser/lexer/listener/visitor templates all present |

The code generator produces valid `.erl` modules. Token constants are emitted as `-define` macros. The serialized ATN is embedded as an integer list. Rule functions, loop constructs, and decision blocks all generate syntactically correct Erlang.

Rule function exports are automatically emitted in the module header. Left-recursive rules use guard-based function clauses.

---

## Runtime Library (`runtime/Erlang/`)

| Module | Lines | Status |
|--------|-------|--------|
| `antlr4_input_stream.erl` | 165 | **Complete** — lookahead, seeking, position tracking |
| `antlr4_token.erl` | 158 | **Complete** — token representation, all accessors |
| `antlr4_token_stream.erl` | 316 | **Complete** — buffered stream, channel filtering, lookahead |
| `antlr4_lexer.erl` | 351 | **Complete** — map/record bridge, token emission, mode stack, lexer action execution |
| `antlr4_lexer_atn_simulator.erl` | 413 | **Complete** — epsilon closure, action accumulation, state map resolution, input threading |
| `antlr4_parser.erl` | ~750 | **Complete** — dual API (explicit + process-dict), precedence stack, recursion rule support, all wrapper functions |
| `antlr4_parser_atn_simulator.erl` | ~280 | **Complete** — adaptive prediction, state map resolution, precedence handling in closure |
| `antlr4_atn.erl` | 194 | **Complete** — ATN structure and state management |
| `antlr4_atn_deserializer.erl` | ~365 | **Complete** — format v4 deserialization, stores precedence/rule/predicate data on transitions |
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

**Total runtime**: ~4,900 lines of Erlang.

---

## Test Infrastructure

| Component | Location | Status |
|-----------|----------|--------|
| `ErlangRunner.java` | `runtime-testsuite/.../erlang/` | 217 lines — compiles runtime + generated code, runs via `erl` |
| `ErlangRuntimeTests.java` | `runtime-testsuite/.../erlang/` | 17 lines — test entry point |
| Erlang test template (`.test.stg`) | — | **Missing** — cannot run ANTLR's standard runtime test suite |
| `test_erlang/Hello.g4` | `test_erlang/` | Simple grammar — 3 tests (basic lexing, skip action, parser) |
| `test_erlang/Expr.g4` | `test_erlang/` | Expression grammar — 2 tests (channel(HIDDEN), token stream filtering) |
| `test_erlang/Calc.g4` | `test_erlang/` | Left-recursive grammar — 4 tests (int, addition, precedence, parentheses) |
| `test_erlang/e2e_test.erl` | `test_erlang/` | Hello.g4 test runner |
| `test_erlang/channel_test.erl` | `test_erlang/` | Expr.g4 channel test runner |
| `test_erlang/precedence_test.erl` | `test_erlang/` | Calc.g4 precedence test runner |

---

## What Remains for Athena SQL

### Likely Ready (Tested Components)

- `-> channel(HIDDEN)` — verified working with Expr.g4
- Precedence predicates with left-recursive rules — verified working with Calc.g4
- Case-insensitive lexing — handled at ATN construction level, no runtime changes needed
- Token stream channel filtering — verified working

### Potential Issues with Larger Grammars

- **Error recovery**: `antlr4_default_error_strategy.erl` has basic single-token insertion/deletion but may not handle all error scenarios in complex grammars.
- **Performance**: Lists are used throughout (e.g., `lists:nth/2` for state lookup). For large ATNs this could be slow. Consider converting to maps or arrays if performance is an issue.
- **Alt labels**: Grammar rules with `# labelName` generate extra context setup code that may produce empty ops and extra commas. The Athena grammar reportedly has no alt labels.

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
  Hello.g4, Calc.g4, Expr.g4                            # Test grammars
  e2e_test.erl, channel_test.erl, precedence_test.erl   # Test runners
  hello_*.erl, calc_*.erl, expr_*.erl                   # Generated output
```
