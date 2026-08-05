//
//  Lexer.swift
//  Computer
//
//  Created by G. R. Akhtar on 02/08/2026.
//  Copyright © 2026 Home. All rights reserved.
//

enum TokenType {
    case number(Double)
    case identifier(String)
    case plus, minus, multiply, divide, modulus
    case assignColon, equal, notEqual
    case plusAssign, minusAssign
    case lParen, rParen, lBrace, rBrace
    case ifKeyword, elseKeyword, elseifKeyword, whileKeyword, forKeyword, toKeyword, stepKeyword, funKeyword, returnKeyword
    case less, greater, and, or
    case printLine, printInline
    case stringLiteral(String)
    case lAngle, rAngle, comma
    case caret
    case eof
}

extension TokenType: Equatable {
    static func == (lhs: TokenType, rhs: TokenType) -> Bool {
        switch (lhs, rhs) {
        case (.number(let a), .number(let b)): return a == b
        case (.identifier(let a), .identifier(let b)): return a == b
        case (.stringLiteral(let a), .stringLiteral(let b)): return a == b

        // Simple cases without associated values
        case (.plus, .plus), (.minus, .minus), (.multiply, .multiply),
             (.divide, .divide), (.modulus, .modulus),
             (.assignColon, .assignColon),
             (.equal, .equal), (.notEqual, .notEqual),
             (.plusAssign, .plusAssign), (.minusAssign, .minusAssign),
             (.lParen, .lParen), (.rParen, .rParen),
             (.lBrace, .lBrace), (.rBrace, .rBrace),
             (.ifKeyword, .ifKeyword), (.elseKeyword, .elseKeyword),
             (.elseifKeyword, .elseifKeyword), (.whileKeyword, .whileKeyword),
             (.forKeyword, .forKeyword), (.toKeyword, .toKeyword),
             (.stepKeyword, .stepKeyword), (.funKeyword, .funKeyword),
             (.returnKeyword, .returnKeyword),
             (.less, .less), (.greater, .greater),
             (.and, .and), (.or, .or),
             (.printLine, .printLine), (.printInline, .printInline),
             (.lAngle, .lAngle), (.rAngle, .rAngle),
             (.comma, .comma), (.caret, .caret),
             (.eof, .eof):
            return true

        default:
            return false
        }
    }
}

class Token {
    let type: TokenType
    // Physical source line the token starts on, 1-based. The language is newline-insensitive
    // everywhere else - this exists for one rule only: a print command must be the first token
    // on its line (§5.10), which is not decidable from the token stream alone because the lexer
    // discards newlines as ordinary whitespace. Defaults to 0 for the virtual `.eof` token that
    // `Parser.currentToken` manufactures, which belongs to no line.
    let line: Int
    init(type: TokenType, line: Int = 0) {
        self.type = type
        self.line = line
    }
}

class Lexer {
    private let input: String
    private var index: String.Index
    private var line = 1
    // Line the token currently being scanned began on. Captured before the token is consumed so
    // that a multi-line string literal is attributed to its opening quote, not its closing one.
    private var tokenLine = 1
    // First character the lexer could not handle, if any. Mirrors Parser.parseError:
    // callers check it after tokenize() and stop before parsing, since the token stream
    // is truncated at that point.
    private(set) var lexError: String?

    init(input: String) {
        self.input = input
        self.index = input.startIndex
    }

