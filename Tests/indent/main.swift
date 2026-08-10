//
//  main.swift
//  Shalimar indent tests
//
//  Exercises Shalimar/Indent.swift, which decides where a brace and the line after it
//  belong. Indent avoids UIKit so this can run as a plain command-line binary, the same
//  way the language core and ScanLayout do - Tests/regression.sh compiles and runs all
//  three and folds their counts into one number.
//
//  Cases are written as the editor sees them: a document with the caret marked ‸, a
//  keystroke, and the document that should come back. That is the level the bug lived
//  at - every piece underneath was individually right.
//

import Foundation

var pass = 0
var fail = 0

func check(_ name: String, _ got: String, _ want: String) {
    if got == want {
        pass += 1
    } else {
        fail += 1
        print("FAIL: \(name)")
        print("      want: \(want.replacingOccurrences(of: "\n", with: "⏎"))")
        print("      got:  \(got.replacingOccurrences(of: "\n", with: "⏎"))")
    }
}

func checkInt(_ name: String, _ got: Int, _ want: Int) {
    if got == want {
        pass += 1
    } else {
        fail += 1
        print("FAIL: \(name)\n      want: \(want)\n      got:  \(got)")
    }
}

/// Types `text` at the caret marked ‸ and returns the document that results - the laid-out
/// edit where Indent asks for one, and the plain insertion where it returns nil, which is
/// exactly what the view controller does with the two answers.
func typing(_ text: String, in marked: String) -> String {
    guard let caret = marked.range(of: "‸") else { return "no caret in fixture" }
    let document = marked.replacingOccurrences(of: "‸", with: "") as NSString
    let location = marked.distance(from: marked.startIndex, to: caret.lowerBound)
    let range = NSRange(location: location, length: 0)

    if let edit = Indent.insertion(of: text, into: document, replacing: range) {
        return document.replacingCharacters(in: edit.range, with: edit.text)
    }
    return document.replacingCharacters(in: range, with: text)
}

// ------------------------------------------------------------------ brace counting

let counts = Indent.braceCounts(in: "   } else {")
checkInt("a line can both close and open, opens",  counts.opens, 1)
checkInt("a line can both close and open, closes", counts.closes, 1)
checkInt("only the leading } pulls the line out",  counts.leadingCloses, 1)

// A } after code on the line is not what dedents that line - `x : 1 }` closes a group
// but the line itself still belongs where it started.
checkInt("a } after code does not lead", Indent.braceCounts(in: "x : 1 }").leadingCloses, 0)

