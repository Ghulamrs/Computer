#!/usr/bin/env bash
#
# Regression suite for the Shalimar language core.
#
# Compiles TokenKind/Node/Parse/Check/Interpreter plus Tests/harness/main.swift into a
# command-line binary and runs every program below through it, asserting that
# the output contains an expected fragment. The core is pure Foundation, so this
# needs no simulator and no Xcode test target - it runs in a couple of seconds.
#
#   ./Tests/regression.sh
#
# Exits non-zero if any case fails, so it drops straight into a git hook or CI.
#
# Expectations are substring matches, which keeps them readable and tolerant of
# the trailing space the print statements emit after each item.
#
# ---------------------------------------------------------------------------------
# SPEC STATUS: SHALIMAR_LANGUAGE.md still describes the 2.x language - untyped
# parameters, named outputs in the <> list, "everything is a Double", strings that
# degrade to 0.0. 3.0 replaced all of that with int/real/char, a Checker stage, and
# arrays. Until that document is rewritten it cannot arbitrate, so this file is the
# working record of 3.0 behaviour. Where a case below encodes a deliberate 3.0
# change, the comment says which 2.x rule it replaced, so the eventual spec rewrite
# has something to work from.
# ---------------------------------------------------------------------------------
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Computer"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

swiftc -O "$SRC/TokenKind.swift" "$SRC/Node.swift" "$SRC/Parse.swift" \
          "$SRC/Check.swift" "$SRC/Interpreter.swift" \
          "$ROOT/Tests/harness/main.swift" -o "$BUILD/shalimar" || {
    echo "FATAL: harness failed to compile"
    exit 1
}

pass=0
fail=0
failures=()

# t <name> <expected substring> <source>
t() {
    printf '%s' "$3" > "$BUILD/case.shm"
    local out
    # alarm guards against a genuine infinite loop in the interpreter turning a
    # failing case into a hung suite.
    out=$(perl -e 'alarm 10; exec @ARGV' "$BUILD/shalimar" "$BUILD/case.shm" 2>&1 | tr '\n' ' ')
    if [[ "$out" == *"$2"* ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        failures+=("$1"$'\n'"      want: $2"$'\n'"      got:  $out")
    fi
}

# ---------------------------------------------------------------- 5.5 definitions
# 3.0: the <> list holds output *types*, not output *names*. 2.x named a variable
# there and let the function fall off its end with whatever that variable held; a
# function that declares outputs must now actually return them.
t "typed output list" "1 2 3" 'fun <int,int,int> = f() { return (1,2,3) }
fun <> = main() { <a,b,c> : f()
? a b c }'
t "multi-value return needs parens" "1 2" 'fun <int,int> = f() { return (1,2) }
fun <> = main() { <a,b> : f()
? a b }'
t "return arity must match outputs" "declares 0 outputs but this return has 3" 'fun <> = f() { return (1,2,3) }
fun <> = main() { f()
? 1 }'
t "declared output needs a return" "declares 1 output but can finish without a return" 'fun <int> = f() { int y : 9 }
fun <> = main() {
? f() }'
t "fresh local scope" "Undefined variable 'k'" 'fun <int> = f() { return k }
fun <> = main() { k : 5
? f() }'
t "main() may not take inputs" "main() must take no inputs" 'fun <> = main(n: int) {
? 1 }'
t "duplicate definition" "already defined" 'fun <> = g() { return 1 }
fun <> = g() { return 2 }
fun <> = main() {
? g() }'
t "unused function warns" "defined but never called" 'fun <int> = unused() { return 1 }
fun <> = main() {
? 42 }'

# --------------------------------------------------------------- 5.6 calls / args
# 3.0: a user function may not take a builtin's name at all. 2.x resolved the clash
# silently in the builtin's favour, so the definition was dead code with no warning.
t "user fn cannot shadow a builtin" "shadows a builtin of the same name" 'fun <real> = sqrt(x: real) { return 999. }
fun <> = main() {
? sqrt(16.) }'
t "builtin rejects string arg" "Cannot use char[] where real is required" 'fun <> = main() {
? sqrt("hi") }'
# Under-supplying a builtin used to trap on args[0] and take the whole app down
# (SIGTRAP, uncatchable, no diagnostic). 3.0 catches it a stage earlier still - the
# checker refuses the program, so nothing runs at all.
t "builtin too few args, 1-arity" "expects 1 argument, got 0" 'fun <> = main() {
? sqrt() }'
t "builtin too few args, 2-arity" "expects 2 arguments, got 1" 'fun <> = main() {
? pow(2.) }'
t "builtin too few args, zero-arity call" "expects 2 arguments, got 0" 'fun <> = main() {
? atan2() }'
t "builtin under-supply is a check error" "Function 'min' expects 2 arguments, got 1" 'fun <> = main() {
? "before"
? min(1.) }'
# 3.0: surplus arguments are an error. 2.x warned and dropped them, which meant a
# call with the arguments in the wrong order still ran and returned a wrong number.
t "builtin extra args rejected" "expects 1 argument, got 2" 'fun <> = main() {
? sqrt(16.,99.) }'
t "too few args errors" "expects 2 arguments, got 1" 'fun <real> = f(a: real, b: real) { return a+b }
fun <> = main() {
? f(1.) }'
t "extra args rejected" "expects 1 argument, got 2" 'fun <int> = f(a: int) { return a }
fun <> = main() {
? f(1,2) }'
t "zero args supplied" "expects 1 argument, got 0" 'fun <int> = f(a: int) { return a }
fun <> = main() {
? f() }'
t "expression as argument" "9" 'fun <int> = f(a: int) { return a }
fun <> = main() {
? f(4+5) }'
t "nested call as argument" "5" 'fun <int> = f(a: int) { return a }
fun <> = main() {
? f(f(5)) }'
t "scalar arguments are by value" "1" 'fun <int> = f(a: int) { a : 99 return 0 }
fun <> = main() { x : 1 f(x)
? x }'
t "recursion" "120" 'fun <int> = fact(n: int) { if n < 2 { return 1 } return n*fact(n-1) }
fun <> = main() {
? fact(5) }'

