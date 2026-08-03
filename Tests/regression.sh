#!/usr/bin/env bash
#
# Regression suite for the Shalimar language core.
#
# Compiles Lexer/Parser/Interpreter plus Tests/harness/main.swift into a
# command-line binary and runs every program below through it, asserting that
# the output contains an expected fragment. The core is pure Foundation, so this
# needs no simulator and no Xcode test target - it runs in a couple of seconds.
#
#   ./Tests/regression.sh
#
# Exits non-zero if any case fails, so it drops straight into a git hook or CI.
#
# Expectations are substring matches, which keeps them readable and tolerant of
# the trailing space the print statements emit after each item. Every case here
# is traceable to a claim in SHALIMAR_LANGUAGE.md - when a case and the spec
# disagree, the spec wins and the interpreter is the thing to fix.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Computer"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

swiftc -O "$SRC/Lexer.swift" "$SRC/Parser.swift" "$SRC/Interpreter.swift" \
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
t "return overrides <> list" "1.0 2.0 3.0" 'fun <> = f() { return 1 2 3 }
fun <> = main() { <a,b,c> : f() ? a b c }'
t "fall off end, <x> unassigned" "0.0" 'fun <x> = f() { y : 9 }
fun <> = main() { ? f() }'
t "fall off end, <x> assigned" "7.0" 'fun <x> = f() { x : 7 }
fun <> = main() { ? f() }'
t "fresh local scope" "Undefined variable 'k'" 'fun <r> = f() { return k }
fun <> = main() { k : 5 ? f() }'
t "main() may not take inputs" "expects 1 arguments" 'fun <> = main(n) { ? 1 }'
t "duplicate definition" "already defined" 'fun <> = g() { return 1 }
fun <> = g() { return 2 }
fun <> = main() { ? g() }'
t "unused function warns" "defined but never called" 'fun <> = unused() { return 1 }
fun <> = main() { ? 42 }'

# --------------------------------------------------------------- 5.6 calls / args
t "builtin beats user fn" "4.0" 'fun <r> = sqrt(x) { return 999 }
fun <> = main() { ? sqrt(16) }'
t "builtin rejects string arg" "must be a number" 'fun <> = main() { ? sqrt("hi") }'
t "too few args errors" "expects 2 arguments, got 1" 'fun <r> = f(a,b) { return a+b }
fun <> = main() { ? f(1) }'
t "extra args warn, still run" "extra args provided" 'fun <r> = f(a) { return a }
fun <> = main() { ? f(1,2) }'
t "zero args supplied" "expects 1 arguments, got 0" 'fun <r> = f(a) { return a }
fun <> = main() { ? f() }'
t "expression as argument" "9.0" 'fun <r> = f(a) { return a }
fun <> = main() { ? f(4+5) }'
t "nested call as argument" "5.0" 'fun <r> = f(a) { return a }
fun <> = main() { ? f(f(5)) }'
t "arguments are by value" "1.0" 'fun <r> = f(a) { a : 99 return 0 }
fun <> = main() { x : 1 f(x) ? x }'
t "recursion" "120.0" 'fun <r> = fact(n) { if n < 2 { return 1 } return n*fact(n-1) }
fun <> = main() { ? fact(5) }'
t "multi-argument call" "7.0" 'fun <r> = f(a,b) { return a+b }
fun <> = main() { ? f(3,4) }'

# ------------------------------------------------- 7 results / multi-assign arity
t "plain assign takes first" "25.0" 'fun <r> = sq(x) { return x*x }
fun <> = main() { y : sq(5) ? y }'
t "call inline in expression" "10.0" 'fun <r> = sq(x) { return x*x }
fun <> = main() { ? 1 + sq(3) }'
t "bare call is not a return" "5.0" 'fun <r> = sq(x) { return x*x }
fun <> = main() { sq(4) ? 5 }'
t "multi-assign captures both" "3.0 9.0" 'fun <m,i> = p() { return 3 9 }
fun <> = main() { <d,k> : p() ? d k }'
t "bare return is empty list" "0.0" 'fun <> = f() { return }
fun <> = main() { x : f() ? x }'
t "multi-assign vs empty return" "Undefined variable 'a'" 'fun <> = f() { return }
fun <> = main() { <a> : f() ? a }'
t "shortfall left untouched" "7.0" 'fun <> = f() { return }
fun <> = main() { a : 7 <a> : f() ? a }'
t "fewer returned warns" "returned 1, expected 2" 'fun <> = f() { return 1 }
fun <> = main() { b : 5 <a,b> : f() ? a b }'
t "more returned warns" "returned 3, expected 1" 'fun <> = f() { return 1 2 3 }
fun <> = main() { <a> : f() ? a }'
t "builtin single multi-assign" "4.0" 'fun <> = main() { <s> : sqrt(16) ? s }'
t "builtin arity warn" "returned 1, expected 2" 'fun <> = main() { <s,t> : sqrt(16) ? s }'

