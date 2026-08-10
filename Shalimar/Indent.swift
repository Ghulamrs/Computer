//
//  Indent.swift
//  Shalimar
//
//  Brace-directed layout for the editor: how deep a line sits, how a whole program is
//  laid out, and what edit a typed newline or } should become.
//
//  No UIKit here, deliberately. Every rule is text in, text out - a document, a caret,
//  an edit - so Tests/regression.sh can exercise them as a command-line binary. It is
//  worth the separation: the one bug this logic has had, a brace pushed down from
//  `if n < 2 { return 1 }` landing a level too deep, could only be found by typing into
//  a simulator and looking, because nothing here was reachable from a test. ScanLayout
//  is kept apart from UIKit for the same reason.
//

import Foundation

enum Indent {
    // Three spaces a level, which is what the phone column can afford: at 14pt a line
    // holds about 39 characters, so a wider step pushes nested bodies into wrapping.
    static let width = 3

    // Braces opened and closed on one line, ignoring any that are not structure: a brace
    // inside a string or after // is text. No escape handling, because the lexer has no
    // escapes - its pattern is "[^"\n]*", so the first quote on the line closes.
    // leadingCloses counts only the braces before anything else on the line; those are
    // what pull the line itself back out a level.
    static func braceCounts(in line: String) -> (opens: Int, closes: Int, leadingCloses: Int) {
        var opens = 0, closes = 0, leadingCloses = 0
        var atLineHead = true
        var inString = false
        var previous: Character?

        for char in line {
            if inString {
                if char == "\"" { inString = false }
                previous = char
                continue
            }
            if char == "\"" {
                inString = true
                atLineHead = false
                previous = char
                continue
            }
            if char == "/" && previous == "/" { break }

            switch char {
            case "{":
                opens += 1
                atLineHead = false
            case "}":
                closes += 1
                if atLineHead { leadingCloses += 1 }
            default:
                if !char.isWhitespace { atLineHead = false }
            }
            previous = char
        }

        return (opens, closes, leadingCloses)
    }

    // How deep in braces the text ends up - the level a line appended to it belongs at.
    static func braceDepth(of source: String) -> Int {
        var depth = 0
        for line in source.components(separatedBy: "\n") {
            let counts = braceCounts(in: line)
            depth = max(0, depth + counts.opens - counts.closes)
        }
        return depth
    }

    // Lays the whole program out by brace depth. Existing leading space is discarded
    // rather than respected: the point is to impose one consistent step, and a file
    // typed on the phone or arriving from the scanner has no indentation worth keeping.
    static func reindented(_ source: String) -> String {
        var depth = 0
        var out = [String]()

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                out.append("")
                continue
            }

            let counts = braceCounts(in: line)
            // Dedent before writing, so a line that opens with } settles under the line
            // that opened its group rather than under the group's contents.
            let level = max(0, depth - counts.leadingCloses)
            out.append(String(repeating: " ", count: level * width) + line)
            depth = max(0, depth + counts.opens - counts.closes)
        }

        return out.joined(separator: "\n")
    }

    // The edit that lays `text` out at its brace level, or nil when what was typed
    // already sits where it belongs and can be inserted untouched.
    //
    // NSRange offsets are UTF-16, so the document is measured as NSString throughout
    // rather than by Character - the two disagree the moment anything non-ASCII lands in
    // the buffer, and the keyboard traits do not guarantee it cannot.
    static func insertion(of text: String,
                          into document: NSString,
                          replacing range: NSRange) -> (text: String, range: NSRange)? {
        guard range.location <= document.length,
              NSMaxRange(range) <= document.length else { return nil }
        let head = document.substring(to: range.location)

        if text == "\n" {
            var depth = braceDepth(of: head)

            // A } waiting on the other side of the caret closes the group the caret is
            // standing in, so the line it is about to begin belongs one step out - under
            // the line that opened the group, not under its contents. Without this, the
            // pair written on one line, `if n < 2 { return 1 }`, sends its closing brace
            // to the depth of the body when it is pushed down: one step right of the `if`
            // it closes, and one step right of where reindented() would put it.
            let tail = document.substring(from: NSMaxRange(range))
            if tail.drop(while: { $0 == " " || $0 == "\t" }).first == "}" {
                depth = max(0, depth - 1)
            }

            guard depth > 0 else { return nil }
            return ("\n" + String(repeating: " ", count: depth * width), range)
        }

        // A } only moves its line when nothing precedes it there; typed mid-line, as in
        // an array literal closing where it opened, it is left exactly where it fell.
        let lineStart = (head as NSString).range(of: "\n", options: .backwards).location
        let start = lineStart == NSNotFound ? 0 : lineStart + 1
        let onLine = document.substring(with: NSRange(location: start, length: range.location - start))
        guard onLine.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }

        let depth = max(0, braceDepth(of: document.substring(to: start)) - 1)
        let replacement = String(repeating: " ", count: depth * width) + "}"
        guard replacement != onLine + "}" else { return nil }
        return (replacement, NSRange(location: start, length: NSMaxRange(range) - start))
    }
}