# Recursion depth: unbounded recursion overflows the native stack (SIGSEGV, uncatchable,
# no output). Per-function cap is 256/(inputs+1); a total-frames backstop covers mutual
# recursion, where no single function ever approaches its own cap.
t "1-arg recursion at limit ok" "0" 'fun <int> = d(n: int) { if n < 1 { return 0 } return d(n-1) }
fun <> = main() {
? d(127) }'
t "1-arg recursion over limit" "Recursion too deep in 'd' (limit 128)" 'fun <int> = d(n: int) { if n < 1 { return 0 } return d(n-1) }
fun <> = main() {
? d(128) }'
t "0-arg recursion limit 256" "Recursion too deep in 'z' (limit 256)" 'fun <int> = z() { return z() }
fun <> = main() {
? z() }'
t "3-arg recursion limit 64" "Recursion too deep in 'w' (limit 64)" 'fun <int> = w(a: int, b: int, c: int) { return w(a,b,c) }
fun <> = main() {
? w(1,2,3) }'
t "sequential calls unaffected" "2000" 'fun <int> = f(n: int) { return 1 }
fun <> = main() { s : 0 for i:1 to 2000 { s +: f(i) }
? s }'
t "mutual recursion backstop" "Call stack too deep (limit 1024)" 'fun <int> = a() { return b() }
fun <int> = b() { return c() }
fun <int> = c() { return d() }
fun <int> = d() { return e() }
fun <int> = e() { return a() }
fun <> = main() {
? a() }'
t "runaway recursion reports, not crashes" "before  Runtime error: line 1: Recursion too deep" 'fun <int> = d(n: int) { return d(n+1) }
fun <> = main() {
? "before"
? d(1) }'
# Depth is per-frame, not a lifetime tally: the counter must come back down on the throwing
# path too, or an earlier caught-and-reported failure would poison every later call.
t "depth unwinds after return" "0  0" 'fun <int> = d(n: int) { if n < 1 { return 0 } return d(n-1) }
fun <> = main() {
? d(120)
? d(120) }'
t "multi-argument call" "7" 'fun <int> = f(a: int, b: int) { return a+b }
fun <> = main() {
? f(3,4) }'

# ------------------------------------------------- 7 results / multi-assign arity
# 3.0: mismatched multi-assign arity is a check error. 2.x warned and carried on,
# silently discarding surplus values and leaving surplus variables untouched.
t "plain assign takes first" "25" 'fun <int> = sq(x: int) { return x*x }
fun <> = main() { y : sq(5)
? y }'
t "call inline in expression" "10" 'fun <int> = sq(x: int) { return x*x }
fun <> = main() {
? 1 + sq(3) }'
t "bare call is not a return" "5" 'fun <int> = sq(x: int) { return x*x }
fun <> = main() { sq(4)
? 5 }'
t "multi-assign captures both" "3 9" 'fun <int,int> = p() { return (3,9) }
fun <> = main() { <d,k> : p()
? d k }'
t "too few targets is an error" "returns 2, but 1 variable listed" 'fun <int,int> = f() { return (1,2) }
fun <> = main() { <a> : f()
? a }'
t "too many targets is an error" "returns 1, but 2 variables listed" 'fun <int> = f() { return 1 }
fun <> = main() { <a,b> : f()
? a }'
t "bare return from a 0-output fn" "5" 'fun <> = f() { return }
fun <> = main() { f()
? 5 }'
# A builtin has no PrototypeNode, so the arity and define steps used to be skipped
# entirely - '<s> : sqrt(16.)' left s undeclared and the next line called it undefined.
t "builtin single multi-assign" "4.0" 'fun <> = main() { <s> : sqrt(16.)
? s }'
t "builtin multi-assign arity" "returns 1, but 2 variables listed" 'fun <> = main() { <s,t> : sqrt(16.)
? s }'
t "builtin multi-assign into declared" "4.0" 'fun <> = main() { real s : 0.
<s> : sqrt(16.)
? s }'