// The lexer has no escapes, so the first quote closes the string. A brace inside one is
// text, and so is anything after //.
checkInt("braces in a string are text",  Indent.braceCounts(in: #"? "{ }""#).opens, 0)
checkInt("braces in a comment are text", Indent.braceCounts(in: "x : 1 // { {").opens, 0)
checkInt("a quote inside a comment does not open a string",
         Indent.braceCounts(in: #"// don"t {"#).opens, 0)

checkInt("depth counts nesting", Indent.braceDepth(of: "fun <> = main() {\n   if x {\n"), 2)
checkInt("a pair on one line is net zero",
         Indent.braceDepth(of: "fun <> = main() {\n   if n < 2 { return 1 }\n"), 1)
checkInt("depth never goes below zero", Indent.braceDepth(of: "}\n}\n}"), 0)

// ------------------------------------------------------------------ whole-file layout

check("reindent lays a program out by depth",
      Indent.reindented("fun <> = main() {\n? \"hi\"\nif x {\ny : 1\n}\n}"),
      "fun <> = main() {\n   ? \"hi\"\n   if x {\n      y : 1\n   }\n}")

check("a closing brace settles under the line that opened its group",
      Indent.reindented("fun <> = main() {\nif x {\ny : 1\n}\n}"),
      "fun <> = main() {\n   if x {\n      y : 1\n   }\n}")

check("existing indentation is discarded, not respected",
      Indent.reindented("         fun <> = main() {\n  ? \"hi\"\n}"),
      "fun <> = main() {\n   ? \"hi\"\n}")

check("blank lines stay blank rather than collecting spaces",
      Indent.reindented("fun <> = main() {\n\n   ? \"hi\"\n}"),
      "fun <> = main() {\n\n   ? \"hi\"\n}")

check("a pair written on one line is left on one line",
      Indent.reindented("fun <> = main() {\nif n < 2 { return 1 }\n}"),
      "fun <> = main() {\n   if n < 2 { return 1 }\n}")

// ------------------------------------------------------------------ pressing return

// The bug this file was extracted for. The caret sits between the body and the } that
// closes the same line; the brace it pushes down belongs under the `if`, not under the
// body the `if` opened.
check("a brace pushed off a one-line pair lands under the line it closes",
      typing("\n", in: "fun <> = main() {\n   if n < 2 { return 1 ‸}\n}"),
      "fun <> = main() {\n   if n < 2 { return 1 \n   }\n}")

check("the same at two levels deep",
      typing("\n", in: "fun <> = main() {\n   if x {\n      if y { z : 1 ‸}\n   }\n}"),
      "fun <> = main() {\n   if x {\n      if y { z : 1 \n      }\n   }\n}")

// The guard against over-correcting: a } that already has a line to itself must stay in
// its column, not walk one level left each time return is pressed in front of it.
check("a brace already on its own line keeps its column",
      typing("\n", in: "fun <> = main() {\n   if x {\n      y : 1\n   ‸}\n}"),
      "fun <> = main() {\n   if x {\n      y : 1\n   \n   }\n}")

check("return after an opening brace steps in",
      typing("\n", in: "fun <> = main() {‸"),
      "fun <> = main() {\n   ")

check("return inside a body holds the body's level",
      typing("\n", in: "fun <> = main() {\n   ? \"hi\"‸"),
      "fun <> = main() {\n   ? \"hi\"\n   ")

check("return at the top level adds no indent",
      typing("\n", in: "fun <> = main() {\n}‸"),
      "fun <> = main() {\n}\n")

check("a } two levels in pushes down to one",
      typing("\n", in: "fun <> = main() {\n   if x { y : 1 ‸}\n}"),
      "fun <> = main() {\n   if x { y : 1 \n   }\n}")

// ------------------------------------------------------------------ typing a brace

check("a } typed at the head of a line pulls that line out",
      typing("}", in: "fun <> = main() {\n   if x {\n      y : 1\n      ‸"),
      "fun <> = main() {\n   if x {\n      y : 1\n   }")

check("a } typed mid-line is left where it fell",
      typing("}", in: "real a[2][2] : {{1.0, 2.0}, {3.0, 4.0‸"),
      "real a[2][2] : {{1.0, 2.0}, {3.0, 4.0}")

check("a } already in the right column is not rewritten",
      typing("}", in: "fun <> = main() {\n   if x {\n      y : 1\n   ‸"),
      "fun <> = main() {\n   if x {\n      y : 1\n   }")

check("a } closing the outermost group goes to column zero",
      typing("}", in: "fun <> = main() {\n   ? \"hi\"\n      ‸"),
      "fun <> = main() {\n   ? \"hi\"\n}")

// ------------------------------------------------------------------ edges

check("an empty document survives a return", typing("\n", in: "‸"), "\n")
check("a caret at the very end is in range",
      typing("\n", in: "fun <> = main() {\n}\n‸"),
      "fun <> = main() {\n}\n\n")

// What the editor does with a laid-out edit has to be idempotent with what reindent
// would do to the same file, or a reindent silently moves what was just typed.
let afterReturn = typing("\n", in: "fun <> = main() {\n   if n < 2 { return 1 ‸}\n}")
check("the result agrees with a full reindent",
      Indent.reindented(afterReturn),
      "fun <> = main() {\n   if n < 2 { return 1\n   }\n}")

print("indent: PASS: \(pass)   FAIL: \(fail)")
exit(fail == 0 ? 0 : 1)
