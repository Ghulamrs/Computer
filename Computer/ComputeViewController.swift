//
//  ComputeViewController.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 5/21/19.
//  Copyright © 2019 Home. All rights reserved.
//

import UIKit
import Messages
import MessageUI
import VisionKit
import Vision

class ComputeViewController: UIViewController, Storyboarded, UITextViewDelegate, VNDocumentCameraViewControllerDelegate {
    weak var coordinator: MainCoordinator?
    @IBOutlet var lineview: UITextView!
    @IBOutlet var program: UITextView!
    @IBOutlet var console: UITextView!
    var count: Int = 0
    var source: String {
        """
        fun <> = main() {
           ? "Hello world!"
        }
        """
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // SF Mono, which has no name to pass to UIFont(name:) on iOS - the system API is
        // the only way to reach it. Set before lineview copies it below so the gutter and
        // the editor keep the same line height and the numbers stay on their lines.
        program.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)

        // Grey, a shade darker than the 0.75 the gutter carried against its old white
        // strip: the numbers are reference, not code, so they should sit behind the
        // violet without disappearing - 0.60 reads about 2.9:1 on white, where 0.75 was
        // 1.8:1 and hard to count down in daylight.
        lineview.textColor = UIColor.init(white: 0.6, alpha: 1)
        lineview.font = program.font
        lineview.isScrollEnabled = true
        // The gutter is a mirror, never a control. Left touchable it was its own scroll
        // view: a stray finger could drag the numbers out of line with the code, and the
        // offset it was handed back each frame fought that drag instead of following it.
        // Its own bounce stays on so it can be pushed past its bounds by the editor's,
        // which is what keeps a number beside its line through the whole spring.
        lineview.isUserInteractionEnabled = false
        // The gutter is 40pt wide in the storyboard and its numbers are right-aligned, so
        // its own padding is width the digits cannot use. Zeroing it buys back 8pt, about
        // what a fourth digit costs - which the old fixed 1...99 gutter never needed and
        // a growing one does. Four digits measure 34.6pt at 14pt SF Mono, so 38pt of usable
        // width leaves the column room to reach 9999 without a number wrapping - and a
        // wrapped number would push every line below it out of register, not just its own.
        // The vertical inset has to keep matching the editor's, or every number sits off
        // the line it counts.
        lineview.textContainerInset = UIEdgeInsets(top: program.textContainerInset.top, left: 0,
                                                   bottom: program.textContainerInset.bottom, right: 2)
        lineview.textContainer.lineFragmentPadding = 0

        program.delegate = self
        // A short program has nothing to scroll - no bar, no travel - and a view that
        // cannot move under the finger reads as a dead one. The bounce is the answer the
        // page gives back: alwaysBounceVertical keeps it for text shorter than the frame,
        // which is the case where UIScrollView would otherwise ignore the drag entirely.
        // The gutter follows the same offset, so the numbers spring with their lines.
        program.bounces = true
        program.alwaysBounceVertical = true
        // Shalimar source is ASCII and its identifiers are case-sensitive, so iOS's text
        // "helpers" all corrupt a program invisibly: smart quotes replace the " the lexer
        // scans for, smart dashes fuse "--" into an en-dash, and sentence capitalization
        // renames a variable. Set every trait here rather than in the storyboard so this
        // stays the single place the editor's input behaviour is defined.
        // .asciiCapable is only a hint - the globe key and pasting both bypass it, so it
        // is a convenience, not a guarantee that the text stays ASCII.
        program.autocapitalizationType = .none
        program.autocorrectionType = .no
        program.spellCheckingType = .no
        program.smartQuotesType = .no
        program.smartDashesType = .no
        program.smartInsertDeleteType = .no
        program.keyboardType = .asciiCapable
        // The mint is back, lightened from 0.8 red to 0.9: enough tint to separate the page
        // from the white column beside it, pale enough that the violet still carries -
        // 4.1:1 here, against 3.9:1 on the original mint and 4.3:1 on plain white.
        program.backgroundColor = UIColor.init(displayP3Red: 0.9, green: 1, blue: 0.975, alpha: 1)
        console.backgroundColor = UIColor.init(white: 0.8, alpha: 0.5)
        // The original violet, deepened to carry at 14pt but not to black - about 4.1:1
        // against the mint background set above. Not .label or a dynamic colour: that
        // background is fixed light, so anything inverting in dark mode would land white
        // on mint.
        program.textColor = Self.codeColour