# ------------------------------------------------------------ 6 strings are char[]
# 3.0: a string is a char array with a type of its own. 2.x had no string type - a
# string used as a value silently became 0.0, so every one of these ran and produced
# a plausible wrong number instead of a diagnostic.
t "string assigns as char[]" "hello" 'fun <> = main() { x : "hello"
? x }'
t "declared string" "abc" 'fun <> = main() { char s[8] : "abc"
? s }'
t "string in arithmetic is a type error" "needs scalars, got int and char[]" 'fun <> = main() {
? 1 + "a" }'
t "string as a condition is a type error" "A condition must be a scalar, not char[]" 'fun <> = main() { if "a" {
? 1 } else {
? 2 } }'
t "string as scalar arg is a type error" "Cannot use char[] where int is required" 'fun <int> = f(a: int) { return a }
fun <> = main() {
? f("hi") }'
t "string prints literally" "ok" 'fun <> = main() {
? "ok" }'
t "non-ASCII allowed in string" "wörld" 'fun <> = main() {
? "héllo wörld" }'

# -------------------------------------------------------- 2.2 lexer / ASCII rule
t "underscore identifier" "7" 'fun <> = main() { _foo : 7
? _foo }'
t "digits inside identifier" "3" 'fun <> = main() { x1 : 3
? x1 }'
t "keywords case-insensitive" "yes" 'fun <> = main() { x : 1 IF x > 0 {
? "yes" } }'
t "Cyrillic homoglyph rejected" "U+0445" 'fun <> = main() { хn : 5
? xn }'
t "Greek homoglyph rejected" "U+039F" 'fun <> = main() { Ο : 5
? O }'
t "unknown character rejected" "U+0040" 'fun <> = main() { x @ : 5
? x }'

# ------------------------------------------------------------------- 2.3 numbers
# The '.' of an attribute and the '.' of a numeral are the same character, and the
# numeral rule is tried first, so these guard that adding '.row' did not open a hole
# in number lexing.
t "malformed number rejected" "Malformed number '1.2.3'" 'fun <> = main() {
? 1.2.3 }'
t "malformed number in expression" "Malformed number '0.0.1'" 'fun <> = main() { x : 0.0.1 + 2
? x }'
t "trailing dot is not malformed" "1.0" 'fun <> = main() {
? 1. }'
t "real literal still lexes whole" "1.5000000" 'fun <> = main() {
? 1.5 }'

# ------------------------------------------------------- exponent notation
# '1e-20' beats writing the zeros out. An exponent always makes a real - the magnitudes
# that need one do not fit an int anyway. The exponent digits are scanned loosely so a
# truncated '1e' is reported as a malformed number rather than splitting into the number
# 1 and an identifier 'e', which would desync every token after it.
t "negative exponent" "0.0000000000000000000100" 'fun <> = main() { real tol : 1e-20
? prec(22) tol }'
t "positive exponent" "10000000000.0000000" 'fun <> = main() {
? 1e10 }'
t "exponent with a point" "1500.0000000" 'fun <> = main() {
? 1.5e3 }'
t "explicit plus exponent" "100000.0000000" 'fun <> = main() {
? 1e+5 }'
t "small exponent" "0.2000000" 'fun <> = main() {
? 2e-1 }'
t "exponent then subtraction" "99998.0000000" 'fun <> = main() {
? 1e5-2. }'
t "truncated exponent is malformed" "Malformed number '1e'" 'fun <> = main() {
? 1e }'
t "exponent sign with no digits" "Malformed number '1e-'" 'fun <> = main() { x : 1e-
? x }'
# The exponent must not swallow an ordinary subtraction, or a name that begins with e.
t "plain subtraction unaffected" "1" 'fun <> = main() {
? 2-1 }'
t "e is still a usable name" "2 5" 'fun <> = main() { e : 5
? 2 e }'

