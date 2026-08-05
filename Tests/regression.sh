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
fun <> = main() { <a,b,c> : f() 
? a b c }'
t "fall off end, <x> unassigned" "0.0" 'fun <x> = f() { y : 9 }
fun <> = main() { 
? f() }'
t "fall off end, <x> assigned" "7.0" 'fun <x> = f() { x : 7 }
fun <> = main() { 
? f() }'
t "fresh local scope" "Undefined variable 'k'" 'fun <r> = f() { return k }
fun <> = main() { k : 5 
? f() }'
t "main() may not take inputs" "expects 1 arguments" 'fun <> = main(n) { 
? 1 }'
t "duplicate definition" "already defined" 'fun <> = g() { return 1 }
fun <> = g() { return 2 }
fun <> = main() { 
? g() }'
t "unused function warns" "defined but never called" 'fun <> = unused() { return 1 }
fun <> = main() { 
? 42 }'

# --------------------------------------------------------------- 5.6 calls / args
t "builtin beats user fn" "4.0" 'fun <r> = sqrt(x) { return 999 }
fun <> = main() { 
? sqrt(16) }'
t "builtin rejects string arg" "must be a number" 'fun <> = main() { 
? sqrt("hi") }'
# Under-supplying a builtin used to trap on args[0] and take the whole app down
# (SIGTRAP, uncatchable, no diagnostic) - it must be a normal caught EvalError.
t "builtin too few args, 1-arity" "expects 1 arguments, got 0" 'fun <> = main() { 
? sqrt() }'
t "builtin too few args, 2-arity" "expects 2 arguments, got 1" 'fun <> = main() { 
? pow(2) }'
t "builtin too few args, zero-arity call" "expects 2 arguments, got 0" 'fun <> = main() { 
? atan2() }'
# Reported through the normal output path rather than trapping: earlier output survives
# and the error follows it, instead of the process dying with nothing printed at all.
# (Double space is real: "?" emits a trailing space per item per 5.10, and the harness
# folds the newline into another space.)
t "builtin under-supply reports, not traps" "before  Error: line 3: Function 'min'" 'fun <> = main() {
? "before" 
? min(1) }'
t "builtin extra args warn, still run" "extra args provided" 'fun <> = main() { 
? sqrt(16,99) }'
t "builtin extra args use the first" "4.0" 'fun <> = main() { 
? sqrt(16,99) }'
t "too few args errors" "expects 2 arguments, got 1" 'fun <r> = f(a,b) { return a+b }
fun <> = main() { 
? f(1) }'
t "extra args warn, still run" "extra args provided" 'fun <r> = f(a) { return a }
fun <> = main() { 
? f(1,2) }'
t "zero args supplied" "expects 1 arguments, got 0" 'fun <r> = f(a) { return a }
fun <> = main() { 
? f() }'
t "expression as argument" "9.0" 'fun <r> = f(a) { return a }
fun <> = main() { 
? f(4+5) }'
t "nested call as argument" "5.0" 'fun <r> = f(a) { return a }
fun <> = main() { 
? f(f(5)) }'
t "arguments are by value" "1.0" 'fun <r> = f(a) { a : 99 return 0 }
fun <> = main() { x : 1 f(x) 
? x }'
t "recursion" "120.0" 'fun <r> = fact(n) { if n < 2 { return 1 } return n*fact(n-1) }
fun <> = main() { 
? fact(5) }'

# Recursion depth: unbounded recursion overflows the native stack (SIGSEGV, uncatchable,
# no output). Per-function cap is 256/(inputs+1); a total-frames backstop covers mutual
# recursion, where no single function ever approaches its own cap.
t "1-arg recursion at limit ok" "0.0" 'fun <r> = d(n) { if n < 1 { return 0 } return d(n-1) }
fun <> = main() { 
? d(127) }'
t "1-arg recursion over limit" "Recursion too deep in 'd' (limit 128)" 'fun <r> = d(n) { if n < 1 { return 0 } return d(n-1) }
fun <> = main() { 
? d(128) }'
t "0-arg recursion limit 256" "Recursion too deep in 'z' (limit 256)" 'fun <r> = z() { return z() }
fun <> = main() { 
? z() }'
t "3-arg recursion limit 64" "Recursion too deep in 'w' (limit 64)" 'fun <r> = w(a,b,c) { return w(a,b,c) }
fun <> = main() { 
? w(1,2,3) }'
t "sequential calls unaffected" "2000.0" 'fun <r> = f(n) { return 1 }
fun <> = main() { s : 0 for i:1 to 2000 { s +: f(i) } 
? s }'
t "mutual recursion backstop" "Call stack too deep (limit 1024)" 'fun <r> = a() { return b() }
fun <r> = b() { return c() }
fun <r> = c() { return d() }
fun <r> = d() { return e() }
fun <r> = e() { return a() }
fun <> = main() { 
? a() }'
t "runaway recursion reports, not crashes" "before  Runtime error: line 1: Recursion too deep" 'fun <r> = d(n) { return d(n+1) }
fun <> = main() { 
? "before" 
? d(1) }'
# Depth is per-frame, not a lifetime tally: the counter must come back down on the throwing
# path too, or an earlier caught-and-reported failure would poison every later call.
t "depth unwinds after return" "0.0  0.0" 'fun <r> = d(n) { if n < 1 { return 0 } return d(n-1) }
fun <> = main() { 
? d(120) 
? d(120) }'
t "multi-argument call" "7.0" 'fun <r> = f(a,b) { return a+b }
fun <> = main() { 
? f(3,4) }'