# ------------------------------------------------------ 6 strings degrade to 0.0
t "string RHS becomes 0.0" "0.0" 'fun <> = main() { x : "hello" ? x }'
t "string in arithmetic" "1.0" 'fun <> = main() { ? 1 + "a" }'
t "string is falsy" "2.0" 'fun <> = main() { if "a" { ? 1 } else { ? 2 } }'
t "string as user fn arg" "0.0" 'fun <r> = f(a) { return a }
fun <> = main() { ? f("hi") }'
t "returned string" "0.0" 'fun <r> = f() { return "a" }
fun <> = main() { ? f() }'
t "string prints literally" "ok" 'fun <> = main() { ? "ok" }'
t "non-ASCII allowed in string" "wörld" 'fun <> = main() { ? "héllo wörld" }'

# -------------------------------------------------------- 2.2 lexer / ASCII rule
t "underscore identifier" "7.0" 'fun <> = main() { _foo : 7 ? _foo }'
t "digits inside identifier" "3.0" 'fun <> = main() { x1 : 3 ? x1 }'
t "keywords case-insensitive" "yes" 'fun <> = main() { x : 1 IF x > 0 { ? "yes" } }'
t "Cyrillic homoglyph rejected" "U+0445" 'fun <> = main() { хn : 5 ? xn }'
t "Greek homoglyph rejected" "U+039F" 'fun <> = main() { Ο : 5 ? O }'
t "unknown character rejected" "U+0040" 'fun <> = main() { x @ : 5 ? x }'

# ------------------------------------------------------------ statements / control
t "hello world" "Hello world!" 'fun <>=main() {
   ? "Hello world!"
}'
t "compound assign +:" "6.0" 'fun <> = main() { x : 5 x +: 1 ? x }'
t "compound assign -:" "4.0" 'fun <> = main() { x : 5 x -: 1 ? x }'
t "if / elseif / else" "mid" 'fun <> = main() { x : 5 if x > 9 { ? "hi" } elseif x > 2 { ? "mid" } else { ? "lo" } }'
t "while loop" "1.0 2.0 3.0" 'fun <> = main() { i : 1 while i < 4 { ! i i +: 1 } }'
t "for loop" "1.0 2.0 3.0" 'fun <> = main() { for i:1 to 3 { ! i } }'
t "for loop with step" "1.0 3.0 5.0" 'fun <> = main() { for i:1 to 5 step 2 { ! i } }'
t "return out of if" "9.0" 'fun <r> = f(n) { if n > 0 { return 9 } return 1 }
fun <> = main() { ? f(5) }'
t "return out of while" "3.0" 'fun <r> = f() { i : 0 while i < 9 { i +: 1 if i = 3 { return i } } return 0 }
fun <> = main() { ? f() }'
t "quadratic program" "Solution 1.0 1.0" 'fun <> = main() {
   a : 1
   b : -2
   c : 1
   d : b^2-4*a*c
   if d < 0 { ? "No real roots" }
   else { d : sqrt(d) x1 : (-b-d)/(2*a) x2 : (-b+d)/(2*a) ? "Solution" x1 x2 }
}'

# ----------------------------------------------------- parser regressions guarded
# Each of these failed at some point during the parser refactor; they are the
# reason this file exists.
t "REG return before }" "1.0" 'fun <r> = f() { return 1 }
fun <> = main() { ? f() }'
t "REG bare call statement" "9.0" 'fun <r> = f() { return 1 }
fun <> = main() { f() ? 9 }'
t "REG = fallback assignment" "5.0" 'fun <> = main() { x = 5 ? x }'
t "REG print starting with -" "4.0" 'fun <> = main() { ? -2^2 }'
t "REG print starting with (" "3.0" 'fun <> = main() { ? (1+2) }'
t "REG parseError reaches caller" "PARSE:" 'fun <> = main() { x : * 5 }'

# ------------------------------------------------------------------- precedence
t "power is right-associative" "512.0" 'fun <> = main() { ? 2^3^2 }'
t "unary minus binds over ^" "4.0" 'fun <> = main() { x : -2^2 ? x }'
t "inline print !" "hello world" 'fun <> = main() { ! "hello" ! "world" }'
t "mixed string and numbers" "Solution 3.0 5.0" 'fun <> = main() { x:3 y:5 ? "Solution" x y }'

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
SNIPPETS

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