# ------------------------------------------------- ? prec(n) print precision
# A print-list directive, not a value: it prints nothing itself and applies from that
# point on, including the rest of its own line. The argument runs -1 through 24 and
# clamps to that range at both ends, so -1 (or anything below it) restores the default
# and nothing is ever refused for being out of range.
t "prec raises places" "0.333333333333" 'fun <> = main() {
? prec(12) 1./3. }'
t "prec lowers places" "0.33" 'fun <> = main() {
? prec(2) 1./3. }'
t "prec persists to later lines" "0.333  0.333" 'fun <> = main() {
? prec(3) 1./3.
? 1./3. }'
t "prec(-1) restores the default" "0.333  0.3333333" 'fun <> = main() {
? prec(3) 1./3.
? prec(-1) 1./3. }'
t "prec applies to a grid too" "1.000  0.500" 'fun <> = main() { real A[1][2] : {{1.,0.5}}
? prec(3) A }'
t "prec prints nothing itself" "x 1.00" 'fun <> = main() {
? prec(2) "x" 1. }'
t "prec takes an expression" "0.3333" 'fun <> = main() { n : 2
? prec(n*2) 1./3. }'
t "prec(24) is the ceiling" "1.000000000000000000000000" 'fun <> = main() {
? prec(24) 1. }'
t "prec clamps above 24" "1.000000000000000000000000" 'fun <> = main() {
? prec(500) 1. }'
t "prec clamps below -1" "1.000  1.0000000" 'fun <> = main() {
? prec(3) 1.
? prec(0-5) 1. }'
t "prec rejects a real" "needs an int number of places" 'fun <> = main() {
? prec(2.5) 1. }'
# Contextual: only 'prec(' in a print list is the directive.
t "prec is still a usable name" "9" 'fun <> = main() { prec : 9
? prec }'
t "prec outside a print list" "belongs in a print list" 'fun <> = main() { prec(3)
? 1. }'
t "a function named prec is refused" "clashes with the print precision directive" 'fun <int> = prec(n: int) { return n }
fun <> = main() {
? 1. }'
t "int and real print differently" "42 42.0" 'fun <> = main() {
? 42 42. }'

# ------------------------------------------------- int() / real() conversions
# Both were implemented in the checker and the interpreter but unreachable: the lexer
# turns 'int' into a type keyword before the parser can read 'int(' as a call, so every
# use was a parse error. real -> int drops the fraction whatever the sign - it is a
# truncation toward zero, never a floor, so -2.7 gives -2 and not -3.
t "int() drops a positive fraction" "2" 'fun <> = main() {
? int(2.7) }'
t "int() drops a negative fraction" "-2" 'fun <> = main() {
? int(0.-2.7) }'
t "int() of an int is identity" "7" 'fun <> = main() {
? int(7) }'
t "real() is exact" "20.0000000" 'fun <> = main() { int i : 20
? real(i) }'
# The declared input types of these two builtins must not coerce the argument: running
# 'real(2.7)' through the int input would truncate the value the call exists to widen.
t "real() does not truncate" "2.7000000" 'fun <> = main() { real x : 2.7
? real(x) }'
t "int() inside arithmetic" "3" 'fun <> = main() { real x : 7.
? int(x/2.) }'
# The gap that had no workaround: a real index is refused outright, and without a
# conversion callable inside the brackets it needed a temporary variable.
t "int() converts an index" "3.0000000" 'fun <> = main() { real A[4] : {1.,2.,3.,4.}
real x : 2.9
? A[int(x)] }'
t "int() in a return" "9" 'fun <int> = f(x: real) { return int(x) }
fun <> = main() {
? f(9.8) }'
t "int() rejects an array" "needs an int or a real, got real[]" 'fun <> = main() { real A[2] : {1.,2.}
? int(A) }'
t "int() rejects a string" "needs an int or a real, got char[]" 'fun <> = main() {
? int("hi") }'
t "int() out of range reports" "Cannot convert" 'fun <> = main() {
? int(pow(10.,30.)) }'
t "int() of nan reports" "Cannot convert nan" 'fun <> = main() {
? int(0./0.) }'
# A type keyword still opens a declaration everywhere it did before - only a keyword
# immediately followed by "(" is read as a conversion.
t "declaration still parses" "5 1.5000000" 'fun <> = main() { int k : 5
real r : 1.5
? k r }'
t "declaration after a print" "1  5" 'fun <> = main() { x : 1
? x
int k : 5
? k }'
t "bare int is still an error" "Parse error" 'fun <> = main() {
? int }'

