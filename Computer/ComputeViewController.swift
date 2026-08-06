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
        program.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)

        lineview.delegate = self
        lineview.textColor = UIColor.init(displayP3Red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
        lineview.font = program.font
        lineview.isScrollEnabled = true
        lineview.text = ""
        for i in 1..<100 {
            lineview.text += String(i) + "\n"
        }

        program.delegate = self
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
        program.backgroundColor = UIColor.init(displayP3Red: 0.8, green: 1, blue: 0.95, alpha: 1)
        console.backgroundColor = UIColor.init(white: 0.8, alpha: 0.5)
        // The original violet, deepened to carry at 12pt but not to black - about 4.1:1
        // against the mint background set below. Not .label or a dynamic colour: that
        // background is fixed light, so anything inverting in dark mode would land white
        // on mint.
        program.textColor = UIColor.init(displayP3Red: 0.63, green: 0.35, blue: 0.75, alpha: 1)

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
    }

    private func append(_ text: String, _ style: ConsoleStyle) {
        let font = console.font ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let run = NSAttributedString(string: text,
                                     attributes: [.foregroundColor: style.color, .font: font])
        let all = NSMutableAttributedString(attributedString: console.attributedText
                                            ?? NSAttributedString(string: ""))
        all.append(run)
        console.attributedText = all
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if !program.text.isEmpty { self.count = 0 }
    }

    // Three spaces a level, which is what the phone column can afford: at 12pt a line
    // holds about 47 characters, so a wider step pushes nested bodies into wrapping and
    // the wrapping is what knocks the line-number gutter out of register.
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
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        lineview.contentOffset = program.contentOffset
    }
    
    @IBAction func ComputeTapped(_ sender: Any) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard let programSource = program.text else {return}

        clearConsole()

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
            if self.count == 0 { program.text += detectedWord + "\n" }
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
        } catch let error as NSError {
            print(error)
        }
    }
}
