//
//  Indent.swift
//  Shalimar
//
//  Brace-directed layout for the editor: how deep a line sits, how a whole program is
//  laid out, and what edit a typed newline, a }, or an arriving paste should become.
//  One rule here is not about indentation at all - the keyboard's double-space period -
//  and lives beside the others because it is the same kind of thing: an edit the editor
//  has to rewrite before it lands, decided from text alone.
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

    // The edit that lays arriving text out at the level it lands in, or nil for text that
    // should go in exactly as it came.
    //
    // Text that arrives in one edit and is longer than a keystroke is a paste, and it
    // brings someone else's indentation with it. From the reference that is six columns
    // of it - every code line there is indented to sit inside the prose - and pasted into
    // the editor it kept them, which is neither the level it belongs at nor a step anything
    // else in the document uses. It is laid out here exactly the way reindented() lays out
    // a whole program, but counting from the depth the caret is standing in rather than
    // from zero, so a body pasted inside a function lands inside it.
    //
    // Two cases are deliberately left alone. A single line dropped into the middle of an
    // existing one is a fragment, and its leading space may be the whole point of it; and
    // a blank line inside the paste stays blank rather than collecting trailing space.
    static func paste(of text: String,
                      into document: NSString,
                      replacing range: NSRange) -> (text: String, range: NSRange)? {
        guard range.location <= document.length,
              NSMaxRange(range) <= document.length else { return nil }

        // One character is a keystroke, never a paste - and a typed space must stay a
        // space, or the space bar would stop working at the head of a line.
        guard text.count > 1,
              text.contains("\n") || text.first == " " || text.first == "\t" else { return nil }

        let head = document.substring(to: range.location)
        let newline = (head as NSString).range(of: "\n", options: .backwards).location
        let lineStart = newline == NSNotFound ? 0 : newline + 1
        let onLine = document.substring(with: NSRange(location: lineStart,
                                                     length: range.location - lineStart))
        let atLineHead = onLine.allSatisfy { $0 == " " || $0 == "\t" }

        var lines = text.components(separatedBy: "\n")
        guard atLineHead || lines.count > 1 else { return nil }

        var out = [String]()
        var depth: Int
        var editStart: Int

        if atLineHead {
            // The space already on the line is the editor's own indent, not the paste's.
            // Taking it into the edit rather than adding to it is what lets the first
            // pasted line be measured the same way as the ones after it.
            editStart = lineStart
            depth = braceDepth(of: document.substring(to: lineStart))
        } else {
            // Mid-line: the first pasted line finishes the line that is already there, so
            // it goes in untouched and only what follows a newline is laid out.
            editStart = range.location
            let first = lines.removeFirst()
            out.append(first)
            depth = braceDepth(of: head + first)
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                out.append("")
                continue
            }
            let counts = braceCounts(in: line)
            let level = max(0, depth - counts.leadingCloses)
            out.append(String(repeating: " ", count: level * width) + line)
            depth = max(0, depth + counts.opens - counts.closes)
        }

        // A paste ending in a newline leaves the caret on a line of its own. It gets the
        // indent Return would have given it, so typing carries on in column instead of
        // restarting at zero under the text that just arrived.
        if out.last == "" && out.count > 1 && depth > 0 {
            out[out.count - 1] = String(repeating: " ", count: depth * width)
        }

        let laidOut = out.joined(separator: "\n")
        let prefix = document.substring(with: NSRange(location: editStart,
                                                     length: range.location - editStart))
        // Nothing to correct: let the insertion happen on its own rather than replacing
        // text with itself, which would cost an undo step and move the caret for nothing.
        guard laidOut != prefix + text else { return nil }
        return (laidOut, NSRange(location: editStart, length: NSMaxRange(range) - editStart))
    }

    // What the keyboard's double-space shortcut should have inserted, or nil when the edit
    // is not that shortcut.
    //
    // Two spaces typed in a row are turned by iOS into ". " - a period after the last
    // non-space character. It is the right thing in prose and wrong in every program: the
    // period lands against a name, and Shalimar reads that as an attribute, so a line that
    // was being typed correctly fails to lex. The keyboard traits set in viewDidLoad do not
    // switch it off; autocorrection and smart punctuation are separate settings from this
    // one, which is why it has to be caught as an edit.
    //
    // The shortcut is recognized by its exact shape - ". " arriving over, or straight
    // after, a single space that itself follows something that is not a space. A pasted
    // ". " that happens to land the same way is indistinguishable from it and becomes two
    // spaces; that is the cost of the rule, and it is a far smaller surprise than a period
    // appearing in the middle of a program.
    static func spacesForSentencePeriod(in document: NSString,
                                        replacing range: NSRange,
                                        with text: String) -> String? {
        guard text == ". ", NSMaxRange(range) <= document.length else { return nil }

        func isSpace(_ location: Int) -> Bool {
            guard location >= 0, location < document.length else { return false }
            return document.substring(with: NSRange(location: location, length: 1)) == " "
        }
        // Nothing at all before the space is the start of the document, where the shortcut
        // does not fire; a second space before it means the run was already broken.
        func opensTheRun(_ location: Int) -> Bool {
            guard location >= 0, location < document.length else { return false }
            let character = document.substring(with: NSRange(location: location, length: 1))
            return character != " " && character != "\n" && character != "\t"
        }

        // The shortcut replaces the space it ate, and puts the period where that space was.
        if range.length == 1, isSpace(range.location), opensTheRun(range.location - 1) {
            return "  "
        }
        // The same thing spelled as an insertion after the space, which is how it arrives
        // when the keyboard leaves the space in place.
        if range.length == 0, isSpace(range.location - 1), opensTheRun(range.location - 2) {
            return " "
        }
        return nil
    }
}