# ----------------------------------------------------- array shape: .row/.col/.dim
# '.row' is axis 0 and '.col' is axis 1 whatever the rank, with '.dim(n)' for the
# rest. An axis the array does not have answers -1 rather than failing, so asking a
# vector for its columns is a legal question with a recognizable answer.
t "matrix row and col" "3 4" 'fun <> = main() { real A[3][4]
? A.row A.col }'
t "dim matches row and col" "3 4" 'fun <> = main() { real A[3][4]
? A.dim(0) A.dim(1) }'
t "rank 3 third axis" "5" 'fun <> = main() { int C[2][3][5]
? C.dim(2) }'
t "row and col work at rank 3" "2 3" 'fun <> = main() { int C[2][3][5]
? C.row C.col }'
t "vector col is -1" "10 -1" 'fun <> = main() { real v[10]
? v.row v.col }'
t "dim past the rank is -1" "-1" 'fun <> = main() { real v[10]
? v.dim(1) }'
t "negative axis is -1" "-1" 'fun <> = main() { real A[2][2]
? A.dim(0-1) }'
t "computed axis" "5" 'fun <> = main() { int C[2][3][5]
? C.dim(1+1) }'
t "attribute chains off a subscript" "4" 'fun <> = main() { real A[3][4]
? A[0].row }'
t "string length is capacity" "8 -1" 'fun <> = main() { char s[8] : "abc"
? s.row s.col }'
t "shape of a reference parameter" "3 4" 'fun <> = show(M[][]: real) {
? M.row M.col }
fun <> = main() { real A[3][4]
show(A) }'
t "row agrees with len" "3 3" 'fun <> = main() { real A[3][4]
? len(A) A.row }'
# The shape is measured, not declared, so a row replaced at run time reports its
# real length rather than the one the declaration asked for.
t "shape is measured not declared" "2" 'fun <> = main() { real A[2][5]
A[0] : {1.,2.}
? A[0].row }'
t "scalar has no dimensions" "int has no dimensions" 'fun <> = main() { x : 1
? x.row }'
t "unknown attribute rejected" "is not an array attribute" 'fun <> = main() { real A[2]
? A.size }'
t "dim needs an axis" "needs an axis in parentheses" 'fun <> = main() { real A[2]
? A.dim }'
t "axis must be an int" "needs an int axis, not real" 'fun <> = main() { real A[2][2]
? A.dim(1.5) }'
t "attribute is read-only" "is read-only" 'fun <> = main() { real A[2]
A.row : 5 }'
# row/col/dim are recognized only after a dot, so they stay ordinary identifiers.
t "row is still a usable name" "9 2" 'fun <> = main() { real A[2][2]
row : 9
? row A.row }'
t "dim is still a usable name" "7" 'fun <> = main() { dim : 7
? dim }'

# --------------------------------------------------- for i < n  (count shorthand)
# 'for i < n' is sugar for 'for i : 0 to n - 1' and expands to exactly that node,
# which is why 'step' rides along unchanged.
t "shorthand matches long form" "long 0 1 2 short 0 1 2" 'fun <> = main() { real A[2][3]
?? "long"
for i : 0 to A.col - 1 {
?? i }
?? "short"
for i < A.col {
?? i } }'
t "shorthand over rows" "0 1" 'fun <> = main() { real A[2][3]
for i < A.row {
?? i } }'
t "shorthand with step" "0 2 4" 'fun <> = main() { int C[2][3][5]
for k < C.dim(2) step 2 {
?? k } }'
t "shorthand on a plain count" "0 1 2 3" 'fun <> = main() { n : 4
for i < n {
?? i } }'
# v.col is -1 here, so the loop is 0 to -2: it runs zero times rather than failing.
t "shorthand over a missing axis" "none" 'fun <> = main() { real v[4]
for j < v.col {
?? "ran" }
? "none" }'
t "nested shorthand" "0 1 2 10 11 12" 'fun <> = main() { real A[2][3]
for i < A.row {
for j < A.col {
?? i*10+j } } }'
# Because it expands to "0 to n - 1", a real bound subtracts before it widens: this
# stops at 1.0, where reading "i < 2.9" literally would also have given 2.0. Recorded
# rather than silently inherited - a count loop over a real bound is the odd case.
t "real bound follows the expansion" "0.0000000 1.0000000" 'fun <> = main() { for i < 2.9 {
?? i } }'
t "shorthand counter is loop-local" "Undefined variable 'i'" 'fun <> = main() { n : 3
for i < n {
?? n }
? i }'
t "long form still works" "3 2 1 0" 'fun <> = main() { for i : 3 to 0 step -1 {
?? i } }'

# ------------------------------------------------- array extents at declaration
# An extent is fixed when the declaration runs and never changes, so a size that can be
# settled statically is refused by the checker rather than by the interpreter. The two
# rules are separate: >= 1, and int - a real is refused outright, never truncated.
t "negative literal extent" "must be at least 1, got -2" 'fun <> = main() { real A[-2]
? 1 }'
t "zero extent" "must be at least 1, got 0" 'fun <> = main() { real A[0]
? 1 }'
t "folded negative extent" "must be at least 1, got -2" 'fun <> = main() { real A[3-5]
? 1 }'
t "negative in second dimension" "must be at least 1, got -3" 'fun <> = main() { real A[2][-3]
? 1 }'
t "real extent refused, not truncated" "must be an int, not real" 'fun <> = main() { real A[2.5]
? 1 }'
t "real variable extent refused" "must be an int, not real" 'fun <> = main() { real k : 2.
real m[k]
? 1 }'
# A static refusal must stop the run outright - the whole point is that nothing has
# happened yet when the diagnostic appears.
t "bad extent runs nothing" "must be at least 1" 'fun <> = main() {
? "ran first"
real A[-2] }'
# Only a size that genuinely depends on a variable reaches the interpreter. It reports the
# value it computed, which the checker's message can afford to omit but this one cannot -
# the number is nowhere in the source.
t "computed zero extent traps" "at least 1, got 0" 'fun <> = main() { k : 2
real m[k-2][4]
? 1 }'
t "computed negative extent traps" "at least 1, got -3" 'fun <> = main() { k : 2
real m[k-5]
? 1 }'
t "computed extent names the array" "'w': array size" 'fun <> = f(v[]: real) { real w[len(v)-9]
? 1 }
fun <> = main() { real p[3] : {1.,2.,3.}
f(p) }'
t "literal extent still legal" "3" 'fun <> = main() { real A[3]
? len(A) }'
t "folded extent still legal" "6" 'fun <> = main() { real A[2*3]
? len(A) }'
t "len() extent still legal" "5" 'fun <> = f(v[]: real) { real A[len(v)]
? len(A) }
fun <> = main() { real v[5] : {1.,2.,3.,4.,5.}
f(v) }'
# len() is capacity for every array, a string included. It used to report a string'"'"'s
# content length, which gave it two domains: never 0 for a numeric array, but 0 for an
# empty string - so "real w[len(s)]" failed on a value that was not a mistake.
t "len of a string is capacity" "8" 'fun <> = main() { char s[8] : "abc"
? len(s) }'
t "len of an empty string" "8" 'fun <> = main() { char s[8] : ""
? len(s) }'
t "len() is never 0" "4" 'fun <> = main() { char s[4] : ""
real w[len(s)]
? len(w) }'