    // Shalimar source is ASCII. These deliberately exclude the rest of Unicode so that a
    // homoglyph - Cyrillic "х" (U+0445), which is indistinguishable on screen from Latin
    // "x" - can never quietly become a second, different identifier.
    private func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
    private func isIdentifierStart(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c == "_") }
    private func isIdentifierBody(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "_") }

    private static func codePoint(of char: Character) -> String {
        guard let scalar = char.unicodeScalars.first else { return "U+?" }
        var hex = String(scalar.value, radix: 16, uppercase: true)
        while hex.count < 4 { hex = "0" + hex }
        return "U+" + hex
    }

    private func peekNext() -> Character? {
        let nextIndex = input.index(after: index)
        return nextIndex < input.endIndex ? input[nextIndex] : nil
    }
    
    private func advance() {
        if index < input.endIndex, input[index] == "\n" { line += 1 }
        index = input.index(after: index)
    }

    private func token(_ type: TokenType) -> Token { Token(type: type, line: tokenLine) }

    func tokenize() -> [Token] {
        var tokens: [Token] = []
        while index < input.endIndex {
            let char = input[index]
            if char.isWhitespace { advance(); continue }
            tokenLine = line
            switch char {
            case "+":
                if peekNext() == ":" { advance(); tokens.append(token(.plusAssign)) }
                else { tokens.append(token(.plus)) }
            case "-":
                if peekNext() == ":" { advance(); tokens.append(token(.minusAssign)) }
                else { tokens.append(token(.minus)) }
            case "*": tokens.append(token(.multiply))
            case "/":
                if peekNext() == "/" {
                    // Line comment: "//" through end of line, wherever it starts.
                    while index < input.endIndex && input[index] != "\n" {
                        advance()
                    }
                    continue
                } else {
                    tokens.append(token(.divide))
                }
            case "%": tokens.append(token(.modulus))
            case "^": tokens.append(token(.caret))
            case ":": tokens.append(token(.assignColon))
            case "=": tokens.append(token(.equal))
            case "(": tokens.append(token(.lParen))
            case ")": tokens.append(token(.rParen))
            case "{": tokens.append(token(.lBrace))
            case "}": tokens.append(token(.rBrace))
            case "?":
                // "??" is inline print, "?" is print-with-newline. Longest match first, as with
                // "+:" / "+" - a lone "?" is only reached once the second "?" is ruled out.
                if peekNext() == "?" { advance(); tokens.append(token(.printInline)) }
                else { tokens.append(token(.printLine)) }
            case "!":
                if peekNext() == "=" { advance(); tokens.append(token(.notEqual)) }
                else {
                    // "!" was the inline-print command before "??" took that role, so this is the
                    // line every program written against the old spelling lands on. A bare "!" is
                    // now no token at all; say what to write instead rather than reporting it as
                    // an anonymous unexpected character.
                    lexError = "Lex error: line \(tokenLine): '!' is not a command. Use '??' to print inline, '!=' for not-equal."
                    return tokens
                }
            case "&": tokens.append(token(.and))
            case "|": tokens.append(token(.or))
            case "<": tokens.append(token(.lAngle))
            case ">": tokens.append(token(.rAngle))
            case ",": tokens.append(token(.comma))
            case "\"":
                var str = ""
                advance()
                while index < input.endIndex && input[index] != "\"" {
                    str.append(input[index]); advance()
                }
                tokens.append(token(.stringLiteral(str)))
                if index < input.endIndex { advance() } // consume closing quote, if the string was actually closed
                continue
            default:
                if isDigit(char) {
                    var numStr = String(char); advance()
                    while index < input.endIndex && (isDigit(input[index]) || input[index] == ".") {
                        numStr.append(input[index]); advance()
                    }
                    // The scanning loop above is deliberately looser than the grammar: it takes any
                    // run of digits and dots, so "1.2.3" arrives here as one string that Double
                    // cannot parse. Reporting it is the point - previously the token was simply not
                    // appended, which desynced the stream and surfaced as a parse error pointing
                    // somewhere else entirely. Note "1." is not malformed: Double("1.") is 1.0.
                    guard let value = Double(numStr) else {
                        lexError = "Lex error: line \(tokenLine): Malformed number '\(numStr)'"
                        return tokens
                    }
                    tokens.append(token(.number(value)))
                    continue
                } else if isIdentifierStart(char) {
                    var idStr = String(char); advance()
                    while index < input.endIndex && isIdentifierBody(input[index]) {
                        idStr.append(input[index]); advance()
                    }
                    switch idStr.lowercased() {
                    case "if": tokens.append(token(.ifKeyword))
                    case "else": tokens.append(token(.elseKeyword))
                    case "elseif": tokens.append(token(.elseifKeyword))
                    case "while": tokens.append(token(.whileKeyword))
                    case "for": tokens.append(token(.forKeyword))
                    case "to": tokens.append(token(.toKeyword))
                    case "step": tokens.append(token(.stepKeyword))
                    case "fun": tokens.append(token(.funKeyword))
                    case "return": tokens.append(token(.returnKeyword))
                    default: tokens.append(token(.identifier(idStr)))
                    }
                    continue
                }
                // Not punctuation, not a number, not an identifier - so it is nothing the
                // language has a token for. Reporting it with its code point is the whole
                // point: an OCR or keyboard homoglyph looks exactly like the ASCII letter
                // it replaced, so "unexpected character 'х'" is only actionable once you
                // can see it is U+0445 and not U+0078. Previously this fell through to the
                // advance() below and the character was dropped without a word, which is
                // what let a mis-scanned "хn" silently become the variable "n".
                lexError = "Lex error: line \(tokenLine): Unexpected character '\(char)' (\(Lexer.codePoint(of: char)))"
                return tokens
            }
            advance()
        }
        return tokens
    }
}