# ------------------------------------------------- 7 results / multi-assign arity
t "plain assign takes first" "25.0" 'fun <r> = sq(x) { return x*x }
fun <> = main() { y : sq(5) 
? y }'
t "call inline in expression" "10.0" 'fun <r> = sq(x) { return x*x }
fun <> = main() { 
? 1 + sq(3) }'
t "bare call is not a return" "5.0" 'fun <r> = sq(x) { return x*x }
fun <> = main() { sq(4) 
? 5 }'
t "multi-assign captures both" "3.0 9.0" 'fun <m,i> = p() { return 3 9 }
fun <> = main() { <d,k> : p() 
? d k }'
t "bare return is empty list" "0.0" 'fun <> = f() { return }
fun <> = main() { x : f() 
? x }'
t "multi-assign vs empty return" "Undefined variable 'a'" 'fun <> = f() { return }
fun <> = main() { <a> : f() 
? a }'
t "shortfall left untouched" "7.0" 'fun <> = f() { return }
fun <> = main() { a : 7 <a> : f() 
? a }'
t "fewer returned warns" "returned 1, expected 2" 'fun <> = f() { return 1 }
fun <> = main() { b : 5 <a,b> : f() 
? a b }'
t "more returned warns" "returned 3, expected 1" 'fun <> = f() { return 1 2 3 }
fun <> = main() { <a> : f() 
? a }'
t "builtin single multi-assign" "4.0" 'fun <> = main() { <s> : sqrt(16) 
? s }'
t "builtin arity warn" "returned 1, expected 2" 'fun <> = main() { <s,t> : sqrt(16) 
? s }'

# ------------------------------------------------------ 6 strings degrade to 0.0
t "string RHS becomes 0.0" "0.0" 'fun <> = main() { x : "hello" 
? x }'
t "string in arithmetic" "1.0" 'fun <> = main() { 
? 1 + "a" }'
t "string is falsy" "2.0" 'fun <> = main() { if "a" { 
? 1 } else { 
? 2 } }'
t "string as user fn arg" "0.0" 'fun <r> = f(a) { return a }
fun <> = main() { 
? f("hi") }'
t "returned string" "0.0" 'fun <r> = f() { return "a" }
fun <> = main() { 
? f() }'
t "string prints literally" "ok" 'fun <> = main() { 
? "ok" }'
t "non-ASCII allowed in string" "wörld" 'fun <> = main() { 
? "héllo wörld" }'

# -------------------------------------------------------- 2.2 lexer / ASCII rule
t "underscore identifier" "7.0" 'fun <> = main() { _foo : 7 
? _foo }'
t "digits inside identifier" "3.0" 'fun <> = main() { x1 : 3 
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
t "malformed number rejected" "Malformed number '1.2.3'" 'fun <> = main() { 
? 1.2.3 }'
t "malformed number in expression" "Malformed number '0.0.1'" 'fun <> = main() { x : 0.0.1 + 2 
? x }'
t "trailing dot is not malformed" "1.0" 'fun <> = main() { 
? 1. }'

