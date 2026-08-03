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
}

class Token {
    let type: TokenType
    init(type: TokenType) { self.type = type }
}

class Lexer {
    private let input: String
    private var index: String.Index
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
    
    private func advance() { index = input.index(after: index) }
    
    func tokenize() -> [Token] {
        var tokens: [Token] = []
        while index < input.endIndex {
            let char = input[index]
            if char.isWhitespace { advance(); continue }
            switch char {
            case "+":
                if peekNext() == ":" { advance(); tokens.append(Token(type: .plusAssign)) }
                else { tokens.append(Token(type: .plus)) }
            case "-":
                if peekNext() == ":" { advance(); tokens.append(Token(type: .minusAssign)) }
                else { tokens.append(Token(type: .minus)) }
            case "*": tokens.append(Token(type: .multiply))
            case "/":
                if peekNext() == "/" {
                    // Line comment: "//" through end of line, wherever it starts.
                    while index < input.endIndex && input[index] != "\n" {
                        advance()
                    }
                    continue
                } else {
                    tokens.append(Token(type: .divide))
                }
            case "%": tokens.append(Token(type: .modulus))
            case "^": tokens.append(Token(type: .caret))
            case ":": tokens.append(Token(type: .assignColon))
            case "=": tokens.append(Token(type: .equal))
            case "(": tokens.append(Token(type: .lParen))
            case ")": tokens.append(Token(type: .rParen))
            case "{": tokens.append(Token(type: .lBrace))
            case "}": tokens.append(Token(type: .rBrace))
            case "?": tokens.append(Token(type: .printLine))
            case "!":
                if peekNext() == "=" { advance(); tokens.append(Token(type: .notEqual)) }
                else { tokens.append(Token(type: .printInline)) }
            case "&": tokens.append(Token(type: .and))
            case "|": tokens.append(Token(type: .or))
            case "<": tokens.append(Token(type: .lAngle))
            case ">": tokens.append(Token(type: .rAngle))
            case ",": tokens.append(Token(type: .comma))
            case "\"":
                var str = ""
                advance()
                while index < input.endIndex && input[index] != "\"" {
                    str.append(input[index]); advance()
                }
                tokens.append(Token(type: .stringLiteral(str)))
                if index < input.endIndex { advance() } // consume closing quote, if the string was actually closed
                continue
            default:
                if isDigit(char) {
                    var numStr = String(char); advance()
                    while index < input.endIndex && (isDigit(input[index]) || input[index] == ".") {
                        numStr.append(input[index]); advance()
                    }
                    if let value = Double(numStr) {
                        tokens.append(Token(type: .number(value)))
                    }
                    continue
                } else if isIdentifierStart(char) {
                    var idStr = String(char); advance()
                    while index < input.endIndex && isIdentifierBody(input[index]) {
                        idStr.append(input[index]); advance()
                    }
                    switch idStr.lowercased() {
                    case "if": tokens.append(Token(type: .ifKeyword))
                    case "else": tokens.append(Token(type: .elseKeyword))
                    case "elseif": tokens.append(Token(type: .elseifKeyword))
                    case "while": tokens.append(Token(type: .whileKeyword))
                    case "for": tokens.append(Token(type: .forKeyword))
                    case "to": tokens.append(Token(type: .toKeyword))
                    case "step": tokens.append(Token(type: .stepKeyword))
                    case "fun": tokens.append(Token(type: .funKeyword))
                    case "return": tokens.append(Token(type: .returnKeyword))
                    default: tokens.append(Token(type: .identifier(idStr)))
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
                lexError = "Lex error: Unexpected character '\(char)' (\(Lexer.codePoint(of: char)))"
                return tokens
            }
            advance()
        }
        return tokens
    }
}