        // Everything used to be red, which meant red carried no signal - a program's own
        // output shouted and its errors blended into it. Output is now near-black and the
        // colour is spent only where something went wrong.
        console.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        console.textColor = ConsoleStyle.output.color
        console.isScrollEnabled = true
        console.isEditable = false
        if coordinator!.fileURL.isEmpty {
            program.text = Self.reindented(source)
        } else {
            load(fileName: coordinator!.fileURL)
        }
        programChanged()

        let tap2 = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        tap2.numberOfTapsRequired = 2
        console.addGestureRecognizer(tap2)

        let tap1 = UITapGestureRecognizer(target: self, action: #selector(textTapped(_:)))
        tap1.numberOfTapsRequired = 1
        console.addGestureRecognizer(tap1)

        // Both on the right (not left) so the automatic back button stays visible.
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "doc.text.viewfinder"),
                style: .plain, target: self, action: #selector(scanTapped)),
            UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.down"),
                style: .plain, target: self, action: #selector(saveTapped)),
            UIBarButtonItem(image: UIImage(systemName: "questionmark.circle"),
                style: .plain, target: self, action: #selector(helpTapped))
        ]

        // Lives in the nav bar (as titleView, dead center) instead of docked below the
        // editor, so the on-screen keyboard - which covers the bottom of the screen -
        // can never overlap it.
        let arrowConfig = UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        let runButton = UIButton(type: .system)
        runButton.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        runButton.setImage(UIImage(systemName: "arrowshape.right.fill", withConfiguration: arrowConfig), for: .normal)
        runButton.tintColor = UIColor.init(displayP3Red: 0.0, green: 0.7, blue: 0.25, alpha: 1)
        runButton.imageView?.contentMode = .scaleAspectFit
        runButton.addTarget(self, action: #selector(ComputeTapped(_:)), for: .touchUpInside)
        navigationItem.titleView = runButton
    }

    // Where a line wraps depends on the editor's width, so a rotation or a split-view
    // resize changes the row count without changing the text. The guard inside leaves
    // this cheap when nothing moved.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshLineNumbers()
        // Same reason as the numbers: a resize rewraps the text, and a strip cut to the
        // old wrapping would sit over the wrong rows.
        layoutErrorStrips()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // Three levels, in the conventional colours: a reader should not have to learn a
    // private scheme to tell a result from a complaint.
    enum ConsoleStyle {
        case output, warning, error

        var color: UIColor {
            switch self {
            case .output:  return UIColor(white: 0.10, alpha: 1)
            case .warning: return UIColor(displayP3Red: 0.70, green: 0.42, blue: 0.0, alpha: 1)
            case .error:   return UIColor(displayP3Red: 0.75, green: 0.0, blue: 0.05, alpha: 1)
            }
        }
    }

    private func clearConsole() {
        console.attributedText = NSAttributedString(string: "")
        errorLines = []
        layoutErrorStrips()
    }

    private func append(_ text: String, _ style: ConsoleStyle) {
        let font = console.font ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let run = NSAttributedString(string: text,
                                     attributes: [.foregroundColor: style.color, .font: font])
        let all = NSMutableAttributedString(attributedString: console.attributedText
                                            ?? NSAttributedString(string: ""))
        all.append(run)
        console.attributedText = all
        if style == .error, let line = Self.reportedLine(in: text) { errorLines.insert(line) }
    }

    // The four stages report errors in four different types - a String from the lexer, a
    // LocatedParseError, a Diagnostic, a RuntimeError - but every one of them prints as
    // "Error: line N:", and the console text is the one place all four meet. Reading the
    // number back out of the message keeps the strip agreeing with what the user is being
    // told: if the console names a line, that line is what gets marked, and a message
    // without a line (a lex error before any line is known) marks nothing.
    private static func reportedLine(in text: String) -> Int? {
        guard let match = text.range(of: "line [0-9]+", options: .regularExpression) else { return nil }
        return Int(text[match].dropFirst("line ".count))
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if !program.text.isEmpty { self.count = 0 }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard textView === program else { return }
        programChanged()
    }