# ------------------------------------------------------------ statements / control
t "hello world" "Hello world!" 'fun <>=main() {
   ? "Hello world!"
}'
t "compound assign +:" "6.0" 'fun <> = main() { x : 5 x +: 1 
? x }'
t "compound assign -:" "4.0" 'fun <> = main() { x : 5 x -: 1 
? x }'
t "if / elseif / else" "mid" 'fun <> = main() { x : 5 if x > 9 { 
? "hi" } elseif x > 2 { 
? "mid" } else { 
? "lo" } }'
t "while loop" "1.0 2.0 3.0" 'fun <> = main() { i : 1 while i < 4 { 
?? i i +: 1 } }'
t "for loop" "1.0 2.0 3.0" 'fun <> = main() { for i:1 to 3 { 
?? i } }'
t "for loop with step" "1.0 3.0 5.0" 'fun <> = main() { for i:1 to 5 step 2 { 
?? i } }'
t "for loop counts down" "3.0 2.0 1.0" 'fun <> = main() { for i:3 to 1 step 0-1 { 
?? i } }'
t "for bounds truncate toward zero" "1.0 2.0" 'fun <> = main() { for i:1 to 2.9 { 
?? i } }'
t "zero step errors" "Step value cannot be zero" 'fun <> = main() { for i:1 to 5 step 0 { 
?? i } }'
# Int(Double) traps - uncatchably - on NaN/infinity/out-of-range, and a builtin result
# reaches these bounds directly. Each of these used to kill the process with no output.
t "NaN loop end" "Loop end out of range" 'fun <> = main() { for i:1 to sqrt(0-1) { 
?? i } }'
t "infinite loop end" "Loop end out of range" 'fun <> = main() { for i:1 to 1/0 { 
?? i } }'
t "NaN loop start" "Loop start out of range" 'fun <> = main() { for i:0/0 to 5 { 
?? i } }'
t "NaN loop step" "Loop step out of range" 'fun <> = main() { for i:1 to 5 step 0/0 { 
?? i } }'
t "out-of-Int-range loop end" "Loop end out of range" 'fun <> = main() { for i:1 to pow(10,400) { 
?? i } }'
t "bad bound reports, not traps" "before  Runtime error: line 2: Loop end" 'fun <> = main() {
? "before" for i:1 to 0/0 { 
?? i } }'
t "return out of if" "9.0" 'fun <r> = f(n) { if n > 0 { return 9 } return 1 }
fun <> = main() { 
? f(5) }'
t "return out of while" "3.0" 'fun <r> = f() { i : 0 while i < 9 { i +: 1 if i = 3 { return i } } return 0 }
fun <> = main() { 
? f() }'
t "quadratic program" "Solution 1.0 1.0" 'fun <> = main() {
   a : 1
   b : -2
   c : 1
   d : b^2-4*a*c
   if d < 0 { 
? "No real roots" }
   else { d : sqrt(d) x1 : (-b-d)/(2*a) x2 : (-b+d)/(2*a) 
? "Solution" x1 x2 }
}'

# ----------------------------------------------------- parser regressions guarded
# Each of these failed at some point during the parser refactor; they are the
# reason this file exists.
t "REG return before }" "1.0" 'fun <r> = f() { return 1 }
fun <> = main() { 
? f() }'
t "REG bare call statement" "9.0" 'fun <r> = f() { return 1 }
fun <> = main() { f() 
? 9 }'
t "REG = fallback assignment" "5.0" 'fun <> = main() { x = 5 
? x }'
t "REG print starting with -" "4.0" 'fun <> = main() { 
? -2^2 }'
t "REG print starting with (" "3.0" 'fun <> = main() { 
? (1+2) }'
t "REG parseError reaches caller" "PARSE:" 'fun <> = main() { x : * 5 }'

# ------------------------------------------------------------------- precedence
t "power is right-associative" "512.0" 'fun <> = main() { 
? 2^3^2 }'
t "unary minus binds over ^" "4.0" 'fun <> = main() { x : -2^2 
? x }'
t "inline print ??" "hello world" 'fun <> = main() {
?? "hello"
?? "world" }'
t "mixed string and numbers" "Solution 3.0 5.0" 'fun <> = main() { x:3 y:5
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
t "command after item list" "must be the first thing on its line" 'fun <> = main() { x : 1
? "hello" ?? x }'
# Indentation is invisible here - the lexer drops it before the parser sees a line at all.
t "indented command is fine" "5.0" 'fun <> = main() {
     x : 5
        ? x
}'
# The very first token of the file has no predecessor to compare lines against, and must
# still count as starting its line. Asserted via main(): a parse error here runs nothing.
t "command first in file" "7.0" '? 9
fun <> = main() {
? 7 }'
# "!" lost its print role to "??" and is now only the first half of "!=".
t "bare ! is not a command" "'!' is not a command" 'fun <> = main() { x : 1
! x }'
t "! keeps != intact" "1.0" 'fun <> = main() { x : 1
? x != 2 }'
t "!= is not two commands" "0.0" 'fun <> = main() {
? 2 != 2 }'

# ------------------------------------------------------- 10 error line reporting
# Lex, parse and runtime errors all name the line. Blank lines and comments count, so
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
t "runtime error names line" "Error: line 4: Undefined variable" 'fun <> = main() {
 x : 1
 y : 2
 ? zz
}'
# The line reported is the innermost statement executing, so an error inside a callee
# names the callee's line rather than the call site's.
t "runtime line is the callee's" "Error: line 2: Undefined variable 'qq'" 'fun <r> = f() {
 return qq
}
fun <> = main() {
 ? f()
}'
# Nothing was executing, so there is no line to name - and none is invented.
t "no main has no line" "Runtime error: No main() function defined" 'fun <> = g() { return 1 }'
t "redefinition names line" "Runtime error: line 2: Function 'g' already defined" 'fun <> = g() { return 1 }
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
SNIPPETS

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