# ------------------------------------------------------------ printing an array as a grid
# "? A" lays a numeric array out in columns, so a program needs no display function of its
# own. Reals are fixed to 7 decimal places: a grid is read down its columns, and full
# Double precision ragged them and filled them with rounding noise.
t "2-D real prints as a grid" "1.000000  2.000000 3.000000  4.000000" 'fun <> = main() { real A[2][2] : {{1.,2.},{3.,4.}}
? A }'
t "1-D real stays on one line" "1.500000  2.250000" 'fun <> = main() { real v[2] : {1.5,2.25}
? v }'
t "int grid has no decimals" "1   2 40  50" 'fun <> = main() { int k[2][2] : {{1,2},{40,50}}
? k }'
t "columns are right-aligned" "1.000000  10.000000" 'fun <> = main() { real A[1][2] : {{1.,10.}}
? A }'
# A label keeps its own line, so the first row is not pushed out of column by it.
t "label then matrix breaks line" "A = 1.000000" 'fun <> = main() { real A[1][1] : {{1.}}
? "A =" A }'
# A string is not a grid - it still prints inline, exactly as before.
t "string still prints inline" "name: abc" 'fun <> = main() { char s[8] : "abc"
? "name:" s }'
# A scalar real keeps full precision; only a grid cell is rounded.
t "scalar real is 7 places" "0.3333333" 'fun <> = main() { x : 1./3.
? x }'

# ------------------------------------------------------------ statements / control
t "hello world" "Hello world!" 'fun <>=main() {
   ? "Hello world!"
}'
t "compound assign +:" "6" 'fun <> = main() { x : 5 x +: 1
? x }'
t "compound assign -:" "4" 'fun <> = main() { x : 5 x -: 1
? x }'
t "if / elseif / else" "mid" 'fun <> = main() { x : 5 if x > 9 {
? "hi" } elseif x > 2 {
? "mid" } else {
? "lo" } }'
t "while loop" "1 2 3" 'fun <> = main() { i : 1 while i < 4 {
?? i i +: 1 } }'
t "for loop" "1 2 3" 'fun <> = main() { for i:1 to 3 {
?? i } }'
t "for loop with step" "1 3 5" 'fun <> = main() { for i:1 to 5 step 2 {
?? i } }'
t "for loop counts down" "3 2 1" 'fun <> = main() { for i:3 to 1 step 0-1 {
?? i } }'
# A real anywhere in the bounds widens the counter, so the loop runs in reals.
t "real bound widens the counter" "1.0000000 2.0000000" 'fun <> = main() { for i:1 to 2.9 {
?? i } }'
t "zero step errors" "Step value cannot be zero" 'fun <> = main() { for i:1 to 5 step 0 {
?? i } }'
# 3.0: int division by zero is an error. 2.x produced inf, which then reached Int() and
# trapped uncatchably wherever a loop bound or an index was computed from it.
t "int division by zero" "Division by zero" 'fun <> = main() {
? 1/0 }'
t "int modulus by zero" "Division by zero" 'fun <> = main() {
? 1%0 }'
t "real division by zero is inf" "inf" 'fun <> = main() {
? 1./0. }'
# Int(Double) traps - uncatchably - on NaN/infinity/out-of-range, and a builtin result
# reaches these bounds directly. Each of these used to kill the process with no output.
t "NaN loop end" "Loop end out of range" 'fun <> = main() { for i:1. to sqrt(0.-1.) {
?? i } }'
t "infinite loop end" "Loop end out of range" 'fun <> = main() { for i:1. to 1./0. {
?? i } }'
t "NaN loop start" "Loop start out of range" 'fun <> = main() { for i:0./0. to 5. {
?? i } }'
t "NaN loop step" "Loop step out of range" 'fun <> = main() { for i:1. to 5. step 0./0. {
?? i } }'
t "out-of-Int-range loop end" "Loop end out of range" 'fun <> = main() { for i:1. to pow(10.,400.) {
?? i } }'
t "bad bound reports, not traps" "before  Runtime error: line 3: Loop end" 'fun <> = main() {
? "before"
for i:1. to 0./0. {
?? i } }'
t "return out of if" "9" 'fun <int> = f(n: int) { if n > 0 { return 9 } return 1 }
fun <> = main() {
? f(5) }'
t "return out of while" "3" 'fun <int> = f() { i : 0 while i < 9 { i +: 1 if i = 3 { return i } } return 0 }
fun <> = main() {
? f() }'
t "quadratic program" "Solution 1.0000000 1.0000000" 'fun <> = main() {
   a : 1.
   b : -2.
   c : 1.
   d : b^2.-4.*a*c
   if d < 0. {
? "No real roots" }
   else { d : sqrt(d) x1 : (0.-b-d)/(2.*a) x2 : (0.-b+d)/(2.*a)
? "Solution" x1 x2 }
}'