    // Everything the editor owes its text after that text moves. Both halves read the
    // same characters, so they belong at the same call sites - a highlight without a
    // renumber leaves the column short, and the reverse leaves a new keyword plain.
    private func programChanged() {
        applySyntaxColours()
        refreshLineNumbers()
        // The marks belong to the run that produced them. Once a character moves, line 7
        // is no longer the line the console complained about, so a strip left behind would
        // be pointing at whatever drifted under it.
        errorLines = []
        layoutErrorStrips()
    }

    // Lines the last run reported an error on, and the strips drawn behind them.
    private var errorLines: Set<Int> = []
    private var errorStrips: [UIView] = []

    // Highlighter yellow, the mark a reader already knows: it says "here" without saying
    // anything about severity, which is right when the console beside it is already saying
    // what went wrong. It is the one colour in the editor that belongs to no other level -
    // not the violets of the code, not the mint of the page - so nothing else can be
    // mistaken for it. Bright, but it costs the text nothing: the code holds 4.0:1 on it,
    // which is what it had on the mint, and the keywords 10.6:1.
    static let errorStripColour = UIColor.init(displayP3Red: 1.0, green: 1.0, blue: 0.0, alpha: 1)

    // A strip per reported line, sized from the layout rather than from a line height, so
    // a line that wraps to three rows is covered by one band three rows tall. They go in
    // at index 0, behind the text view's own container view - painted over the text they
    // would wash it out, and as an attribute on the characters they would stop at the last
    // one and leave a ragged right edge instead of a strip.
    private func layoutErrorStrips() {
        errorStrips.forEach { $0.removeFromSuperview() }
        errorStrips = []
        guard !errorLines.isEmpty else { return }

        let source = (program.text ?? "") as NSString
        let layoutManager = program.layoutManager
        layoutManager.ensureLayout(for: program.textContainer)

        for range in Self.characterRanges(of: errorLines, in: source) {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var box = layoutManager.boundingRect(forGlyphRange: glyphs, in: program.textContainer)
            // An empty line holds no glyphs, so it has no bounding box - its fragment is
            // the only thing that knows where the cursor would sit.
            if box.height == 0 {
                if glyphs.location < layoutManager.numberOfGlyphs {
                    box = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                } else if layoutManager.extraLineFragmentTextContainer != nil {
                    box = layoutManager.extraLineFragmentRect
                } else {
                    continue
                }
            }

            let strip = UIView(frame: CGRect(x: 0,
                                             y: box.minY + program.textContainerInset.top,
                                             width: max(program.bounds.width, program.contentSize.width),
                                             height: box.height))
            strip.backgroundColor = Self.errorStripColour
            strip.isUserInteractionEnabled = false
            program.insertSubview(strip, at: 0)
            errorStrips.append(strip)
        }
    }

    // The character range of each wanted line, walked once rather than by splitting the
    // whole program into an array of lines for the one or two that are wanted.
    private static func characterRanges(of lines: Set<Int>, in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var line = 1
        var start = 0
        var i = 0
        while i <= source.length {
            if i == source.length || source.character(at: i) == 0x0A {
                if lines.contains(line) {
                    ranges.append(NSRange(location: start, length: i - start))
                }
                line += 1
                start = i + 1
            }
            i += 1
        }
        return ranges
    }

