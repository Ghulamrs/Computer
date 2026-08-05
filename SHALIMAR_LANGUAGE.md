# The Shalimar Language

A developer reference for **Shalimar**, the small numeric scripting language interpreted by
`Lexer.swift` / `Parser.swift` / `Interpreter.swift` in this project (Xcode project `Computer`,
target `Computer`). This document is the authoritative specification: when the interpreter and
this document disagree, that is a conformance bug in the interpreter, not a documentation error —
fix the code, or deliberately renegotiate and update this file, but don't let them silently drift.

This file both teaches the language to someone writing `.shm` programs, and documents the
interpreter's actual internals for whoever maintains `Lexer.swift`/`Parser.swift`/`Interpreter.swift`.
Sections marked **Implementation note** are for the latter audience and describe real, verified
behavior of the current code — including a couple of sharp edges worth knowing before you rely on
them.

---

## 1. Overview

- Every program is a set of function definitions; execution begins at `main()`.
- There is exactly one data type: 64-bit floating point (`Double`). No integers, no booleans, no
  arrays, no first-class strings (see [§6](#6-the-type-model-everything-is-a-double)).
- Control flow: `if`/`elseif`/`else`, `while`, `for ... to ... step ...`.
- Functions can return **multiple** values; the caller captures them with the multi-assign
  syntax `<a,b> : f(...)`.
- Output goes through `?` (print with newline) or `??` (print without newline). Each must be the
  first thing on its line, so there is at most one print command per line. See
  [§5.10](#510-print).
- Statements have no terminator (no `;`) — the parser instead uses targeted lookahead to know where
  one statement ends and the next begins. See
  [§8](#8-statement-boundaries--why-there-are-no-semicolons). Newlines are insignificant
  *everywhere except* the print rule above, which is the one place layout carries meaning.

### 1.1 A complete example

```
fun <> = main() {
   a : 1
   b : 2
   c : 1
   d : b^2 - 4*a*c        // discriminant, correct precedence: ^ then * then -
   if d < 0 {
      ? "No real roots"
   } else {
      d : sqrt(d)
      x1 : (-b - d) / (2*a)
      x2 : (-b + d) / (2*a)
      ? "Solution" x1 x2
   }
}
```

---

## 2. Lexical structure

Source is read left to right; whitespace (including newlines) is skipped and otherwise
insignificant. The lexer does, however, count newlines as it discards them and stamps each token
with the line it started on, because one rule needs it: a print command must be the first token on
its line ([§5.10](#510-print)). Nothing else in the language consults layout.

### 2.1 Comments

```
Comment ::= "//" { Character } (newline | EOF)
```

`//` may appear at the start of a line or after code on the same line; everything from `//` to the
end of that line is discarded.

**Implementation note:** there is **no block-comment (`/* ... */`) support in the lexer**, despite
`ComputeViewController.swift`'s `formatIndentation`/`braceBalance` helpers containing logic that
recognizes `/* ... */` for the purpose of re-indenting scanned/pasted source in the editor UI. That
logic is purely cosmetic (it decides how to indent text you paste into the editor) and is
independent of the actual language grammar. If you type `/* comment */` in a real program, the
lexer does **not** treat it as a comment — `/` lexes as `divide`, `*` as `multiply`, and the words
inside as identifiers, producing a parse error. Don't let the editor's tolerance of `/* */` fool you
into thinking the language supports it.

### 2.2 Identifiers

```
Identifier ::= (Letter | "_") { Letter | Digit | "_" }
Letter     ::= "a".."z" | "A".."Z"
Digit      ::= "0".."9"
```

Case-sensitive. Keywords (`if`, `else`, `elseif`, `while`, `for`, `to`, `step`, `fun`, `return`) are
recognized case-insensitively at the lexer level (`idStr.lowercased()` is switched on) and can never
be used as identifiers.

**`Letter` and `Digit` are ASCII only — this is deliberate.** The lexer enforces it with
`c.isASCII && c.isLetter`, not the bare `c.isLetter` you might expect. Swift's `isLetter` is true for
*every* Unicode letter, and letting those through is actively dangerous here rather than merely
permissive: Cyrillic `х` (U+0445) and Latin `x` (U+0078) are the same glyph on screen but different
identifiers, so `хn : y - 4` assigns to a variable that no `xn` in the program will ever read. That
is not hypothetical — it is exactly how a camera-scanned program failed, surfacing as a baffling
`Error: Undefined variable 'x'` pointing at a line where `x` was plainly defined. The same trap
exists for Greek `Α`/`Ο`/`Ρ` and for non-ASCII digits.

A non-ASCII character therefore produces a **lex error** naming its code point (see
[§10.1](#101-lex-errors-lexerlexerror-shown-as-lex-error-)), which is the only way to make the
difference visible. It is important that this is an error and not a silent skip: dropping the
character would quietly turn `хn` into the identifier `n` and simply relocate the bug.

The editor also normalizes confusable characters to ASCII on the way in (`asciiConfusables` /
`normalizedToASCII` in `ComputeViewController.swift`) for text that is typed, pasted, or scanned, so
in practice the lexer's check is the backstop rather than the first line of defence — but it is the
authoritative one, since a `.shm` file loaded from disk bypasses the editor entirely.

### 2.3 Numbers

```
Number ::= Digit { Digit } [ "." Digit { Digit } ]
```

All numbers are `Double`. `Digit` is ASCII `0`–`9` only, for the reasons given in
[§2.2](#22-identifiers) — a non-ASCII digit is a lex error, not a numeral. There is no
scientific/exponent notation (`1e10` is not supported — `e` is just a letter, so `1e10` lexes as the
number `1` immediately followed by the identifier `e10`, which will then fail to parse as a valid
continuation).

**Implementation note — malformed numbers are a lex error:** the lexer's *scanning* loop is looser
than the grammar above — it consumes any run of digits and `.` characters, so `1.2.3` arrives at the
conversion step as the single string `"1.2.3"`, which `Double` cannot parse. That now produces
`Lex error: line <n>: Malformed number '1.2.3'`
([§10.1](#101-lex-errors-lexerlexerror-shown-as-lex-error-)) and stops tokenizing, exactly like an
unrecognized character.

Note that a *trailing* dot is not malformed: `Double("1.")` is `1.0`, so `? 1.` prints `1.0` and is
accepted, even though the grammar above requires at least one digit after the `.`. The grammar is
the intent; `Double`'s parser is what actually decides, and it is the more permissive of the two.

Previously no token at all was emitted for a malformed run — it vanished from the token stream,
desyncing everything after it and surfacing as a confusing parse error pointing at the wrong place.

### 2.4 String literals

```
StringLiteral ::= '"' { Character } '"'
```

No escape sequences are supported. If the closing `"` is missing before end of input, the lexer
does **not** error — it just includes everything up to EOF as the string's content (intentional,
tolerant behavior; see the comment on that branch in `Lexer.swift`).

`Character` here is genuinely unconstrained: **the ASCII-only rule of [§2.2](#22-identifiers) applies
to identifiers and numbers, not to string contents.** `? "héllo wörld ✓"` lexes and prints fine,
because the string branch consumes raw characters up to the closing quote without consulting the
identifier predicates. That is the intended split — non-ASCII is a hazard when it is silently
*naming* something, and harmless when it is just text being printed.

### 2.5 Operators and punctuation

| Token(s) | Meaning |
|---|---|
| `+` `-` `*` `/` `%` `^` | arithmetic: add, subtract, multiply, divide, modulus, power |
| `:` | assignment (`x : expr`) / separator (`for i : 0 to 10`, multi-assign) |
| `=` | **overloaded**, see below |
| `!=` | not-equal comparison |
| `<` `>` | **overloaded**, see below |
| `&` `\|` | logical and / or (operate on truthiness, see [§6.2](#62-truthiness)) |
| `+:` `-:` | compound assign (`x +: 1` ⇔ `x : x + 1`) |
| `(` `)` | grouping / call argument list |
| `{` `}` | block delimiters |
| `,` | list separator |
| `?` | print with trailing newline (only when *not* immediately followed by a second `?`) |
| `??` | print with no trailing newline |
| `!` | **not a token on its own** — only the first half of `!=`; a bare `!` is a lex error |
| `"` | string literal delimiter |

**Implementation note — `TokenType.eof` is never emitted.** The enum has an `eof` case, but
`Lexer.tokenize()` never appends one: the token array contains only real tokens. End of input is
represented *virtually*, by `Parser.currentToken` manufacturing `Token(type: .eof)` once
`currentIndex` runs past the end. This is what lets `consume`/`match` report a clean
`Unexpected token 'eof'` at end of input instead of indexing out of bounds.

Two consequences, both easy to get wrong:

- `currentToken.type == .eof` and `currentIndex >= tokens.count` are the *same test*. Writing
  `while currentIndex < tokens.count && currentToken.type != .eof` is redundant — the second half
  can never decide anything. Test one or the other.
- Loops that detect end of input via `currentIndex < tokens.count` (`parseBlock` among them) depend
  on there being no terminator token. Making the lexer emit a real `.eof` would stop that guard
  firing and downgrade `Missing '}' to close block` into a generic unexpected-token error, so that
  change would have to be made across the parser in one pass, not file by file.

**`=` is overloaded three ways**, disambiguated purely by grammatical position:
1. Inside an expression, it's the **equality comparison** operator (`if d = 0 { ... }`).
2. At the very start of a statement, `identifier = expr` is accepted as a **fallback assignment
   operator** — it behaves exactly like `identifier : expr`, but the parser prints
   `Warning: '=' used for assignment. Use ':' instead.` to stdout (via Swift's `print`, **not**
   through the `Interpreter.output` callback, so this particular warning never reaches the app's
   on-screen console — only Xcode's console).
3. In a function definition header, `fun <outputs> = name(inputs) { ... }` — the separator between
   the output list and the function name.

**`<` / `>` are overloaded two ways**:
1. Inside an expression, standard less-than / greater-than comparison.
2. As angle brackets around a variable list: multi-assign's `<a,b> : f(...)` and a function
   definition's output list `<out1,out2>`.

The parser disambiguates `<` via lookahead (`looksLikeMultiAssignHeader`): at any point it could
start a new statement or continue an expression, it peeks ahead for the exact shape
`Identifier {"," Identifier} ">" ":"` before committing to "this is a multi-assign header, not a
less-than". `>` itself is never ambiguous — by the time the parser is scanning for it, it's already
inside a bracket-list context, never general expression parsing.

---

## 3. Grammar (EBNF)

```
Program       ::= { Statement }

Statement     ::= Assignment
                | CompoundAssign
                | MultiAssign
                | ReturnStmt
                | FunctionDef
                | FunctionCall
                | IfStmt
                | WhileStmt
                | ForStmt
                | PrintStmt

Assignment    ::= Identifier ":" Expression
                | Identifier "=" Expression   (* fallback, warning *)

CompoundAssign ::= Identifier "+:" Expression
                 | Identifier "-:" Expression

MultiAssign   ::= "<" Identifier { "," Identifier } ">" ":" FunctionCall

ReturnStmt    ::= "return" { Expression }   (* the parser allows zero expressions too *)

FunctionDef   ::= "fun" OutputList "=" Identifier "(" InputList ")" Block
OutputList    ::= "<" [ Identifier { "," Identifier } ] ">"
InputList     ::= [ Identifier { "," Identifier } ]

FunctionCall  ::= Identifier "(" [ Expression { "," Expression } ] ")"

IfStmt        ::= "if" Expression Block
                  { "elseif" Expression Block }
                  [ "else" Block ]

WhileStmt     ::= "while" Expression Block

ForStmt       ::= "for" Identifier ":" Expression "to" Expression [ "step" Expression ] Block

Block         ::= "{" { Statement } "}"

PrintStmt     ::= "?" PrintItems              (* must be first token on its line *)
                | "??" PrintItems             (* must be first token on its line *)
PrintItems    ::= Expression { Expression }

Expression    ::= OrExpr
OrExpr        ::= AndExpr { "|" AndExpr }
AndExpr       ::= CompareExpr { "&" CompareExpr }
CompareExpr   ::= AddExpr { ("=" | "!=" | "<" | ">") AddExpr }
AddExpr       ::= MulExpr { ("+" | "-") MulExpr }
MulExpr       ::= PowExpr { ("*" | "/" | "%") PowExpr }
PowExpr       ::= Term [ "^" PowExpr ]
Term          ::= Number | StringLiteral | Identifier | FunctionCall | "-" Term | "(" Expression ")"

Identifier    ::= (Letter | "_") { Letter | Digit | "_" }
Number        ::= Digit { Digit } [ "." Digit { Digit } ]
StringLiteral ::= '"' { Character } '"'
Comment       ::= "//" { Character } (newline | EOF)
```

---

## 4. Operator precedence

Loosest-binding to tightest-binding:

| Tier | Operators | Associativity |
|---|---|---|
| 1 (loosest) | `\|` | left |
| 2 | `&` | left |
| 3 | `=` `!=` `<` `>` | left |
| 4 | `+` `-` | left |
| 5 | `*` `/` `%` | left |
| 6 | `^` | **right** |
| 7 (tightest) | unary `-`, literals, identifiers, calls, `(...)` | — |

`(...)` grouping overrides precedence anywhere, exactly as you'd expect: `(2*a)`, `(-b-d)/(2*a)`,
etc.

`^` is right-associative: `2^3^2` is `2^(3^2) = 512`, not `(2^3)^2 = 64`.

### 4.1 Unary minus vs. `^` — a real gotcha

Unary minus (`parseTerm`'s `.minus` case) recurses into `parseTerm` for its operand and folds the
negation in immediately, returning the negated result as a single `Term` — *before* the caller
(`parsePower`) gets a chance to see a following `^`. The practical effect: **when a negated
expression is the base (left operand) of `^`, the negation applies before exponentiation** —

```
-2^2   evaluates as (-2)^2  =  4      (not -4, unlike Python's -2**2 == -4)
-a^2   evaluates as (-a)^2
```

On the exponent (right-hand) side it behaves the way you'd expect from ordinary math notation,
since `parsePower` recurses right-associatively there:

```
2^-2   evaluates as 2^(-2)  =  0.25
```

If you want `-(a^2)` specifically, write it with explicit parentheses: `-(a^2)`.

---

## 5. Statements

### 5.1 Assignment

`x : expr` evaluates `expr` and stores the result in `x`. `x = expr` does the same but is a
"fallback" spelling that emits a console warning (see [§2.5](#25-operators-and-punctuation)) —
always prefer `:`.

### 5.2 Compound assignment

`x +: expr` ⇔ `x : x + expr`; `x -: expr` ⇔ `x : x - expr`. `x` must already exist (it's read
before being reassigned) — using `+:`/`-:` on an undefined variable throws
`Error: Undefined variable 'x'`.

### 5.3 Multi-assign — the way to consume more than one return value

```
<a, b> : someFunction(args)
```

Calls `someFunction`, and assigns its returned values positionally to `a`, `b`, ... (extra returned
values beyond the variable list are silently discarded; extra variables beyond the returned values
keep their previous value — untouched, not zeroed — since the loop is `for (i, v) in
vals.enumerated() where i < multiAssign.variables.count`).

This is required whenever you want more than one of a function's return values. For just the
first (or only) return value, plain assignment works too — see [§7](#7-user-defined-function-results-and-multi-value-returns).

**The one arity check that does exist**: if the number of values actually returned doesn't match
the number of variables listed, this prints `Warning: '<name>' returned <n>, expected <m>` (via
`output`, so it reaches the on-screen console) — but the assignment still proceeds exactly as
described above (truncated/partial). This is a warning, not an error: nothing else about the
language's permissive return/receive behavior changes because of it. It's also the only place a
**builtin** call's result can be multi-assigned at all — `<s> : sqrt(16)` treats the builtin's
single value as a one-element list for this purpose (`<s,t> : sqrt(16)` warns `returned 1,
expected 2` and only `s` gets set). See [§7.2](#72-return--multi-assign-arity-is-almost-entirely-unchecked)
for the full picture of what is and isn't checked.

### 5.4 Return

```
return expr1 expr2 ...
```

A function can return zero or more space-separated values. `executeBlock` stops running the
current block the moment it hits an explicit `return` (including one nested inside its own
`if`/`while`/`for`, which propagates the return out through the wrapping block) — see
[§7](#7-user-defined-function-results-and-multi-value-returns) for exactly how that propagation is
scoped so a bare function-call statement elsewhere in the same block doesn't trigger it.

If a function falls off the end of its body without hitting `return`, its result is built from
whatever its declared **output variables** hold in local scope at that point (`0.0` for any that
were never assigned) — see [§5.5](#55-function-definitions).

### 5.5 Function definitions

```
fun <out1, out2> = name(in1, in2) {
    ...
}
```

- **The output list `<...>` does not control how many values the function actually returns —
  only what happens if the body never hits an explicit `return`.** Two independent rules:
  1. If the body executes `return expr1 expr2 ...`, the caller gets exactly that many values,
     regardless of what (if anything) is declared in `<...>`. Even `fun <> = f() { return 1 2 3 }`
     is legal and returns three values.
  2. Only if the body falls off the end *without* hitting `return` does the declared list matter:
     the function returns the current values of those named local variables, in order — zero
     values for `<>`, one for `<x>`, two or more for `<a,b,...>`.

  So `<>` is used both for functions that return nothing meaningful (`main()`) *and* for functions
  that always return via explicit `return` (where the empty list is just decorative, since `return`
  overrides it either way) — it is **not** specifically for "more than one output"; if anything the
  opposite association would be closer, since `<>` literally declares *zero* named outputs.
- Each call gets a **fresh, empty local scope** — there are no closures and no access to the
  caller's variables. (There *is* a `globalSymbols` dictionary in `Interpreter` that variable lookups
  fall back to, but nothing in the interpreter ever writes to it — it is permanently empty in the
  current implementation. Don't rely on it for cross-function shared state; it doesn't currently do
  anything.)
- `main()` must exist, take no inputs, and is the program's entry point — `runProgram` calls it
  with `args: []`. If `main` declares any inputs, that call will immediately throw
  `wrongArgCount`.
- **Duplicate definitions are a hard error.** `runProgram` collects every top-level `FunctionDefNode`
  into a `[String: FunctionDefNode]` keyed by name; the moment it sees a second definition for a
  name already seen (including a second `main`), it throws
  `Runtime error: Function '<name>' already defined` and nothing runs. This is checked once, up
  front, before `main` executes.
- **A defined-but-never-called function is only a warning, not an error.** Before running `main`,
  the evaluator walks the *entire* program's AST (including inside every other function body) to
  collect every function name that's actually called anywhere, and prints
  `Warning: function '<name>' is defined but never called` (once per such function, sorted by name,
  `main` itself excluded from the check) via the normal `output` callback — so, unlike the `=`
  fallback warning, this one *does* reach the app's on-screen console.

### 5.6 Function calls

```
name(expr1, expr2, ...)
```

Resolution order: **built-ins are checked first**, then user-defined functions
(`builtins[name]` before `userFunctions[name]`) — so you cannot shadow a built-in name like `sqrt`
with your own function of the same name; the built-in always wins.

Built-in functions reject string-literal arguments outright (`Error: Function '<f>' argument <n>
must be a number, got '"..."'`) — they only ever operate on numbers. The string-literal check runs
*before* the argument-count check below, so `pow("a")` reports the bad argument type at position 1
rather than the missing second argument.

**Under-supply is an error; over-supply is a warning — for built-ins and user functions alike.**
`executeFunction` binds a user function's *declared* input list positionally and throws
`wrongArgCount` the moment it runs out of supplied values. Built-ins are checked the same way
against the arity recorded alongside each one (`Builtin.arity` in `Interpreter.swift`):
`sqrt()` throws `Error: Function 'sqrt' expects 1 arguments, got 0`, `pow(2)` throws
`expects 2 arguments, got 1`.

Surplus arguments are the permissive direction in both cases: `f(1, 2)` against `fun <r> = f(a)`
binds `a : 1`, evaluates and discards the `2`, and the call still runs — as does `sqrt(16, 99)`,
which returns `4`. Either prints `Warning: '<name>' extra args provided - ignoring` through
`output` first, so the dropped argument is visible on the on-screen console rather than swallowed.
The warning fires once per offending *call*, so a call in a loop warns on every iteration.

The asymmetry is deliberate: too few arguments leaves a parameter genuinely unbound and cannot
proceed, whereas too many is recoverable and rejecting it would break programs that already run.

**Implementation note:** each built-in's arity is stored next to its closure rather than derived,
because the closures index `args[0]`/`args[1]` directly. Under-supply used to reach that indexing
and trap on an array bound — and a Swift bounds violation is not a catchable `Error`, so it bypassed
`runProgram`'s `do`/`catch` entirely and killed the app with nothing printed. Keeping arity in the
same literal as the closure is what stops the check and the indexing drifting apart; a new built-in
that reads `args[2]` must declare `arity: 3` in the same breath.

Argument passing is strictly **by value**: arguments are reduced to `Double`s before the call and
copied into the callee's fresh local scope, so `f(x)` can never modify the caller's `x`.

### 5.6.1 Recursion depth limits

Recursion is supported, but bounded. Two limits apply, and the first one reached throws:

| Limit | Value | Error |
|---|---|---|
| Per function | `256 / (declared inputs + 1)` | `Runtime error: Recursion too deep in '<name>' (limit <n>)` |
| Whole program | 1024 frames total | `Runtime error: Call stack too deep (limit 1024)` |

So a function declaring no inputs may nest 256 deep, one input 128, two inputs 85, three 64. The
cap scales down with arity on the reasoning that a wider function's frame carries more bound locals.
Integer division, floored at 1.

**These count stack depth, not calls made.** A loop calling the same function 5,000 times in
sequence is unaffected — each call returns, and decrements, before the next begins. Only frames
still on the stack count. The counter is decremented on the throwing path as well as the normal
one, so a caught-and-reported failure deep in a call chain doesn't leave the budget permanently
consumed for later calls.

The **whole-program backstop exists because the per-function limit cannot see mutual recursion**:
in a cycle `a → b → c → a`, no single function ever approaches its own cap while the frames
accumulate regardless. Measured before the backstop was added, 40 zero-input functions in a cycle
(up to 10,240 frames) still overflowed the native stack. 1024 sits deliberately between the two —
4× the largest per-function limit, so ordinary nesting never reaches it, and comfortably under the
~2,500 frames measured as survivable in practice.

**Why a limit at all:** exceeding the native stack is a `SIGSEGV`, not a Swift error. Like a trap
([§10.3](#103-runtime-errors-evalerror-shown-as-error---runtime-error-)) it cannot be caught, so
`fun <r> = d(n) { return d(n+1) }` used to kill the app outright with a blank console. Counting
frames in the interpreter is what converts that into a reportable `EvalError`.

**These caps are lower than the stack can actually take** — deliberately, to fail early and
legibly rather than near the real ceiling. The practical cost is that a genuinely deep recursive
program is rejected: `fact(150)` with its single input exceeds the 128 limit even though the stack
would handle it. Rewrite such cases as a loop, or raise the `256` numerator and the
`totalDepthLimit` constant in `Interpreter.swift` — they are one-line changes and the only two
places the policy lives.

### 5.7 `if` / `elseif` / `else`

Standard: the first branch (`if` or any `elseif`) whose condition is non-zero runs; if none match
and an `else` is present, it runs. See [§6.2](#62-truthiness) for what "non-zero" means here.

### 5.8 `while`

Runs `body` while `condition` is non-zero.

### 5.9 `for`

```
for i : start to end step increment { ... }
```

`step` is optional and defaults to `1`. Unlike everything else in the language, the loop bounds are
**truncated toward zero to `Int`** once, before the loop starts — the loop variable itself is a
whole-number `Double` counting up/down by `Int(step)` each iteration. A step of `0` throws
`Runtime error: Step value cannot be zero`. A positive step counts up while `i <= end`; a negative
step counts down while `i >= end`.

A bound that no `Int` can represent — `nan`, `±inf`, or a magnitude past `Int.max` — throws
`Runtime error: Loop <start|end|step> out of range: <value>`. This matters because such bounds
arrive from ordinary arithmetic rather than exotic input: `for i : 1 to sqrt(0-1)` (`nan`),
`to 1/0` (`inf`), and `to pow(10,400)` (overflows to `inf`) are all reachable in a page of normal
code. The `nan` step case is reported as out of range rather than as a zero step, since it never
reaches the zero check.

**Implementation note:** the conversion is `Int(exactly: value.rounded(.towardZero))`, not a bare
`Int(value)`. The bare form *traps* on those three cases, and a Swift trap is not a catchable
`Error` — it bypasses `runProgram`'s `do`/`catch` and takes the app down with an empty console,
the same failure mode the built-in arity gap had ([§5.6](#56-function-calls)). `Int(exactly:)`
returns `nil` for exactly the untranslatable values (including the `Double(Int.max)` edge, which is
really `Int.max + 1`) while leaving truncation of ordinary values unchanged.

### 5.10 Print

```
? expr1 expr2 ...      // with trailing newline
?? expr1 expr2 ...     // no trailing newline
```

**A print command must be the first token on its line.** Indentation doesn't count — the lexer has
already dropped it — so an indented `? x` inside a block is fine. What is rejected is a command with
any other token before it on the same line:

```
fun <> = main() {
  x : 1
  ? x                  // fine, and indented
  ?? x                 // fine, its own line
}

fun <> = main() { x : 1 ? x }     // Parse error: '?' must be the first thing on its line
? x ?? y                          // Parse error: '??' must be the first thing on its line
? "hello" ?? x                    // same - the second command is mid-line
```

One consequence is the rule's real purpose: **at most one print command per line**, since a second
one necessarily has the first command's items before it. Both errors are raised the same way; there
is no separate "two commands" diagnostic.

Each item is printed followed by a single space (`"\(v) "` for numbers, `"<literal> "` for string
literals), then the newline (or not) is appended once at the end. Note this means `?` always leaves
a trailing space before the newline, and consecutive `??` prints run together with no separator
between them beyond each item's own trailing space.

**Interaction with camera scanning.** Line breaks now carry meaning, so the scanner has to
reproduce them faithfully. Vision returns text regions with bounding boxes — it does not promise one
region per printed line, in either direction — so `ScanLayout.lines(from:)` reconstructs the lines
from geometry rather than trusting the order or count of observations:

- **Splits are repaired.** A wide gap in a printed line (`x : 1        ? x`) can come back as two
  separate regions. Regions whose vertical centres are within half a line height are grouped into
  one line and ordered left to right. This is the case that matters most: emitting them as two lines
  would turn a program the scanner should *reject* into one that quietly runs, with nothing on
  screen to say the scan changed its meaning.
- **Merges are reported, not repaired.** Two printed lines read as a single region cannot be undone
  by grouping, and splitting on an interior `?` is not an option — `? x ? y` typed deliberately on
  one line has to stay the error this section makes it. Instead
  `ScanLayout.linesWithLateCommand(in:)` finds lines whose `?`/`??` isn't first (ignoring string
  contents and `//` comments) and the post-scan alert names the first one, while the user is already
  being asked to check the text. Running it anyway gives the ordinary parse error with its line.

`ScanLayout.swift` has no UIKit or Vision dependency for the same reason the language core doesn't:
so it can be tested from the command line. See `Tests/scanlayout/main.swift`.

**Implementation note — why this needs `Token.line`.** Newlines are whitespace to the lexer, so
`? x ?? y` and the same two commands on two lines produce *identical* token streams: `??` cannot
begin a print item, so it ends the first item list and starts a second statement either way. Nothing
in the token sequence distinguishes them. Enforcing the rule therefore required tokens to remember
their source line — `Token.line`, set in `Lexer` and read only by `Parser.startsLine(at:)`. It is
the sole piece of source layout the language preserves.

Only **literal** string arguments are printed as text; anything else (numbers, variables,
expressions, function calls) is evaluated and printed via Swift's default `Double` string
interpolation — so integers print with a trailing `.0` (`9.0`, not `9`).

**Implementation note — where the item list stops.** `parsePrint` keeps consuming items while the
next token could begin a term (`startsTerm`) and doesn't look like the start of a new statement
(`looksLikeNewStatement`, see [§8](#8-statement-boundaries--why-there-are-no-semicolons)). That makes
`startsTerm` load-bearing rather than a convenience: a token missing from it doesn't produce an
error, it silently ends the list. When it accepted only numbers, strings and identifiers, `? -2^2`
and `? (1+2)` collected *zero* items and printed a blank line — no diagnostic at all. It now also
accepts `-` and `(`. If you extend the expression grammar with a new prefix token, add it here too,
or printing it will quietly produce nothing.

---

## 6. The type model: everything is a `Double`

There is exactly one runtime value type. `NumberNode`/`VariableNode`/arithmetic all operate on
`Double`. `StringNode` exists in the AST but **is not a general expression value** — the evaluator's
generic `evaluate()` returns `.normal(0.0)` for any `StringNode` it encounters outside the two
places that special-case it (print items, and the "reject as a builtin argument" check). Concretely:

```
x : "hello"     // legal to parse; x becomes 0.0, not the string "hello"
? "hello"       // prints the literal text "hello " (this is the only place strings are "real")
sqrt("4")       // Error: Function 'sqrt' argument 1 must be a number, got '"4"'
```

There is no boolean type, no arrays, no records/structs, no closures.

### 6.1 Numbers

All arithmetic is `Double`. `%` is `truncatingRemainder(dividingBy:)` (C-style remainder, sign
follows the dividend, not Python's always-positive modulo).

### 6.2 Truthiness

`if`, `while`, and `&`/`|` all treat any value `!= 0` as true, `== 0` as false. Comparison and
logical operators *produce* `1.0` for true and `0.0` for false, so they compose naturally:
`a & b`, `x = 0`, etc.

---

## 7. User-defined function results and multi-value returns

A user-defined function call (`FunctionCallNode` resolving through `userFunctions`, not
`builtins`) always evaluates internally to `EvalControl.returnValues([...])`, even when it returns
exactly one value — the same representation `<a,b> : f(...)` needs to capture multiple values.
Every place that consumes an evaluated sub-expression as a plain number (assignment,
compound-assign, binary operators, function-call arguments, `if`/`while` conditions, `for` bounds,
print items, `return`'s own expressions) reduces either form to a single `Double` via a shared
`numericValue(_:)` helper, which takes `.returnValues`'s *first* value (`0.0` if it returned
nothing). So a single-value user function behaves exactly like a built-in wherever you use it:

```
fun <r> = square(x) { return x*x }

fun <> = main() {
    y : square(5)        // y becomes 25 — plain assignment takes the first return value
    ? 1 + square(3)      // works inline too — prints "10.0 " (1 + 9)
    square(4)            // a bare call statement just runs it and discards the result
}
```

**Multi-assign is still the only way to capture more than one return value** — plain assignment
only ever sees the first:

```
fun <m, i> = prime(n) { ... return m i }

<d, k> : prime(9)   // captures both m and i
d : prime(9)        // d only gets the first return value (m); i's value is unreachable this way
```

### 7.1 Why a bare call statement doesn't end up returning from its caller

Because a user function call's `.returnValues` looks identical whether it came from an actual
`return` or from evaluating a call expression, `executeBlock` cannot use "did this statement's
evaluation produce `.returnValues`" as its return-detection signal on its own — that would make a
throwaway statement like `square(4)` (called only for a side effect, if it had one) incorrectly
terminate the function it's in, handing the callee's return values up as the caller's.

Instead, `executeBlock` only treats a statement's `.returnValues` result as ending the block when
the statement is one of the kinds that can structurally *contain or forward* an explicit `return` —
`ReturnNode` itself, or a control-flow wrapper (`IfElseChainNode`, `WhileNode`, `ForLoopNode`) whose
body might hold one:

```swift
switch stmt {
case is ReturnNode, is IfElseChainNode, is WhileNode, is ForLoopNode:
    if case .returnValues = result { return result }
default:
    break
}
```

Every other statement kind (`AssignmentNode`, `CompoundAssignNode`, `MultiAssignNode`, or a bare
`FunctionCallNode` statement) uses/discards whatever it gets back and always yields `.normal(...)`
as its own result, so it never accidentally triggers this propagation. A `return` nested inside an
`if`/`while`/`for` still correctly unwinds all the way out, because each wrapping control-flow node
is itself in the propagating set.

### 7.2 Return / multi-assign arity is almost entirely unchecked

A `return` statement's expression count and a multi-assign's variable count are independent, and
almost nothing about their relationship is validated. Verified case by case:

- **Bare `return` with zero expressions is legal** and returns an empty list. `parseReturn`'s loop
  simply breaks immediately if `}` (or something that looks like a new statement) follows `return`
  with nothing in between — there is no minimum-one-expression check in the actual parser, contrary
  to what the EBNF in [§3](#3-grammar-ebnf) implies (`"return" Expression { Expression }` reads as
  "at least one"; the code doesn't enforce that).
- **A function falling off the end with `<>` declared** also produces an empty return list, via the
  fallback path in [§5.5](#55-function-definitions) (`def.outputs.map { ... }` on an empty array).
- **Multi-assign against an empty return list**: every receiving variable is left completely
  untouched (not zeroed) — see [§5.3](#53-multi-assign--the-way-to-consume-more-than-one-return-value).
  If a receiver had no prior value, it stays genuinely undefined; referencing it later throws
  `Error: Undefined variable`.
- **Plain assignment against an empty return list**: `x : f()` sets `x` to `0.0` (the `numericValue`
  fallback), not an error.
- **Multi-assign with fewer returned values than variables** (`<a,b,c> : f()`, `f` returns 2): the
  same "untouched, not zeroed" rule applies to the shortfall variable(s).
- **Multi-assign with more returned values than variables** (`<p> : f()`, `f` returns 3): only the
  first `N` (however many variables were listed) are captured; the rest are silently discarded —
  there is no way to skip to "just the 2nd value" without also listing a placeholder for the 1st.
- **The one check that does exist**: a count mismatch between the multi-assign's variable list and
  the actual return count prints `Warning: '<name>' returned <n>, expected <m>` — see
  [§5.3](#53-multi-assign--the-way-to-consume-more-than-one-return-value). This is purely
  informational; it does not change truncation/zero-fill behavior, does not check *names* (only
  counts), and has no equivalent for plain assignment (`x : f()` never warns, regardless of how many
  values `f` actually returned).
- **This is asymmetric with call *input* arguments**: too few arguments to a user function throws
  `wrongArgCount` (a real, fatal `EvalError`, not a warning) — see [§5.6](#56-function-calls). Too
  *many* input arguments is silently tolerated (the binding loop only iterates over declared inputs,
  so extras are simply never read). So across the whole function-call mechanism, the only
  fatal-by-default arity check is "too few call arguments"; every other direction (too many call
  arguments, and both directions of return/receive-list mismatch) is either a non-fatal warning
  (return/receive count only) or fully silent.

None of this is enforced by variable *names* anywhere — see [§5.5](#55-function-definitions) for the
mismatched-declaration example (`fun <p,q> = weird(x) { return 10 20 30 x }` returns four values
under a two-name declaration with zero complaint).

---

## 8. Statement boundaries — why there are no semicolons

Statements are separated purely by grammar shape and targeted lookahead, never by punctuation.
Newlines don't separate them either — with one exception that is a *restriction* rather than a
separator: a print command must open its line ([§5.10](#510-print)), so a print statement can never
be the second thing on one. Everything below concerns where a statement ends, which remains a
question of shape alone. Two heuristics do the real work, both in `Parser.swift`:

- `looksLikeMultiAssignHeader(at:)` — distinguishes `<` starting a fresh `<a,b> : f(...)` statement
  from `<` as a less-than comparison operator, by peeking ahead for the exact shape
  `Identifier {"," Identifier} ">" ":"`.
- `looksLikeNewStatement(at:)` — used by `PrintStmt`'s item list and `ReturnStmt`'s expression list,
  both of which are *unseparated* sequences of expressions (`PrintItems ::= Expression {
  Expression}`). Without a way to know when to stop, `? x` followed on the next line by `x -: 1`
  would greedily consume that second `x` as one more thing to print, desyncing everything after it.
  The heuristic: stop consuming more items the moment the upcoming tokens look like the start of a
  new `Assignment`/`CompoundAssign`/`MultiAssign` (i.e., `identifier` followed by `:`/`=`/`+:`/`-:`,
  or a multi-assign header).

This is why print/return item lists work correctly with bare literals and variables between
statements, but you should not expect the parser to gracefully recover from genuinely ambiguous
input — when in doubt, put each statement on stricter footing (e.g. don't end a `return`/`print`
list with a bare identifier that's also about to be reassigned on the very next line in a way that
doesn't match the heuristic above).

**Gap confirmed by testing:** `looksLikeNewStatement` only recognizes an *assignment-shaped*
follow-on statement (`identifier` then `:`/`=`/`+:`/`-:`, or a multi-assign header) as the signal to
stop consuming print/return items — it does **not** recognize a bare function-call statement
(`identifier` then `(`). So a `?`/`return` item list immediately followed by a bare call statement
on the next line will greedily swallow that call as one more item to print/return, instead of
treating it as a separate statement:

```
? x
someFunction(1)      // gets absorbed as a second print item of the "? x" line above,
                      // not parsed as its own statement
```

If you need a bare call statement right after a `?`/`return` line, separate them with something the
heuristic *does* recognize as a new statement (e.g. an assignment in between), or simply reorder so
the bare call doesn't immediately follow an unterminated item list.

---

## 9. Built-in functions and constants

All built-ins operate on and return `Double`; none accept string-literal arguments. The argument
counts below are enforced: supplying fewer throws `wrongArgCount`, supplying more warns and drops
the surplus, exactly as for user functions ([§5.6](#56-function-calls)).

| Function | Signature | Notes |
|---|---|---|
| `abs(x)` | 1 arg | absolute value |
| `sqrt(x)` | 1 arg | square root; `NaN` for negative `x` (not an error) |
| `pow(x, y)` | 2 args | `x` raised to `y` (equivalent to `x^y`) |
| `log(x)` | 1 arg | natural log |
| `sin(x)` `cos(x)` `tan(x)` | 1 arg each | radians |
| `asin(x)` `acos(x)` `atan(x)` | 1 arg each | radians |
| `atan2(y, x)` | 2 args | |
| `max(x, y)` `min(x, y)` | 2 args each | |
| `round(x)` | 1 arg | round-half-away-from-zero |
| `ceil(x)` `floor(x)` | 1 arg each | |

| Constant | Value |
|---|---|
| `pi` | `Double.pi` |
| `e` | `M_E` |

Constants resolve through the same lookup as variables (`symbols[name] ?? globalSymbols[name] ??
constants[name]`), so a local variable named `pi` or `e` shadows the constant.

---

## 10. Diagnostics

**Every error names the line it happened on**, inserted between the prefix and the text:

```
Lex error: line 3: Unexpected character 'х' (U+0445)
Parse error: line 7: '?' must be the first thing on its line
Error: line 12: Undefined variable 'zz'
Runtime error: line 4: Loop end out of range: nan
```

The message bodies listed below are written without that prefix; each is preceded by
`<kind>: line <n>: ` in real output. The one exception is an error raised when no statement is
executing — `No main() function defined` — which has no line to name and prints without one rather
than claiming line 0. Where each kind gets its line from differs, and is worth knowing when a number
looks off:

| Kind | Line reported | Source |
|---|---|---|
| Lex | where the offending character is | `Lexer.tokenLine`, counted as newlines are discarded |
| Parse | the token the parser choked on | `currentToken.line` at the single point that records `parseError` |
| Runtime | the **statement** that was executing, not the expression | `Interpreter.currentLine`, updated in `evaluate` from any `StatementNode` |

Runtime granularity is deliberately per-statement: expression nodes carry no line, so an error
inside a long expression is reported against the statement containing it. Inside a called function
the callee's own lines take over, so a failure two calls deep names the line that actually failed,
not the call site.

### 10.1 Lex errors (`Lexer.lexError`, shown as `Lex error: line <n>: ...`)

- `Unexpected character '<c>' (U+XXXX)` — the character is not punctuation the language
  recognizes, not an ASCII digit, and not an ASCII identifier character. The code point is included
  because the usual cause is a homoglyph (`х` U+0445 for `x` U+0078), where the message would be
  unreadable without it. See [§2.2](#22-identifiers).
- `Malformed number '<run>'` — a run of digits and `.` characters that `Double` cannot
  parse, i.e. one with more than one `.` in it (`1.2.3`). A trailing dot is *not* malformed. See
  [§2.3](#23-numbers).
- `'!' is not a command. Use '??' to print inline, '!=' for not-equal.` — a `!` not
  followed by `=`. `!` was the inline-print command before `??` replaced it, so every program
  written against the older spelling lands here; the message names the replacement rather than
  reporting an anonymous unexpected character. See [§5.10](#510-print).

`tokenize()` stops at the first offending character and returns the tokens collected so far, so the
token stream is deliberately truncated. **Callers must check `lexer.lexError` before parsing** — a
parse error raised from a truncated stream points at the wrong place. `ComputeViewController` checks
it immediately after `tokenize()` and returns.

These three are the lexer's only error cases; everything else it accepts. The one remaining thing it
cannot make sense of but does not report is an unterminated string literal, which is deliberately
tolerated rather than dropped (see [§2.4](#24-string-literals)).

### 10.2 Parse errors (`ParseError`, shown as `Parse error: line <n>: ...`)

- `Unexpected token '<TokenType>'` — the parser hit a token it had no rule for at that position.
  (After a fix in this session, this prints the token's *type* (e.g. `lParen`), not a raw dump of
  the internal `Token` class instance — earlier this printed something like
  `Unexpected token: Computer.Token`, which was itself the bug being diagnosed.)
- `Invalid assignment operator '<tok>'. Use ':' instead.` — currently unused by any code path (no
  call site constructs this case), reserved for future stricter assignment-operator checking.
- `Missing '{' to start block` / `Missing '}' to close block`.
- `'<?|??>' must be the first thing on its line` — a print command with another token before it on
  the same line, which also covers a second print command on a line already carrying one. See
  [§5.10](#510-print).

Parsing stops at the first error (`parser.parseError`); nothing runs.

### 10.3 Runtime errors (`EvalError`, shown as `Error: line <n>: ...` / `Runtime error: line <n>: ...`)

- `Undefined variable '<v>'`
- `Unknown function '<f>'`
- `Function '<f>' expects <n> arguments, got <m>'` — too few arguments supplied, for both
  user functions and built-ins; see [§5.6](#56-function-calls).
- `Function '<f>' argument <n> must be a number, got '<literal>'` — built-ins rejecting a
  string-literal argument.
- `<message>` (shown with the `Runtime error` prefix) — catch-all (e.g. `No main() function defined`, `Function '<name>'
  already defined`, `Step value cannot be zero`, `Loop <start|end|step> out of range: <value>`,
  `Recursion too deep in '<name>' (limit <n>)`, `Call stack too deep (limit 1024)`).

`runProgram` catches everything and writes the description through the `output` callback, so the UI
always shows *something* rather than crashing the app on a bad program.

**The exceptions to watch for are failures that are not `Error`s at all** — they do not unwind,
cannot be caught, and so bypass this `do`/`catch` entirely, killing the app with a blank console
instead of a message. Two kinds, all known instances now fixed:

- **Traps**, from an operation Swift defines as a fatal error rather than a throw: an
  under-supplied built-in indexing `args[0]` ([§5.6](#56-function-calls)), and a `nan`/`inf`
  for-loop bound converted with `Int(...)` ([§5.9](#59-for)). Worth naming as a class because it
  is invisible in review — the trapping operations look like ordinary Swift. The three to watch
  when extending the interpreter are **array subscripting**, **`Int(someDouble)`**, and
  **force-unwrapping**; each needs a guard that throws an `EvalError`, since none will throw one
  on its own.
- **Native stack exhaustion** (`SIGSEGV`) from unbounded recursion, which no local guard can
  catch — it is bounded instead by counting frames, see
  [§5.6.1](#561-recursion-depth-limits).

The shared lesson: anything that can terminate the process rather than raise an `EvalError` has to
be prevented *before* it happens, because there is no layer above `runProgram` that can report it.

### 10.4 Non-fatal warnings (also via `output`, so they reach the on-screen console)

- `Warning: function '<name>' is defined but never called` — printed once per such function, before
  `main` runs; see [§5.5](#55-function-definitions).
- `Warning: '<name>' returned <n>, expected <m>` — a multi-assign's variable count didn't match the
  actual return count; execution still proceeds with the usual truncate/leave-untouched behavior.
  See [§5.3](#53-multi-assign--the-way-to-consume-more-than-one-return-value) and
  [§7.2](#72-return--multi-assign-arity-is-almost-entirely-unchecked).
- `Warning: '<name>' extra args provided - ignoring` — a call supplied more arguments than the
  function (user-defined or built-in) takes; the surplus is dropped and the call proceeds. Printed
  once per offending call, so a call inside a loop warns on each iteration. See
  [§5.6](#56-function-calls).

Kept deliberately terse (one line, no multi-clause sentences) since the console renders on a narrow
mobile width and wraps long messages across several lines.

Contrast with the `=`-fallback-assignment warning ([§2.5](#25-operators-and-punctuation)), which is
a bare Swift `print(...)` in `Parser.swift` and does **not** go through `output` — it never reaches
this on-screen console at all, only Xcode's.

---

## 11. Known limitations & maintainer notes

A running list of things that are real, verified behavior of the current interpreter and worth
knowing before you extend it — some are fine as documented quirks, some are worth fixing:

1. **A print/return item list swallows an immediately-following bare call statement** —
   `looksLikeNewStatement` doesn't recognize `identifier(` as the start of a new statement, only
   assignment shapes. See [§8](#8-statement-boundaries--why-there-are-no-semicolons).
2. ~~**Built-in functions don't check argument count.**~~ **Fixed**, along with a second instance of
   the same underlying hazard found while auditing for it:
   - Each built-in now carries its arity, and under-supply throws `wrongArgCount` like any other
     error — `sqrt()` reports `expects 1 arguments, got 0` instead of trapping on `args[0]`.
     See [§5.6](#56-function-calls).
   - `for` loop bounds convert via `Int(exactly:)`, so a `nan`/`inf`/out-of-range bound throws
     `Loop <role> out of range` instead of trapping on `Int(someDouble)`. Reachable from plain
     arithmetic: `for i : 1 to sqrt(0-1)`. See [§5.9](#59-for).

   Both were **traps, not throws** — uncatchable, so they bypassed `runProgram`'s `do`/`catch` and
   killed the app with an empty console rather than printing an error. See
   [§10.3](#103-runtime-errors-evalerror-shown-as-error---runtime-error-) for the general class and
   what to watch for when extending the interpreter.

   Audited and confirmed *not* affected: the 16 built-in closures themselves are total on `Double`
   input — `sqrt(0-1)`, `log(0)`, `asin(2)`, `1/0`, `5 % 0` all yield `nan`/`inf` rather than
   trapping, since Swift's floating-point arithmetic has no trapping cases here. There are no
   force-unwraps or other raw array subscripts in `Interpreter`/`Parser`/`Lexer`.

10. **Recursion is capped well below what the stack could take** — `256 / (inputs + 1)` per
    function and 1024 frames overall, so `fact(150)` is rejected despite being runnable. This is
    the deliberate cost of bounding it at all: unbounded recursion exhausts the native stack as a
    `SIGSEGV`, which is uncatchable and killed the app outright. Both numbers are one-line changes
    in `Interpreter.swift` if the ceiling proves too tight in practice. See
    [§5.6.1](#561-recursion-depth-limits).
3. **`globalSymbols` is dead code.** It's consulted on every variable/constant lookup but nothing
   in the interpreter ever writes to it — there is currently no actual mechanism for true global
   variables shared across function calls.
4. ~~**Malformed numeric literals are silently dropped**, not reported as a lex error.~~ **Fixed.**
   They now go through the same `lexError` channel an unrecognized character does, removing the
   asymmetry this item described — `1.2.3` reports `Lex error: Malformed number '1.2.3'` instead of
   vanishing from the token stream and desyncing everything after it. See [§2.3](#23-numbers) and
   [§10.1](#101-lex-errors-lexerlexerror-shown-as-lex-error-). The lexer now has exactly two error
   cases and no remaining silent-drop path.
5. **No scientific notation, no integer type, no arrays/collections, no closures.**
6. **The `=`-fallback-assignment warning bypasses the app's console.** It's a bare Swift `print(...)`
   call in `Parser.swift`, not routed through `Interpreter.output`, so it only ever appears in Xcode's
   debug console, never on-screen in the app — unlike the unused-function warning, which does reach
   the UI.
7. **The editor's OCR/paste re-indenting logic in `ComputeViewController.swift` assumes `/* */`
   block comments exist** (for indentation purposes only) even though the lexer doesn't recognize
   them as comments at all — see [§2.1](#21-comments). If block comments are ever added to the
   language, that's the other file that needs to be revisited too (though it will already "just
   work" cosmetically).
8. **Unary minus binds tighter than `^` on the base side** — `-2^2 == 4`, not the `-4` you'd get in
   Python/JS. See [§4.1](#41-unary-minus-vs---a-real-gotcha).
9. **Calls still accept too many arguments** — surplus arguments are evaluated and dropped rather
   than rejected, for built-ins as well as user functions. This is no longer *silent* (it warns, see
   [§5.6](#56-function-calls)), and is kept permissive on purpose so existing programs keep
   running; promoting it to a hard `wrongArgCount` is a one-line change in each of the two places
   that warn (`executeFunction` and the builtin branch of `evaluate`) if that is ever wanted.
11. ~~**`Token.line` exists for exactly one rule, and errors still have no line numbers.**~~
    **Fixed** — all three kinds of error now name their line ([§10](#10-diagnostics)). Two limits
    are deliberate and worth knowing:
    - Runtime lines are **per statement, not per expression**. Only `StatementNode` conformers carry
      a line, so an error inside a long expression names the statement containing it. Putting a line
      on every expression node would make the number more precise at the cost of threading it
      through every node type and construction site.
    - `Interpreter.currentLine` is a single running value, not a call stack. It names the innermost
      statement that was executing, which is the useful answer, but there is no traceback showing
      the chain of calls that got there.
12. **The `BinaryOpNode.Op` switch in `evaluate` is exhaustive on purpose** — it used to carry a
    `default: throw EvalError.runtime("Unsupported operator")` arm that the compiler flagged as
    unreachable (`default will never be executed`), since every case of the enum was already
    handled. It is gone, which means adding a new operator to `BinaryOpNode.Op` is now a *compile*
    error in `Interpreter.swift` rather than a runtime error nobody could reach. Don't reintroduce
    the `default` to silence that build failure — handle the new case.
13. **A scanned line that Vision merges with its neighbour can only be reported, not recovered.**
    `ScanLayout` repairs the opposite mistake (one printed line split into several regions) but a
    merge destroys the boundary before the app sees it. The post-scan alert names the first line
    whose print command isn't first; splitting it is the user's job. Automatic splitting is
    deliberately not attempted — it would silently rewrite a program whose one-line print command
    is a real error. See the scanning notes in [§5.10](#510-print).

---

## 12. Architecture map

| Stage | File | Responsibility |
|---|---|---|
| Lex | `Lexer.swift` | source `String` → `[Token]`, each stamped with its source line |
| Parse | `Parser.swift` | `[Token]` → `[ASTNode]` (one node per top-level statement), plus AST node type definitions; statement nodes keep the line they start on (`StatementNode`) |
| Evaluate | `Interpreter.swift` | walks the AST, maintains per-call local symbol tables, resolves built-ins vs. user functions, drives all program `output` |
| UI wiring | `ComputeViewController.swift` | owns the program/console `UITextView`s, invokes `Lexer` → `Parser` → `Interpreter` on Run, wires `Interpreter.output` to the on-screen console, plus save/load-to-Documents and OCR-scan-to-source features |
| Scan layout | `ScanLayout.swift` | OCR text regions → source lines: groups regions into lines by vertical overlap, orders and re-indents them, and flags lines whose print command isn't first ([§5.10](#510-print)). No UIKit/Vision dependency, so it is testable outside the app |
| Test harness | `Tests/harness/main.swift` | command-line driver over the three core files; mirrors `ComputeTapped`'s order (lex → check `lexError` → parse → check `parseError` → run) so the suite tests what the app actually does |
| Regression suite | `Tests/regression.sh` | ~115 language cases asserting the behavior described in this document, plus the scan-layout tests below; exits non-zero on failure |
| Scan-layout tests | `Tests/scanlayout/main.swift` | 16 cases over `ScanLayout` built from synthetic bounding boxes — ordering, split-line rejoining, indentation, and late-command detection. Compiled and run by `regression.sh` as a second binary, with failures folded into its counts |

### 12.1 Running the tests

The language core is pure Foundation with no UIKit dependency, so it compiles and runs outside the
app — no simulator and no Xcode test target required:

```
./Tests/regression.sh
```

Every case traces to a claim in this document. **When a case and this document disagree, the
document wins** and the interpreter is what gets fixed — same rule as the preamble.

A pre-commit hook in `.githooks/pre-commit` runs the suite against the *staged* tree (via
`git checkout-index` into a scratch directory, so an unstaged local fix can't mask a commit that is
broken on its own). Enable it once per clone:

```
git config core.hooksPath .githooks
```

It skips unless the commit touches `Lexer`/`Parser`/`Interpreter` or `Tests/`, and
`git commit --no-verify` overrides it.

`Interpreter.output: (String) -> Void` defaults to a plain `print(...)`, but the app always replaces
it with a closure that appends to the console `UITextView` before calling `runProgram`. Anything
written via `output` reaches the screen; anything written via a bare Swift `print(...)` elsewhere in
`Parser`/`Lexer`/`Interpreter` does not (see item 6 in [§11](#11-known-limitations--maintainer-notes)).