# ----------------------------------------------------- parser regressions guarded
# Each of these failed at some point during the parser refactor; they are the
# reason this file exists.
t "REG return before }" "1" 'fun <int> = f() { return 1 }
fun <> = main() {
? f() }'
t "REG bare call statement" "9" 'fun <int> = f() { return 1 }
fun <> = main() { f()
? 9 }'
t "REG = fallback assignment" "5" 'fun <> = main() { x = 5
? x }'
t "REG print starting with -" "4" 'fun <> = main() {
? -2^2 }'
t "REG print starting with (" "3" 'fun <> = main() {
? (1+2) }'
t "REG parseError reaches caller" "PARSE:" 'fun <> = main() { x : * 5 }'

# ------------------------------------------------------------------- precedence
t "power is right-associative" "512" 'fun <> = main() {
? 2^3^2 }'
t "unary minus binds over ^" "4" 'fun <> = main() { x : -2^2
? x }'
t "inline print ??" "hello world" 'fun <> = main() {
?? "hello"
?? "world" }'
t "mixed string and numbers" "Solution 3 5" 'fun <> = main() { x:3 y:5
? "Solution" x y }'

# ------------------------------------ 5.10 print commands own their line ('?', '??')
# The rule needs Token.line: without it "? x ?? x" and the same two commands on two
# lines are the identical token stream, so neither could be rejected without the other.
t "? must start its line" "must be the first thing on its line" 'fun <> = main() { x : 1 ? x }'
t "?? must start its line" "must be the first thing on its line" 'fun <> = main() { x : 1 ?? x }'
t "two commands one line" "'??' must be the first thing on its line" 'fun <> = main() { x : 1
? x ?? x }'
t "two ? one line" "'?' must be the first thing on its line" 'fun <> = main() { x : 1
? x ? x }'

# A print command owns its line at *both* ends: it must open the line, and its items stop
# where the line does. Before the second half existed, the statement after a print was read
# as more items whenever it began with something startsTerm accepts - a parse error for an
# indexed assignment, and silently wrong output for a bare call, which ran early and had its
# result printed. No token pattern separates those from real items: "? l f(x)" and a bare
# "f(x)" on the next line are the same tokens in the same order, so only the line tells.
t "indexed assign after print" "1.0000000  9.0000000" 'fun <> = main() { real v[2] : {1.,2.}
? v[0]
v[1] : 9.
? v[1] }'
t "bare call after print keeps order" "label  inside" 'fun <> = hi() {
? "inside" }
fun <> = main() {
? "label"
hi() }'
t "call still works as an item" "root 4.0" 'fun <> = main() {
? "root" sqrt(16.) }'
t "items still run to end of line" "x 3 sq 9" 'fun <> = main() { x : 3
? "x" x "sq" x*x }'
t "indexed item on the same line" "v0 7.0000000 v1 8.0000000" 'fun <> = main() { real v[2] : {7.,8.}
? "v0" v[0] "v1" v[1] }'
t "attribute item on the same line" "rows 2 cols 2" 'fun <> = main() { real A[2][2]
? "rows" A.row "cols" A.col }'
t "command after item list" "must be the first thing on its line" 'fun <> = main() { x : 1
? "hello" ?? x }'
# Indentation is invisible here - the lexer drops it before the parser sees a line at all.
t "indented command is fine" "5" 'fun <> = main() {
     x : 5
        ? x
}'
# 3.0: only declarations and definitions live outside a function, so a print can no
# longer be the first token of the file. 2.x allowed statements at top level.
t "no statements in global space" "Only declarations and 'fun' definitions may appear outside" '? 9
fun <> = main() {
? 7 }'
t "global declaration is allowed" "4" 'int g : 4
fun <> = main() {
? g }'
# "!" lost its print role to "??" and is now only the first half of "!=".
t "bare ! is not a command" "'!' is not a command" 'fun <> = main() { x : 1
! x }'
t "! keeps != intact" "1" 'fun <> = main() { x : 1
? x != 2 }'
t "!= is not two commands" "0" 'fun <> = main() {
? 2 != 2 }'