    // Three levels, and the order of them is the point: keywords darkest, code in the
    // middle, comments palest. Violet for code, the same hue driven down near indigo for
    // the words the language reserves - a different hue would have made the keywords a
    // second subject competing with the program, where this reads as emphasis inside one
    // voice. Against the mint they measure 10.7:1, 4.1:1 and 2.7:1, so the eye meets them
    // in that order and a comment is the last thing it stops on.
    static let codeColour = UIColor.init(displayP3Red: 0.63, green: 0.35, blue: 0.75, alpha: 1)
    static let keywordColour = UIColor.init(displayP3Red: 0.32, green: 0.08, blue: 0.52, alpha: 1)
    // Grey, and neutral rather than a paled violet: a comment is not weak code, it is not
    // code at all, and dropping the hue says that more plainly than lightening it would.
    // 2.7:1 is quiet but still legible - the reader who goes looking can read it.
    static let commentColour = UIColor.init(white: 0.6, alpha: 1)
    // The one place a hue change is earned: a literal is the user's own data passing
    // through, not language, so depth alone cannot say what it is. Rose - a pink deep
    // enough to be read, which a pale one is not: at 5.1:1 it sits between the code and
    // the keywords, so a literal announces itself inside the line rather than blending
    // into it. Lightening it is where it stops working - the same pink as a pastel falls
    // to 1.6:1, fainter than the comments it is supposed to outrank.
    static let stringColour = UIColor.init(displayP3Red: 0.75, green: 0.10, blue: 0.38, alpha: 1)

    // Lowercased, because the lexer folds case before it compares (TokenKind.swift) - so
    // WHILE is the keyword too, and colouring only "while" would tell the reader that the
    // capital one is an identifier when the language disagrees.
    static let keywords: Set<String> = [
        "if", "elseif", "else", "while", "for", "to", "step", "fun", "return",
        "int", "real", "char"
    ]

    // The colouring has to agree with the lexer about what a word is, or it teaches the
    // wrong thing: "for" inside a comment is prose, and "to" inside a string is data.
    // So this walks the text the way tokenList does rather than matching \bfor\b - "//"
    // to end of line, a quote to the next quote (the lexer's string pattern has no escapes
    // and does not stop at a newline), and identifiers only in what is left over.
    private func applySyntaxColours() {
        let storage = program.textStorage
        let source = storage.string as NSString
        let whole = NSRange(location: 0, length: source.length)
        let body = program.font ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        // Weight is free here in a way it would not be in a proportional face: the
        // monospaced system font advances every glyph the same distance at every weight,
        // measured identical from medium to bold. So bold cannot rewrap a line or shift
        // a number off the line it counts - it only makes the word heavier.
        let heavy = UIFont.monospacedSystemFont(ofSize: body.pointSize, weight: .bold)

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: Self.codeColour, range: whole)
        storage.addAttribute(.font, value: body, range: whole)

        var i = 0
        while i < source.length {
            let c = source.character(at: i)
            // "//" - the rest of the line is a comment. The lexer throws these away
            // before the parser ever sees them, and the grey says so.
            if c == 0x2F, i + 1 < source.length, source.character(at: i + 1) == 0x2F {
                let start = i
                while i < source.length, source.character(at: i) != 0x0A { i += 1 }
                storage.addAttribute(.foregroundColor, value: Self.commentColour,
                                     range: NSRange(location: start, length: i - start))
                continue
            }
            // A quote opens a string that runs to the next quote, newlines included.
            // Quotes and all: the delimiters are part of the literal, and colouring the
            // body alone would leave them looking like stray operators.
            if c == 0x22 {
                let start = i
                i += 1
                while i < source.length, source.character(at: i) != 0x22 { i += 1 }
                i += 1
                // An unterminated string runs off the end, so the span has to be clipped
                // back to the text - the lexer's pattern closes the quote optionally too.
                let end = min(i, source.length)
                storage.addAttribute(.foregroundColor, value: Self.stringColour,
                                     range: NSRange(location: start, length: end - start))
                continue
            }
            if Self.isIdentifierHead(c) {
                let start = i
                while i < source.length, Self.isIdentifierBody(source.character(at: i)) { i += 1 }
                let range = NSRange(location: start, length: i - start)
                if Self.keywords.contains(source.substring(with: range).lowercased()) {
                    storage.addAttribute(.foregroundColor, value: Self.keywordColour, range: range)
                    storage.addAttribute(.font, value: heavy, range: range)
                }
                continue
            }
            i += 1
        }
        storage.endEditing()