# ------------------------------------------------------- 10 error line reporting
# Lex, parse and check errors all name the line. Blank lines and comments count, so
# these double as a check that the lexer's newline counting isn't skipping anything.
t "lex error names line" "Lex error: line 3:" 'fun <> = main() {
 x : 1
 хn : 5
}'
t "lex line counts blanks" "Lex error: line 5:" 'fun <> = main() {

 // a comment

 y : 1.2.3
}'
t "parse error names line" "Parse error: line 3:" 'fun <> = main() {
 x : 1
 x : 2 ? x
}'
t "end of input names last line" "Parse error: line 3: Missing" 'fun <> = main() {
 x : 1
 ? x'
t "check error names line" "Error: line 4: Undefined variable" 'fun <> = main() {
 x : 1
 y : 2
 ? zz
}'
# The line reported is the statement the name appears in, so a name used inside a
# callee names the callee's line rather than the call site's.
t "error line is the callee's" "Error: line 2: Undefined variable 'qq'" 'fun <int> = f() {
 return qq
}
fun <> = main() {
 ? f()
}'
# 3.0: missing main() and redefinition are both caught by the checker, before anything
# runs. 2.x discovered them at run time, so earlier output had already appeared.
t "no main is reported" "No main() function defined" 'fun <int> = g() { return 1 }'
t "redefinition names both lines" "Function 'g' already defined (line 1)" 'fun <> = g() { return 1 }
fun <> = g() { return 2 }
fun <> = main() {
? g() }'

# ------------------------------------------------- end of input at every position
# Truncated source must produce a diagnostic - never a hang, crash, or silent pass.
while IFS= read -r snippet; do
    t "EOF: $snippet" "Parse error" "$snippet"
done <<'SNIPPETS'
fun
fun <
fun <> = main()
fun <> = main() {
fun <> = main() { return
fun <> = main() { ?
fun <> = main() { x :
fun <> = main() { ? (1
fun <> = main() { if
fun <> = main() { for i:1 to
fun <> = main() { <a,b> :
fun <> = main() { for i <
fun <> = main() { for i < n step
fun <> = main() { x : y.
fun <> = main() { x : y.dim(
fun <int> = f(a
SNIPPETS

# ---------------------------------------------------------------------- examples
# Examples/*.shm are the programs printed on the scan sheets, so they are the closest
# thing here to an end-to-end test: if one stops running, what gets photographed off
# paper stops working. They also cover ground the unit cases do not - array arguments
# by reference, nested functions, and grid output at real sizes.
e() {
    local out
    out=$(perl -e 'alarm 10; exec @ARGV' "$BUILD/shalimar" "$ROOT/Examples/$1" 2>&1 | tr '\n' ' ')
    if [[ "$out" == *"$2"* ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        failures+=("example $1"$'\n'"      want: $2"$'\n'"      got:  $out")
    fi
}
e factorial.shm "factorial of 10  is 3628800"
e fibonacci.shm "0 1 1 2 3 5 8 13 21 34 55 89"
e gcd.shm       "gcd of 48 18  is 6"
e prime.shm     "97  is a prime"
e quadratic.shm "roots 2.0000000 3.0000000"
e table.shm     "7 x 9 = 63"
e invert.shm    "1.444444  -1.222222  -0.555556"
e invert.shm    "singular, det 0.0000000"
e rotmat.shm    "yaw 90"
e rotmat.shm    "1.000000   0.000000   0.000000"

# ------------------------------------------------------- scan layout (OCR line rebuild)
# A second binary: ScanLayout.swift is part of the app but has no UIKit or Vision
# dependency precisely so its line-rebuilding can be tested here. Its failures are folded
# into this suite's counts so the hook and CI see one number.
scan_out=$(swiftc -O "$SRC/ScanLayout.swift" "$ROOT/Tests/scanlayout/main.swift" \
                  -o "$BUILD/scanlayout" 2>&1) && "$BUILD/scanlayout"
scan_status=$?
if (( scan_status != 0 )); then
    fail=$((fail + 1))
    failures+=("scan layout tests"$'\n'"      see output above"$'\n'"      $scan_out")
fi

# ------------------------------------------------------------------------ report
echo
echo "PASS: $pass   FAIL: $fail"
if (( fail > 0 )); then
    echo
    echo "FAILURES:"
    for f in "${failures[@]}"; do
        echo "  - $f"
    done
fi
exit $(( fail > 0 ? 1 : 0 ))