        // Without this the next character typed inherits whatever the caret was sitting
        // in, so a word typed after a keyword starts out keyword-coloured until the next
        // pass repaints it - a flicker on every keystroke at the end of a line.
        program.typingAttributes = [.font: body, .foregroundColor: Self.codeColour]
    }

    // [a-zA-Z_] then [a-zA-Z0-9_]*, which is the identifier pattern in tokenList.
    private static func isIdentifierHead(_ c: unichar) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
    }

    private static func isIdentifierBody(_ c: unichar) -> Bool {
        isIdentifierHead(c) || (c >= 0x30 && c <= 0x39)
    }

    // The gutter used to be a fixed 1...99, printed once at load. That was wrong in both
    // directions: it ran out on a hundredth line, and on a five-line program it counted
    // 94 lines that were not there. It is generated from the editor now, so the last
    // number in the column is always the last line of the program.
    //
    // Counting "\n" would be enough for the length, but not for the alignment: a line
    // too long for the column occupies two rows on screen while remaining one line to
    // the lexer. Numbering rows would then report the wrong line for every error below
    // the first wrap. So the numbers come from the layout instead - one row per line
    // fragment, but a number only on the fragment that begins a line, and a blank on
    // each continuation. A wrapped line keeps exactly one number, opposite its head.
    private func refreshLineNumbers() {
        let source = (program.text ?? "") as NSString
        let layoutManager = program.layoutManager
        // The fragments below are only as current as the layout, and an edit that has
        // not been laid out yet would be counted at its old width.
        layoutManager.ensureLayout(for: program.textContainer)

        var column: [String] = []
        var line = 0
        let everything = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        layoutManager.enumerateLineFragments(forGlyphRange: everything) { _, _, _, glyphRange, _ in
            let characters = layoutManager.characterRange(forGlyphRange: glyphRange,
                                                          actualGlyphRange: nil)
            // A fragment begins a line when the character before it is the newline that
            // ended the previous one - or when there is no character before it at all.
            let startsLine = characters.location == 0
                || source.character(at: characters.location - 1) == 0x0A
            if startsLine {
                line += 1
                column.append(String(line))
            } else {
                column.append("")
            }
        }

        // Text ending in a newline, and empty text, both leave a final empty line that
        // holds no glyphs - it is where the cursor sits after Return. TextKit keeps it
        // out of the enumeration above and in the extra fragment instead, but it is a
        // line the user can type on and it needs a number like any other.
        if layoutManager.extraLineFragmentTextContainer != nil {
            line += 1
            column.append(String(line))
        }

        let numbers = column.joined(separator: "\n")
        guard numbers != lineview.text else { return }
        lineview.text = numbers
        // Replacing the text resets the gutter's scroll position, so put it back in step
        // with the editor rather than waiting for the next scroll to do it.
        lineview.contentOffset = program.contentOffset
    }

    // Three spaces a level, which is what the phone column can afford: at 14pt a line
    // holds about 39 characters, so a wider step pushes nested bodies into wrapping.
    static let indentWidth = 3

    // Braces opened and closed on one line, ignoring any that are not structure: a brace
    // inside a string or after // is text. No escape handling, because the lexer has no
    // escapes - its string pattern is "[^"]*", so the first quote always closes.
    // leadingCloses counts only the braces before anything else on the line; those are
    // what pull the line itself back out a level.
    private static func braceCounts(in line: String) -> (opens: Int, closes: Int, leadingCloses: Int) {
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
            out.append(String(repeating: " ", count: level * indentWidth) + line)
            depth = max(0, depth + counts.opens - counts.closes)
        }

        return out.joined(separator: "\n")
    }

    // NSRange offsets are UTF-16, so the document is measured as NSString throughout
    // rather than by Character - the two disagree the moment anything non-ASCII lands in
    // the buffer, and the keyboard traits do not guarantee it cannot.
    private static func textRange(in textView: UITextView, for range: NSRange) -> UITextRange? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length) else { return nil }
        return textView.textRange(from: start, to: end)
    }

    // The edit that lays out `text` at its brace level, or nil when what the user typed
    // already sits where it belongs and can be inserted untouched.
    private static func indentedInsertion(of text: String,
                                          into textView: UITextView,
                                          replacing range: NSRange) -> (text: String, range: NSRange)? {
        let document = (textView.text ?? "") as NSString
        guard range.location <= document.length else { return nil }
        let head = document.substring(to: range.location)

        if text == "\n" {
            let depth = braceDepth(of: head)
            guard depth > 0 else { return nil }
            return ("\n" + String(repeating: " ", count: depth * indentWidth), range)
        }

        // A } only moves its line when nothing precedes it there; typed mid-line, as in
        // an array literal closing where it opened, it is left exactly where it fell.
        let lineStart = (head as NSString).range(of: "\n", options: .backwards).location
        let start = lineStart == NSNotFound ? 0 : lineStart + 1
        let onLine = document.substring(with: NSRange(location: start, length: range.location - start))
        guard onLine.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }

        let depth = max(0, braceDepth(of: document.substring(to: start)) - 1)
        let replacement = String(repeating: " ", count: depth * indentWidth) + "}"
        guard replacement != onLine + "}" else { return nil }
        return (replacement, NSRange(location: start, length: NSMaxRange(range) - start))
    }

    // The keyboard traits set in viewDidLoad are only a hint - the globe key and pasting
    // both bypass them - so this is where ASCII is actually enforced. It shares the
    // scanner's substitution table, so text that is typed, pasted, or scanned all end up
    // as the same ASCII source rather than a lookalike that fails at run time.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard textView === program else { return true }

        // Enter carries the brace depth onto the new line, and a } typed as the first
        // thing on a line pulls that line back one level. Between them the text stays
        // laid out as it is typed, so reindenting is only needed on the way in.
        if text == "\n" || text == "}" {
            if let indented = Self.indentedInsertion(of: text, into: textView, replacing: range),
               let editRange = Self.textRange(in: textView, for: indented.range) {
                textView.replace(editRange, withText: indented.text)
                return false
            }
            return true
        }

        let normalized = Self.normalizedToASCII(text)
        guard normalized != text else { return true }

        // Insert the cleaned text and reject the original edit. This cannot recurse:
        // normalized text holds no confusables, so the guard above short-circuits it.
        if let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
           let end = textView.position(from: start, offset: range.length),
           let editRange = textView.textRange(from: start, to: end) {
            textView.replace(editRange, withText: normalized)
            return false
        }
        return true
    }
    
    @objc func doubleTapped() {
        if program.text.isEmpty {
            let x = console.text.components(separatedBy: ["\n"])
            program.text += x[5] + "\n"
            program.text += x[6] + "\n"
            program.text += x[7] + "\n  "
            program.text += x[18] + "\n"
            program.text += x[8] + "\n"
            programChanged()
        }
    }
    
    // One way only. This fires for the gutter's own scrolling too, and answering that by
    // reassigning the gutter's offset is a loop that reports as a twitch on screen.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === program else { return }
        lineview.contentOffset = program.contentOffset
    }
    
    @IBAction func ComputeTapped(_ sender: Any) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard let programSource = program.text else {return}

        clearConsole()
        // Every stage below can return early, and the strips have to be drawn whichever
        // one stopped the run - so this is deferred rather than repeated at four exits.
        defer { layoutErrorStrips() }

        let lexer = Lexer(input: programSource)
        let tokens = lexer.tokenize()

        // Must come before parsing: tokenize() stops at the offending character, so the
        // token stream is truncated and any parse error from here would point elsewhere.
        if let lexError = lexer.lexError {
            append("\(lexError)\n", .error)
            return
        }

        let parser = Parser(tokens: tokens)
        let astNodes = parser.parseProgram()

        if let parseError = parser.parseError {
            append("\(parseError)\n", .error)
            return
        }

        // The 3.0 stage between parsing and running. It validates every call, return and
        // reference argument against the prototype that owns it, resolves every name, and
        // hands back a rewritten AST in which each implicit conversion is a ConvertNode -
        // so the interpreter does no inference of its own.
        let checker = Checker()
        let checkedAST = checker.check(astNodes)

        // Warnings show either way; only errors stop the run. Unlike the other two stages
        // this one does not stop at the first problem, so the console lists them all.
        for diagnostic in checker.diagnostics {
            append("\(diagnostic)\n", diagnostic.severity == .error ? .error : .warning)
        }
        if checker.hasErrors { return }

        let interpreter = Interpreter()
        interpreter.diagnostic = { [weak self] text in self?.append(text, .error) }
        interpreter.output = { [weak self] text in
            self?.append(text, .output)
        }
        interpreter.run(checkedAST)
    }

    // Pushed rather than presented so the editor keeps its place underneath and the
    // automatic back button returns to exactly the program being written.
    @objc func helpTapped() {
        navigationController?.pushViewController(HelpViewController(), animated: true)
    }

    @objc func scanTapped() {
        guard VNDocumentCameraViewController.isSupported else {
            let a = UIAlertController(title: "Scan Unavailable",
                message: "Document scanning isn't supported on this device.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            present(a, animated: true, completion: nil)
            return
        }

        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        present(scanner, animated: true, completion: nil)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                       didFinishWith scan: VNDocumentCameraScan) {
        let pageImages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
        controller.dismiss(animated: true) { [weak self] in
            self?.recognizeText(in: pageImages)
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true, completion: nil)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true) { [weak self] in
            let a = UIAlertController(title: "Scan Failed", message: "\(error)", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            self?.present(a, animated: true, completion: nil)
        }
    }

    private func recognizeText(in pageImages: [UIImage]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var allLines: [String] = []
            for image in pageImages {
                guard let cgImage = image.cgImage else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false // code, not prose - don't autocorrect it
                request.recognitionLanguages = ["en-US"]
                if #available(iOS 16.0, *) {
                    request.automaticallyDetectsLanguage = false
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])

                    // Vision doesn't guarantee reading order, doesn't promise one observation per
                    // printed line, and strips leading whitespace from each string. ScanLayout
                    // rebuilds lines, order and indentation from the bounding boxes - which line a
                    // piece of text belongs to now changes what the program means, so it cannot be
                    // left to the order Vision happened to return (see ScanLayout.swift).
                    let fragments: [ScanLayout.Fragment] = (request.results ?? []).compactMap {
                        guard let text = $0.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                        return ScanLayout.Fragment(text: Self.normalizedToASCII(text), box: $0.boundingBox)
                    }
                    allLines += ScanLayout.lines(from: fragments)
                } catch {
                    print(error)
                }
            }

            let programLines = Self.trimToProgramBody(allLines)
            let scannedText = programLines.joined(separator: "\n")
            // A print command that isn't first on its line is a parse error the moment this runs,
            // and after a scan the likeliest cause is two printed lines read as one. Saying so here,
            // while the user is already being asked to check the text, beats letting them hit Run
            // and work backwards from the line number.
            let lateCommands = ScanLayout.linesWithLateCommand(in: programLines)

            DispatchQueue.main.async {
                guard let self = self else { return }
                // Line count is preserved, so the numbers in lateCommands still point at
                // the lines the user is about to be shown.
                self.program.text = Self.reindented(scannedText)
                self.programChanged()
                var message = "Let's review the code before running."
                if let first = lateCommands.first {
                    message += "\n\nLine \(first) has a '?' that isn't at the start of the line"
                    if lateCommands.count > 1 {
                        message += " (and \(lateCommands.count - 1) more)"
                    }
                    message += ". Two lines may have been scanned as one."
                }
                let a = UIAlertController(
                            title:   "Scan May Be Incomplete",
                            message: message,
                            preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                self.present(a, animated: true, completion: nil)
            }
        }
    }

    // OCR routinely substitutes non-ASCII characters that are visually identical to ASCII
    // ones - Cyrillic "х" (U+0445) for Latin "x", a smart quote for ", an en-dash for "-".
    // Shalimar is an ASCII language, so every one of these is a scanning mistake, and they
    // are invisible on screen: the lexer's `char.isLetter` check happily accepts a Cyrillic
    // letter as an identifier character, so "хn" silently becomes a *different* variable
    // than "xn" - producing either wrong results or "Undefined variable" at run time.
    // Only glyphs that are genuinely confusable with ASCII are mapped, so deliberate
    // non-ASCII text (in a string literal, say) is left alone.
    private static let asciiConfusables: [Character: Character] = [
        // Cyrillic lowercase
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
        "і": "i", "ј": "j", "ѕ": "s", "к": "k",
        // Cyrillic uppercase
        "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O",
        "Р": "P", "С": "C", "Т": "T", "У": "Y", "Х": "X",
        // Greek uppercase
        "Α": "A", "Β": "B", "Ε": "E", "Ζ": "Z", "Η": "H", "Ι": "I", "Κ": "K",
        "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Υ": "Y", "Χ": "X",
        // Greek lowercase
        "ο": "o", "ρ": "p", "ν": "v", "ι": "i",
        // Punctuation and operators the scanner likes to prettify
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{2018}": "'", "\u{2019}": "'",
        "\u{2013}": "-", "\u{2014}": "-", "\u{2212}": "-",
        "×": "*", "÷": "/", "\u{00A0}": " ",
        "：": ":", "（": "(", "）": ")", "＊": "*", "，": ",",
        // A dot used to appear only inside a numeral, where a wrong glyph produced a loud
        // "Malformed number". Since '.row'/'.col'/'.dim(n)' it also carries syntax, so the
        // full-stop lookalikes have to be folded back to ASCII too.
        "。": ".", "．": ".", "•": "."
    ]

    private static func normalizedToASCII(_ text: String) -> String {
        // 1:1 character substitution - line lengths are preserved, which matters because
        // the indentation math above divides a line's width by its character count.
        String(text.map { asciiConfusables[$0] ?? $0 })
    }

    // Crops scanned lines down to the entry point's block: from `fun <> = main() {`
    // through the `}` that balances it, dropping any page header/footer noise Vision
    // picked up outside the program itself.
    private static func trimToProgramBody(_ lines: [String]) -> [String] {
        guard let startIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("fun") && trimmed.contains("main(") && trimmed.hasSuffix("{")
        }) else {
            return lines
        }

        var braceBalance = 0
        for i in startIndex..<lines.count {
            for char in lines[i] {
                if char == "{" { braceBalance += 1 }
                else if char == "}" { braceBalance -= 1 }
            }
            if braceBalance <= 0 {
                return Array(lines[startIndex...i])
            }
        }
        return Array(lines[startIndex...])
    }

    @objc private func textTapped(_ tapGesture: UITapGestureRecognizer) {
        let textView = tapGesture.view as? UITextView
        let point = tapGesture.location(in: textView!)
        if let detectedWord = getWordAtPosition(tapGesture, point) {
            if self.count == 0 {
                program.text += detectedWord + "\n"
                programChanged()
            }
        }
    }

    private func getWordAtPosition(_ tapGesture: UITapGestureRecognizer, _ point: CGPoint) -> String? {
        let textView = tapGesture.view as? UITextView
        if let textPosition = textView!.closestPosition(to: point) {
            if let range = textView!.tokenizer.rangeEnclosingPosition(
                textPosition, with: .line, inDirection: UITextDirection(rawValue: 1)) {
                return textView!.text(in: range)
            }
        }

        return nil
    }

    @objc func saveTapped() {
        guard let coordinator = coordinator else { return }
        if coordinator.fileURL.isEmpty {
            promptForFileName { [weak self] name in
                guard let self = self, let name = name else { return }
                self.coordinator?.fileURL = name
                self.save(fileName: name)
            }
        } else {
            save(fileName: coordinator.fileURL)
        }
    }

    private func promptForFileName(completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "Save Program", message: "Enter a name for this program.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Program name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(nil) })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            let name = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/", with: "-")
            completion((name?.isEmpty ?? true) ? nil : name)
        })
        present(alert, animated: true, completion: nil)
    }

    func save(fileName: String) {
        do {
            let docDirURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            // fileName is already extensioned when re-saving an existing file (coordinator.fileURL
            // is the file's full name as listed on the home screen); only append ".shm" for a
            // brand-new name typed into the save prompt, so re-saving doesn't produce "x.shm.shm".
            var fileURL = docDirURL.appendingPathComponent(fileName)
            if fileURL.pathExtension != "shm" {
                fileURL = fileURL.appendingPathExtension("shm")
            }
            try program.text.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
        } catch let error as NSError {
            print(error)
        }
    }

    func load(fileName: String) {
        do {
            let docDirURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let fileURL = docDirURL.appendingPathComponent(fileName) //.appendingPathExtension("sha")
            program.text = Self.reindented(try String(contentsOf: fileURL))
            programChanged()
        } catch let error as NSError {
            print(error)
        }
    }
}
